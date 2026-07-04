---
description: "Toggle Claude Code autonomous mode (broad-but-safe permissions + guard hook) on/off/status"
argument-hint: "on | off | status  [--project]"
allowed-tools: Bash
---

# Autonomous mode

Turn the **broad-but-safe permission overlay** on or off. It sets
`defaultMode: acceptEdits`, unions a dev-toolchain allow-list + safety deny-list,
and installs a `PreToolUse` **guard hook** (`claude/hooks/guard.py`) that blocks
secret-exfil, catastrophic recursive deletes, force-push, and RCE pipes even when
the allow-list would otherwise let a `bash`/`sh` command through.

**Requested action:** `$ARGUMENTS` (default: `status`)

Run the toggle for the requested action, then report the result verbatim. Default
to `status` if no action was given. Pass `--project` straight through when present.

```bash
claude/autonomous-mode.sh ${ARGUMENTS:-status}
```

Reminders to surface to the user:
- Changes take effect on the **next** Claude Code session (settings load at start) —
  tell them to restart.
- The guard hook is referenced by **absolute path**; if this repo is moved, re-run
  `on` to refresh it.
- `on` is safe to re-run — it re-syncs the profile without clobbering the
  `settings.pre-autonomous.json` backup; `off` restores that backup exactly.
