# Autonomous Mode (Claude Code)

A broad-but-safe permission overlay that **cuts mid-session permission prompts** so an
agent can run the dev toolchain without stopping to ask. **Opt-in, reversible, off by
default.** Even when on, a deny list **and a `PreToolUse` guard hook** block catastrophic
/ secret-exfil operations.

- Files: `claude/settings.autonomous.json` (the profile) + `claude/autonomous-mode.sh`
  (the toggle) + `claude/hooks/guard.sh` → `claude/hooks/guard.py` (the guard hook — the
  real safety net; guard.sh is a fast pre-filter, guard.py decides).
- Applies to Claude Code only (it's a Claude permission-settings concept).
- **Plugin installs** get the guard from the plugin's own `hooks/hooks.json`, on every
  session, whether or not autonomous mode is on — see
  [Plugin installs vs clone installs](#plugin-installs-vs-clone-installs).

> **Why a hook, not just a deny-list?** Autonomous mode allows `bash`/`sh`, so the
> granular allow-list is effectively advisory — anything can run via `bash -c '…'`. That
> makes the **deny side** the real boundary, and string-prefix deny patterns can't reason
> about a shell command: `rm -fr /` (flag order), `cat ~/.ssh/id_rsa` (Bash bypasses the
> `Read(**/*.pem)` deny), `find . -delete`, `git reset --hard`. The guard hook inspects
> the **actual command** and blocks these regardless of phrasing.

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

## Plugin installs vs clone installs

| | Plugin (`/plugin install agent-recipes@agent-recipes`) | Clone (`claude/autonomous-mode.sh` from a checkout) |
|---|---|---|
| Where the guard runs | `hooks/hooks.json` inside the plugin, `guard.sh plugin` — path follows plugin updates | an **absolute path** to `claude/hooks/guard.sh` written into `settings.json` by `on` |
| When it runs | every session, from install | only while autonomous mode is on |
| Toggle | `/autonomous-mode on\|off\|status [--project]` (runs the script with `--plugin`: merges permissions only, writes no hook, removes a legacy absolute-path entry) | `claude/autonomous-mode.sh on\|off\|status [--project]` |
| Mode | option `guard_mode` (below) | always enforce |

**`guard_mode`** (plugin option, `/plugin configure agent-recipes@agent-recipes`, restart after):

| `guard_mode` | Session asks before running commands (`default`, `plan`) | Session runs commands without asking (`acceptEdits`, `auto`, `dontAsk`, `bypassPermissions`) |
|---|---|---|
| `auto` (default) | a permission prompt with the guard's reason — even if an allow rule would have let the command through | **blocked** |
| `always` | blocked | blocked |
| `off` | not checked | not checked |

A payload without a permission mode is blocked (fail safe); an unknown value behaves as
`always`. The legacy entrypoint (no argument, as written into `settings.json` by a clone
install) ignores the option and always enforces, so older installs never get weaker.

> **Turn autonomous mode off before disabling or uninstalling the plugin.** The broad
> permissions live in your `settings.json`; the guard lives in the plugin. Removing the
> plugin first leaves the permissions without the guard. `/autonomous-mode on` and the
> toggle print this reminder.

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
- **A `deny` list that always wins** (defense-in-depth): `sudo`, catastrophic `rm -rf` of
  `/`, `/Users`, `/home`, `~`, `$HOME`, `.git`, `git push --force`/`-f`, `mkfs`, `dd if=`,
  and reading private keys (`*.pem`, `id_rsa`, `id_ed25519`).
- **A `PreToolUse` guard hook** (`claude/hooks/guard.sh`) — the enforcement that actually
  holds, because it reads the command instead of matching a prefix. It blocks:
  - secret/private-key reads via **any** shell reader (`cat`/`grep`/`sed`/`base64`/`scp`…
    of `*.pem`, `id_rsa`, `~/.ssh`, `.env`) — closes the `Bash(cat secret.pem)` bypass
  - **any other command that names a secret file** — decided per shell word, so
    `jq -R . ~/.aws/credentials`, `sort .env`, `git diff --no-index /dev/null .env`,
    `tar czf k.tgz ~/.ssh`, a `< .env` redirection, and a `python3 -c "…('.env')…"`
    one-liner are blocked, and `.env.example` exempts only itself (`cat .env .env.example`
    blocks). A read hidden in a command substitution or a wrapper (`echo "$(< .env)"`,
    `bash -c 'sort .env'`, `curl -d @.env`) is still a read. Commands that only touch
    metadata or write to the file stay allowed: `ls`, `stat`, `test`/`[`/`[[`, `find`,
    `touch`, `mkdir`, `chmod`, `chown`, `rm`, `echo`, `printf`, `source`/`.`, `export`,
    `git add|commit|status|check-ignore|rm|mv|log|ls-files`, an output redirection
    (`openssl rand -hex 32 > .env`), a plain assignment (`F=.env`), and `cp`/`mv`/`ln`
    whose destination is the secret (`cp .env.example .env`, `mv .env .env.bak`). The
    verdict table is `tests/test_guard_secrets.sh`.
  - recursive deletes of protected roots regardless of flag order (`rm -fr /`, `rm … ~`,
    `rm -rf .`), plus `find -delete` / `find -exec rm`
  - `mkfs`, `dd of=/dev/…`, `curl … | bash` (remote-code-execution), `sudo`, fork bombs
  - history/work destroyers: `git push --force`/`-f`/`+refspec`, `git reset --hard`,
    `git clean -fd`/`-fdx` — while **allowing** the safe `git push --force-with-lease`

Anything not in `allow` (and not in `deny`) still prompts as normal — autonomous mode
widens the no-prompt set, it does not blindly allow everything. In a clone install the
guard hook is referenced by **absolute path**, so keep this repo in place (or re-run `on`
after moving it); a plugin install needs nothing. Tune what it blocks by editing `claude/hooks/guard.py`; if you add a rule, add a
matching token to `TRIGGERS` in `claude/hooks/guard.sh` too. Verify with
`tests/test_autonomous_mode.sh`, `tests/test_guard_secrets.sh` and `tests/test_plugin_guard.sh`.

**Known limits of the secret rule** (documented rather than chased — the guard is a
seatbelt; real isolation is a container, a VM or a separate OS user):

- `env` / `printenv` after `source .env`, and programs that read `.env` on their own
  (`docker compose`, `dotenv`, test runners) are not seen as reads.
- Globbing (`cat .e*`), and a file name assembled at run time.
- Some commands that merely *name* a secret file are now stopped although they do not
  read it — `docker compose --env-file .env up`, `vim .env`, `jq .env settings.json`. In
  `guard_mode: auto` a prompting session (`default`, `plan`) gets a **permission
  question** with the reason rather than a block, so a false positive costs one click;
  in a non-prompting session run the command yourself (`! command` in the prompt).

**Why two files?** The hook runs on every Bash and Read call, and starting Python costs
~16 ms whatever the verdict. `guard.sh` answers "could this payload trip any rule at
all?" with a single `grep` (~4 ms) and exits early when it cannot — on a real 8k-command
corpus that skips Python on 90.5% of calls, ~3.2x faster overall. `guard.py` remains the
only thing that decides what is blocked; the pre-filter may only skip work, never change
a verdict, and the test suite asserts the two always agree.

---

## How it works (so you can trust it)

`on`:
1. Backs up your current settings to `…/settings.pre-autonomous.json` — **once** (a
   repeat `on` re-syncs the profile without clobbering the backup).
2. **Merges** the profile into `settings.json`: sets `defaultMode`, unions the `allow`
   and `deny` lists, and installs the guard hook (substituting `__GUARD__` in the profile
   with the absolute path to `claude/hooks/guard.sh`, idempotently — no duplicate on
   re-sync, and an older guard.py install is upgraded in place). With `--plugin` (what
   `/autonomous-mode` passes) no hook is written and a legacy entry is removed — the
   plugin's `hooks.json` is the guard. **Your other keys are preserved** (`model`,
   `statusLine`, `enabledPlugins`, `editorMode`, …).

`off`:
- Restores the exact pre-autonomous `settings.json` from the backup. (If no backup
  exists, it removes `defaultMode` **and** strips the guard hook so prompts return.)

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
  input — it bypasses the deny list too. The guard **hook** still runs and still blocks
  (exit 2) in that mode; it is the only part of autonomous mode that does.

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
