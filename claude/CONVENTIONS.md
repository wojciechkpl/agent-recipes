# Claude Code Agent Conventions

Global rules and standards shared across all Claude Code agents in this collection.

## Core Principles

### 1. TDD Is Mandatory
Every agent that writes or modifies code enforces Test-Driven Development:
- **RED**: Write a failing test FIRST
- **GREEN**: Write minimal code to pass the test
- **REFACTOR**: Improve code while keeping tests green

Never skip the RED phase. Never write implementation before the test.

### 2. Measure Before Optimizing
Never optimize without profiling data. Establish baselines, identify the 20% causing 80% of issues, optimize one thing at a time, and validate with benchmarks.

### 3. Security by Default
- No hardcoded secrets — use environment variables or secret managers
- Validate at system boundaries (user input, external APIs)
- Parameterized queries for all database access
- HTTPS/TLS for all external communication

### 4. Reproducibility
- Pin all dependency versions (no `>=`, no `latest`)
- Lock files committed to version control
- Deterministic seeds for ML experiments
- Docker environments for ML workloads

### 5. Configuration over Hard-Coding
Never bury magic numbers, tunable constants, paths, URLs, credentials, or business
values as inline literals. Centralize them:
- **Named constants** (module/class top) for fixed values — with a comment on the
  unit and *why* that value.
- **Config files / env vars** (12-factor) for anything environment- or
  deployment-specific (endpoints, ports, feature flags, credentials).
- **Parameters with defaults** for tunables a caller might vary (seeds, limits,
  thresholds, retry counts, batch sizes) — never a literal buried in the body.
- A bare literal is acceptable only when self-evident and used once (e.g. `0`/`1`
  for indexing). Anything reused, tuned, or non-obvious gets a name.

Implementers extract these at write time; reviewers flag inline magic values.

### 6. Gather Inputs Once, Then Execute
Front-load uncertainty; do not dribble validation questions across a task.
- **Preflight.** Before changing anything, enumerate every input the change needs —
  target files, desired behavior, acceptance criteria, constraints, environment.
  Answer what you can by **reading the code/config yourself**; never ask the user for
  what you can discover.
- **Ask once, batched.** If blocking unknowns remain, ask them in a single
  consolidated round (prefer a structured multiple-choice), not one question at a time.
- **State assumptions and default.** Prefer a sensible, stated default over a question;
  let the user correct it. Only a genuinely blocking ambiguity warrants stopping.
- **Surface, don't silently pick.** If a task has multiple valid interpretations,
  surface them with their tradeoffs and choose one explicitly (saying why) — never
  resolve the ambiguity invisibly.
- **Then execute autonomously** through the planned steps/gates without re-confirming
  each one. Re-prompt only for a new decision the gathered inputs didn't cover, or
  before an irreversible / outward-facing action (deploy, push, drop, send).

### 7. Surgical, Minimal Diffs
Change only what the task requires — the smallest correct diff is the goal.
- Touch only the lines/files the task needs. No drive-by edits, opportunistic
  refactors, renames, or reformatting of code you didn't have to change.
- Match the surrounding style and idiom; do not reflow, reorder imports, or reformat
  untouched code (leave that to the formatter, in its own change).
- Keep concerns separate: a feature, a fix, and a refactor are distinct changes —
  don't bundle them. Spotted an unrelated issue? Report it; don't fix it inline.
- Preserve public APIs and existing behavior unless the task is explicitly to change
  them. Prefer extending and reusing existing helpers over rewriting or duplicating.
- **Dead code:** delete dead code your change *introduces*; for pre-existing dead code
  you merely noticed, report it — don't silently remove it (that's an unrelated change).

### 8. Simplicity First (YAGNI)
Build only what the task asks for; the simplest thing that meets the criteria wins.
- No features, options, or extension points beyond the request. No abstraction for code
  with a single caller. No "flexible"/"configurable" layers, plugin points, or generality
  that weren't asked for.
- No error handling for impossible states — handle inputs that can actually occur, not
  hypothetical ones. (Boundary validation per §3 still applies.)
- **This reconciles with §5, it does not contradict it.** Name the values you already
  use; don't invent configurability you don't. Extracting a literal you are *already*
  using into a named constant/parameter is good (§5); building a config system, a
  flexible layer, or generalized hooks nobody requested is overengineering (§8). The
  test: does the parameter have a *current* caller/value, or is it speculative?
- Prefer deleting to adding. If a simpler design meets the success criteria, use it.

### 9. Goal-Driven Execution
Work to explicit success criteria, then prove you met them.
- Before starting, state what "done" means as **observable, checkable outcomes** (tests
  pass, endpoint returns X, metric beats Y) — not a list of steps. Then iterate freely
  toward them; the gates do the steering.
- **Verify before claiming done.** Run the check and show the result — never assert a
  success you did not observe (see §1 and the workflow gate pattern). A failed or unrun
  check is reported honestly, not papered over.
- **Bound the loop.** Track attempts; stop at a stated budget (rounds / time) and
  summarize what was tried, rather than spiraling and losing track of prior attempts.

## Severity Classification

All auditing and review agents use a shared severity scale:
- **🔴 Critical**: MUST fix — security vulnerabilities, data loss, crashes (CVSS 9.0–10.0)
- **🟠 Major**: SHOULD fix — logic errors, missing error handling, performance (CVSS 7.0–8.9)
- **🟡 Minor**: CAN fix — naming, style, minor optimization (CVSS 4.0–6.9)
- **🔵 Suggestion**: OPTIONAL — alternative approaches, educational notes (CVSS 0.1–3.9)
- **ℹ️ Info**: No action — context, best practice notes

See `shared/severity-scale.md` for full specification.

## Agent Composition

Agents are organized by scope:
- **Core agents** (`agents/*.md`): General-purpose workflow agents
- **Language experts** (`agents/languages/*.md`): Deep language/domain specialization
- **Specialized agents** (`agents/specialized/*.md`): Research and design
- **Skills** (`skills/<name>/SKILL.md`): Shared procedures that agents and
  workflows load inline via the Skill tool (the directory name is the skill name)

### Skill Usage
Skills contain reusable protocols invoked inline — no subagent dispatch:
- `tdd-generic` — Red-Green-Refactor cycle for any language
- `language-detection` — Auto-detect project stack
- `static-analysis` — Language-appropriate linting and type checking
- `git-best-practices` — Conventional commits, branch naming, PR hygiene
- `docker-ml-environment` — Containerized ML infrastructure
- `mlflow-tracking` — ML experiment tracking and model registry
- `asana-sync` — best-effort Asana side-channel for workflow runs

## Naming Conventions

See `shared/naming-conventions.md` for the full standard. Key rules:
- Recipe files: `kebab-case.md`
- Recipe identifiers (frontmatter `name`): `kebab-case`
- Display names: Title Case

## Quality Standards

### File Size Limits
- Max 400 lines per source file
- Max 30 lines per function (50 for Bash, 40 for Rust)
- Max 7 public methods per class

### Test Coverage
- Minimum 80% line coverage for production code
- 90% for security-critical paths
- Every bug fix requires a regression test

### Documentation
- Public APIs must have docstrings
- Complex logic must have explanatory comments
- Architecture decisions documented in design docs
