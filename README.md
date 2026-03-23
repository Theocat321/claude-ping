# ⚡ ClaudePing

A floating HUD for macOS that appears **next to your mouse cursor** when Claude Code finishes a task or needs input. Click it to jump straight back to the terminal.

No more babysitting Claude Code windows. Switch to another app, and ClaudePing will find you when it's time.

## How it works

```
Claude Code finishes a task
        ↓
Hook script fires
        ↓
Sends message to ClaudePing via Unix socket
        ↓
Floating HUD appears near your cursor
        ↓
Click → jumps to terminal window
        (or wait 8s → auto-dismisses)
```

- **Green HUD** = task completed
- **Amber HUD** = Claude needs your input
- Different sounds for each event
- Stacks multiple pings if several sessions finish at once
- Detects your terminal app (Terminal, iTerm2, Kitty, Ghostty, Warp, WezTerm, Alacritty)
- Runs as a menu bar app (⚡ icon) — no dock clutter

## Install

```bash
git clone <this-repo> claude-ping
cd claude-ping
chmod +x install.sh
./install.sh
```

The installer will:
1. Compile the Swift app
2. Install the hook script
3. Configure Claude Code's hooks (non-destructively merges with your existing hooks)
4. Set up a LaunchAgent so it starts automatically on login

**Prerequisites:** Xcode Command Line Tools (`xcode-select --install`)

## Uninstall

```bash
./uninstall.sh
```

Removes everything cleanly — app, hooks, LaunchAgent, and the Claude Code hook entries.

## Manual test

Click the ⚡ menu bar icon → "Send Test Ping" to verify it's working.

Or from any terminal:

```bash
python3 -c "
import socket
sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.connect('${TMPDIR:-/tmp/}claude-ping.sock')
sock.sendall(b'project=test-project\nevent=stop\nterminal=Terminal\n')
sock.close()
"
```

## Files

| File | Location |
|------|----------|
| App binary | `~/.claude-ping/ClaudePing` |
| Hook script | `~/.claude-ping/claude-ping-hook.sh` |
| LaunchAgent | `~/Library/LaunchAgents/com.claudeping.agent.plist` |
| Log file | `~/.claude-ping/claudeping.log` |
| Socket | `$TMPDIR/claude-ping.sock` |

## How the hooks work

ClaudePing plugs into Claude Code's [hooks system](https://docs.anthropic.com/en/docs/claude-code/hooks). Two hooks are configured in `~/.claude/settings.json`:

- **Stop hook** — fires when Claude finishes any response
- **Notification hook** (`idle_prompt`) — fires when Claude is idle and waiting for input

The hook script detects which terminal app is running, finds the project name from git, and sends a message to the ClaudePing app over a Unix socket. If ClaudePing isn't running, it falls back to a standard macOS notification.

## Customization

Edit `~/.claude-ping/claude-ping-hook.sh` to change behavior. Edit the Swift source and recompile to customize the HUD appearance (colors, size, timing, sounds).

## License

MIT
