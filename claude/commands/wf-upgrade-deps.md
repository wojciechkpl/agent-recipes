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

## Run state & bounded retries (uniform protocol)

This workflow is **resumable** and its gate loops are **bounded**. Maintain
`.wf/state.json` throughout the run:

1. **START.** If `.wf/state.json` exists with `"status": "in_progress"`:
   - same `workflow` → show its `phase`, `gates`, and `next`, then ask the user
     ONCE: **resume** from the recorded phase or **start over** (reset the file).
     Trust recorded gate results only if the evidence still holds (e.g. re-run
     the test command rather than assuming a phase is still green).
   - different `workflow` → warn the user and ask before overwriting.
2. **AFTER EVERY GATE** — pass or fail — rewrite the file:
   ```json
   {"workflow": "wf-upgrade-deps", "task": "<original $ARGUMENTS>",
    "phase": "<current phase>", "status": "in_progress",
    "gates": {"<PHASE>": {"result": "pass|fail", "attempts": 1,
                          "evidence": "<one line: what was actually checked>"}},
    "next": "<the next concrete action>"}
   ```
3. **ON FINISH** set `"status": "done"`. When stopping early, set
   `"status": "stopped"` plus a `"reason"`. The file is transient — safe to
   delete; suggest adding `.wf/` to the project's `.gitignore` if it isn't.
4. **AFTER ANY CONTEXT COMPACTION**, re-read `.wf/state.json` before
   dispatching anything else.

**Retry contract:** every loop in the steps above ("dispatch again", "loop until
APPROVE", re-measure cycles) is bounded to **3 attempts per phase** unless the
step names its own limit, counted in `gates.<PHASE>.attempts`. On the final
failed attempt: STOP, write `"status": "stopped"`, and report the full failure
history to the user. Never advance past a failing gate, and never loop past the
cap — a bounded honest stop beats an unbounded token burn.
