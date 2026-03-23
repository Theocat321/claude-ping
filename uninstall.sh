#!/bin/bash
# uninstall.sh — Remove ClaudePing

set -euo pipefail

BOLD='\033[1m'
GREEN='\033[0;32m'
DIM='\033[2m'
RESET='\033[0m'

INSTALL_DIR="$HOME/.claude-ping"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/com.claudeping.agent.plist"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"

echo ""
echo -e "${BOLD}Uninstalling ClaudePing...${RESET}"

# Stop the agent
launchctl unload "$LAUNCH_AGENT" 2>/dev/null || true
rm -f "$LAUNCH_AGENT"
echo -e "  ${GREEN}✓${RESET} LaunchAgent removed"

# Remove hooks from Claude Code settings
if [ -f "$CLAUDE_SETTINGS" ]; then
    python3 << 'PYEOF'
import json, os

path = os.path.expanduser("~/.claude/settings.json")
try:
    with open(path) as f:
        settings = json.load(f)
except:
    exit(0)

hooks = settings.get("hooks", {})
for key in ["Stop", "Notification"]:
    if key in hooks:
        hooks[key] = [
            entry for entry in hooks[key]
            if not any("claude-ping-hook" in h.get("command", "") for h in entry.get("hooks", []))
        ]
        if not hooks[key]:
            del hooks[key]

if not hooks:
    del settings["hooks"]

with open(path, "w") as f:
    json.dump(settings, f, indent=2)
PYEOF
    echo -e "  ${GREEN}✓${RESET} Claude Code hooks removed"
fi

# Remove install directory
rm -rf "$INSTALL_DIR"
echo -e "  ${GREEN}✓${RESET} Files removed"

# Clean up socket
rm -f "${TMPDIR:-/tmp/}claude-ping.sock"

echo ""
echo -e "${GREEN}${BOLD}ClaudePing uninstalled.${RESET}"
echo ""
