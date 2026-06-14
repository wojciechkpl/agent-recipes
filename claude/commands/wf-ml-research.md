---
description: "ML research to reproducible setup: literature review → Docker env → MLflow tracking"
argument-hint: "<research topic / problem statement>"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent
---

# Workflow: ML Research → Reproducible Setup

**Topic:** $ARGUMENTS

You are the **orchestrator**. You dispatch specialists via the `Agent` tool and own
the gate between phases. The goal is to go from an open research question to a
**reproducible experiment scaffold** — survey first, then build the environment the
candidate approach needs. Do not build infrastructure before the research has named
a concrete approach to test.

## Subagents you will dispatch
- `ai-researcher` — literature review, candidate approaches, tradeoff analysis,
  recommendation (has web search).
- `docker-ml-environment` — reproducible, GPU-capable container for the chosen stack.
- `mlflow-tracking` — experiment tracking, params/metrics/artifacts, model registry.

## Steps

1. **RESEARCH.** Dispatch `ai-researcher` on $ARGUMENTS. Require: a focused
   literature review, a small set of candidate approaches with a tradeoff matrix,
   and **one recommended approach** with its concrete requirements (framework,
   dataset(s), compute profile, key hyperparameters, evaluation metric). Have it
   **persist the recommendation and stack to a known artifact, `.wf/ml-approach.md`**,
   so ENV and TRACKING read it directly (a separate subagent cannot see another's
   output — the file is the reliable hand-off).
   **GATE:** do not proceed until the output names a specific approach and its stack.
   If the question is too broad to converge, report that and ask the user to narrow
   it rather than building an environment for an undecided approach.

2. **ENVIRONMENT.** Dispatch `docker-ml-environment`, pointing it at
   `.wf/ml-approach.md`, to build a reproducible container for the recommended
   stack — **pinned** framework/CUDA versions, the data-access pattern, and a
   deterministic seed convention.
   **GATE:** the image must build and the framework must import (a one-line sanity
   check). Distinguish two failure modes:
   - **Host limitation** (no NVIDIA runtime / Docker unavailable) → STOP, report to
     the user, and offer a CPU-only image variant. Do not loop on an environmental
     impossibility.
   - **Dockerfile defect** → iterate with `docker-ml-environment` using the raw
     build error, up to 3 attempts, then escalate to the user.
   Never hand a broken environment to the tracking step.

3. **TRACKING.** Dispatch `mlflow-tracking` to wire experiment tracking into the
   environment: an experiment, logged params/metrics/artifacts, and a registry entry
   convention. Include a minimal runnable example that logs one dummy run end-to-end.
   **GATE:** verify the dummy run was actually logged — query the tracking backend
   (`mlflow runs list -e <experiment>`, the REST `/api/2.0/mlflow/runs/search`, or
   inspect the local `mlruns/` store) and confirm the run id plus at least one logged
   metric. If the tracking server isn't reachable, that is a `could-not-run` (report
   it) — not a pass.

4. **REPORT.** Show: the recommended approach and why, the env build + import check,
   the tracking sanity run, and the exact commands to launch a real experiment.
   State honestly what is scaffolded vs. what still needs real data/compute.

## Asana sync (optional)
If an Asana project is configured, dispatch the `asana-sync` subrecipe to reflect this
run on the relevant Asana task — typically `start`, a `comment` at each gate/finding, and
`done` (with links) on completion, or `blocked` if a gate stops it. Best-effort and
non-blocking: a silent no-op if Asana isn't configured or reachable.
