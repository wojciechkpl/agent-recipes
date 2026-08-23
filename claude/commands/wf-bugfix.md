---
description: "Bug fix with a regression test first: reproduce → red → fix → review"
argument-hint: "<bug description or failing symptom>"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent, Skill
---

# Workflow: Bug Fix (regression-test-first)

**Bug:** $ARGUMENTS

You are the **orchestrator**. You do NOT write the fix yourself — you dispatch the
specialists below via the `Agent` tool and own the gate between phases. A bug is
not fixed until a test that was RED before is GREEN after.

## Subagents you will dispatch
- `debugger` — reproduce the bug, isolate root cause, write a FAILING regression
  test that captures it.
- a matching language expert (`python-expert`, `rust-expert`, `flutter-expert`,
  `postgresql-expert`, or `bash-expert`) — apply the minimal fix.
- `code-reviewer` — verify the fix and check for regressions.

## Steps

1. **REPRODUCE + RED.** Dispatch `debugger` with: *"Reproduce: $ARGUMENTS. Identify
   the root cause via observe → hypothesize → test. Then write a regression test
   that FAILS because of this bug. Do not fix the bug yet."* Run the test command.
   **GATE:** the regression test MUST fail, for the right reason — it reproduces
   the bug. If the test command errors for a toolchain/setup reason (missing
   interpreter, deps, virtualenv) rather than failing on the bug, STOP and report
   the raw error to the user. Record the root cause the debugger identified.

2. **GREEN.** Dispatch the matching `{lang}-expert` with: *"Apply the minimal fix
   for this root cause: <cause>. Make the regression test pass. You may NOT edit
   the test."* Run the full test suite.
   **GATE:** the regression test and the entire existing suite must pass. If
   anything else breaks, dispatch again with the failure output.

3. **REVIEW.** Dispatch `code-reviewer` on the diff, focused on correctness and
   whether the fix addresses the root cause rather than masking the symptom.
   **GATE:** REQUEST CHANGES loops back to GREEN.

4. **REPORT.** Show the user: the root cause, the regression test (red→green), the
   fix diff, and the review verdict.

## Asana sync (optional side-channel)
If an Asana project is configured (see the `asana-sync` skill), invoke the `asana-sync` skill:
`start` at step 1, a `comment` at the regression red→green and at the review, `done`
(+ fix summary) at REPORT. Preflighted and graceful — a silent no-op if Asana isn't
configured or reachable; it never blocks the fix.

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
   {"workflow": "wf-bugfix", "task": "<original $ARGUMENTS>",
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
