# Task Board - Claude Orchestration Rules

## Overview
This is a shared task board at `data/tasks.json`. Humans interact via the web UI at `http://localhost:4000`. Claude instances read and write the JSON file directly.

## Work Loop
Once the human confirms "yes", run this loop autonomously until the backlog is empty or the human interrupts:

### Step 1: Brainstorm (if needed)
- **Clear context first.** Before brainstorming, summarize completed work in a short status report, then release any large file contents or intermediate state from memory. This keeps the session lean for the next task.
- If the task effort is NOT `XS`, use the `superpowers:brainstorming` skill to analyze the task before development
- Update the task `details` field with the brainstorm output
- **Create follow-up tasks:** If brainstorming breaks a large task into sub-phases or sub-tasks, create those as separate tasks in `backlog` with proper `depends_on` chains. This makes the work visible on the board and lets the human re-prioritize.

### Step 1.5: Create Development Branch
- Before any development begins, create a new git branch **from `main`** in the target project:
  - Branch name: `task-{task_id}/{short-slug}` (e.g., `task-5/add-dark-mode`)
  - Always start from main: `git checkout main && git pull && git checkout -b <branch-name>`
  - Never branch from another feature branch — always branch from `main`
  - Alternative: use a git worktree for full isolation: `git worktree add ../worktrees/<branch-name> -b <branch-name> main`
- All development and commits happen on this branch, never directly on `main`
- The branch is merged to `main` during Step 4 (Stage and Close) after tests pass

### Step 2: Dispatch DEV Worker
- Update tasks.json: set `assigned_to` to `claude-dev-{task_id}`, set `status` to `developing`, log history
- Launch a Task subagent (type: `general-purpose`) with a prompt containing:
  - The full task details (title, description, details, type)
  - The project working directory: the absolute path to `../repos/{project}` relative to this repo
  - Instruction to do the development work in that project folder
  - Instruction to update `data/tasks.json` when done: set `status` to `testing`, set `developed_by` to its worker ID, log history
- **Keep prompts lean:** Do NOT paste tasks.json diffs, full JSON blobs, or large data excerpts into worker prompts. Give the worker the task ID and file path — it can read what it needs.

### Step 3: Dispatch TEST Worker
- After the dev worker completes, read `data/tasks.json` to confirm the task is in `testing`
- Launch a DIFFERENT Task subagent (type: `general-purpose`) with a prompt containing:
  - The full task details and what was changed by the dev worker
  - The project working directory
  - Instruction to check if the project has a test suite (look for test files, package.json scripts, etc.)
    - If test suite exists: run tests AND review the code changes
    - If no test suite: perform code review only (check correctness, edge cases, style)
  - On PASS: update tasks.json — set `status` to `staged`, set `tested_by` to its worker ID, log history
  - On FAIL: update tasks.json — set `status` to `developing`, add failure notes to `details`, log history

### Step 4: Merge to Main
- After the test worker completes, read `data/tasks.json`
- If the task is in `staged`:
  - Navigate to the project folder
  - Check if it's a git repo (`git status`)
    - If git repo: stage and commit changes, then merge the development branch into `main` (`git checkout main && git merge <branch>`)
    - **Push rules by task type:**
      - `maintenance` tasks: **auto-push to remote** (`git push` on `main`) immediately after merge, then set `status` to `closed`, log history
      - All other types (`feature`, `brainstorm`, `simple`): **Do NOT push automatically.** Leave the task in `staged` status. Pushing is human-initiated via the "Push All Staged to Remote" button in the UI (see Step 4.5), which also moves tasks to `closed`.
    - If not a git repo: skip git operations, set `status` to `closed`, log history
  - **Project-specific: `todos`** — if the completed task modified server.js or any server-side code, restart the Node server (kill the process on port 4000, then run `node server.js` in the background)
- If the task was moved back to `developing` (test failure): loop back to Step 2 with a fresh dev worker

### Step 4.5: Push Remote and Close (on request)
- Check if `data/push-remote.flag` exists
- If the flag file exists:
  - For each project that has tasks in `staged` status (or any project with unpushed commits on `main`), navigate to that project folder and run `git push` on `main`
  - After a successful push, move all `staged` tasks for that project to `closed` (set `status` to `closed`, log history)
  - Delete the flag file after pushing: `rm data/push-remote.flag`
  - Log which projects were pushed (to stdout or a history entry)
- **Flag expiry:** If the flag exists but there are no tasks in `staged` status and no unpushed commits on any project's `main`, delete the flag without pushing (staging is empty, nothing to push).
- If the flag does not exist: skip this step (no push requested)
- This flag can also be created manually from the command line: `touch data/push-remote.flag`

### Step 5: Next Task
- Read `data/tasks.json` for the next highest-priority `backlog` task
- If found: continue the loop from Step 1
- If no more backlog tasks: follow the **Idle — No Tasks** procedure below

### Parallel Dispatch
The orchestrator MAY run up to **3 dev workers concurrently** to speed up throughput:

1. **When to parallelize.** After dispatching a dev worker for one task, check `data/tasks.json` for additional eligible `backlog` tasks. If independent tasks are available, dispatch additional dev workers (up to 3 total in-flight).
2. **Independence requirement.** Never parallelize tasks that depend on each other (check `depends_on`). Also avoid parallelizing tasks that modify the same project files when there is a clear overlap risk.
3. **Each task is self-contained.** Every parallel task still gets its own branch (`task-{id}/{slug}`), its own dev worker, and its own test worker. The standard Step 1 through Step 4 flow applies to each.
4. **Monitor completion.** While dev workers are in-flight, periodically read `data/tasks.json` to detect tasks that have moved to `testing`. Dispatch test workers for completed dev tasks promptly — do not wait for all dev workers to finish before starting any testing.
5. **Merge sequentially.** When multiple tasks reach `staged`, merge them to `main` one at a time to avoid merge conflicts. If a conflict occurs, resolve it before proceeding to the next merge.
6. **Backfill slots.** When a parallel slot frees up (task moves past `developing`), check for the next eligible `backlog` task and dispatch a new dev worker to keep up to 3 slots utilized.

## Idle — No Tasks
When the backlog is empty or all remaining tasks are unactionable (blocked by dependencies, human-assigned, or `simple` type):
1. Report "Board clear — no eligible tasks."
2. **Check push flag.** Run Step 4.5 (check if `data/push-remote.flag` exists and push if so).
3. **Exit Claude Code.** Write the exit flag file: `touch data/claude-exit.flag` via the Bash tool. The external shell script (`run-claude.sh`) monitors for this file and terminates the Claude process automatically. Do NOT wait for user input — write the flag immediately after step 2.

## Human Interrupt
The human can interrupt the work loop at any time between task cycles:
- `stop` or `pause` — exit the work loop, leave remaining tasks in their current state
- `skip task #N` — skip a specific task, move to the next one
- Any other message — pause the loop, respond to the human, then ask whether to resume

## Data File Location
`data/tasks.json` relative to this project root.

## Reading Tasks
```bash
# Read the file directly with your Read tool
Read data/tasks.json
```

## Writing Tasks
Always follow this pattern:
1. Read `data/tasks.json` completely
2. Parse the JSON
3. Make your changes (update fields, add history entries)
4. Write the **entire file** back with 2-space indented JSON
5. Never partially write or append — always overwrite the full file

## Creating Tasks
- Increment `next_id` from the file and use it as the new task's `id`
- Set `created_at` and `updated_at` to current ISO 8601 timestamp
- Add a history entry: `{ "action": "created", "by": "claude-{your-id}", "at": "<timestamp>" }`
- Claude-created tasks should use status `backlog` (not `new`)

## Task Fields
| Field | Type | Values |
|-------|------|--------|
| id | number | Auto-increment from next_id |
| type | string | simple, brainstorm, feature, maintenance |
| status | string | new, backlog, developing, testing, staged, closed |
| priority | number | 1-5 (1 = most urgent) |
| effort | string | XS, S, M, L, XL, XXL |
| title | string | Short descriptive title |
| description | string | Summary for card view |
| details | string | Full spec, acceptance criteria, notes |
| project | string | Folder name from sibling repos (e.g. "fleet-pioneers") |
| assigned_to | string/null | Worker identifier |
| developed_by | string/null | Who developed this task |
| tested_by | string/null | Who tested this task |
| depends_on | number/null | Task ID that must be closed first |

## Status Transition Rules

```
new ──→ backlog ──→ developing ──→ testing ──→ staged ──→ closed
 (human only)  (claim it)    (work done)   (test pass) (pushed to remote)
                                             (merged to main)
```

### Critical Rules
1. **`new` is the human triage inbox.** Claude must NEVER move tasks it did not create from `new` to `backlog`. Only humans triage.
2. **Claude creates in `backlog`.** When Claude needs to assign work to a child worker, create the task with `status: "backlog"`.
3. **Brainstorm before developing.** When picking up a `backlog` task, always use the `superpowers:brainstorming` skill to analyze it first — unless the task effort is already set to `XS`. This ensures proper requirements exploration before committing to implementation.
4. **Claim before working.** Set `assigned_to` to your worker ID before changing status to `developing`.
5. **No self-testing.** When a task reaches `testing`, a DIFFERENT Claude instance must test it. The `tested_by` field must differ from `developed_by`. The orchestrator assigns testing to a new worker.
6. **Set `developed_by`** when moving status from `developing` to `testing`.
7. **Set `tested_by`** when moving status from `testing` to `staged` or back.
8. **Dependency check.** Before picking up a `backlog` task, check if `depends_on` is set. If the referenced task's status is not `closed`, skip this task and move to the next eligible one.
9. **Human-assigned tasks.** Skip any task where `assigned_to` is a non-Claude identifier (i.e., does not start with `claude-`). Human-assigned tasks are for human work only.
10. **Skip `simple` type tasks.** Tasks with `type: "simple"` are human-only work items (e.g., system administration, manual installs). Claude must never pick up or work on `simple` tasks — skip them entirely when scanning the backlog.

## Priority Ordering
Always work on the highest-priority (lowest number) available task first:
- P1 before P2, P2 before P3, etc.
- Among same priority, prefer smaller effort (XS before S before M, etc.)

## History Logging
Every change must append to the `history` array:
```json
{
  "action": "status_changed",
  "changes": [{ "field": "status", "from": "backlog", "to": "developing" }],
  "by": "claude-worker-1",
  "at": "2026-02-17T10:00:00Z"
}
```

## Worker Identity
Use a consistent identifier for your session:
- Format: `claude-{descriptive-name}` (e.g., `claude-orchestrator`, `claude-dev-1`, `claude-tester-1`)
- Set this in `assigned_to`, `developed_by`, and `tested_by` fields
- Use the same ID for all history entries in your session

## Project Scope
- Tasks have a `project` field matching a folder name in the parent `repos/` directory
- The absolute path to a project is: the parent directory of this repo + the project name
- Only work on tasks that match the project you were assigned
- Available projects are auto-discovered from sibling directories
