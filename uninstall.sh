#!/bin/bash
# Stop the app, remove login start, remove our hooks, remove state. Leaves this folder.
set -uo pipefail
cd "$(dirname "$0")"
LABEL=local.claude-bulb
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null && echo "app stopped"
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist" && echo "login item removed"
python3 hooks.py remove
rm -rf "$HOME/.claude-bulb" && echo "state removed"
echo "To delete the code too: rm -rf $(pwd)"
