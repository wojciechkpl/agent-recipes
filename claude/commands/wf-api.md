---
description: "Design then build an API contract-first: design → implement (TDD) → review → docs"
argument-hint: "<api/endpoint description>"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent
---

# Workflow: API (contract-first)

**API:** $ARGUMENTS

You are the **orchestrator**. You do NOT write code yourself — you dispatch
specialists via the `Agent` tool and own the gate between phases. The contract
produced in DESIGN is the source of truth that IMPLEMENT and REVIEW are checked
against.

## Subagents you will dispatch
- `api-designer` — endpoint/resource design, OpenAPI/schema, error format, pagination, auth.
- `language-detection` — identify the stack and test command.
- `test-architect` — RED phase: failing tests derived from the contract.
- a matching language expert (`python-expert`, `rust-expert`, etc.) — GREEN phase: implement.
- `code-reviewer` — quality + contract-conformance gate.
- `documentation-agent` — API reference from the contract.

## Steps

1. **DESIGN.** Dispatch `api-designer` for: $ARGUMENTS. Require a concrete contract —
   resource model, endpoint specs (method, path, request/response), error schema
   (e.g. RFC 7807), pagination, auth, and status codes. **Persist the contract to a
   known artifact: `.wf/api-contract.md`.** Every downstream phase reads that exact
   path (a separate subagent cannot see another's output, so the file is the only
   reliable hand-off).
   **GATE:** the contract must cover every endpoint the user asked for before you
   proceed. If ambiguous, ask the user, do not guess the interface.

2. **DETECT.** Dispatch `language-detection`; pick the matching `{lang}-expert` and
   record the test command. Stop if no expert matches.

3. **IMPLEMENT (test-first).** Drive the same contract-first TDD loop as
   `/wf-feature`:
   - RED: dispatch `test-architect` to write failing tests derived **from the
     contract in `.wf/api-contract.md`** (request validation, success responses,
     error responses, status codes). Tests only — no implementation. Run the suite;
     confirm meaningfully red (stop and report if it errors for a toolchain reason).
   - GREEN: dispatch the same `{lang}-expert` to implement the endpoints until tests
     pass; it may NOT edit test files. Run the suite; confirm green. If the runner
     errors for a toolchain reason rather than an assertion failure, stop and report.

4. **REVIEW.** Dispatch `code-reviewer` on the diff, explicitly checking
   **conformance to the contract in `.wf/api-contract.md`** (paths, schemas, status
   codes, error shape) plus the usual correctness/security/perf.
   **GATE:** REQUEST CHANGES (any 🔴/🟠) loops back to GREEN; deviations from the
   contract are blocking. If 3 review rounds pass without converging, stop and
   surface the open findings to the user rather than looping further.

5. **DOCS.** Dispatch `documentation-agent` to generate the API reference from
   `.wf/api-contract.md` and the implementation.

6. **REPORT.** Show: the contract summary, passing test output, the review verdict,
   and any intentional contract changes made during implementation.

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
   {"workflow": "wf-api", "task": "<original $ARGUMENTS>",
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
