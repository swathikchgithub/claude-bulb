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

echo "passed: $pass  failed: $fail"
[ "$fail" -eq 0 ]
