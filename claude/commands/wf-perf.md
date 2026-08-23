---
description: "Measure-driven optimization: baseline → optimize → verify → re-measure → review"
argument-hint: "<hot path / function / endpoint to optimize>"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent, Skill
---

# Workflow: Performance (measure-driven)

**Target:** $ARGUMENTS

You are the **orchestrator**. Optimization is **evidence-gated**: no change is kept
unless a re-measurement beats the recorded baseline AND the test suite still passes.
You do NOT write the optimization yourself — you dispatch specialists and own the
gate. Never optimize on intuition; optimize on numbers.

## Subagents you will dispatch
- `performance-optimizer` — measure a reproducible baseline, then re-measure.
- a matching language expert (`python-expert`, `rust-expert`, etc.) — apply the change.
- `code-reviewer` — confirm the change is sound and doesn't trade correctness for speed.

## Steps

1. **BASELINE.** Dispatch `performance-optimizer` to: identify the real bottleneck
   for $ARGUMENTS (profile, don't guess), and produce a **reproducible benchmark**
   plus the baseline numbers (latency / throughput / memory, with units and how to
   re-run). Record the baseline verbatim — it is the bar to beat. **Also commit a
   target improvement threshold NOW, before any change exists** (e.g. "≥20% latency
   reduction, repeatable across 3 runs"), so the step-5 gate compares against a
   number chosen before the result is known and cannot be rationalized after the fact.
   **GATE:** if the profiler shows the named target is NOT actually the bottleneck,
   report that and ask the user whether to retarget. Do not optimize a non-hotspot.

2. **GUARD.** Confirm there are tests covering the target's behavior (run the suite).
   If correctness coverage is thin, dispatch the `{lang}-expert` to add a
   characterization test FIRST so the optimization can't silently change results.

3. **OPTIMIZE.** First **capture a restore point** so the revert gates are actually
   executable: in a git repo, record the current commit (and ensure the tree is
   clean or stashed); otherwise save a copy of the files about to change. Then
   dispatch the `{lang}-expert` with the profile + baseline: apply the minimal change
   that addresses the measured bottleneck. Behavior must not change.

4. **VERIFY.** Run the full test suite.
   **GATE:** all tests must pass. A failing suite = revert; correctness is not
   negotiable for speed.

5. **RE-MEASURE.** Dispatch `performance-optimizer` to re-run the *same* benchmark
   and compare to baseline.
   **GATE:** keep the change only if it beats baseline by at least the threshold
   pre-committed in step 1 (state the measured delta against that threshold). If it
   doesn't, **revert to the step-3 restore point** and report the negative result
   honestly.

6. **REVIEW.** Dispatch `code-reviewer` to check the kept change for soundness and
   readability cost. REQUEST CHANGES loops back to OPTIMIZE; if 3 rounds don't
   converge, stop and surface the open findings to the user.

7. **REPORT.** Show: bottleneck, baseline vs. final numbers (with delta), the test
   result, the diff, and the review verdict. If reverted, say so plainly.

## Asana sync (optional)
If an Asana project is configured, invoke the `asana-sync` skill (Skill tool) to reflect this
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
   {"workflow": "wf-perf", "task": "<original $ARGUMENTS>",
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
