---
description: "Toggle Claude Code autonomous mode (broad-but-safe permissions + guard hook) on/off/status"
argument-hint: "on | off | status  [--project]"
allowed-tools: Bash
---

# Autonomous mode

Turn the **broad-but-safe permission overlay** on or off. It sets
`defaultMode: acceptEdits`, unions a dev-toolchain allow-list + safety deny-list,
and relies on the plugin's `PreToolUse` **guard hook** (`hooks/guard.sh` →
`hooks/guard.py`, wired by `hooks/hooks.json`) to block secret-exfil, catastrophic
recursive deletes, force-push, and RCE pipes even when the allow-list would
otherwise let a `bash`/`sh` command through.

**Requested action:** `$ARGUMENTS` (default: `status`)

Run the toggle for the requested action, then report the result verbatim. Default
to `status` if no action was given. Pass `--project` straight through when present.

```bash
CLAUDE_PLUGIN_OPTION_GUARD_MODE='${user_config.guard_mode}' \
bash "${CLAUDE_PLUGIN_ROOT}/autonomous-mode.sh" $ARGUMENTS --plugin
```

Claude Code fills in the `${...}` placeholders when this command is loaded from the
plugin, so run it exactly as it appears — an option that was never set stays as
literal text, which the script treats as "not set". With no action the toggle reports
`status`.

Reminders to surface to the user:
- Changes take effect on the **next** Claude Code session (settings load at start) —
  tell them to restart.
- The guard ships with the plugin (option `guard_mode`: `auto` | `always` | `off`,
  default `auto`). Turn autonomous mode **off before** disabling or uninstalling the
  plugin — otherwise the broad permissions stay while the guard is gone.
- `on` is safe to re-run — it re-syncs the profile without clobbering the
  `settings.pre-autonomous.json` backup; `off` restores that backup exactly.
