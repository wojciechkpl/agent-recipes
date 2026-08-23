---
description: "ML experiment loop: frame → data → baseline → variant → compare (tracked) → report"
argument-hint: "<hypothesis / approach to test>"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent, Skill
---

# Workflow: ML Experiment

**Hypothesis:** $ARGUMENTS

You are the **orchestrator**. An experiment is only meaningful if it is reproducible
and its conclusion follows from logged evidence — never from a single unseeded run or
a vibe. You dispatch specialists and own the gates. (To go from an open question to a
chosen approach first, run `/wf-ml-research`; this workflow tests a *named* hypothesis.)

## Subagents you will dispatch
- `ai-researcher` — sharpen the hypothesis, baseline, metric, and what would falsify it.
- `data-engineer` — reproducible dataset prep (deterministic, validated).
- a matching language expert (`python-expert`, etc.) — implement baseline + variant.
- the `mlflow-tracking` **skill** (run inline via the Skill tool) — log params/metrics/artifacts for every run.
- the `docker-ml-environment` **skill** (run inline via the Skill tool) — (if needed) a reproducible, pinned environment.

## Steps
1. **FRAME.** Dispatch `ai-researcher` (or read `.wf/ml-approach.md` if `/wf-ml-research`
   produced one): state the hypothesis, the **single primary metric**, the baseline,
   and the decision rule (what result confirms vs. refutes). Pre-commit the seed(s).
   **Persist the plan — hypothesis, primary metric, baseline, decision rule, seed — to
   `.wf/experiment-plan.md`; the BASELINE/VARIANT and `mlflow-tracking` steps read it**
   (a separate subagent cannot see another's output — the file is the hand-off).
   **GATE:** do not proceed without a falsifiable hypothesis and one primary metric.
2. **DATA.** Dispatch `data-engineer` for a reproducible, validated dataset split
   (fixed seed, documented). **GATE:** same input → same split, verified.
3. **BASELINE.** Implement/obtain the baseline; run it; log to MLflow (params, metric,
   seed). Record the baseline metric value.
4. **VARIANT.** Implement the hypothesis change; run under the **same** data/seed/eval;
   log to MLflow. Keep everything but the tested variable constant.
5. **COMPARE.** Pull both runs' metrics from MLflow. State the delta and whether it
   meets the decision rule. Prefer ≥1 repeat/seed to guard against noise.
   **GATE:** the comparison must come from logged runs you can point to, not memory.
6. **REPORT.** Hypothesis, setup (data/seed/env), baseline vs. variant metrics with
   delta, and the verdict — **including a negative result, stated honestly**. Note
   host limits (e.g. no GPU) if they capped the run.

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
   {"workflow": "wf-experiment", "task": "<original $ARGUMENTS>",
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
