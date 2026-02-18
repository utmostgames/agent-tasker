# Claude-Human Shared Task Board

## Overview
A super-lightweight localhost-only Kanban task board for human-Claude collaboration. Claude instances can read, write, and move tasks to coordinate work across sub-agents. Zero external dependencies.

## Architecture
```
todos/
├── server.js          # Zero-dependency Node.js server
├── index.html         # Single-file dark-mode Kanban UI (inline CSS/JS)
├── data/
│   └── tasks.json     # Flat-file task store (Claude reads/writes directly)
├── CLAUDE.md          # Orchestration rules for Claude instances
└── package.json       # "npm start" convenience
```

### Data Flow
- **Human** → browser → server.js API → reads/writes `tasks.json`
- **Claude** → reads/writes `tasks.json` directly via file tools (no server needed)
- **Web UI** → polls `tasks.json` via server every 2s for live updates

## Data Model

### Task Schema
```json
{
  "id": 1,
  "type": "feature",
  "status": "new",
  "priority": 2,
  "effort": "M",
  "title": "Add user authentication",
  "description": "Short summary for card view",
  "details": "Full specification, acceptance criteria, notes",
  "project": "fleet-pioneers",
  "assigned_to": null,
  "developed_by": null,
  "tested_by": null,
  "created_at": "2026-02-17T10:00:00Z",
  "updated_at": "2026-02-17T10:00:00Z",
  "history": [
    { "action": "created", "by": "human", "at": "2026-02-17T10:00:00Z" }
  ]
}
```

### Enums
- **Type:** simple, brainstorm, feature, maintenance
- **Status:** new, backlog, developing, testing, staged, closed
- **Priority:** 1-5 (lower = more urgent)
- **Effort:** XS, S, M, L, XL, XXL

## Server API

| Method | Endpoint | Purpose |
|--------|----------|---------|
| GET | `/` | Serve index.html |
| GET | `/api/tasks` | Read all tasks (optional `?project=X`) |
| POST | `/api/tasks` | Create a task |
| PATCH | `/api/tasks/:id` | Update a task |
| DELETE | `/api/tasks/:id` | Delete a task |
| GET | `/api/projects` | Auto-discover `../repos/*` directories |

## Web UI Features
- Dark mode Kanban board (GitHub-dark palette)
- Drag-and-drop between status columns
- Columns: New | Backlog | Developing | Testing | Staged | (Closed hidden, toggleable)
- Filter bar: Type toggles, Effort toggles
- Search: filters by title, description, details
- Column sorting: priority (default), date, effort, alphabetical
- Project dropdown: auto-discovers from `../repos/*`
- Card design: priority color stripe, type badge, effort badge, title, truncated description
- Inline card expansion or modal for full editing

### Priority Colors
- P1: red (#f85149)
- P2: orange (#d29922)
- P3: yellow (#e3b341)
- P4: blue (#58a6ff)
- P5: gray (#8b949e)

## Claude Orchestration Rules (enforced via CLAUDE.md, not code)
1. **New is human-only triage:** Claude must NOT move tasks it didn't create from New to Backlog
2. **Claude can create in Backlog:** To assign work to child workers, create tasks directly with status `backlog`
3. **No self-testing:** The same Claude worker that developed a task must NOT test it
4. **Claim before working:** Set `assigned_to` before starting
5. **Priority ordering:** Work P1 first
6. **Read before write:** Always read tasks.json fresh before modifying
7. **Log history:** Append to `history[]` on every change

## Design Decisions
- **No database:** JSON flat file for maximum simplicity and Claude readability
- **No build step:** Single HTML file with inline CSS/JS
- **No framework:** Vanilla JS only
- **No WebSocket:** 2-second polling is sufficient for localhost
- **No auth:** Localhost only, trusted environment
- **No node_modules:** Server uses only Node.js built-in modules
