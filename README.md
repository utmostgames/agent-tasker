# Agent Tasker

A lightweight localhost Kanban board where humans create tasks through a web UI and Claude Code agents autonomously develop, test, and deploy them.

## Prerequisites

- **An understanding of the inherent risks of allowing AI a free hand to assist you**
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) with the [obra:superpowers](https://github.com/anthropics/claude-code-plugins) plugin
- [Node.js](https://nodejs.org/) to run the web board
- A browser to view it

## Getting Started

1. **Clone this repo as a child of your main working folder** (sibling to the projects you want Claude to work on):

   ```
   cd ~/source/repos
   git clone https://github.com/utmostgames/agent-tasker.git
   ```

2. **Start Claude Code from the repo with permissions bypassed:**

   ```
   cd agent-tasker
   claude --dangerously-skip-permissions "start working"
   ```

3. **Open the board** at [http://localhost:4000](http://localhost:4000)

4. **Add a task!** Set the project name to match a sibling folder, and Claude will find it.

## How It Works

- **Humans** create and triage tasks through the web UI
- **Claude** reads `data/tasks.json` directly, picks up backlog tasks, and runs an autonomous dev/test/deploy loop
- **CLAUDE.md** contains the orchestration rules — customize it to fit your workflow
- The board auto-refreshes so you can watch tasks move across columns in real time

## More Details on How It Works
- Control+Enter will add the new task from the New Task overlay (same as "Save" button)
- The Types are for organizing task types:
   - Feature is a generic new task
   - Brainstorm will always prompt you for more detail
   - Maintenence is for editing this project's functionality
   - Simple is for human-only tasks, like paying your AWS bill!
- States:
   - New is for finalizing your thoughts.
   - Backlog is where Claude looks for new tasks
   - Dev is active development
   - Test is active testing
   - Staging is merge/commit/push
   - Closed is archival
- Changing 'assign to' to your user name will make Claude ignore that work item, but so will task Type 'Simple'

## What should I do with this thing?
- Make a task to add Light Mode. Mention "frontend design" if you have that skill; create the task against agent-tasker project, start in Backlog state.
   - Claude will read the task board every 60 seconds, and automatically begin working on tasks by priority!
- Make a task to update Readme.md in ~/source/repos/your-project; create the task against your-project. Give it as much detail as you like, treat Name, Description & Details as if they are prompt boxes! Create in or move to Backlog state, and work will begin!

## Anything else?

Fork me! Contribute!
