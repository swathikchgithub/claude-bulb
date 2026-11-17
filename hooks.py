#!/usr/bin/env python3
"""Add or remove the claude-bulb hooks in ~/.claude/settings.json.

usage: hooks.py add | remove
Every hook we own has 'claude-bulb' in its command, so 'remove' deletes exactly
those and leaves your other hooks alone. A timestamped backup is written first.
"""
import json, os, shutil, sys, time

SETTINGS = os.path.expanduser("~/.claude/settings.json")
# The binary lives next to this script, so the repo can be cloned anywhere.
BIN = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bin", "claude-bulb")
MARK = "claude-bulb"

# event -> (matcher or None, action)
BULB_HOOKS = {
    "PermissionRequest": (None, "on"),
    "Notification": ("permission_prompt|idle_prompt|elicitation_dialog", "on"),
    "Stop": (None, "on"),
    "UserPromptSubmit": (None, "off"),
    "PostToolUse": (None, "off"),
    "PostToolUseFailure": (None, "off"),
    "SessionEnd": (None, "off"),
}


def is_ours(group):
    return any(MARK in h.get("command", "") for h in group.get("hooks", []))


def remove(hooks):
    for event in list(hooks):
        hooks[event] = [g for g in hooks[event] if not is_ours(g)]
        if not hooks[event]:
            del hooks[event]


def add(hooks):
    remove(hooks)  # idempotent: never add twice
    for event, (matcher, action) in BULB_HOOKS.items():
        group = {"hooks": [{"type": "command", "command": f"{BIN} {action}", "timeout": 5}]}
        if matcher:
            group["matcher"] = matcher
        hooks.setdefault(event, []).append(group)


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in ("add", "remove"):
        sys.exit(__doc__)
    action = sys.argv[1]
    settings = {}
    if os.path.exists(SETTINGS):
        backup = f"{SETTINGS}.bak-claude-bulb-{time.strftime('%Y%m%d-%H%M%S')}"
        shutil.copy2(SETTINGS, backup)
        print(f"backup: {backup}")
        with open(SETTINGS) as f:
            settings = json.load(f)
    hooks = settings.setdefault("hooks", {})
    add(hooks) if action == "add" else remove(hooks)
    if not hooks:
        del settings["hooks"]
    with open(SETTINGS, "w") as f:
        json.dump(settings, f, indent=2)
        f.write("\n")
    print(f"claude-bulb hooks: {action} done in {SETTINGS}")


if __name__ == "__main__":
    main()
