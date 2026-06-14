---
description: "Understand a codebase: scope → investigate (read-only) → document an onboarding map"
argument-hint: "[path or subsystem, default = whole repo] [— optional question]"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent
---

# Workflow: Understand a Codebase

**Target:** $ARGUMENTS  *(default: the whole repo)*

You are the **orchestrator**. The goal is a trustworthy mental model of an unfamiliar
codebase: structure, data flow, risks — and, if asked, a direct answer to a specific
question. This is **read-only** except for the documentation it produces.

## Subagents you will dispatch
- `analyst` — read-only investigation; produces the structured analysis.
- `documentation-agent` — turns the analysis into a durable onboarding/architecture doc.

## Steps
1. **SCOPE.** Resolve the target and the question (if any). For a large repo, identify
   the entry points and the few subsystems that matter most rather than everything.
2. **INVESTIGATE.** Dispatch `analyst` to map: components → responsibilities, the data
   flow of a representative request, external integrations, and the riskiest areas —
   with `file:line` evidence and observed-vs-inferred labels. **You (the orchestrator)
   capture the analyst's returned analysis to `.wf/analysis.md`** — the analyst is
   read-only and cannot write files. If a specific question was asked, require a
   direct answer first.
   **GATE:** the analysis must cite evidence; do not accept unsupported claims.
3. **DEEP-DIVE (optional).** If the question needs more, dispatch `analyst` again on
   the specific path with the narrower question.
4. **DOCUMENT.** Dispatch `documentation-agent` to turn `.wf/analysis.md` into a
   reader-friendly `ARCHITECTURE.md` / onboarding guide: a system overview, a
   component map, a data-flow diagram (Mermaid), and "where to start" pointers.
5. **REPORT.** Summarize the mental model, answer the question if one was asked, and
   link the produced doc. Flag what remains uncertain or unverified.

## Asana sync (optional)
If an Asana project is configured, dispatch the `asana-sync` subrecipe to reflect this
run on the relevant Asana task — typically `start`, a `comment` at each gate/finding, and
`done` (with links) on completion, or `blocked` if a gate stops it. Best-effort and
non-blocking: a silent no-op if Asana isn't configured or reachable.
