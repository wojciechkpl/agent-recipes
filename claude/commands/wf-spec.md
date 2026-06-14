---
description: "Idea → PRD → design: clarify → product-manager PRD → architecture + ordered plan"
argument-hint: "<rough feature idea>"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent
---

# Workflow: Spec & Design

**Idea:** $ARGUMENTS

You are the **orchestrator**. This is the front end of the feature lifecycle: turn a
rough idea into a prioritized PRD and a reviewable technical design + plan that
`/wf-feature` can then implement. You do NOT write code. You ask before you assume.

## Subagents you will dispatch
- `product-manager` — the PRD: problem, users, goals/non-goals, user stories,
  acceptance criteria, success metrics, and prioritization (the what / why / for-whom).
- `ai-researcher` — (optional) prior art / options for an unfamiliar problem space.
- `architect` — the technical design document and ordered implementation plan (the how).

## Steps
1. **CLARIFY.** Identify the blocking unknowns (scope, users, constraints, success
   criteria) and, per §6, gather them in one batched round — ask the user only what you
   cannot determine yourself. Proceed once the problem is well-enough defined.
2. **PRD.** Dispatch `product-manager` to produce `.wf/prd.md`: problem & value, target
   users, goals / explicit non-goals, user stories, **acceptance criteria** (observable,
   testable), **success metrics**, and a **prioritization** with the MVP line drawn and
   tradeoffs surfaced (not silently cut). Downstream phases read this file.
   **GATE:** the PRD must state measurable success criteria and an explicit MVP scope.
3. **PRIOR ART (optional).** For a novel/algorithmic problem, dispatch `ai-researcher`
   to summarize existing approaches and tradeoffs to inform the design.
4. **DESIGN.** Dispatch `architect`, pointing it at `.wf/prd.md`, to produce
   `.wf/design.md`: options considered + chosen approach, component/interface
   breakdown, a data-flow/Mermaid diagram, and an **ordered plan with acceptance
   criteria per step**.
   **GATE:** the design must cover every acceptance criterion in the PRD.
5. **REPORT.** Summarize the PRD (incl. MVP scope + metrics) and the chosen design, list
   open questions, and hand off: "run `/wf-feature` (or `/wf-api`) against
   `.wf/design.md` to build it."

## Asana sync (optional side-channel) — seed the roadmap
If an Asana project is configured (see the `asana-sync` subrecipe), after the PRD
(step 2) dispatch `asana-sync` to **seed the project as the roadmap/board**:
find-or-create the project, then create **one task per prioritized MVP item** in the
**To Do** section (Later-list items go to a separate "Backlog" section or are omitted).
Each task carries its **acceptance criteria** in the description and a **stable
`task_key`** (feature slug) so the execution workflows (`/wf-feature`, `/wf-bugfix`, …)
later find-and-advance the *same* task (To Do → In Progress → Done) instead of creating
duplicates. Preflighted and graceful — a silent no-op if Asana isn't configured or
reachable.
