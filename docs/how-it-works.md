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
| `Sources/main.swift` | Entry point. With an argument (`on`, `off`, `clear-all`) it acts as a hook; with none it starts the menu bar app. |
| `Sources/BulbStore.swift` | Owns the state folder: create, delete and list session files. Rejects unsafe session ids (path traversal). |
| `Sources/HookCommand.swift` | Parses the hook JSON and calls BulbStore. Always exits 0 on bad input so it can never break Claude Code. |
| `Sources/BulbApp.swift` | `NSStatusItem` in the menu bar: SF Symbol `lightbulb`, red blink, `Glass` sound every 30 s, menu. |
| `build.sh` | `swiftc -O Sources/*.swift -o bin/claude-bulb` |
| `test.sh` | Tests the hook side against a temporary state folder (`CLAUDE_BULB_DIR`). |
| `hooks.py` | Adds or removes the claude-bulb hooks in `~/.claude/settings.json`, with a backup. Identifies its own hooks by `claude-bulb` in the command. |
| `install.sh` / `uninstall.sh` | Build, test, LaunchAgent, hooks / the reverse. |

## Cost

- Hook call: one short process, a few milliseconds, creates or deletes one empty file.
- App: one directory listing every 0.5 s. Time O(n) where n = waiting sessions (usually 0 to 3).

## Environment variable

`CLAUDE_BULB_DIR` overrides the state folder (default `~/.claude-bulb/state`).
`test.sh` uses it so tests never touch your real state.
