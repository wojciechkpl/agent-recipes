# Tutorials

Ten step-by-step walkthroughs for the agents in this repo, each showing the
**Goose** command and the **Claude Code** prompt side by side.

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

See [goose/coding_agent_context/MISSION_INDEX.md](../goose/coding_agent_context/MISSION_INDEX.md) for the full mission selection guide.
