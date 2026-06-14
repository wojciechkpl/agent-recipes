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
