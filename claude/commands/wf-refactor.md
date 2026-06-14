---
description: "Safe refactor under a test guard: cover → checkpoint → refactor → verify unchanged → review"
argument-hint: "<target (file/module)> — <refactor goal>"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent
---

# Workflow: Refactor (behavior-preserving)

**Target / goal:** $ARGUMENTS

You are the **orchestrator**. A refactor changes structure, never behavior — so it is
only safe behind a green test suite that exists *before* the change and stays green
*after*. You do NOT refactor yourself; you dispatch specialists and own the gates.

## Subagents you will dispatch
- `analyst` — (optional) map the target's behavior and dependencies first.
- `test-architect` — add **characterization tests** if existing coverage is thin.
- a matching language expert (`python-expert`, `typescript-expert`, etc.) — the refactor.
- `code-reviewer` — confirm the change is an improvement and behavior is unchanged.

## Steps
1. **GUARD.** Identify the test command and run it. If the target's behavior is not
   well covered, dispatch `test-architect` to write **characterization tests** that
   pin the *current* observable behavior, and confirm they pass on the unchanged code.
   **GATE:** you must have a green suite covering the target before touching it. If
   the suite errors for a toolchain reason, stop and report.
2. **CHECKPOINT.** Record a restore point — **prefer git (`git stash`/commit)** so it
   also captures *new* files the refactor may create (e.g. an extracted module), not
   just edits. If git isn't available, have the `{lang}-expert` declare the full set of
   files it will add/change so the checkpoint covers them. This makes the step-4 revert
   reliable.
3. **REFACTOR.** Dispatch the `{lang}-expert`: improve structure toward the goal
   (extract, rename, dedupe, simplify) **without changing behavior**; tests are the
   contract and must not be edited to fit the new shape.
4. **VERIFY.** Run the full suite.
   **GATE:** every test that passed before must still pass. Any change in behavior =
   revert to the checkpoint and report. Correctness is not negotiable.
5. **REVIEW.** Dispatch `code-reviewer` to confirm the refactor genuinely improves
   readability/structure and didn't smuggle in a behavior change. REQUEST CHANGES
   loops back to REFACTOR (max 3 rounds, then surface to the user).
6. **REPORT.** Show the diff, before/after test results (both green), and the review
   verdict.

## Asana sync (optional)
If an Asana project is configured, dispatch the `asana-sync` subrecipe to reflect this
run on the relevant Asana task — typically `start`, a `comment` at each gate/finding, and
`done` (with links) on completion, or `blocked` if a gate stops it. Best-effort and
non-blocking: a silent no-op if Asana isn't configured or reachable.
