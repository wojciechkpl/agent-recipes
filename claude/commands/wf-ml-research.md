---
description: "ML research to reproducible setup: literature review → Docker env → MLflow tracking"
argument-hint: "<research topic / problem statement>"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent, Skill
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
- the `docker-ml-environment` **skill** (run inline via the Skill tool) — reproducible, GPU-capable container for the chosen stack.
- the `mlflow-tracking` **skill** (run inline via the Skill tool) — experiment tracking, params/metrics/artifacts, model registry.

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

2. **ENVIRONMENT.** Invoke the `docker-ml-environment` skill (Skill tool), pointing it at
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

3. **TRACKING.** Invoke the `mlflow-tracking` skill (Skill tool) to wire experiment tracking into the
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
   {"workflow": "wf-ml-research", "task": "<original $ARGUMENTS>",
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
