# claude-bulb 💡

A tiny macOS menu bar light for [Claude Code](https://code.claude.com).
When Claude is **waiting for you** (a permission prompt, a question, or a finished turn),
the bulb next to your clock **blinks red** and plays a sound every 30 seconds.
When you answer, it goes calm.

![claude-bulb going from calm to blinking red and back](docs/demo.gif)

<sub>The bulb's states, drawn with the same SF Symbols and colours the app uses (an illustration, not a screen recording).</sub>

No dependencies beyond Apple's own tools. About 150 lines of Swift, Bash and Python.

```
 calm:     💡 (outline, follows light/dark menu bar)
 waiting:  🔴 blinking red bulb + "Glass" sound every 30 s
```

## Requirements

- macOS 12 (Monterey) or newer, Apple Silicon or Intel
- Apple Command Line Tools (gives `swiftc` and `python3`):
  ```bash
  xcode-select --install
  ```
- Claude Code (CLI or desktop app)

## Install

```bash
git clone https://github.com/swathikchgithub/claude-bulb.git ~/tools/claude-bulb
~/tools/claude-bulb/install.sh
```

You can clone it anywhere; the hooks point at wherever the repo lives.
If you move the folder later, run `install.sh` again.

`install.sh` does four things:

1. Builds `bin/claude-bulb` from `Sources/` with `swiftc`.
2. Runs `test.sh`.
3. Installs a LaunchAgent (`~/Library/LaunchAgents/local.claude-bulb.plist`) so the bulb
   starts now and at every login.
4. Adds the hooks to `~/.claude/settings.json` (global, all projects).
   A timestamped backup of that file is written first. Your other hooks are left alone.

Then **restart any Claude Code sessions** that were already open, so they load the hooks.

## Use

Nothing to do. Work with Claude as usual. The bulb lights up when Claude needs you.

Click the bulb for its menu:

| Menu item | What it does |
|---|---|
| Mute sound | Keep blinking, stop the sound (until the app restarts) |
| Clear now | Turn the bulb off for all sessions |
| Quit Claude Bulb | Stop the app until next login |

### When does it light up?

| Claude Code hook | Bulb |
|---|---|
| `PermissionRequest` (Claude asks to use a tool) | red |
| `Notification`: `permission_prompt`, `idle_prompt`, `elicitation_dialog` | red |
| `Stop` (Claude finished its turn) | red |
| `UserPromptSubmit`, `PostToolUse`, `PostToolUseFailure`, `SessionEnd` | calm |

Each Claude session is tracked separately, so with two sessions open,
answering one does not hide the other.

## Try it by hand

```bash
echo '{"session_id":"manual-test"}' | ~/tools/claude-bulb/bin/claude-bulb on
```
```bash
echo '{"session_id":"manual-test"}' | ~/tools/claude-bulb/bin/claude-bulb off
```

## Uninstall

```bash
~/tools/claude-bulb/uninstall.sh
```
```bash
rm -rf ~/tools/claude-bulb
```

`uninstall.sh` stops the app, removes the LaunchAgent, removes only the claude-bulb hooks
from `~/.claude/settings.json` (backup first) and deletes `~/.claude-bulb/`.

## Docs

- [How it works](docs/how-it-works.md): the design, file by file
- [Customize](docs/customize.md): change the sound, interval or triggers
- [Troubleshooting](docs/troubleshooting.md)

## License

[MIT](LICENSE)
