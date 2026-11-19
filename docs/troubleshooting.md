# Troubleshooting

## I don't see the bulb

- Is it running?
  ```bash
  launchctl print gui/$(id -u)/local.claude-bulb | grep state
  ```
  If not, start it: `launchctl kickstart gui/$(id -u)/local.claude-bulb`
- A crowded menu bar can hide items behind the notch on MacBooks.
  Quit a few menu bar apps, or hold ⌘ and drag icons to make room.

## The bulb never turns red

- Restart your Claude Code sessions; hooks load when a session starts.
- Check the hooks are there:
  ```bash
  grep -c claude-bulb ~/.claude/settings.json
  ```
  Should print a number above 0. If 0, run `./install.sh` again.
- Test by hand (see README "Try it by hand"). If that works, the hooks are the issue.

## The bulb stays red

- Something left a state file behind (for example Claude Code crashed before `SessionEnd`).
  Click the bulb → **Clear now**, or:
  ```bash
  ~/tools/claude-bulb/bin/claude-bulb clear-all
  ```
- After you approve a long-running command, the bulb stays red until that command
  finishes, because the next "calm" hook (`PostToolUse`) fires only then.

## No sound

- Check "Mute sound" is not ticked in the bulb's menu.
- Check system volume and that alert sounds are not muted in System Settings → Sound.

## I moved the folder

The hooks contain the full path to `bin/claude-bulb`. Run `install.sh` from the new location.

## Restore my settings.json

Every change writes a backup next to it:
```bash
ls ~/.claude/settings.json.bak-claude-bulb-*
```
Copy the one you want back over `~/.claude/settings.json`.

## The bulb disappeared after a rebuild

`launchctl print gui/$(id -u)/local.claude-bulb` shows `last exit reason = OS_REASON_CODESIGNING`.
macOS kills a signed binary that was overwritten in place. `build.sh` avoids this by building
`bin/claude-bulb.new`, signing it and moving it over the old file. If you build by hand, do the same,
then restart:

```bash
launchctl kickstart -k gui/$(id -u)/local.claude-bulb
```
