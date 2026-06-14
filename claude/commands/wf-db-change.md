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
