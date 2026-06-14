---
description: "Guarded dependency upgrade: audit → upgrade one at a time → test → revert-on-break → review"
argument-hint: "[specific dependency, default = all outdated/vulnerable]"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent
---

# Workflow: Upgrade Dependencies

**Scope:** $ARGUMENTS  *(if empty, all outdated/vulnerable dependencies)*

You are the **orchestrator**. Dependency upgrades break things — so upgrade **one at
a time** behind the test suite, and revert any single bump that breaks. You do NOT
edit code yourself; you dispatch specialists and own the gates.

## Subagents you will dispatch
- `dependency-auditor` — list outdated/vulnerable deps, prioritized by risk.
- a matching language expert (`python-expert`, `typescript-expert`, etc.) — apply each
  bump and fix the resulting breakage.
- `code-reviewer` — review the net change.

## Steps
1. **AUDIT.** Dispatch `dependency-auditor` to produce a prioritized list (security
   🔴 first, then outdated). Confirm a runnable test command exists; run it once to
   establish a green baseline. **GATE:** if the baseline isn't green, stop — fix the
   suite before upgrading (you can't tell an upgrade break from a pre-existing one).
2. **PER DEPENDENCY (loop, highest-risk first).** For each dep in scope:
   a. **CHECKPOINT the manifest + lockfile** (`git stash`/commit, or save the manifest
      and lockfile) — a bump mutates the lockfile and transitive tree, so a revert must
      restore those, not just source files.
   b. Dispatch the `{lang}-expert` to bump **only that one** dependency (and pinned
      transitives if required) and fix any resulting breakage — no unrelated changes.
   c. Run the full suite. **GATE:** green → keep and move on. Broken and unfixable
      within reason → **revert the manifest + lockfile to the checkpoint and
      reinstall**, record it as *deferred (breaking)*, and continue with the next.
3. **REVIEW.** Dispatch `code-reviewer` on the cumulative diff (lockfile + any code
   adaptations).
4. **REPORT.** A table: each dep → old→new version, kept/deferred, and why. List the
   security 🔴s this cleared and any deferred breaking upgrades that need follow-up.
   Never report "upgraded" for a dep whose suite you did not see go green.

## Asana sync (optional)
If an Asana project is configured, dispatch the `asana-sync` subrecipe to reflect this
run on the relevant Asana task — typically `start`, a `comment` at each gate/finding, and
`done` (with links) on completion, or `blocked` if a gate stops it. Best-effort and
non-blocking: a silent no-op if Asana isn't configured or reachable.
