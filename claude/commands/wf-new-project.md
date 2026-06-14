---
description: "Scaffold a new project, prove the harness with a TDD smoke feature, then document"
argument-hint: "<project name> <language> [type: cli|api|library|...]"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent
---

# Workflow: New Project

**Request:** $ARGUMENTS

You are the **orchestrator**. You dispatch specialists via the `Agent` tool and own
the gate between phases. A scaffold is not "done" until its own test harness runs a
real test green — an empty scaffold that has never executed a test is unproven.

## Subagents you will dispatch
- `project-bootstrapper` — production-ready structure (src/tests layout, packaging,
  linting, CI, Docker, pre-commit) for the language/type.
- `test-architect` — RED: a single failing smoke test that exercises the harness.
- a matching language expert (`python-expert`, `rust-expert`, etc.) — GREEN: make
  the smoke test pass.
- `documentation-agent` — README, quickstart, and a changelog seed.

## Steps

1. **SCAFFOLD.** Dispatch `project-bootstrapper` with the name, language, and type
   from $ARGUMENTS. It should produce the directory layout, dependency manifest with
   **pinned** versions, linter/formatter config, test config, Dockerfile, and CI.
   Instruct it to set up the **test harness and config only — do not implement a
   first feature**; the first capability is added via TDD in step 3. (This avoids a
   pre-existing passing feature colliding with the RED smoke test below.)
   **GATE:** the scaffold must define a runnable test command. If the request is
   ambiguous (language or type unclear), ask the user — do not guess the stack.

2. **VERIFY TOOLCHAIN.** Install/build and run the (possibly empty) test command
   yourself.
   **GATE:** the toolchain must be functional — deps resolve, the test runner
   starts. If it errors, send the scaffold back to `project-bootstrapper` with the
   raw error; do not proceed on a broken harness.

3. **SMOKE FEATURE (TDD).** Prove the harness end-to-end with one tiny real feature:
   - RED: dispatch `test-architect` to write ONE failing smoke test for a trivial
     first capability the scaffold does **not** yet implement (e.g. a version string,
     a health check, a pure helper). If the bootstrapper left a passing entry-point
     feature, pick a different, unimplemented capability so the test genuinely starts
     red. Run it; confirm it fails for the right reason.
   - GREEN: dispatch the `{lang}-expert` to implement it (tests off-limits). Run the
     suite; confirm green.
   **GATE:** red → green proven. This is what certifies the scaffold actually works.

4. **DOCS.** Dispatch `documentation-agent` for a README (what it is, how to install,
   how to run tests, how to build the Docker image) and a changelog seed.

5. **REPORT.** Show: the directory tree, the green smoke-test output, the test/build
   commands, and any decisions the user should confirm (license, CI provider, etc.).

## Asana sync (optional)
If an Asana project is configured, dispatch the `asana-sync` subrecipe to reflect this
run on the relevant Asana task — typically `start`, a `comment` at each gate/finding, and
`done` (with links) on completion, or `blocked` if a gate stops it. Best-effort and
non-blocking: a silent no-op if Asana isn't configured or reachable.
