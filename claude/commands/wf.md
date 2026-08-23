---
description: "Workflow router: describe the task, get routed to the right /wf-* workflow"
argument-hint: "<task description>"
allowed-tools: Read, Glob, Grep, SlashCommand
---

# Workflow Router

**Task:** $ARGUMENTS

You are the **workflow router**. Your only job is to pick the right `/wf-*`
workflow for the task above and hand off to it. You do NOT do the task yourself,
and you do NOT dispatch agents — the chosen workflow owns all orchestration.

## Steps

1. **No task given?** If `$ARGUMENTS` is empty, print the routing table below as
   a compact list (command — when to use it) and stop.

2. **Classify.** Match the task against the routing table, top to bottom; first
   confident match wins. Peek at context only if it settles the choice cheaply
   (e.g. does `.wf/design.md` or `.wf/prd.md` exist? is there a failing test
   named in the task?).

3. **Route.** Announce the choice in ONE line — `Routing to /wf-<name>: <ten-word
   reason>` — then invoke the workflow via the SlashCommand tool, passing the
   task through verbatim (e.g. `/wf-feature $ARGUMENTS`). If the SlashCommand
   tool is unavailable, tell the user the exact command to run instead.

4. **Ambiguous?** If two workflows genuinely fit, ask the user ONE short
   either/or question, then route. Never ask more than one question.

5. **No workflow fits?** If the task is a single focused action (review one
   file, explain an error, rename a symbol), say so and name the matching
   *agent* instead (e.g. `@agent-code-reviewer`) — a workflow would be overhead.

## Routing table

| If the task is… | Route to |
|-----------------|----------|
| Still a rough idea — needs a PRD / priorities / success metrics before any code | `/wf-spec` |
| "Add/implement feature X" (tests-first build) | `/wf-feature` |
| Something is broken / wrong output / failing behavior to fix | `/wf-bugfix` |
| Restructure/clean up code without changing behavior | `/wf-refactor` |
| "Check/gate my changes before a PR or merge" | `/wf-pre-pr` |
| Something is slow; wants a measured speedup | `/wf-perf` |
| Design + build a new API endpoint/service, contract-first | `/wf-api` |
| Schema/migration change to a database | `/wf-db-change` |
| Start a brand-new project/repo from nothing | `/wf-new-project` |
| Understand/map/onboard an unfamiliar codebase | `/wf-understand` |
| Repo-wide rename/codemod touching many files | `/wf-migrate` |
| Upgrade/audit dependencies safely | `/wf-upgrade-deps` |
| Cut/tag/ship a release | `/wf-release` |
| Big divisible task to run as parallel agent streams | `/wf-fanout` |
| Open ML question → reproducible tracked setup | `/wf-ml-research` |
| A named ML hypothesis to run against a baseline | `/wf-experiment` |

**Tie-breakers**

- Feature vs. spec: if scope/priorities/success criteria are still fuzzy → `/wf-spec`;
  if it's buildable as stated → `/wf-feature`. A `.wf/prd.md` or `.wf/design.md`
  already present → `/wf-feature` (it reads them).
- Bugfix vs. perf: wrong *result* → `/wf-bugfix`; correct but *slow* → `/wf-perf`.
- Feature vs. api: primarily a new public HTTP/RPC contract → `/wf-api`; otherwise `/wf-feature`.
- Refactor vs. migrate: one module/behavior-preserving cleanup → `/wf-refactor`;
  mechanical change repeated across the repo → `/wf-migrate`.
