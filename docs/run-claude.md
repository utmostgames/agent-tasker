# run-claude.sh -- Auto-launch Claude for Task Board Work

## What It Does

`run-claude.sh` is a bash loop that monitors `data/tasks.json` for eligible tasks and automatically launches Claude to work on them.

**Eligible tasks** are those where:
- `type` is NOT `"simple"` (simple tasks are human-only)
- `status` is NOT `"closed"` or `"new"` (closed tasks are done; new tasks need human triage)

When eligible tasks exist, the script runs `claude --dangerously-skip-permissions "start working"` in the foreground. Claude processes the task board according to CLAUDE.md orchestration rules. When Claude exits (task board cleared or session ended), the script loops back, re-checks the task file, and launches Claude again if more work remains.

When no eligible tasks are found, the script sleeps for 60 seconds and re-checks.

## Prerequisites

1. **jq** -- JSON processor for parsing tasks.json
   ```bash
   # Ubuntu/Debian
   sudo apt install jq

   # macOS
   brew install jq

   # Fedora/RHEL
   sudo dnf install jq
   ```

2. **Claude CLI** -- The `claude` command must be available in your PATH
   - Install from: https://docs.anthropic.com/en/docs/claude-code

## Running Manually

From the `agent-tasker` project root:

```bash
./run-claude.sh
```

The script runs in the foreground. Press `Ctrl+C` to stop.

## Running in the Background

Use `nohup` to keep it running after you close the terminal:

```bash
nohup ./run-claude.sh > logs/run-claude.log 2>&1 &
```

Create the logs directory first if needed:
```bash
mkdir -p logs
```

To stop it later:
```bash
# Find the process
ps aux | grep run-claude.sh

# Kill it
kill <PID>
```

## Running as a systemd User Service (Auto-start on Login)

This sets up the script to start automatically when you log in to your desktop session.

### 1. Create the service file

```bash
mkdir -p ~/.config/systemd/user

cat > ~/.config/systemd/user/run-claude.service << 'EOF'
[Unit]
Description=Claude Task Board Monitor
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/home/mujadaddy/source/repos/agent-tasker
ExecStart=/home/mujadaddy/source/repos/agent-tasker/run-claude.sh
Restart=on-failure
RestartSec=30
Environment=PATH=/usr/local/bin:/usr/bin:/bin:%h/.local/bin:%h/.npm-global/bin

[Install]
WantedBy=default.target
EOF
```

> **Note:** Adjust the `PATH` in the `Environment` line if your `claude` or `jq` binaries are installed elsewhere. Run `which claude` and `which jq` to find their locations and ensure those directories are included.

### 2. Enable and start

```bash
# Reload systemd to pick up the new service
systemctl --user daemon-reload

# Enable it to start on login
systemctl --user enable run-claude.service

# Start it now
systemctl --user start run-claude.service
```

### 3. Check status and logs

```bash
# Status
systemctl --user status run-claude.service

# Follow logs
journalctl --user -u run-claude.service -f
```

### 4. Stop or disable

```bash
# Stop the service
systemctl --user stop run-claude.service

# Disable auto-start on login
systemctl --user disable run-claude.service
```

## Running with cron @reboot

This approach starts the script when the machine boots (or when your user session starts via cron).

### 1. Edit your crontab

```bash
crontab -e
```

### 2. Add the @reboot entry

```cron
@reboot /home/mujadaddy/source/repos/agent-tasker/run-claude.sh >> /home/mujadaddy/source/repos/agent-tasker/logs/run-claude.log 2>&1
```

Make sure the logs directory exists:
```bash
mkdir -p /home/mujadaddy/source/repos/agent-tasker/logs
```

### 3. Verify

After a reboot, check that it is running:
```bash
ps aux | grep run-claude.sh
```

> **Caveat:** cron runs with a minimal environment. If `claude` or `jq` are not in the default PATH, use their full paths in the script or add a PATH export at the top of your crontab:
> ```cron
> PATH=/usr/local/bin:/usr/bin:/bin:/home/mujadaddy/.local/bin
> @reboot /home/mujadaddy/source/repos/agent-tasker/run-claude.sh >> ...
> ```

## Customization

- **Poll interval**: Edit the `POLL_INTERVAL=60` variable in `run-claude.sh` to change how often it checks for tasks when idle (value in seconds).
- **Task filter**: Modify the `jq` query in the `count_eligible_tasks()` function to change which tasks are considered eligible.
