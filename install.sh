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
  <!-- Restart after a crash or a failed launch; Quit from the menu exits cleanly and stays quit. -->
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
</dict>
</plist>
EOF
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
# bootout returns before the old job is fully gone; bootstrap then fails with
# "5: Input/output error". Retry for a few seconds instead of failing the install.
for try in 1 2 3 4 5; do
  launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null && break
  [ "$try" = 5 ] && { echo "could not start the menu bar app; run: launchctl bootstrap gui/$(id -u) $PLIST"; exit 1; }
  sleep 1
done
echo "menu bar app started (and will start at every login)"

python3 hooks.py add
echo "done. New Claude Code sessions pick up the hooks; restart running ones."
