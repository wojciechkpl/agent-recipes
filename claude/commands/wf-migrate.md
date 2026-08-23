---
description: "Large-scale codemod: discover sites → transform each in isolation → verify per-site → review"
argument-hint: "<the migration, e.g. 'rename API getUser() -> fetchUser()'>"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent
---

# Workflow: Migrate / Codemod

**Migration:** $ARGUMENTS

You are the **orchestrator**. A migration touches many sites; the risks are *missing*
a site and *conflicting* edits. So: enumerate every site explicitly, transform each in
isolation, verify per-site, and never silently skip. You dispatch specialists and own
the gates.

## Subagents you will dispatch
- `analyst` — discover and enumerate every affected site (read-only).
- a matching language expert (`python-expert`, `typescript-expert`, etc.) — apply the
  transform. Use **worktree isolation** so parallel transforms don't conflict.
- `code-reviewer` — review the consolidated change.

## Steps
1. **DISCOVER.** Use `grep`/`glob` and dispatch `analyst` to produce the **complete
   list of affected sites** (file:line) plus any tricky variants the naive search
   misses (aliases, re-exports, dynamic uses). **You (the orchestrator) capture the
   returned list to `.wf/migration-sites.md`** — the analyst is read-only.
   **GATE:** establish a green test baseline first. If the suite errors for a
   toolchain reason (not a real failure), stop and report; if it's legitimately not
   green, stop — you can't distinguish migration breakage from pre-existing breakage.
2. **PLAN.** Define the exact transformation rule and the order. Decide automatable
   (mechanical) vs. manual sites. State the rollback (git checkpoint).
3. **TRANSFORM.** For each site (or batch), dispatch the `{lang}-expert` to apply the
   rule. **By default run sequentially** against the working tree (protected by the
   step-2 checkpoint). **To parallelize independent batches, dispatch with
   `isolation: worktree`** so edits don't conflict, then **collect each worktree's diff
   and apply them back to the main tree — resolving any overlaps — before VERIFY.**
   Mechanical sites can be scripted; non-trivial ones get individual attention.
4. **VERIFY.** Run the test suite (per batch and at the end).
   **GATE:** all green. Any breakage → fix or revert that site; do not proceed on red.
5. **REVIEW.** Dispatch `code-reviewer` on the full diff for correctness and missed/
   incorrect sites.
6. **REPORT.** Sites transformed vs. **deferred/skipped (with reasons)** — never let a
   bounded migration read as complete when it isn't. Include the final green test run.

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
   {"workflow": "wf-migrate", "task": "<original $ARGUMENTS>",
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
