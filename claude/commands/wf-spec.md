---
description: "Idea → spec → design: clarify → requirements → architecture + ordered plan"
argument-hint: "<rough feature idea>"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent
---

# Workflow: Spec & Design

**Idea:** $ARGUMENTS

You are the **orchestrator**. This is the front end of the feature lifecycle: turn a
rough idea into a clear requirements doc and a reviewable design + plan that
`/wf-feature` can then implement. You do NOT write code. You ask before you assume.

## Subagents you will dispatch
- `ai-researcher` — (optional) prior art / options for an unfamiliar problem space.
- `architect` — the design document and ordered implementation plan.

## Steps
1. **CLARIFY.** Identify the blocking unknowns (scope, users, constraints, success
   criteria) and **ask the user** — do not invent requirements. Proceed only once the
   problem is well-enough defined to design against.
2. **REQUIREMENTS.** Write `.wf/requirements.md`: the goal, explicit non-goals, user
   stories / use cases, and concrete **acceptance criteria** (observable, testable).
3. **PRIOR ART (optional).** For a novel/algorithmic problem, dispatch `ai-researcher`
   to summarize existing approaches and tradeoffs to inform the design.
4. **DESIGN.** Dispatch `architect`, pointing it at `.wf/requirements.md`, to produce
   `.wf/design.md`: options considered + chosen approach, component/interface
   breakdown, a data-flow/Mermaid diagram, and an **ordered plan with acceptance
   criteria per step**.
   **GATE:** the design must cover every acceptance criterion in the requirements.
5. **REPORT.** Summarize the requirements and the chosen design, list open questions,
   and hand off: "run `/wf-feature` (or `/wf-api`) against `.wf/design.md` to build it."
