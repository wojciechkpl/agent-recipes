# AI Agent Recipes

A curated collection of AI agent configurations, **built first for [Claude Code](https://code.claude.com) (by Anthropic)** and also available for Kiro (AWS) and Goose (Block). Each agent enforces best practices, TDD, and language-specific conventions.

> **Claude Code is the primary, recommended platform.** It's the only one with the full **workflow layer** — 16 `/wf-*` orchestration commands that sequence the agents with gates — plus the one-command **plugin** install and the §1–§9 conventions. Kiro (JSON) and Goose (YAML) share the same core agents and standards; only the format differs.

👉 **Jump to [Claude Code setup](#claude-code-anthropic--primary).**

## Repository Structure

```
.
├── setup.sh                # One-line setup for new machines
├── shared/                 # Cross-platform standards
│   ├── severity-scale.md       # Shared 🔴🟠🟡🔵ℹ️ severity classification
│   └── naming-conventions.md   # Shared naming standards
│
├── claude/                 # ★ PRIMARY — Claude Code agents + workflows (Markdown); also a loadable plugin
│   ├── README.md               # Claude-specific documentation
│   ├── CONVENTIONS.md          # Global rules for all Claude agents (§1–§9)
│   ├── .claude-plugin/         # plugin.json — load all agents + workflows in one command
│   ├── commands/               # 16 workflow slash commands (/wf-*)
│   ├── autonomous-mode.sh      # optional broad-permission toggle (+ settings.autonomous.json)
│   ├── AUTONOMOUS-MODE.md       # how to use autonomous mode (on/off, scopes, safety)
│   └── agents/
│       ├── *.md                # 15 core agents
│       ├── languages/*.md      # 6 language experts
│       ├── specialized/*.md    # 2 specialized agents
│       └── subrecipes/*.md     # 7 shared subrecipes
│
├── goose/                  # Goose agent recipes (YAML)
│   ├── README.md               # Goose-specific documentation
│   ├── TUTORIAL.md             # Step-by-step Goose usage guide
│   ├── general/
│   │   ├── *.yaml              # 17 core recipes
│   │   ├── languages/*.yaml    # 6 language experts
│   │   ├── subrecipes/*.yaml   # 11 shared subrecipes
│   │   └── workflows/*.yaml    # 16 workflow recipes (Goose renderings of /wf-*)
│   └── coding_agent_context/   # Portable orchestration framework
│       ├── missions/           # Step-by-step workflow instructions
│       ├── roles/              # Sub-agent identity definitions
│       ├── recipes/            # Goose execution configs
│       └── tools/              # Docker infrastructure scripts
│
├── kiro/                   # Kiro agents (JSON)
│   ├── README.md               # Kiro-specific documentation
│   ├── setup-kiro.sh           # Installation script
│   └── agents/
│       ├── *.json              # 15 core agents
│       ├── languages/*.json    # 6 language experts
│       ├── specialized/*.json  # 2 specialized agents
│       └── subrecipes/*.json   # 7 shared subrecipes
│
└── README.md               # This file
```

---

## Quick Start

### One-Line Setup (recommended)

```bash
git clone https://github.com/wojciechkpl/agent-recipes.git ~/agent-recipes
cd ~/agent-recipes
./setup.sh --all        # Installs Claude agents + configures Goose recipe path
```

The setup script supports selective installation and previewing changes:

```bash
./setup.sh --claude            # Claude agents + /wf-* workflows (user-level, all projects)
./setup.sh --claude-project    # Claude agents + workflows for current project only (team-shareable)
./setup.sh --goose             # Goose recipe path only
./setup.sh --all               # Both Claude + Goose
./setup.sh --dry-run --all     # Preview without making changes
./setup.sh --uninstall         # Remove everything
```

### Claude Code (Anthropic) — primary

`./setup.sh --claude` installs both the **agents** and the **`/wf-*` workflow commands**
(user-level). Or load everything at once as a **plugin** — no copying, agents *and*
workflows available immediately:

```bash
claude --plugin-dir /path/to/agent-recipes/claude
```

For manual installation of agents only:

```bash
# Project-level (recommended for teams)
mkdir -p .claude/agents/languages .claude/agents/specialized .claude/agents/subrecipes
cp claude/agents/*.md .claude/agents/
cp claude/agents/languages/*.md .claude/agents/languages/
cp claude/agents/specialized/*.md .claude/agents/specialized/
cp claude/agents/subrecipes/*.md .claude/agents/subrecipes/

# Or user-level (available in all your projects)
mkdir -p ~/.claude/agents/languages ~/.claude/agents/specialized ~/.claude/agents/subrecipes
cp claude/agents/*.md ~/.claude/agents/
cp claude/agents/languages/*.md ~/.claude/agents/languages/
cp claude/agents/specialized/*.md ~/.claude/agents/specialized/
cp claude/agents/subrecipes/*.md ~/.claude/agents/subrecipes/
```

Agents activate automatically — just describe your task:
```
claude
> Review the auth module for security issues   # → delegates to security-auditor
> Debug the failing test in user_service        # → delegates to debugger
```

**To force a specific agent** instead of relying on automatic delegation, @-mention it,
set a session default, or run a workflow (workflows dispatch *named* agents deterministically):
```
> @agent-code-reviewer review the auth module   # explicit — this task only
claude --agent code-reviewer                     # explicit — whole session
> /wf-feature add a rate limiter                 # workflow → named agents, no guessing
```

See [claude/README.md](claude/README.md) for full installation and usage details.

### Goose (Block)
```bash
# Install Goose
brew install block/tap/goose

# Run a recipe directly
goose run --recipe goose/general/code-reviewer.yaml

# With parameters
goose run --recipe goose/general/debugger.yaml \
  --params symptom="TypeError in auth middleware" project_path="."

# Language expert
goose run --recipe goose/general/languages/python-expert.yaml

# ML research
goose run --recipe goose/general/ai-researcher.yaml
```

See [goose/TUTORIAL.md](goose/TUTORIAL.md) for 15 detailed use-case walkthroughs.

---

## Agent Catalog

### Core Agents (17)
| Agent | Goose | Claude | Purpose |
|-------|-------|--------|---------|
| Code Reviewer | `general/code-reviewer.yaml` | `agents/code-reviewer.md` | Correctness, security, performance, maintainability review |
| Test Architect | `general/test-architect.yaml` | `agents/test-architect.md` | TDD **RED** phase — writes failing tests as an independent test author |
| Architect | `general/architect.yaml` | `agents/architect.md` | System design docs + ordered implementation plans (no code) |
| Debugger | `general/debugger.yaml` | `agents/debugger.md` | Scientific debugging: observe → hypothesize → test → fix |
| Security Auditor | `general/security-auditor.yaml` | `agents/security-auditor.md` | OWASP Top 10, secret detection, CVE scanning, compliance |
| Performance Optimizer | `general/performance-optimizer.yaml` | `agents/performance-optimizer.md` | Measure → analyze → optimize → validate (data-driven) |
| Documentation Agent | `general/documentation-agent.yaml` | `agents/documentation-agent.md` | API docs, READMEs, Mermaid diagrams, changelogs |
| API Designer | `general/api-designer.yaml` | `agents/api-designer.md` | REST/GraphQL/gRPC with proper HTTP semantics, OpenAPI |
| Dependency Auditor | `general/dependency-auditor.yaml` | `agents/dependency-auditor.md` | Vulnerability, license, unused deps, size analysis |
| Project Bootstrapper | `general/project-bootstrapper.yaml` | `agents/project-bootstrapper.md` | Scaffold projects with TDD, CI/CD, Docker, linting |
| AI/ML Researcher | `general/ai-researcher.yaml` | `agents/specialized/ai-researcher.md` | Literature review, ML design, math formulation, MLflow |
| UX Designer | `general/ux-designer.yaml` | `agents/specialized/ux-designer.md` | Journey mapping, wireframes, design systems, WCAG 2.2 |
| Product Manager | `general/product-manager.yaml` | `agents/product-manager.md` | PRDs, user stories, acceptance criteria, prioritization (RICE/MoSCoW), success metrics |
| Analyst | `general/analyst.yaml` | `agents/analyst.md` | Read-only codebase investigator — structure, data flow, risks |
| Data Engineer | `general/data-engineer.yaml` | `agents/data-engineer.md` | Data transforms/pipelines, Polars/Rust-first, schema validation |
| SRE / DevOps | `general/sre.yaml` | `agents/sre.md` | CI/CD, Dockerfiles, IaC, observability, deployment |
| Technical Writer | `general/technical-writer.yaml` | `agents/technical-writer.md` | Long-form writing — blogs, RFCs, tutorials, paper drafts |

### Language Experts (6)
| Agent | Goose | Claude | Focus |
|-------|-------|--------|-------|
| Python Expert | `languages/python-expert.yaml` | `languages/python-expert.md` | Python 3.10+, PEP 604/612/695, pytest, FastAPI/Django/PyTorch |
| Flutter Expert | `languages/flutter-expert.yaml` | `languages/flutter-expert.md` | Dart 3.x sealed classes, Riverpod, go_router, clean architecture |
| Rust Expert | `languages/rust-expert.yaml` | `languages/rust-expert.md` | Ownership/lifetimes, tokio async, thiserror/anyhow, proptest |
| PostgreSQL Expert | `languages/postgresql-expert.yaml` | `languages/postgresql-expert.md` | Schema design, keyset pagination, RLS, BRIN indexes |
| Bash Expert | `languages/bash-expert.yaml` | `languages/bash-expert.md` | Defensive scripting, CI/CD pipelines, bats-core testing |
| TypeScript Expert | `languages/typescript-expert.yaml` | `languages/typescript-expert.md` | Strict TypeScript, React/Node, ESLint/Prettier, vitest/jest |

### Subrecipes / Shared Workflows
| Subrecipe | Goose | Claude | Purpose |
|-----------|-------|--------|---------|
| TDD Generic | `subrecipes/tdd-generic.yaml` | `subrecipes/tdd-generic.md` | Red-Green-Refactor cycle for any language |
| Language Detection | `subrecipes/language-detection.yaml` | `subrecipes/language-detection.md` | Auto-detect project stack |
| Static Analysis | `subrecipes/static-analysis.yaml` | `subrecipes/static-analysis.md` | Linters, formatters, type checkers |
| Git Best Practices | `subrecipes/git-best-practices.yaml` | `subrecipes/git-best-practices.md` | Conventional commits, branch naming, PR hygiene |
| Docker ML Environment | `subrecipes/docker-ml-environment.yaml` | `subrecipes/docker-ml-environment.md` | Containerized ML with GPU support |
| MLflow Tracking | `subrecipes/mlflow-tracking.yaml` | `subrecipes/mlflow-tracking.md` | Experiment tracking, model registry, HPO |
| arXiv Search | `subrecipes/arxiv-search.yaml` | — | arXiv API paper discovery |
| Citation Graph | `subrecipes/citation-graph.yaml` | — | Semantic Scholar citation analysis |
| Literature Review | `subrecipes/literature-review.yaml` | — | PRISMA-inspired systematic review |
| Design System | `subrecipes/design-system.yaml` | — | Design tokens, component specs |
| Asana Sync | `subrecipes/asana-sync.yaml` | `agents/subrecipes/asana-sync.md` | Best-effort Asana task sync — preflight, find-or-create project, resolve assignee, graceful degradation |

### Goose-Only: Coding Agent Context
A portable orchestration framework for complex multi-step workflows. See [goose/coding_agent_context/](goose/coding_agent_context/).

| Component | Purpose |
|-----------|---------|
| **Missions** (9) | Step-by-step workflows: tactical updates, TDD, architecture, data exploration, ML research, docs, code review |
| **Roles** (7) | Sub-agent identities: analyst, architect, developer, QA, doc writer, code reviewer, ML researcher |
| **Tools** (6) | Docker-based infrastructure: test runner, dev container, data explorer |

---

## Workflows (Claude Code)

Individual agents do one job. **Workflows** are `/wf-*` slash commands that orchestrate
several agents into a multi-step pipeline with **gates** between phases — the agents
hold the expertise, the workflow defines the hand-offs and the stop conditions. Think
of an agent as a specialist and a workflow as the lead engineer who sequences them and
refuses to move on until each step actually passes.

> Workflows are **first-class on Claude Code** (the `/wf-*` slash commands below).
> Goose has recipe renderings of all 15 under `goose/general/workflows/` (run with
> `goose run --recipe goose/general/workflows/wf-feature.yaml`); **Kiro has no workflow
> primitive** (agents only). Canonical catalog: [`shared/workflows.md`](shared/workflows.md).

### Install & invoke

```bash
./setup.sh --claude                              # installs agents + /wf-* commands (user-level)
# or load the whole bundle as a plugin:
claude --plugin-dir /path/to/agent-recipes/claude
```

Then just type the command in Claude Code:

```
/wf-feature add a token-bucket rate limiter to the API client
/wf-pre-pr
/wf-bugfix median() returns the wrong value for even-length lists
```

### The 16 workflows

**Core dev loop**

| Command | What it does | Agents it orchestrates |
|---------|--------------|------------------------|
| `/wf-feature` | Build a feature via strict TDD | detect → `architect`/`api-designer` → `test-architect` (RED) → `{lang}-expert` (GREEN) → `code-reviewer` → `documentation-agent` |
| `/wf-bugfix` | Fix a bug, regression-test first | `debugger` (writes failing test) → `{lang}-expert` (fix) → `code-reviewer` |
| `/wf-refactor` | Behavior-preserving refactor under a test guard | `analyst` → `test-architect` (characterization) → `{lang}-expert` → `code-reviewer` |
| `/wf-pre-pr` | Pre-merge quality gate | `static-analysis` + `code-reviewer` + `security-auditor` + `dependency-auditor` (parallel) |
| `/wf-perf` | Measure-driven optimization | `performance-optimizer` (baseline) → `{lang}-expert` → re-measure → `code-reviewer` |

**Plan & build**

| Command | What it does | Agents it orchestrates |
|---------|--------------|------------------------|
| `/wf-spec` | Idea → PRD → design + plan | `product-manager` (PRD) → `ai-researcher` → `architect` (feeds `/wf-feature`) |
| `/wf-api` | Contract-first API build | `api-designer` → `test-architect` → `{lang}-expert` → `code-reviewer` → `documentation-agent` |
| `/wf-new-project` | Scaffold + prove the harness + docs | `project-bootstrapper` → `test-architect` → `{lang}-expert` → `documentation-agent` |
| `/wf-db-change` | Schema change with a safe, tested migration | `postgresql-expert` (forward+rollback) → `test-architect` → `code-reviewer` |

**Understand, maintain, ship**

| Command | What it does | Agents it orchestrates |
|---------|--------------|------------------------|
| `/wf-understand` | Map/onboard an unfamiliar codebase | `analyst` (read-only) → `documentation-agent` |
| `/wf-migrate` | Large-scale codemod | `analyst` (discover) → `{lang}-expert` (worktree isolation) → `code-reviewer` |
| `/wf-upgrade-deps` | Guarded one-at-a-time dependency upgrade | `dependency-auditor` → `{lang}-expert` → `code-reviewer` |
| `/wf-release` | Cut a release (gated, confirmed) | `security-auditor` + `dependency-auditor` → `documentation-agent` → `sre` → `git-best-practices` |
| `/wf-fanout` | Run a task as parallel, isolated agent streams | decompose → `Agent` ×N (non-overlapping files / worktree) → per-stream verify+commit → reconcile |

**ML**

| Command | What it does | Agents it orchestrates |
|---------|--------------|------------------------|
| `/wf-ml-research` | Open question → reproducible setup | `ai-researcher` → `docker-ml-environment` → `mlflow-tracking` |
| `/wf-experiment` | Run + compare a named ML hypothesis | `ai-researcher` → `data-engineer` → `{lang}-expert` → `mlflow-tracking` |

### When to use a workflow vs. a single agent

Use a **single agent** for a one-shot task (“review this file”, “explain this error”).
Reach for a **workflow** when the task has multiple phases that must each be verified
before the next — that’s where the gates earn their keep.

| Your situation | Use |
|----------------|-----|
| Still a rough idea — need a PRD (priorities + success metrics) + a design before coding | `/wf-spec` |
| “Add feature X” and you want tests-first with a review gate | `/wf-feature` |
| Something is broken and you want a regression test to lock the fix | `/wf-bugfix` |
| Clean up structure without changing behavior, safely | `/wf-refactor` |
| About to open a PR; want one consolidated 🔴/🟠 gate | `/wf-pre-pr` |
| A hot path is slow and you want a *measured* improvement (or a revert) | `/wf-perf` |
| Building a new endpoint/service, contract-first | `/wf-api` |
| A schema/migration change you don't want to lock the DB or lose data | `/wf-db-change` |
| Starting a brand-new repo from nothing | `/wf-new-project` |
| Dropped into an unfamiliar codebase and need a map | `/wf-understand` |
| A repo-wide rename/codemod across many files | `/wf-migrate` |
| Dependencies are stale/vulnerable and you want a guarded upgrade | `/wf-upgrade-deps` |
| Cutting a release with a quality gate + changelog | `/wf-release` |
| Open ML question → reproducible, tracked setup | `/wf-ml-research` |
| A named ML hypothesis you want to run + compare against a baseline | `/wf-experiment` |
| Just one focused action (review / debug / refactor one thing) | the matching **agent**, no workflow |

### Worked example: `/wf-feature`

```
/wf-feature add a chunk(items, size) helper that splits a list into fixed-size chunks
```

What the orchestrator actually does — and refuses to skip:

1. **DETECT** — runs `language-detection`; finds Python + pytest, picks `python-expert`.
2. **DESIGN** *(skipped for a small feature; used for multi-module work)*.
3. **RED** — dispatches **`test-architect`** (a *different* agent from the implementer) to
   write failing tests for the happy path, edge cases, and error conditions, then runs
   the suite. **Gate:** the tests must fail *because the behavior is missing* — if the
   runner errors for a toolchain reason, it stops and tells you instead of pretending.
4. **GREEN** — dispatches **`python-expert`** to make the tests pass, forbidden from
   editing any test file. Runs the suite. **Gate:** all green, or it loops with the
   failure output.
5. **REVIEW** — dispatches **`code-reviewer`**. **Gate:** a 🔴/🟠 verdict loops back to
   GREEN; only an APPROVE proceeds.
6. **DOCS** — dispatches `documentation-agent` for docstrings + a changelog entry.
7. **REPORT** — shows the diff, the passing test output, and the review verdict.

The result is a feature whose tests were written by one agent and implemented by
another (genuine RED/GREEN separation), reviewed before it lands.

### Why workflows are trustworthy: the gate pattern

Every workflow is **evidence-gated** — it will not advance on a claim, only on a checked
result:

- `/wf-feature` & `/wf-api` won’t reach GREEN until the orchestrator has *seen* the tests
  go red for the right reason, and won’t finish until it has *seen* them pass.
- `/wf-pre-pr` returns **BLOCK** on any 🔴, and **BLOCK (inconclusive)** if any analyzer
  failed to run — a broken scan never reads as a clean pass.
- `/wf-perf` commits an improvement threshold *before* the change exists and **reverts**
  if the re-measurement doesn’t beat it — correctness is never traded for speed.

### Examples

**Real invocations** — type the command; the workflow runs the named agents through their gates:

```bash
/wf-feature add a POST /users/{id}/avatar upload endpoint
/wf-bugfix login 500s when the email has a trailing space
/wf-refactor extract the retry logic in api/client.py into a decorator
/wf-perf the dashboard query that takes ~3s
/wf-upgrade-deps requests            # one bump at a time; reverts any that breaks tests
/wf-pre-pr                           # consolidated 🔴/🟠 gate before you open the PR
/wf-understand what does the billing module do and where do I start?
/wf-spec a referral program for the app
/wf-db-change add a partial index on orders(user_id) where status = 'open'
/wf-ml-research best lightweight reranker for our search
/wf-experiment does adding BM25 features beat the embedding-only baseline?
```

**End-to-end: concept → shipped** — workflows compose, handing off through `.wf/` files:

```bash
/wf-spec     dark-mode toggle in settings   # → .wf/prd.md + .wf/design.md (seeds the Asana backlog)
/wf-feature  implement dark mode            # reads .wf/design.md; TDD build → review → docs
/wf-pre-pr                                   # static-analysis + review + security + deps gate
/wf-release  minor                           # changelog + version bump + tag (asks before pushing)
```

**Turn on Asana** — drop a `.claude/asana.json` in the repo and every run reflects to your board
(find-or-create the task by key, move **To Do → In Progress → Done**, a comment per gate, PR link on done):

```json
{ "project_name": "my-app", "default_assignee": "me", "create_if_missing": true }
```

> Prefer one focused action? Skip the workflow and call the agent: `@agent-code-reviewer review src/auth`.

---

## Tutorial

### 1. Review Code Before a PR

**Goose:**
```bash
goose run --recipe goose/general/code-reviewer.yaml \
  --params target_path="src/" review_depth="deep" focus_areas="all"
```

**Claude Code:**
```
> Use the code-reviewer agent to review src/ with deep focus on all areas
```

Both produce a structured report:
```
# Code Review: src/
## Verdict: REQUEST CHANGES
## Critical Issues (🔴)
  src/auth/handler.py:45 — SQL injection via string interpolation
## Major Issues (🟠)
  src/api/users.py:23 — N+1 query in user list endpoint
## Suggestions (🔵)
  src/models/user.py:12 — Consider using dataclass instead of dict
```

### 2. Debug a Failing Test

**Goose:**
```bash
goose run --recipe goose/general/debugger.yaml \
  --params symptom="test_user_auth fails with 401" bug_type="logic_error"
```

**Claude Code:**
```
> Debug why test_user_auth fails with a 401 error
```

The debugger follows a scientific method:
1. **OBSERVE** — Reproduce the failure, read error output
2. **HYPOTHESIZE** — Rank likely causes (expired token? wrong endpoint? missing header?)
3. **TEST** — Isolate and test each hypothesis
4. **FIX** — Write regression test FIRST (RED), then apply minimal fix (GREEN)
5. **VERIFY** — Run full test suite, confirm no regressions

### 3. Bootstrap a New Project

**Goose:**
```bash
goose run --recipe goose/general/project-bootstrapper.yaml \
  --params project_name="my-api" language="python" project_type="api_service"
```

**Claude Code:**
```
> Use the project-bootstrapper agent to create a Python API service called "my-api"
```

Creates a production-ready scaffold:
```
my-api/
├── src/my_api/
│   ├── api/v1/routes/
│   ├── services/
│   ├── models/
│   └── schemas/
├── tests/
├── pyproject.toml          # ruff + mypy strict
├── Dockerfile              # Multi-stage, non-root
├── docker-compose.yaml
├── .github/workflows/ci.yml
├── Makefile
└── .pre-commit-config.yaml
```

### 4. Security Audit Before Release

**Goose:**
```bash
goose run --recipe goose/general/security-auditor.yaml \
  --params audit_scope="full" compliance_framework="owasp"
```

**Claude Code:**
```
> Run a full OWASP security audit on this project
```

Produces:
```
# Security Audit Report
## Risk Score: 6.2/10
## Critical (🔴): 2 findings
  - Hardcoded AWS key in src/config.py:12
  - SQL injection in src/api/search.py:34
## High (🟠): 3 findings
  - Missing rate limiting on /api/auth/login
  - Session tokens not rotated after password change
  - Debug mode enabled in production config
```

### 5. ML Research Workflow

**Goose:**
```bash
goose run --recipe goose/general/ai-researcher.yaml \
  --params research_topic="contrastive learning for recommendations" \
          research_type="literature_review" scope="focused"
```

**Claude Code:**
```
> Use the ai-researcher agent to survey contrastive learning for recommendation systems
```

Delivers:
1. PRISMA-style literature review with arXiv search
2. Citation graph analysis (PageRank, influence flow)
3. 3-5 solution candidates with architecture diagrams
4. Weighted tradeoff decision matrix
5. Mathematical formulation with gradient computation
6. Docker-based experiment setup with MLflow tracking

### 6. Design a REST API

**Goose:**
```bash
goose run --recipe goose/general/api-designer.yaml \
  --params api_name="user-service" api_style="rest" api_maturity="production"
```

**Claude Code:**
```
> Use the api-designer agent to design a production REST API for the user service
```

Produces: domain model (Mermaid ER), endpoint specs, OpenAPI 3.1 schema, RFC 7807 error format, cursor-based pagination, auth patterns, and contract-first TDD plan.

### 7. UX Design with Accessibility

**Goose:**
```bash
goose run --recipe goose/general/ux-designer.yaml \
  --params task_type="full_ux_process" platform="mobile" wcag_level="AA"
```

**Claude Code:**
```
> Use the ux-designer agent for a full UX process on the mobile onboarding flow, targeting WCAG AA
```

Delivers: user personas, journey maps (Mermaid), information architecture, ASCII wireframes for all 7 screen states, design tokens as CSS/Dart code, WCAG 2.2 AA audit, responsive breakpoints, and TDD test plan.

### 8. Use Language Experts

**Goose:**
```bash
# Refactor Python code
goose run --recipe goose/general/languages/python-expert.yaml \
  --params target_path="src/services/" task="refactor"

# Optimize PostgreSQL queries
goose run --recipe goose/general/languages/postgresql-expert.yaml \
  --params target_path="migrations/" task="optimize_queries"
```

**Claude Code:**
```
> Have the python-expert agent refactor src/services/
> Use the postgresql-expert to optimize the slow queries in our migrations
```

### 9. Chain Multiple Agents

**Goose** (sequential recipe execution):
```bash
# Design → Implement → Review → Document
goose run --recipe goose/general/api-designer.yaml \
  --params api_name="orders" api_style="rest"

goose run --recipe goose/general/languages/python-expert.yaml \
  --params task="implement" target_path="src/api/orders/"

goose run --recipe goose/general/code-reviewer.yaml \
  --params target_path="src/api/orders/" review_depth="deep"

goose run --recipe goose/general/documentation-agent.yaml \
  --params target_path="src/api/orders/" doc_type="api_reference"
```

**Claude Code** (agents chain automatically via conversation):
```
> Design a REST API for the orders service, then implement it in Python,
  review the code, and generate API documentation
```

### 10. Goose: Coding Agent Context (Multi-Step Missions)

For complex workflows that need persistent state, sub-agent dispatch, and Docker execution:

```bash
# Architecture design for a new feature
goose run --recipe goose/coding_agent_context/recipes/mission_architecture_design.yaml \
  --params feature="user-recommendations"

# TDD implementation (reads the design doc from previous step)
goose run --recipe goose/coding_agent_context/recipes/mission_tdd.yaml \
  --params feature="user-recommendations"

# Code review
goose run --recipe goose/coding_agent_context/recipes/mission_review_code_change.yaml \
  --params feature="user-recommendations"
```

See [goose/coding_agent_context/MISSION_INDEX.md](goose/coding_agent_context/MISSION_INDEX.md) for the full mission selection guide.

---

## Enforced Practices

All agents enforce these principles regardless of platform:

| Practice | How Enforced |
|----------|-------------|
| **TDD** | Every agent requires tests FIRST — Red-Green-Refactor is mandatory |
| **Language best practices** | Per-language checklists (PEP 484 for Python, Effective Dart, etc.) |
| **Modularity** | Max 400 lines/file, 30 lines/function, 7 public methods/class |
| **Security** | Secret detection, OWASP checks, regression tests for vulnerabilities |
| **Docker** | ML work requires Docker environments for reproducibility |
| **Accessibility** | UX work requires WCAG 2.2 AA compliance |
| **Severity scale** | Shared 🔴🟠🟡🔵ℹ️ classification (see `shared/severity-scale.md`) |
| **Naming** | Consistent conventions across platforms (see `shared/naming-conventions.md`) |

---

## Format Comparison

| Feature | Goose (YAML) | Claude Code (Markdown) |
|---------|-------------|----------------------|
| File format | `.yaml` with structured fields | `.md` with YAML frontmatter |
| Parameters | Typed `parameters:` with defaults and options | Natural language in prompt |
| Sub-delegation | `sub_recipes:` with file paths | Chain agents via main conversation |
| Retry logic | `retry:` block with shell checks | `hooks:` with exit codes |
| Tool access | `extensions:` (builtin/MCP) | `tools:` allowlist |
| Persistent memory | None | `memory: user/project/local` |
| Model control | `settings.temperature` | `model: sonnet/opus/haiku` |
| Composability | Recipe chaining via CLI | Automatic delegation in conversation |

---

## Choosing Between Platforms

| If you need... | Use |
|----------------|-----|
| Parameterized recipes with typed inputs | **Goose** |
| Persistent agent memory across sessions | **Claude Code** |
| Sub-agent orchestration with role isolation | **Goose** (coding_agent_context) |
| Automatic delegation based on task description | **Claude Code** |
| Docker-based execution with safety constraints | **Goose** (coding_agent_context) |
| CI/CD integration with recipe execution | **Goose** |
| Interactive development with conversation context | **Claude Code** |
| Multi-step missions with progress tracking | **Goose** (coding_agent_context) |

---

## Contributing

1. Fork the repository
2. Add or modify agents in both `goose/` and `claude/` directories
3. Ensure TDD is enforced in every new agent
4. Follow naming conventions in `shared/naming-conventions.md`
5. Update agent catalogs in this README and platform-specific READMEs
6. Submit a PR with description of the agent's purpose

When adding a new recipe:
- Create it in both `goose/general/` (YAML) and `claude/agents/` (Markdown)
- If it's a shared workflow, add it to `subrecipes/` on both platforms
- Update the Agent Catalog tables in all three READMEs

---

## License

MIT
