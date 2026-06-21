# Autonomous Mode (Claude Code)

A broad-but-safe permission overlay that **cuts mid-session permission prompts** so an
agent can run the dev toolchain without stopping to ask. **Opt-in, reversible, off by
default.** Even when on, a deny list still blocks catastrophic / secret-exfil operations.

- Files: `claude/settings.autonomous.json` (the profile) + `claude/autonomous-mode.sh` (the toggle)
- Applies to Claude Code only (it's a Claude permission-settings concept).

---

## Quick start

```bash
# GLOBAL — all projects (~/.claude/settings.json)
claude/autonomous-mode.sh on
claude/autonomous-mode.sh off
claude/autonomous-mode.sh status

# PROJECT — current repo only (./.claude/settings.json)
claude/autonomous-mode.sh on --project
claude/autonomous-mode.sh off --project
claude/autonomous-mode.sh status --project
```

> **Restart Claude Code after toggling.** Settings load at session start, so a change
> takes effect on your **next** session in that folder — not the current one.

---

## Three ways to turn it on

| Method | Scope | Persistence | How |
|--------|-------|-------------|-----|
| **Toggle command** (recommended) | global or per-project | persists across sessions | `claude/autonomous-mode.sh on [--project]` |
| **Launch flag** | that session only | one session | `claude --permission-mode acceptEdits` (auto-accept edits) or `claude --dangerously-skip-permissions` (skip *all* prompts — strongest, riskiest) |
| **In-session** | current session | until you change it | press **Shift+Tab** to cycle modes (default → acceptEdits → plan) |

The toggle command and the launch flag are independent — use whichever fits. The flag
needs no files and is great for a one-off; the command is best for a persistent setup.

---

## What it changes

The profile (`claude/settings.autonomous.json`) sets:

- **`defaultMode: acceptEdits`** — file edits/writes apply without a prompt.
- **A broad `allow` list** for the project dev toolchain, e.g. `git`, `gh`, `make`,
  `docker`/`docker compose`, `uv`/`pytest`/`ruff`/`alembic`, `flutter`/`dart`,
  `npx`/`npm`, `cargo`, `psql`, `gcloud`, and read-only shell utilities (`ls`, `cat`,
  `rg`, `find`, `sed`, `jq`, …).
- **A `deny` list that always wins**, even in autonomous mode:
  - `sudo`
  - catastrophic `rm -rf` of `/`, `/Users`, `/home`, `~`, `$HOME`, or `.git`
  - `git push --force` / `git push -f`
  - `mkfs`, `dd if=`
  - reading private keys: `*.pem`, `id_rsa`, `id_ed25519`

Anything not in `allow` (and not in `deny`) still prompts as normal — autonomous mode
widens the no-prompt set, it does not blindly allow everything.

---

## How it works (so you can trust it)

`on`:
1. Backs up your current settings to `…/settings.pre-autonomous.json` (once).
2. **Merges** the profile into `settings.json`: sets `defaultMode`, unions the `allow`
   and `deny` lists with anything already there. **Your other keys are preserved**
   (`model`, `statusLine`, `enabledPlugins`, `editorMode`, …).

`off`:
- Restores the exact pre-autonomous `settings.json` from the backup. (If no backup
  exists, it just removes `defaultMode` so prompts return.)

`status`: reports ON/OFF for the chosen scope.

**Settings precedence** (Claude Code merges, last wins): enterprise → user
(`~/.claude`) → project (`.claude/settings.json`) → project-local
(`.claude/settings.local.json`) → CLI flags. So a per-project `on` overrides a global
`off`, and a launch flag overrides everything for that session.

---

## Recipes

- **Trust everything everywhere:** `claude/autonomous-mode.sh on` (global), restart.
- **Trust one repo only:** from that repo, `claude/autonomous-mode.sh on --project`.
- **Just this once, no setup:** launch with `claude --permission-mode acceptEdits`.
- **Back to prompts:** `claude/autonomous-mode.sh off` (or `off --project`), restart.

---

## Safety notes

- It reduces prompts; it does **not** waive your quality gates — keep running
  tests/lint and verifying before claiming done (see `CONVENTIONS.md` §1, §9).
- The committed profile contains **no secrets**. The live `settings.local.json` and the
  `settings.pre-autonomous.json` backup may contain personal allow entries — keep them
  **gitignored** (`.claude/settings.local.json`, `.claude/settings.pre-autonomous.json`).
- Avoid `--dangerously-skip-permissions` for anything touching production or untrusted
  input — it bypasses the deny list too.

---

## Troubleshooting

- **Still getting prompts after `on`?** You didn't restart — settings load at session
  start. Restart Claude Code in that folder.
- **`status` says ON but a command still prompts?** That command isn't in the `allow`
  list (or matches `deny`). Add a pattern to `claude/settings.autonomous.json` `allow`
  and re-run `on`, or approve it once.
- **Want a clean reset?** `off` restores the backup. To wipe entirely:
  `rm ~/.claude/settings.pre-autonomous.json` (after `off`) or, per project,
  `rm ./.claude/settings.local.json`.
- **Did it clobber my settings?** No — `on` backs up first and `off` restores; your
  `model`/`statusLine`/plugin keys are preserved through the merge.

---

## Not available for Goose / Kiro

Autonomous mode is specific to Claude Code's `settings.json` permission model. Goose and
Kiro use different permission/config systems, so there is no equivalent toggle for them.
