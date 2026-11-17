#!/bin/bash
# Build, test, start at login (LaunchAgent), and add the global Claude Code hooks.
set -euo pipefail
cd "$(dirname "$0")"
LABEL=local.claude-bulb
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

./build.sh
./test.sh

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$(pwd)/bin/claude-bulb</string></array>
  <key>RunAtLoad</key><true/>
  <key>ProcessType</key><string>Interactive</string>
</dict>
</plist>
EOF
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "menu bar app started (and will start at every login)"

python3 hooks.py add
echo "done. New Claude Code sessions pick up the hooks; restart running ones."
