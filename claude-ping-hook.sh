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

# Get project name from git repo, or fall back to current directory name
PROJECT=""
if git rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
    PROJECT=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null || echo "")
fi
if [ -z "$PROJECT" ]; then
    PROJECT=$(basename "$PWD")
fi

# Detect which terminal is running this
TERMINAL_APP=""
TERMINAL_PID=""

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

# Check if ClaudePing is listening
if [ ! -S "$SOCKET" ]; then
    # ClaudePing isn't running — fall back to osascript notification
    osascript -e "display notification \"$PROJECT — Claude Code $EVENT\" with title \"ClaudePing\" sound name \"Glass\""
    exit 0
fi

# Send the ping via Unix socket
# Using Python since nc on macOS doesn't reliably support Unix sockets
python3 -c "
import socket, sys
sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
try:
    sock.connect('$SOCKET')
    msg = 'project=$PROJECT\nevent=$EVENT\nterminal=$TERMINAL_APP\npid=$TERMINAL_PID\n'
    sock.sendall(msg.encode())
except Exception as e:
    print(f'ClaudePing: could not connect — {e}', file=sys.stderr)
finally:
    sock.close()
" 2>/dev/null || true
