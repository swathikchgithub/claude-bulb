# Customize

After any change, run `./install.sh` again (it rebuilds, re-tests, restarts the app
and rewrites the hooks).

## Sound

In `Sources/BulbApp.swift`:

```swift
private let soundEvery: TimeInterval = 30          // seconds between repeats
...
if !muted { NSSound(named: "Glass")?.play() }      // sound name
```

Any file name from `/System/Library/Sounds` works without the extension:
Basso, Blow, Bottle, Frog, Funk, Glass, Hero, Morse, Ping, Pop, Purr, Sosumi, Submarine, Tink.
Preview one with `afplay /System/Library/Sounds/Ping.aiff`.

For a single sound with no repeat, set `soundEvery` to a very large number, e.g. `86_400`.

## Which events light the bulb

In `hooks.py`, edit `BULB_HOOKS`:

```python
BULB_HOOKS = {
    "PermissionRequest": (None, "on"),
    "Notification": ("permission_prompt|idle_prompt|elicitation_dialog", "on"),
    "Stop": (None, "on"),
    "UserPromptSubmit": (None, "off"),
    ...
}
```

Example: to stop lighting up every time a turn finishes, delete the `"Stop"` line.
The other `on` events still catch prompts and questions.

Hook event names and Notification types are listed in the
[Claude Code hooks docs](https://code.claude.com/docs/en/hooks).

## Blink speed

In `Sources/BulbApp.swift`, the timer interval (`withTimeInterval: 0.5`) controls both
how fast it blinks and how quickly it notices a change.
