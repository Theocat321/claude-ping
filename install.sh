#!/bin/bash
# install.sh — Install ClaudePing
# Compiles the Swift app, installs the hook, and configures Claude Code.

set -euo pipefail

BOLD='\033[1m'
DIM='\033[2m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
RESET='\033[0m'

INSTALL_DIR="$HOME/.claude-ping"
HOOK_PATH="$INSTALL_DIR/claude-ping-hook.sh"
APP_PATH="$INSTALL_DIR/ClaudePing"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
LAUNCH_AGENT_DIR="$HOME/Library/LaunchAgents"
LAUNCH_AGENT="$LAUNCH_AGENT_DIR/com.claudeping.agent.plist"

echo ""
echo -e "${BOLD}⚡ ClaudePing Installer${RESET}"
echo -e "${DIM}Floating notifications for Claude Code${RESET}"
echo ""

# ── Step 1: Check prerequisites ──────────────────────────────────
echo -e "${CYAN}[1/5]${RESET} Checking prerequisites..."

if ! command -v swiftc &>/dev/null; then
    echo -e "${RED}Error:${RESET} swiftc not found. Install Xcode Command Line Tools:"
    echo "       xcode-select --install"
    exit 1
fi

if ! command -v python3 &>/dev/null; then
    echo -e "${RED}Error:${RESET} python3 not found."
    exit 1
fi

echo -e "       ${GREEN}✓${RESET} swiftc found"
echo -e "       ${GREEN}✓${RESET} python3 found"

# ── Step 2: Compile Swift app ────────────────────────────────────
echo -e "${CYAN}[2/5]${RESET} Compiling ClaudePing..."

mkdir -p "$INSTALL_DIR"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
swiftc -O \
    -framework Cocoa \
    -o "$APP_PATH" \
    "$SCRIPT_DIR/ClaudePing.swift" 2>&1

echo -e "       ${GREEN}✓${RESET} Compiled to $APP_PATH"

# ── Step 3: Install hook script ──────────────────────────────────
echo -e "${CYAN}[3/5]${RESET} Installing hook script..."

cp "$SCRIPT_DIR/claude-ping-hook.sh" "$HOOK_PATH"
chmod +x "$HOOK_PATH"

echo -e "       ${GREEN}✓${RESET} Hook installed at $HOOK_PATH"

# ── Step 4: Configure Claude Code hooks ──────────────────────────
echo -e "${CYAN}[4/5]${RESET} Configuring Claude Code hooks..."

mkdir -p "$(dirname "$CLAUDE_SETTINGS")"

# Create settings.json if it doesn't exist
if [ ! -f "$CLAUDE_SETTINGS" ]; then
    echo '{}' > "$CLAUDE_SETTINGS"
fi

# Use python3 to safely merge hooks into existing settings
python3 << 'PYEOF'
import json, sys, os

settings_path = os.path.expanduser("~/.claude/settings.json")

try:
    with open(settings_path, "r") as f:
        settings = json.load(f)
except (json.JSONDecodeError, FileNotFoundError):
    settings = {}

hook_path = os.path.expanduser("~/.claude-ping/claude-ping-hook.sh")

# Define the hooks we want to add
stop_hook = {
    "matcher": "",
    "hooks": [{
        "type": "command",
        "command": f"{hook_path} stop"
    }]
}

notification_hook = {
    "matcher": "idle_prompt",
    "hooks": [{
        "type": "command",
        "command": f"{hook_path} input_needed"
    }]
}

# Merge into existing hooks (don't overwrite user's existing hooks)
if "hooks" not in settings:
    settings["hooks"] = {}

hooks = settings["hooks"]

# Check if our hooks are already installed
def has_claude_ping(hook_list):
    for entry in hook_list:
        for h in entry.get("hooks", []):
            if "claude-ping-hook" in h.get("command", ""):
                return True
    return False

if "Stop" not in hooks:
    hooks["Stop"] = []
if not has_claude_ping(hooks["Stop"]):
    hooks["Stop"].append(stop_hook)

if "Notification" not in hooks:
    hooks["Notification"] = []
if not has_claude_ping(hooks["Notification"]):
    hooks["Notification"].append(notification_hook)

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)

print("       Hooks configured successfully")
PYEOF

echo -e "       ${GREEN}✓${RESET} Claude Code hooks configured"

# ── Step 5: Set up Launch Agent (auto-start) ─────────────────────
echo -e "${CYAN}[5/5]${RESET} Setting up auto-start..."

mkdir -p "$LAUNCH_AGENT_DIR"

cat > "$LAUNCH_AGENT" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.claudeping.agent</string>
    <key>ProgramArguments</key>
    <array>
        <string>${APP_PATH}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${INSTALL_DIR}/claudeping.log</string>
    <key>StandardErrorPath</key>
    <string>${INSTALL_DIR}/claudeping.log</string>
</dict>
</plist>
EOF

# Stop existing agent if running
launchctl unload "$LAUNCH_AGENT" 2>/dev/null || true

# Start the agent
launchctl load "$LAUNCH_AGENT"

echo -e "       ${GREEN}✓${RESET} LaunchAgent installed (auto-starts on login)"

# ── Done ─────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}⚡ ClaudePing is installed and running!${RESET}"
echo ""
echo -e "  ${DIM}Menu bar:${RESET}   Look for the ⚡ icon — click it to test or quit"
echo -e "  ${DIM}How it works:${RESET} When Claude Code finishes, a floating HUD"
echo -e "              appears near your cursor. Click it to jump back."
echo ""
echo -e "  ${DIM}Files:${RESET}"
echo -e "    App:       $APP_PATH"
echo -e "    Hook:      $HOOK_PATH"
echo -e "    Settings:  $CLAUDE_SETTINGS"
echo -e "    Agent:     $LAUNCH_AGENT"
echo ""
echo -e "  ${DIM}To uninstall:${RESET}"
echo -e "    ${SCRIPT_DIR}/uninstall.sh"
echo ""
