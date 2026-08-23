---
description: "Understand a codebase: scope → investigate (read-only) → document an onboarding map"
argument-hint: "[path or subsystem, default = whole repo] [— optional question]"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent, Skill
---

# Workflow: Understand a Codebase

**Target:** $ARGUMENTS  *(default: the whole repo)*

You are the **orchestrator**. The goal is a trustworthy mental model of an unfamiliar
codebase: structure, data flow, risks — and, if asked, a direct answer to a specific
question. This is **read-only** except for the documentation it produces.

## Subagents you will dispatch
- the built-in `Explore` agent — read-only investigation (breadth: very thorough).
  It replaces the retired `analyst`; the dispatch prompt below carries the report contract.
- `documentation-agent` — turns the analysis into a durable onboarding/architecture doc.

## Steps
1. **SCOPE.** Resolve the target and the question (if any). For a large repo, identify
   the entry points and the few subsystems that matter most rather than everything.
2. **INVESTIGATE.** Dispatch the built-in `Explore` agent (breadth: very thorough) to map: components → responsibilities, the data
   flow of a representative request, external integrations, and the riskiest areas —
   with `file:line` evidence and observed-vs-inferred labels, structured as:
   Summary / Key Components / Data Flow / Dependencies & Integrations /
   Findings & Risks / Recommendations / Open Questions. **You (the orchestrator)
   capture the returned analysis to `.wf/analysis.md`** — Explore is read-only
   and cannot write files. If a specific question was asked, require a direct
   answer first.
   **GATE:** the analysis must cite evidence; do not accept unsupported claims.
3. **DEEP-DIVE (optional).** If the question needs more, dispatch `Explore` again on
   the specific path with the narrower question.
4. **DOCUMENT.** Dispatch `documentation-agent` to turn `.wf/analysis.md` into a
   reader-friendly `ARCHITECTURE.md` / onboarding guide: a system overview, a
   component map, a data-flow diagram (Mermaid), and "where to start" pointers.
5. **REPORT.** Summarize the mental model, answer the question if one was asked, and
   link the produced doc. Flag what remains uncertain or unverified.

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
   {"workflow": "wf-understand", "task": "<original $ARGUMENTS>",
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
