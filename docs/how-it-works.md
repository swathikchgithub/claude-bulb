# How it works

## The big picture

```
Claude Code ──hook──► claude-bulb on|off ──► ~/.claude-bulb/state/<session_id>
                                                        │
             menu bar app (same binary, no arguments) ──┘ checks the folder every 0.5 s
                any file present → blink red + sound      empty → calm
```

Two moving parts talk through a folder, nothing else:

1. **Claude Code hooks** run a command when something happens (a permission prompt,
   a finished turn, a new prompt). The command is `claude-bulb on` or `claude-bulb off`.
   Claude Code passes a JSON object on stdin; we read only `session_id`.
2. **The menu bar app** looks at the state folder twice a second and draws the bulb.

Why a folder and not a socket or a server? It is the simplest thing that works:
no open ports, no process that must be running for hooks to succeed, and it survives
the app restarting. If the app is not running, hooks still work; the bulb just isn't shown.

Why one file per session? With a single on/off flag, answering session A would turn the
bulb off even though session B is still waiting.

## Files

| File | Job |
|---|---|
| `Sources/main.swift` | Entry point. With `on`, `off` or `clear-all` it acts as a hook; `usage` prints the report; with none it starts the menu bar app. |
| `Sources/BulbStore.swift` | Owns the state folder: create, read, delete and prune session files. Rejects unsafe session ids (path traversal). |
| `Sources/WaitingList.swift` / `Sources/WaitingMenuSection.swift` | The "Waiting on you" lines, for `claude-bulb list` and the top of the menu. |
| `Sources/HookCommand.swift` | Parses the hook JSON, works out the reason (tool, question, finished turn), and calls BulbStore. Always exits 0 on bad input so it can never break Claude Code. |
| `Sources/BulbApp.swift` | `NSStatusItem` in the menu bar: SF Symbol `lightbulb`, red blink, `Glass` sound every 30 s, menu with today's usage. |
| `Sources/TokenUsage.swift` | The four token meters (input, cache write 5m/1h, cache read, output) and how to add them. |
| `Sources/UsageReader.swift` | Reads transcripts in `~/.claude/projects` (subagent files count toward their session). Files in, replies out. |
| `Sources/Pricing.swift` | Loads `prices.json` and turns tokens into dollars, with Haiku 5.5's long-prompt tier. Unknown model gives no price. |
| `Sources/UsageReport.swift` | Dedupes replies by message id, sums per session and in total, formats the lines. |
| `prices.json` | USD per million tokens per model, copied from Anthropic's pricing page. |
| `Sources/DiskScanner.swift` | Known Claude locations plus discovery by name; sizes as allocated on disk. Never follows symlinks. |
| `Sources/ProcessScanner.swift` | Parses `ps`; a process counts if it runs from a Claude install, and so does everything it started. |
| `Sources/ServiceScanner.swift` | Parses `launchctl list` and the LaunchAgents/LaunchDaemons folders. |
| `Sources/FootprintReport.swift` | Totals and lines for the menu and `claude-bulb footprint`. |
| `Sources/FootprintMenu.swift` | The submenu: memory and services on every open, disk at most every 10 minutes. |
| `Sources/Shell.swift` | Runs `/bin/ps` and `/bin/launchctl` directly, never through a shell. |
| `build.sh` | `swiftc -O Sources/*.swift -o bin/claude-bulb` |
| `test.sh` | Tests the hook side against a temporary state folder (`CLAUDE_BULB_DIR`), and the usage report against `tests/fixtures`. |
| `hooks.py` | Adds or removes the claude-bulb hooks in `~/.claude/settings.json`, with a backup. Identifies its own hooks by `claude-bulb` in the command. |
| `install.sh` / `uninstall.sh` | Build, test, LaunchAgent, hooks / the reverse. |

## Cost

- Hook call: one short process, a few milliseconds, creates or deletes one empty file.
- App: one directory listing every 0.5 s. Time O(n) where n = waiting sessions (usually 0 to 3).
- Usage: only when the menu opens, on a background thread. Time O(L) over the lines of transcripts
  touched today. About 0.7 s for 9 million tokens of transcripts. The blink timer never waits for it.
- Footprint: `ps` and `launchctl` on every menu open (milliseconds). The disk walk takes about 3 s for
  18 GB, on a background thread, at most every 10 minutes. Process grouping is one pass over a
  parent-to-children map: time O(P), space O(P) for P processes.

## How usage is counted

1. Find every `*.jsonl` under `~/.claude/projects` changed since midnight. `<session>/subagents/*.jsonl`
   belongs to `<session>`.
2. Keep lines with `message.usage`, a real model (not `<synthetic>`) and a `timestamp` since midnight.
3. **Dedupe by `message.id`.** Claude Code writes one reply on several lines with the same usage;
   adding every line would count it two or three times.
4. Price each reply on its own: tokens × the model's rate in `prices.json` ÷ 1,000,000.
   Haiku 5.5 uses its higher rates when that reply's prompt (input + cache writes + cache reads) is over 100,000 tokens.

Worked example from `tests/fixtures` (what `test.sh` checks):

| Reply | Model | Tokens | Cost |
|---|---|---|---|
| `msg_a` (on 2 lines) | Opus 5.5 | in 1,000 · write 2,000 · read 100,000 · out 500 | (1000×4 + 2000×5 + 100000×0.20 + 500×20) / 1M = $0.044 |
| `msg_d` (subagent) | Haiku 5.5, prompt 200,000 > 100,000 | read 200,000 · out 2,000 | (200000×0.05 + 2000×2.50) / 1M = $0.015 |
| `msg_b` | unknown model | out 7 | unpriced |
| `msg_e` | Opus 5.5, fast mode | out 3 | unpriced |

Total: out 2,510 ("2.5k"), $0.059 ("$0.06"), 2 unpriced. Without dedupe, out would be 3,010.

## Environment variables

| Variable | Default | Used for |
|---|---|---|
| `CLAUDE_BULB_DIR` | `~/.claude-bulb/state` | Waiting-session files |
| `CLAUDE_BULB_PROJECTS` | `$CLAUDE_CONFIG_DIR/projects`, else `~/.claude/projects` | Transcripts to read |
| `CLAUDE_BULB_PRICES` | `prices.json` next to `bin/` | Price table |
| `CLAUDE_BULB_HOME` | your home folder and `/` | Where the footprint looks (tests use a fake folder) |
| `CLAUDE_BULB_PS` / `CLAUDE_BULB_LAUNCHCTL` | run the real command | A file whose text stands in for `ps` / `launchctl` output |

`test.sh` sets these so tests never touch your real files.

## The state file

`~/.claude-bulb/state/<session_id>` holds a few hundred bytes of JSON (empty files from older
versions still count; they show as "unknown session"):

```json
{"project":"orca-platform","reason":"needs permission: Bash",
 "message":"Claude needs your permission to use Bash",
 "since":"2026-11-18T17:00:00Z","transcriptPath":"/Users/you/.claude/projects/.../<session_id>.jsonl"}
```

- A later `Notification` for the same session keeps the more specific reason and adds its message.
- `since` is kept from the first event, so "3 min ago" means how long Claude has been waiting.
- Stale: the file's modification time is over 12 hours old, or `transcriptPath` no longer exists.
  The app prunes every 30 seconds and when the menu opens; `claude-bulb list` prunes first.

