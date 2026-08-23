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

## Run state & bounded retries (uniform protocol)

This workflow is **resumable** and its gate loops are **bounded**. Maintain
`.wf/state.json` throughout the run:

1. **START.** If `.wf/state.json` exists with `"status": "in_progress"`:
   - same `workflow` → show its `phase`, `gates`, and `next`, then ask the user
     ONCE: **resume** from the recorded phase or **start over** (reset the file).
     Trust recorded gate results only if the evidence still holds (e.g. re-run
     the test command rather than assuming a phase is still green).
   - different `workflow` → warn the user and ask before overwriting.
2. **AFTER EVERY GATE** — pass or fail — rewrite the file:
   ```json
   {"workflow": "wf-new-project", "task": "<original $ARGUMENTS>",
    "phase": "<current phase>", "status": "in_progress",
    "gates": {"<PHASE>": {"result": "pass|fail", "attempts": 1,
                          "evidence": "<one line: what was actually checked>"}},
    "next": "<the next concrete action>"}
   ```
3. **ON FINISH** set `"status": "done"`. When stopping early, set
   `"status": "stopped"` plus a `"reason"`. The file is transient — safe to
   delete; suggest adding `.wf/` to the project's `.gitignore` if it isn't.
4. **AFTER ANY CONTEXT COMPACTION**, re-read `.wf/state.json` before
   dispatching anything else.

**Retry contract:** every loop in the steps above ("dispatch again", "loop until
APPROVE", re-measure cycles) is bounded to **3 attempts per phase** unless the
step names its own limit, counted in `gates.<PHASE>.attempts`. On the final
failed attempt: STOP, write `"status": "stopped"`, and report the full failure
history to the user. Never advance past a failing gate, and never loop past the
cap — a bounded honest stop beats an unbounded token burn.
