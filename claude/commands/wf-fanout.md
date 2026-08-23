---
description: "Fan a task out to parallel agents safely: decompose → isolate → dispatch → commit each stream → reconcile"
argument-hint: "<task that splits into independent parallel streams>"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent
---

# Workflow: Parallel Fan-Out

**Task:** $ARGUMENTS

You are the **orchestrator**. Decompose the task into independent streams, run them in
parallel via the `Agent` tool, and land each result without the streams clobbering each
other. You own all git operations; specialist agents edit files but **never commit**.
See `git-best-practices` → *Concurrent Sessions & Worktree Isolation*.

## Steps

1. **DECOMPOSE.** Split the task into 2–N streams that touch **non-overlapping file
   sets**. State each stream's scope and files. If streams must touch the same files,
   either serialize them or give each an isolated `git worktree` (see step 2). If it
   doesn't decompose cleanly, STOP — this isn't a fan-out; use `/wf-feature` etc.

2. **ISOLATE.** Create the branch (`git branch --show-current` to confirm you're on it).
   If any streams overlap files, or another session shares this clone, dispatch each
   with `isolation: "worktree"`; otherwise non-overlapping streams can share the tree.

3. **DISPATCH (parallel).** Send all streams in one message (concurrent). Each agent
   gets its scope + this instruction: *"Edit only your files. Write a regression test
   per change. Run the relevant tests/linters. Do NOT git commit — leave changes in
   the tree; report files changed + results."*

4. **VERIFY + COMMIT each stream.** As each returns: re-run its tests, confirm
   `git branch --show-current` is still your branch, then commit **that stream's
   explicit paths** with a Conventional Commit. Do this per stream — never let several
   streams' uncommitted changes pile up in one tree. **GATE:** a stream that failed
   verification loops back to its agent with the failure output before you commit it.

5. **RECONCILE + GATE.** Run the full suite once all streams are committed.
   `git merge origin/<base>` if the base advanced, and fix any debt the merge surfaces
   (PR CI lints the merge, not your branch alone). Optionally run `/wf-pre-pr`.
   **GATE:** all tests green + no 🔴 before opening the PR.

6. **REPORT.** Per stream: files, tests, commit. Plus the reconcile result and the
   final green status.

## Recovery
If a branch collision scrambled the tree (a shared-clone hazard): your commits are safe
on the branch ref. `git worktree add /tmp/recover <branch>` for a clean checkout,
re-apply salvageable uncommitted work there, commit/push from the worktree. Never
`reset --hard` or blanket-`checkout --` files another session may be mid-edit on.

## Asana sync (optional)
If an Asana project is configured, dispatch the `asana-sync` subrecipe: `start` at
DECOMPOSE, a `comment` per stream committed, `done` at REPORT. Best-effort and
non-blocking — a silent no-op if Asana isn't configured or reachable.

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
   {"workflow": "wf-fanout", "task": "<original $ARGUMENTS>",
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
