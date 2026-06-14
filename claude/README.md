# Claude Code Agents

Specialized AI agents for [Claude Code](https://code.claude.com) — the CLI tool from Anthropic.

Each agent is a Markdown file with YAML frontmatter that defines a focused subagent with its own system prompt, tool access, model selection, and optional persistent memory.

## Installation

### Option 0: As a plugin (single portable unit — agents + workflows)
The `claude/` directory is a self-contained Claude Code plugin (`claude/.claude-plugin/plugin.json`)
that bundles all **29 agents** and **15 workflow commands**. Load it directly:
```bash
claude --plugin-dir /path/to/agent-recipes/claude
```
Everything (agents + `/wf-*` commands) is available with no copying. This is the
recommended way to get the agents *and* the workflows together. The copy-based
options below install agents only; use `setup.sh` to also install the workflow commands.

### Option 1: Project-Level (recommended for teams)
```bash
# From your project root
mkdir -p .claude/agents/languages .claude/agents/specialized .claude/agents/subrecipes

# Copy all agents
cp /path/to/agent-recipes/claude/agents/*.md .claude/agents/
cp /path/to/agent-recipes/claude/agents/languages/*.md .claude/agents/languages/
cp /path/to/agent-recipes/claude/agents/specialized/*.md .claude/agents/specialized/
cp /path/to/agent-recipes/claude/agents/subrecipes/*.md .claude/agents/subrecipes/
```

Then commit `.claude/agents/` to version control — your team gets the agents automatically.

### Option 2: User-Level (personal, all projects)
```bash
mkdir -p ~/.claude/agents/languages ~/.claude/agents/specialized ~/.claude/agents/subrecipes
cp claude/agents/*.md ~/.claude/agents/
cp claude/agents/languages/*.md ~/.claude/agents/languages/
cp claude/agents/specialized/*.md ~/.claude/agents/specialized/
cp claude/agents/subrecipes/*.md ~/.claude/agents/subrecipes/
```

## Usage

### Automatic Delegation
Claude automatically delegates based on agent descriptions:
```
Review the auth module for security issues
→ Claude delegates to security-auditor agent

Debug this failing test
→ Claude delegates to debugger agent
```

### Explicit Invocation
```
Use the code-reviewer agent to check my recent changes
Have the python-expert agent refactor this module
Use the ai-researcher agent to find the best recommendation algorithm
```

### Managing Agents
```bash
# List all agents (interactive)
/agents

# List agents (CLI)
claude agents
```

## Agent Catalog

### Core Agents
| Agent | Model | Tools | Memory | Description |
|-------|-------|-------|--------|-------------|
| `code-reviewer` | Sonnet | Read-only | Project | Code review for quality, security, performance |
| `test-architect` | Sonnet | All | Project | TDD RED phase — writes failing tests as an independent test author |
| `architect` | Sonnet | All | Project | System design docs + ordered implementation plans (no code) |
| `product-manager` | Sonnet | All | Project | PRDs, user stories, acceptance criteria, prioritization (RICE/MoSCoW), success metrics |
| `debugger` | Inherit | All | Project | Scientific debugging: observe → hypothesize → test → fix |
| `security-auditor` | Sonnet | Read + Bash | Project | OWASP Top 10, secret detection, CVE scanning |
| `performance-optimizer` | Inherit | All | Project | Measure → analyze → optimize → validate |
| `documentation-agent` | Inherit | All | — | API docs, READMEs, architecture diagrams, changelogs |
| `api-designer` | Sonnet | All | — | REST/GraphQL/gRPC design with OpenAPI generation |
| `dependency-auditor` | Haiku | Read + Bash | — | Vulnerability, license, unused, size analysis |
| `project-bootstrapper` | Sonnet | All | — | Scaffold new projects with TDD, CI/CD, Docker |
| `analyst` | Sonnet | Read-only | Project | Read-only codebase investigator — structure, data flow, risks |
| `data-engineer` | Sonnet | All | User | Data transforms/pipelines, Polars/Rust-first, schema validation |
| `sre` | Sonnet | All | Project | CI/CD, Dockerfiles, IaC, observability, deployment |
| `technical-writer` | Sonnet | All | Project | Long-form writing — blogs, RFCs, tutorials, paper drafts |

### Language Experts
| Agent | Description |
|-------|-------------|
| `python-expert` | Modern Python 3.10+, type hints, pytest, FastAPI/Django/PyTorch |
| `flutter-expert` | Dart 3.x, Riverpod, go_router, clean architecture, widget testing |
| `rust-expert` | Ownership, lifetimes, tokio async, thiserror/anyhow, proptest |
| `postgresql-expert` | Schema design, query optimization, RLS, partitioning, monitoring |
| `bash-expert` | Defensive scripting, CI/CD pipelines, bats-core testing |
| `typescript-expert` | Strict TypeScript, React/Node, ESLint/Prettier, vitest/jest |

### Specialized Agents
| Agent | Model | Description |
|-------|-------|-------------|
| `ai-researcher` | Opus | Literature review, ML solution design, tradeoff analysis, MLflow |
| `ux-designer` | Sonnet | Journey mapping, wireframes, design systems, WCAG 2.2 audit |

### Subrecipes (Shared Workflows)
| Agent | Description |
|-------|-------------|
| `tdd-generic` | Language-agnostic Red-Green-Refactor cycle |
| `language-detection` | Auto-detect project language, framework, toolchain |
| `static-analysis` | Language-appropriate linting and type checking |
| `git-best-practices` | Conventional commits, branch naming, PR hygiene |
| `docker-ml-environment` | Containerized ML infrastructure with GPU support |
| `mlflow-tracking` | ML experiment tracking, model registry, HPO |

## Workflows (slash commands)

Multi-step **workflows** that orchestrate the agents above. Installed into
`.claude/commands/` (project) or `~/.claude/commands/` (user) by `setup.sh`, then
invoked as slash commands. Each is a thin sequencer — the agents hold the knowledge;
the workflow defines the hand-offs and gates. Canonical catalog: `shared/workflows.md`.

| Command | Purpose | Orchestrates |
|---------|---------|--------------|
| `/wf-feature` | Implement a feature via strict TDD | `language-detection` → `architect`/`api-designer` → `test-architect` (RED) → `{lang}-expert` (GREEN) → `code-reviewer` → `documentation-agent` |
| `/wf-bugfix` | Fix a bug, regression-test first | `debugger` → `{lang}-expert` → `code-reviewer` |
| `/wf-pre-pr` | Pre-merge gate (any 🔴 blocks) | `static-analysis` + `code-reviewer` + `security-auditor` + `dependency-auditor` |
| `/wf-api` | Contract-first API build | `api-designer` → `test-architect` → `{lang}-expert` → `code-reviewer` → `documentation-agent` |
| `/wf-perf` | Measure-driven optimization | `performance-optimizer` → `{lang}-expert` → `code-reviewer` |
| `/wf-new-project` | Scaffold + TDD smoke + docs | `project-bootstrapper` → `test-architect` → `{lang}-expert` → `documentation-agent` |
| `/wf-ml-research` | Research → reproducible setup | `ai-researcher` → `docker-ml-environment` → `mlflow-tracking` |
| `/wf-refactor` | Behavior-preserving refactor under a test guard | `analyst` → `test-architect` → `{lang}-expert` → `code-reviewer` |
| `/wf-upgrade-deps` | Guarded one-at-a-time dependency upgrade | `dependency-auditor` → `{lang}-expert` → `code-reviewer` |
| `/wf-experiment` | Run + compare an ML hypothesis | `ai-researcher` → `data-engineer` → `{lang}-expert` → `mlflow-tracking` |
| `/wf-understand` | Map/onboard an unfamiliar codebase | `analyst` → `documentation-agent` |
| `/wf-spec` | Idea → PRD → design + plan | `product-manager` (PRD) → `ai-researcher` → `architect` |
| `/wf-release` | Cut a release (gated) | `security-auditor` + `dependency-auditor` → `documentation-agent` → `sre` |
| `/wf-migrate` | Large-scale codemod | `analyst` → `{lang}-expert` (worktree isolation) → `code-reviewer` |
| `/wf-db-change` | Schema change with safe migration | `postgresql-expert` → `test-architect` → `code-reviewer` |

## Conventions

See `CONVENTIONS.md` for global rules enforced across all agents:
- TDD is mandatory for all code-writing agents
- Shared severity scale (🔴🟠🟡🔵ℹ️) for all auditing agents
- Naming conventions align with Goose recipes (see `shared/naming-conventions.md`)

## Key Differences from Goose Recipes

| Feature | Goose Recipe (YAML) | Claude Code Agent (Markdown) |
|---------|--------------------|-----------------------------|
| Parameters | Explicit typed params | Natural language in prompt |
| Sub-delegation | `sub_recipes:` | Can't spawn subagents; chain via main conversation |
| Retry/validation | `retry:` block with checks | `hooks:` with PreToolUse/PostToolUse |
| Tool control | `extensions:` | `tools:` allowlist / `disallowedTools:` denylist |
| Memory | None | `memory: user/project/local` — persistent cross-session |
| Background | N/A | `background: true` for concurrent work |
| Model | `settings.temperature` | `model: sonnet/opus/haiku/inherit` |
