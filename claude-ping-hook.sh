#!/bin/bash
# claude-ping-hook.sh
# Claude Code hook script — sends a ping to ClaudePing when Claude finishes or needs input.
# 
# Usage in Claude Code hooks:
#   Stop event:         claude-ping-hook.sh stop
#   Notification event: claude-ping-hook.sh input_needed

set -euo pipefail

EVENT="${1:-stop}"
SOCKET="${TMPDIR:-/tmp/}claude-ping.sock"
CWD_ABS="$(pwd -P 2>/dev/null || pwd)"
CWD_SHORT="$CWD_ABS"
if [ -n "${HOME:-}" ]; then
    CWD_SHORT="${CWD_ABS/#$HOME/~}"
fi

# Build richer project/worktree context
REPO_ROOT=""
BRANCH=""
CONTEXT=""
PROJECT=""

if git rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
    REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"
    BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
fi

if [ -n "$REPO_ROOT" ]; then
    REPO_NAME="$(basename "$REPO_ROOT")"
    PARENT_NAME="$(basename "$(dirname "$REPO_ROOT")")"

    if [[ "$REPO_ROOT" =~ /worktrees/([^/]+)/([^/]+)$ ]]; then
        CONTEXT="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
    elif [ -n "$PARENT_NAME" ] && [ "$PARENT_NAME" != "$REPO_NAME" ]; then
        CONTEXT="${PARENT_NAME}/${REPO_NAME}"
    else
        CONTEXT="$REPO_NAME"
    fi
else
    REPO_NAME="$(basename "$CWD_ABS")"
    PARENT_NAME="$(basename "$(dirname "$CWD_ABS")")"
    if [ -n "$PARENT_NAME" ] && [ "$PARENT_NAME" != "/" ] && [ "$PARENT_NAME" != "$REPO_NAME" ]; then
        CONTEXT="${PARENT_NAME}/${REPO_NAME}"
    else
        CONTEXT="$REPO_NAME"
    fi
fi

if [ -n "$BRANCH" ] && [ "$BRANCH" != "HEAD" ]; then
    PROJECT="${CONTEXT} (${BRANCH})"
else
    PROJECT="$CONTEXT"
fi

# Detect which terminal is running this
TERMINAL_APP=""
TERMINAL_PID=""
TTY_PATH=""

detect_terminal() {
    local pid=$$
    while [ "$pid" -gt 1 ]; do
        local parent_pid
        parent_pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
        [ -z "$parent_pid" ] && break
        
        local parent_name
        parent_name=$(ps -o comm= -p "$parent_pid" 2>/dev/null || echo "")
        
        case "$parent_name" in
            *Terminal*) TERMINAL_APP="Terminal"; TERMINAL_PID="$parent_pid"; return ;;
            *iTerm*) TERMINAL_APP="iTerm2"; TERMINAL_PID="$parent_pid"; return ;;
            *kitty*) TERMINAL_APP="kitty"; TERMINAL_PID="$parent_pid"; return ;;
            *Ghostty*) TERMINAL_APP="Ghostty"; TERMINAL_PID="$parent_pid"; return ;;
            *WezTerm*) TERMINAL_APP="WezTerm"; TERMINAL_PID="$parent_pid"; return ;;
            *Warp*) TERMINAL_APP="Warp"; TERMINAL_PID="$parent_pid"; return ;;
            *Alacritty*) TERMINAL_APP="Alacritty"; TERMINAL_PID="$parent_pid"; return ;;
            *tmux*) ;; # skip tmux, keep going up
            *) ;;
        esac
        
        pid="$parent_pid"
    done
    
    # Fallback
    TERMINAL_APP="${TERM_PROGRAM:-Terminal}"
}

detect_terminal
TTY_PATH="$(tty 2>/dev/null || true)"
if [ "${TTY_PATH:-}" = "not a tty" ]; then
    TTY_PATH=""
fi
TERMINAL_LABEL="$TERMINAL_APP"
if [ -n "$TTY_PATH" ] && [[ "$TTY_PATH" == /dev/* ]]; then
    TERMINAL_LABEL="${TERMINAL_LABEL} ${TTY_PATH}"
fi
if [ -n "$TERMINAL_PID" ]; then
    TERMINAL_LABEL="${TERMINAL_LABEL} (pid ${TERMINAL_PID})"
fi

# Check if ClaudePing is listening
if [ ! -S "$SOCKET" ]; then
    # ClaudePing isn't running — fall back to osascript notification
    NOTIFY_BODY="${PROJECT} — ${CWD_SHORT}"
    NOTIFY_TITLE="ClaudePing: ${EVENT}"
    NOTIFY_BODY="${NOTIFY_BODY//\"/\\\"}"
    NOTIFY_TITLE="${NOTIFY_TITLE//\"/\\\"}"
    osascript -e "display notification \"$NOTIFY_BODY\" with title \"$NOTIFY_TITLE\" sound name \"Glass\""
    exit 0
fi

# Send the ping via Unix socket
# Using Python since nc on macOS doesn't reliably support Unix sockets
CLAUDEPING_SOCKET="$SOCKET" \
CLAUDEPING_PROJECT="$PROJECT" \
CLAUDEPING_EVENT="$EVENT" \
CLAUDEPING_TERMINAL="$TERMINAL_LABEL" \
CLAUDEPING_TERMINAL_APP="$TERMINAL_APP" \
CLAUDEPING_TERMINAL_PID="$TERMINAL_PID" \
CLAUDEPING_TTY="$TTY_PATH" \
CLAUDEPING_CONTEXT="$CONTEXT" \
CLAUDEPING_BRANCH="$BRANCH" \
CLAUDEPING_REPO_ROOT="$REPO_ROOT" \
CLAUDEPING_CWD="$CWD_ABS" \
CLAUDEPING_CWD_SHORT="$CWD_SHORT" \
CLAUDEPING_PARADEV_WORKSPACE="${SUPERSET_WORKSPACE_ID:-}" \
CLAUDEPING_PARADEV_TERMINAL="${SUPERSET_TERMINAL_ID:-}" \
CLAUDEPING_PARADEV_CLI="${SUPERSET_HOME_DIR:+$SUPERSET_HOME_DIR/bin/paradev}" \
python3 - <<'PY' 2>/dev/null || true
import os
import socket
import sys

sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
try:
    sock.connect(os.environ["CLAUDEPING_SOCKET"])
    fields = [
        ("project", os.environ.get("CLAUDEPING_PROJECT", "")),
        ("event", os.environ.get("CLAUDEPING_EVENT", "")),
        ("terminal", os.environ.get("CLAUDEPING_TERMINAL", "")),
        ("terminal_app", os.environ.get("CLAUDEPING_TERMINAL_APP", "")),
        ("pid", os.environ.get("CLAUDEPING_TERMINAL_PID", "")),
        ("tty", os.environ.get("CLAUDEPING_TTY", "")),
        ("context", os.environ.get("CLAUDEPING_CONTEXT", "")),
        ("branch", os.environ.get("CLAUDEPING_BRANCH", "")),
        ("repo_root", os.environ.get("CLAUDEPING_REPO_ROOT", "")),
        ("cwd", os.environ.get("CLAUDEPING_CWD", "")),
        ("cwd_short", os.environ.get("CLAUDEPING_CWD_SHORT", "")),
        ("paradev_workspace", os.environ.get("CLAUDEPING_PARADEV_WORKSPACE", "")),
        ("paradev_terminal", os.environ.get("CLAUDEPING_PARADEV_TERMINAL", "")),
        ("paradev_cli", os.environ.get("CLAUDEPING_PARADEV_CLI", "")),
    ]
    msg = "".join(f"{k}={v}\n" for k, v in fields)
    sock.sendall(msg.encode())
except Exception as e:
    print(f"ClaudePing: could not connect — {e}", file=sys.stderr)
finally:
    sock.close()
PY
