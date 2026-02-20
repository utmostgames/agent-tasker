#!/usr/bin/env bash
#
# run-claude.sh — Automatically launch Claude when eligible tasks exist
#
# Monitors data/tasks.json for tasks that are NOT type "simple" and NOT
# in status "closed" or "new". When eligible tasks are found, launches
# Claude in foreground mode. When Claude exits (or signals via exit flag),
# loops back to check for more work.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASKS_FILE="$SCRIPT_DIR/data/tasks.json"
EXIT_FLAG="$SCRIPT_DIR/data/claude-exit.flag"
POLL_INTERVAL=60  # seconds to wait when no tasks are found
FLAG_CHECK_INTERVAL=2  # seconds between exit-flag checks

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

# ── Helper: run Claude with exit-flag monitor ───────────────────────
run_claude_with_monitor() {
  # Clean up any stale exit flag
  rm -f "$EXIT_FLAG"

  # Launch Claude in background (exec replaces subshell so kill targets Claude directly)
  (cd "$SCRIPT_DIR" && exec claude --dangerously-skip-permissions "start working") &
  local claude_pid=$!

  # Monitor for exit flag while Claude is running
  while kill -0 "$claude_pid" 2>/dev/null; do
    if [[ -f "$EXIT_FLAG" ]]; then
      echo "[$(date '+%Y-%m-%d %H:%M:%S')] Exit flag detected. Shutting down Claude..."
      rm -f "$EXIT_FLAG"
      kill "$claude_pid" 2>/dev/null
      wait "$claude_pid" 2>/dev/null || true
      return 0
    fi
    sleep "$FLAG_CHECK_INTERVAL"
  done

  # Claude exited on its own
  wait "$claude_pid" 2>/dev/null || true
  rm -f "$EXIT_FLAG"
}

# ── Main loop ───────────────────────────────────────────────────────
echo "=== run-claude.sh ==="
echo "Monitoring: $TASKS_FILE"
echo "Exit flag:  $EXIT_FLAG"
echo "Poll interval when idle: ${POLL_INTERVAL}s"
echo "Press Ctrl+C to stop."
echo ""

while true; do
  ELIGIBLE=$(count_eligible_tasks)

  if [[ "$ELIGIBLE" -gt 0 ]]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Found $ELIGIBLE eligible task(s). Launching Claude..."

    run_claude_with_monitor

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Claude exited. Re-checking tasks..."
  else
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] No eligible tasks. Sleeping ${POLL_INTERVAL}s..."
    sleep "$POLL_INTERVAL"
  fi
done
