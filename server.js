const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = 4000;
const DATA_FILE = path.join(__dirname, 'data', 'tasks.json');
const REPOS_DIR = path.resolve(__dirname, '..');
const INDEX_FILE = path.join(__dirname, 'index.html');

// Ensure data directory exists
function ensureDataDir() {
  const dir = path.dirname(DATA_FILE);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  if (!fs.existsSync(DATA_FILE)) {
    fs.writeFileSync(DATA_FILE, JSON.stringify({ tasks: [], next_id: 1 }, null, 2));
  }
}

function readTasks() {
  ensureDataDir();
  return JSON.parse(fs.readFileSync(DATA_FILE, 'utf8'));
}

function writeTasks(data) {
  ensureDataDir();
  fs.writeFileSync(DATA_FILE, JSON.stringify(data, null, 2));
}

function parseBody(req) {
  return new Promise((resolve, reject) => {
    let body = '';
    req.on('data', chunk => body += chunk);
    req.on('end', () => {
      try { resolve(JSON.parse(body)); }
      catch { reject(new Error('Invalid JSON')); }
    });
  });
}

function json(res, status, data) {
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(data));
}

function discoverProjects() {
  try {
    return fs.readdirSync(REPOS_DIR, { withFileTypes: true })
      .filter(d => d.isDirectory() && !d.name.startsWith('.'))
      .map(d => d.name)
      .sort();
  } catch { return []; }
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://localhost:${PORT}`);
  const pathname = url.pathname;

  // Serve index.html
  if (req.method === 'GET' && pathname === '/') {
    try {
      const html = fs.readFileSync(INDEX_FILE, 'utf8');
      res.writeHead(200, { 'Content-Type': 'text/html' });
      res.end(html);
    } catch {
      res.writeHead(500);
      res.end('index.html not found');
    }
    return;
  }

  // GET /api/projects
  if (req.method === 'GET' && pathname === '/api/projects') {
    return json(res, 200, discoverProjects());
  }

  // GET /api/tasks
  if (req.method === 'GET' && pathname === '/api/tasks') {
    const data = readTasks();
    const project = url.searchParams.get('project');
    const tasks = project
      ? data.tasks.filter(t => t.project === project)
      : data.tasks;
    return json(res, 200, tasks);
  }

  // POST /api/tasks
  if (req.method === 'POST' && pathname === '/api/tasks') {
    try {
      const body = await parseBody(req);
      const data = readTasks();
      const now = new Date().toISOString();
      const task = {
        id: data.next_id++,
        type: body.type || 'simple',
        status: body.status || 'new',
        priority: body.priority || 3,
        effort: body.effort || 'M',
        title: body.title || 'Untitled',
        description: body.description || '',
        details: body.details || '',
        project: body.project || '',
        depends_on: body.depends_on || null,
        assigned_to: body.assigned_to || null,
        developed_by: null,
        tested_by: null,
        created_at: now,
        updated_at: now,
        history: [{ action: 'created', by: body.created_by || 'human', at: now }]
      };
      data.tasks.push(task);
      writeTasks(data);
      return json(res, 201, task);
    } catch (e) {
      return json(res, 400, { error: e.message });
    }
  }

  // PATCH /api/tasks/:id
  const patchMatch = pathname.match(/^\/api\/tasks\/(\d+)$/);
  if (req.method === 'PATCH' && patchMatch) {
    try {
      const id = parseInt(patchMatch[1]);
      const body = await parseBody(req);
      const data = readTasks();
      const task = data.tasks.find(t => t.id === id);
      if (!task) return json(res, 404, { error: 'Task not found' });

      const now = new Date().toISOString();
      const changes = [];

      for (const [key, value] of Object.entries(body)) {
        if (key === 'history' || key === 'id' || key === 'created_at') continue;
        if (task[key] !== value) {
          changes.push({ field: key, from: task[key], to: value });
          task[key] = value;
        }
      }

      if (changes.length > 0) {
        task.updated_at = now;
        task.history.push({
          action: 'updated',
          changes,
          by: body._updated_by || 'human',
          at: now
        });
      }

      // Remove internal field
      delete task._updated_by;

      writeTasks(data);
      return json(res, 200, task);
    } catch (e) {
      return json(res, 400, { error: e.message });
    }
  }

  // DELETE /api/tasks/:id
  const deleteMatch = pathname.match(/^\/api\/tasks\/(\d+)$/);
  if (req.method === 'DELETE' && deleteMatch) {
    const id = parseInt(deleteMatch[1]);
    const data = readTasks();
    const idx = data.tasks.findIndex(t => t.id === id);
    if (idx === -1) return json(res, 404, { error: 'Task not found' });
    data.tasks.splice(idx, 1);
    writeTasks(data);
    return json(res, 200, { deleted: id });
  }

  // 404
  json(res, 404, { error: 'Not found' });
});

ensureDataDir();
server.listen(PORT, () => {
  console.log(`Task Board running at http://localhost:${PORT}`);
});
