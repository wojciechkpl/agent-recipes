---
description: "ML experiment loop: frame → data → baseline → variant → compare (tracked) → report"
argument-hint: "<hypothesis / approach to test>"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent
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
- `mlflow-tracking` — log params/metrics/artifacts for every run.
- `docker-ml-environment` — (if needed) a reproducible, pinned environment.

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
