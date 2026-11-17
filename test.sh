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

echo "passed: $pass  failed: $fail"
[ "$fail" -eq 0 ]
