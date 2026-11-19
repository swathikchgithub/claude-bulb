#!/bin/bash
# Tests the hook side of the binary (on / off / clear-all) against a temp state folder.
# The menu bar drawing is checked by eye (see README "Verify").
set -uo pipefail
cd "$(dirname "$0")"
BIN=./bin/claude-bulb
export CLAUDE_BULB_DIR="$(mktemp -d)/state"
pass=0; fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1 (want '$3', got '$2')"; fi; }
count() { ls "$CLAUDE_BULB_DIR" 2>/dev/null | wc -l | tr -d ' '; }

echo '{"session_id":"s1","hook_event_name":"Stop"}' | $BIN on
check "on creates a file for the session" "$(count)" "1"

echo '{"session_id":"s2"}' | $BIN on
check "two waiting sessions give two files" "$(count)" "2"

echo '{"session_id":"s1"}' | $BIN off
check "off removes only that session" "$(ls "$CLAUDE_BULB_DIR")" "s2"

echo '{"session_id":"../../etc/evil"}' | $BIN on
check "unsafe session id is ignored" "$(count)" "1"

echo 'not json' | $BIN on
check "bad JSON falls back to 'unknown' and still exits 0" "$?" "0"

$BIN clear-all
check "clear-all empties the folder" "$(count)" "0"

$BIN bogus </dev/null 2>/dev/null
check "unknown action exits 2" "$?" "2"

# --- list: which session is waiting, and why
export CLAUDE_BULB_DIR="$(mktemp -d)/state"
tr="$(mktemp)"
echo "{\"session_id\":\"p1\",\"hook_event_name\":\"PermissionRequest\",\"tool_name\":\"Bash\",\"cwd\":\"/x/orca-platform\",\"transcript_path\":\"$tr\"}" | $BIN on
check "permission request names the project and tool" "$($BIN list | grep -c 'orca-platform — needs permission: Bash')" "1"
echo "{\"session_id\":\"p1\",\"hook_event_name\":\"Notification\",\"notification_type\":\"permission_prompt\",\"message\":\"Claude needs your permission to use Bash\",\"cwd\":\"/x/orca-platform\",\"transcript_path\":\"$tr\"}" | $BIN on
check "a later notification keeps the specific reason" "$($BIN list | grep -c 'needs permission: Bash')" "1"
check "a later notification adds its message" "$($BIN list | grep -c 'Claude needs your permission to use Bash')" "1"
echo "{\"session_id\":\"q1\",\"hook_event_name\":\"PermissionRequest\",\"tool_name\":\"AskUserQuestion\",\"cwd\":\"/x/evalify\",\"transcript_path\":\"$tr\"}" | $BIN on
check "AskUserQuestion reads as a question" "$($BIN list | grep -c 'evalify — asked you a question')" "1"
printf '{"session_id":"s9","hook_event_name":"Stop","cwd":"/x/maven","transcript_path":"%s","last_assistant_message":"Tests pass now.\\nMore detail here."}' "$tr" | $BIN on
check "finished turn shows the first line of Claude's last reply" "$($BIN list | grep -c '"Tests pass now."')" "1"
touch "$CLAUDE_BULB_DIR/oldstyle"
check "empty files from older versions still show" "$($BIN list | grep -c 'unknown session oldstyle')" "1"
check "list counts every waiting session" "$($BIN list | head -1)" "Waiting on you (4):"
touch -t 202001010000 "$CLAUDE_BULB_DIR/oldstyle"
check "entries untouched for 12 hours are removed" "$($BIN list | grep -c 'Removed 1 stale: oldstyle')" "1"
rm -f "$tr"
check "entries whose transcript is gone are removed" "$($BIN list | head -1)" "Nothing is waiting on you."
echo '{"session_id":"p1"}' | $BIN on; echo '{"session_id":"p2"}' | $BIN on; echo '{"session_id":"p1"}' | $BIN off
check "off clears only its own session" "$(ls "$CLAUDE_BULB_DIR")" "p2"
$BIN clear-all

# --- usage: tokens and cost from transcript fixtures (expected numbers worked out by hand in docs/how-it-works.md)
export CLAUDE_BULB_PROJECTS=./tests/fixtures/projects
export CLAUDE_BULB_PRICES=./prices.json
report="$($BIN usage --since 2026-01-01)"
total="$(echo "$report" | grep 'Total:')"
check "usage dedupes repeated lines of one reply (out 500+7+3+2000)" "$(echo "$total" | grep -o 'out [^ ]*')" "out 2.5k"
check "usage counts subagent files in their session (read 100k+200k)" "$(echo "$total" | grep -o 'read [^ ]*')" "read 300.0k"
check "usage prices Haiku 5.5 long prompts at the higher tier" "$(echo "$total" | grep -o '\$[0-9.]*')" "\$0.06"
check "unknown model and fast mode count as unpriced, not guessed" "$(echo "$total" | grep -o '+[0-9]* unpriced')" "+2 unpriced"
check "session is labelled by its project folder" "$(echo "$report" | grep -c '  demo:')" "1"
check "replies before --since are left out" "$(echo "$total" | grep -o 'in [^ ]*')" "in 1.0k"
CLAUDE_BULB_PRICES=/nonexistent $BIN usage --since 2026-01-01 | grep 'Total:' | grep -q '\$0.00 (+4 unpriced)'
check "missing prices.json shows tokens with every reply unpriced" "$?" "0"
$BIN usage --since not-a-date 2>/dev/null
check "bad --since date exits 2" "$?" "2"

# --- footprint: fake home folder, fake ps and launchctl output
fake="$(mktemp -d)"
mkdir -p "$fake/Library/Application Support/Claude/vm_bundles" "$fake/Library/Application Support/Claude/Cache" \
         "$fake/.claude" "$fake/Library/Caches/com.anthropic.mystery" "$fake/Library/LaunchAgents"
head -c 3000000 /dev/zero > "$fake/Library/Application Support/Claude/vm_bundles/vm.img"
head -c 1500000 /dev/zero > "$fake/Library/Application Support/Claude/Cache/c"
head -c 2000 /dev/zero > "$fake/.claude/settings.json"
head -c 2000 /dev/zero > "$fake/Library/Caches/com.anthropic.mystery/x"
touch "$fake/Library/LaunchAgents/com.anthropic.helper.plist"
fp="$(CLAUDE_BULB_HOME="$fake" CLAUDE_BULB_PS=./tests/fixtures/ps.txt CLAUDE_BULB_LAUNCHCTL=./tests/fixtures/launchctl.txt $BIN footprint)"
check "disk lists the biggest location first" "$(echo "$fp" | grep -A1 '^Disk:' | tail -1 | grep -o 'Claude app data')" "Claude app data"
check "disk shows the biggest sub-folder under it" "$(echo "$fp" | grep -A2 '^Disk:' | tail -1 | grep -o 'vm_bundles')" "vm_bundles"
check "disk finds unknown claude/anthropic folders" "$(echo "$fp" | grep -c 'Other: com.anthropic.mystery')" "1"
check "disk counts only locations that exist" "$(echo "$fp" | grep -o 'in [0-9]* locations')" "in 3 locations"
check "memory counts Claude processes and their children, not unrelated node" "$(echo "$fp" | grep -o 'in [0-9]* processes')" "in 7 processes"
check "MCP servers and shells started by Claude are grouped" "$(echo "$fp" | grep -o 'Started by Claude (MCP servers, shells) ([0-9]*)')" "Started by Claude (MCP servers, shells) (2)"
check "Claude Code inside the app folder is still Claude Code" "$(echo "$fp" | grep -o 'Claude Code (1)')" "Claude Code (1)"
check "services: only Claude/Anthropic launchd jobs" "$(echo "$fp" | grep -o 'Background services: [0-9]*')" "Background services: 4"
check "service that is loaded but idle shows not running" "$(echo "$fp" | grep -c 'Claude auto-updater (com.anthropic.claudefordesktop.ShipIt): not running')" "1"
check "plist on disk but not loaded is reported" "$(echo "$fp" | grep -c 'com.anthropic.helper: installed, not loaded')" "1"
rm -rf "$fake"

echo "passed: $pass  failed: $fail"
[ "$fail" -eq 0 ]
