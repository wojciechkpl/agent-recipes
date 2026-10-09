---
description: "Cross-device sync of agent memory and user instructions (Claude Code, Goose, Hermes, Codex) through a private git repo"
argument-hint: "init [git-url] | status | pull | push | off | config [dir=… remote=… tools=… auto_memory=yes|no]"
allowed-tools: Bash
---

# Sync state

Keep agent memory and the user's instruction file in a **private** git repository (the
state store, default `~/.agent-state`) so they follow the user across devices — and
across tools: Claude Code's agent memory, per-project auto memory and `CLAUDE.md`;
Goose's memory and `.goosehints`; Hermes' memories; Codex's `AGENTS.md`. Every tool's
own instruction file is a link to one shared `INSTRUCTIONS.md`. Nothing is synced until
`init` has been run on a device; after that the plugin's SessionStart / SessionEnd
hooks pull and push automatically.

**Requested action:** `$ARGUMENTS` (default: `status`)

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/state-sync.sh" $ARGUMENTS
```

Run the line exactly as it appears and report the output verbatim.

`config` shows or writes `~/.config/agent-recipes/state.conf` — where the store lives
(`dir=`), which remote syncs it (`remote=`, empty = this machine only), which tools are
included (`tools="claude goose hermes codex"`, default: detected) and whether Claude's
per-project auto memory joins (`auto_memory=yes|no`). The hooks and this command read
the same file. `init` with no URL uses the configured remote; with neither, the store is
local-only (history, no network).

Before running `init`:
- Confirm with the user that the repository is **private** and that they intend to
  store agent memory there. Do not create a repository for them unless asked.
- `init` moves the existing memory and instruction files into the store and leaves
  symlinks behind; a differing `.goosehints` or `AGENTS.md` is folded into
  `INSTRUCTIONS.md` under a `## From <tool>` heading, originals backed up under
  `~/.claude/.state-sync-backup/`. `off` reverses the links and stops the hooks on this
  device.

If `init` fails with an authentication error, git could not reach the repository
without prompting (hooks and this command never prompt). Tell the user to check that
`git ls-remote <git-url>` works in their own terminal, then retry.

Never synced: settings, credentials, sessions and transcripts, Codex's own memory
store. Files that look like secrets are held back; `status` lists them, and warns when a
Hermes memory file has grown past the size Hermes accepts.
