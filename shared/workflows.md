# Workflow Catalog

> Single source of truth for multi-agent **workflows**. A workflow is a thin
> sequencer that dispatches the existing single-purpose agents (see
> `claude/agents/`, `goose/general/`) and defines the hand-offs, gates, and loops
> between them. Workflows add **orchestration**, not new domain knowledge.
>
> Renderings:
> - **Claude Code** → `claude/commands/wf-*.md` (slash commands)
> - **Goose** → `goose/coding_agent_context/missions/*.md` (missions)
> - **Kiro** → not yet supported (agents only)
>
> Keep this table and the renderings in sync by hand. There is intentionally
> **no build-script generator** — that is the boundary that keeps this layer light.

## Conventions

- Claude command names are prefixed `wf-` so they are easy to identify and
  uninstall, and never collide with a user's own commands. The one exception is
  **`/wf` (Claude-only)** — a *router*, not a workflow: it classifies the task
  against this catalog and hands off to exactly one `/wf-*` command via the
  SlashCommand tool. It never dispatches agents itself.
- The orchestrator (main agent) **never writes code itself** — it dispatches
  specialists via the `Agent` tool, one phase at a time, and owns the gate logic.
- A "gate" is a stop/loop condition the orchestrator enforces between phases
  (e.g. "tests must be red before GREEN", "code-reviewer must APPROVE").
- **Resumable + bounded (uniform protocol).** Every Claude workflow ends with the
  same **"Run state & bounded retries"** section: it maintains `.wf/state.json`
  (workflow, task, phase, per-gate result/attempts/evidence, next action), offers
  to resume an interrupted run on start, re-reads the state after context
  compaction, and bounds every gate loop to **3 attempts per phase** (unless a
  step names its own limit) before stopping with the full failure history.
  `tests/test_setup_commands.sh` asserts every `wf-*.md` carries the block and
  names itself in it; the `/wf` router also offers to resume an in-progress run.
- **Commit each phase's verified output before starting the next.** The orchestrator
  owns the commits; specialist agents leave changes in the tree (they don't commit).
  Don't let several phases' uncommitted changes accumulate — a branch switch or a
  parallel agent can scramble or lose them.
- **Isolate parallel file-mutating agents.** When a phase fans out to agents that edit
  files concurrently (or another session shares the clone), give each its own
  `git worktree` (the `Agent` tool's `isolation: "worktree"`) or guarantee
  non-overlapping file sets. Verify `git branch --show-current` before every commit/push.
  See `git-best-practices` → *Concurrent Sessions & Worktree Isolation*.

## Catalog

| Workflow | Purpose | Agent sequence | Gates / loops |
|----------|---------|----------------|---------------|
| `wf-feature` | Implement a feature via strict TDD | `language-detection` → (`architect` \| `api-designer` \| `ai-researcher`, optional design) → `test-architect` (RED: tests only) → `{lang}-expert` (GREEN: impl only) → `code-reviewer` → `documentation-agent` | tests MUST fail after RED before GREEN; `code-reviewer` REQUEST CHANGES loops back to GREEN |
| `wf-bugfix` | Fix a bug with a regression test first | `debugger` (reproduce + write failing regression test) → `{lang}-expert` (GREEN: minimal fix, no test edits) → `code-reviewer` | regression test red→green; review loops to GREEN |
| `wf-pre-pr` | Pre-merge quality gate | `static-analysis` → `code-reviewer` → `security-auditor` → `dependency-auditor` | any 🔴 finding BLOCKS; emit a consolidated gate report |
| `wf-api` | Design then build an API endpoint/service | `api-designer` → `test-architect` (RED) → `{lang}-expert` (GREEN) → `code-reviewer` → `documentation-agent` | contract-first; review loop |
| `wf-perf` | Measure-driven performance optimization | `performance-optimizer` (baseline) → `{lang}-expert` (optimize) → `code-reviewer` → `performance-optimizer` (re-measure) | optimized result MUST beat baseline or revert |
| `wf-new-project` | Scaffold a new project | `project-bootstrapper` → `test-architect` (RED smoke) → `{lang}-expert` (GREEN) → `documentation-agent` | toolchain must run; scaffold certified by a smoke test going red→green |
| `wf-ml-research` | ML research → reproducible setup | `ai-researcher` → `docker-ml-environment` → `mlflow-tracking` | approach must be named before ENV; image must build + import (host-limit → stop, defect → retry ≤3); tracking run must be verifiably logged |
| `wf-refactor` | Behavior-preserving refactor under a test guard | `Explore` (built-in, opt) → `test-architect` (characterization tests) → `{lang}-expert` (refactor) → `code-reviewer` | green suite before AND after; behavior change → revert to checkpoint |
| `wf-upgrade-deps` | Guarded dependency upgrade | `dependency-auditor` → `{lang}-expert` (one bump at a time) → `code-reviewer` | green baseline required; each dep kept only if suite stays green, else reverted + deferred |
| `wf-experiment` | Run + compare an ML hypothesis | `ai-researcher` → `data-engineer` → `{lang}-expert` → `mlflow-tracking` (+ `docker-ml-environment`) | falsifiable hypothesis + 1 primary metric; conclusion from logged runs only; honest negative results |
| `wf-understand` | Map/onboard an unfamiliar codebase | `Explore` (built-in, read-only) → `documentation-agent` | analysis must cite `file:line` evidence; read-only except docs |
| `wf-spec` | Idea → PRD → design + plan | `product-manager` (PRD) → (`ai-researcher` opt) → `architect` | clarify once; PRD states measurable success + MVP scope; design covers every acceptance criterion; feeds `wf-feature` |
| `wf-release` | Cut a release | `security-auditor` + `dependency-auditor` → `documentation-agent` → (`sre`) → `git-best-practices` | any 🔴 / failing tests BLOCK; no tag/push without user confirmation |
| `wf-migrate` | Large-scale codemod | `Explore` (built-in; discover sites) → `{lang}-expert` (transform, worktree isolation) → `code-reviewer` | green baseline; per-site verify; deferred/skipped sites reported, never silent |
| `wf-db-change` | Schema change with a safe migration | `postgresql-expert` (forward + rollback) → `test-architect` → (`{lang}-expert`) → `code-reviewer` | rollback must work on scratch DB; no blocking migration on large tables; no prod apply without confirmation |

## New supporting agents

These agents back the workflows above:

- **`product-manager`** — PRD, prioritization (RICE/MoSCoW), success metrics (powers `wf-spec`).
- *(retired)* `analyst` — replaced by the built-in **Explore** agent in `wf-understand` / `wf-migrate` / `wf-refactor`; the structured-report contract now lives in those workflows' dispatch prompts.
- **`data-engineer`** — data transforms/pipelines, Polars/Rust-first (powers `wf-experiment`).
- **`sre`** — CI/CD, containers, IaC, deployment (powers `wf-release`).
- **`technical-writer`** — long-form writing (blogs, RFCs, papers); complements `documentation-agent`.
- **`typescript-expert`** — a `{lang}-expert` for TypeScript/JS (web/Node).
- **`asana-sync`** (subrecipe) — best-effort Asana task sync; optional side-channel in
  **every** workflow. Preflights availability, finds-or-creates the project, resolves the
  assignee; silent no-op if Asana isn't configured/reachable (config via caller /
  `ASANA_PROJECT_GID` / `.claude/asana.json`).

## TDD agent-separation note

The repo has a dedicated **`test-architect`** (RED — writes the failing tests) that
is a genuinely distinct identity from the **`{lang}-expert`** (GREEN — makes them
pass). This is true identity-based separation: the test author is not the
implementer, so the tests specify the contract rather than the implementation.

Fallback (if `test-architect` is not installed): enforce the separation by
**constraint** — dispatch the same `{lang}-expert` twice with role-locked
instructions (RED: "tests only, do NOT implement"; GREEN: "make tests pass, you may
NOT edit any test file").

## Phase status

- [x] `wf-feature`  (Phase 1)
- [x] `wf-bugfix`   (Phase 1)
- [x] `wf-pre-pr`   (Phase 2)
- [x] `wf-api`      (Phase 2)
- [x] `wf-perf`     (Phase 2)
- [x] `wf-new-project` (Phase 3)
- [x] `wf-ml-research`  (Phase 3)
- [x] `wf-refactor`     (Phase 5)
- [x] `wf-upgrade-deps` (Phase 5)
- [x] `wf-experiment`   (Phase 5)
- [x] `wf-understand`   (Phase 5)
- [x] `wf-spec`         (Phase 5)
- [x] `wf-release`      (Phase 5)
- [x] `wf-migrate`      (Phase 5)
- [x] `wf-db-change`    (Phase 5)
