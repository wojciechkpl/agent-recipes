---
description: "Schema change with a safe migration: design (+rollback) → safety gate → test on scratch DB → review"
argument-hint: "<schema change, e.g. 'add index on orders(user_id)'>"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent
---

# Workflow: Database Change

**Change:** $ARGUMENTS

You are the **orchestrator**. A schema change can lock tables, lose data, or be
impossible to undo — so it ships with a tested rollback and a locking-impact
assessment, never blindly. You dispatch specialists and own the gates.

## Subagents you will dispatch
- `postgresql-expert` — design the forward + rollback migration and assess impact.
- `test-architect` — tests for the migration and any data-integrity invariants.
- a matching language expert — application/ORM-side changes, if the schema change
  requires them.
- `code-reviewer` — review migration + code together.

## Steps
1. **DESIGN.** Dispatch `postgresql-expert` to write the **forward migration AND a
   matching rollback**, plus an impact note: locks taken, table size sensitivity,
   downtime, and whether a backfill is needed. Persist to `.wf/db-change.md`.
2. **SAFETY GATE.** Review the impact. **GATE:** on a large/hot table, a blocking
   `ALTER`/index build is **not** acceptable — require an online/concurrent strategy
   (`CREATE INDEX CONCURRENTLY`, add-nullable-then-backfill-then-constrain, etc.). A
   migration with no working rollback also blocks.
3. **TEST.** Apply the migration to a **scratch/throwaway database — prefer an
   ephemeral container or a local disposable DB; never a schema inside a shared or
   production database**: run forward → assert the change → run rollback → assert the
   original state. Dispatch `test-architect` for data-integrity tests if invariants
   are involved.
   **GATE:** forward and rollback must both succeed on the scratch DB. If the DB tooling
   isn't available on this host, report that as a could-not-run — do not claim success.
4. **APP CHANGES (if needed).** Dispatch the `{lang}-expert` for ORM/model/query
   updates, tested.
5. **REVIEW.** Dispatch `code-reviewer` on the migration + app diff.
6. **REPORT.** The migration + rollback, the impact assessment, the scratch-DB test
   result, and the exact apply/rollback commands — plus any backfill/online steps the
   user must run against production. Do not apply to a real database without confirmation.

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
   {"workflow": "wf-db-change", "task": "<original $ARGUMENTS>",
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
