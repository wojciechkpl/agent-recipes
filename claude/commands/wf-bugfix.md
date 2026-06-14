---
description: "Bug fix with a regression test first: reproduce → red → fix → review"
argument-hint: "<bug description or failing symptom>"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent
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
