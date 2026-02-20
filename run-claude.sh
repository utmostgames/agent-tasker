#!/usr/bin/env bash
#
# run-claude.sh — Automatically launch Claude when eligible tasks exist
#
# Monitors data/tasks.json for tasks that are NOT type "simple" and NOT
# in status "closed" or "new". When eligible tasks are found, launches
# Claude in foreground mode. When Claude exits, loops back to check
# for more work.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASKS_FILE="$SCRIPT_DIR/data/tasks.json"
POLL_INTERVAL=60  # seconds to wait when no tasks are found

# ── Dependency check ────────────────────────────────────────────────
if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is required but not installed."
  echo "  Ubuntu/Debian : sudo apt install jq"
  echo "  macOS (brew)  : brew install jq"
  echo "  Fedora/RHEL   : sudo dnf install jq"
  exit 1
fi

if ! command -v claude &>/dev/null; then
  echo "ERROR: claude CLI is required but not found in PATH."
  echo "  Install from: https://docs.anthropic.com/en/docs/claude-code"
  exit 1
fi

# ── Helper: count eligible tasks ────────────────────────────────────
count_eligible_tasks() {
  if [[ ! -f "$TASKS_FILE" ]]; then
    echo 0
    return
  fi
  jq '[.tasks[] | select((.type == "simple" or .status == "closed" or .status == "new") | not)] | length' "$TASKS_FILE" 2>/dev/null || echo 0
}

# ── Main loop ───────────────────────────────────────────────────────
echo "=== run-claude.sh ==="
echo "Monitoring: $TASKS_FILE"
echo "Poll interval when idle: ${POLL_INTERVAL}s"
echo "Press Ctrl+C to stop."
echo ""

while true; do
  ELIGIBLE=$(count_eligible_tasks)

  if [[ "$ELIGIBLE" -gt 0 ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Found $ELIGIBLE eligible task(s). Launching Claude..."

    # Run Claude in foreground — script blocks here until Claude exits
    (cd "$SCRIPT_DIR" && claude --dangerously-skip-permissions "start working") || true

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Claude exited. Re-checking tasks..."
  else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] No eligible tasks. Sleeping ${POLL_INTERVAL}s..."
    sleep "$POLL_INTERVAL"
  fi
done
