---
description: "Cross-device sync of agent memory and user CLAUDE.md through a private git repo"
argument-hint: "init <git-url> | status | pull | push | off"
allowed-tools: Bash
---

# Sync state

Keep `~/.claude/agent-memory/` and `~/.claude/CLAUDE.md` in a **private** git
repository so they follow the user across devices. Nothing is synced until `init` has
been run on a device; after that the plugin's SessionStart / SessionEnd hooks pull and
push automatically.

**Requested action:** `$ARGUMENTS` (default: `status`)

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/state-sync.sh" $ARGUMENTS
```

Run the line exactly as it appears and report the output verbatim.

Before running `init`:
- Confirm with the user that the repository is **private** and that they intend to
  store agent memory there. Do not create a repository for them unless asked.
- `init` moves the existing `agent-memory/` and `CLAUDE.md` into `~/.claude-state/`
  and leaves symlinks behind. `off` reverses that and stops the hooks on this device.

If `init` fails with an authentication error, git could not reach the repository
without prompting (hooks and this command never prompt). Tell the user to check that
`git ls-remote <git-url>` works in their own terminal, then retry.

Never synced: `settings*.json`, credentials, `plugins/`, `projects/`. Files that look
like secrets are held back; `status` lists them.
