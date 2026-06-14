---
description: "Feature via TDD: detect → design → red → green → review → docs"
argument-hint: "<feature description>"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent
---

# Workflow: Feature (TDD)

**Feature:** $ARGUMENTS

You are the **orchestrator**. You do NOT write code or tests yourself — you
dispatch the specialist subagents below via the `Agent` tool, one phase at a
time, and you own the gate between phases. Stop and report if any gate fails.

## Subagents you will dispatch
- `language-detection` — identify language, framework, test runner, toolchain.
- `architect`, `api-designer`, or `ai-researcher` — optional design step for
  non-trivial features (multi-module design / interface / algorithm respectively).
- `test-architect` — RED phase: writes the failing tests (the test AUTHOR).
- a matching language expert (`python-expert`, `rust-expert`, `flutter-expert`,
  `postgresql-expert`, or `bash-expert`) — GREEN phase: makes the tests pass.
- `code-reviewer` — quality / security / performance gate.
- `documentation-agent` — docstrings, README, changelog.

## Steps

1. **DETECT.** Dispatch `language-detection`. Record the stack and the exact test
   command. Pick the matching `{lang}-expert`. If no expert matches, tell the user
   and stop.

2. **DESIGN (optional).** If `.wf/design.md` already exists (e.g. from `/wf-spec`),
   read it and build to it instead of re-designing. Otherwise, if the feature spans
   multiple modules or introduces a new public API, dispatch `architect` (multi-module
   design + ordered plan), `api-designer` (for an interface), or `ai-researcher` (for
   an algorithm) to produce a design note. Skip for small features.

3. **RED.** Dispatch `test-architect` (the dedicated test AUTHOR — a *different*
   agent from the implementer, so the tests specify the contract rather than the
   implementation):
   *"Write ONLY failing tests that specify the behavior for: $ARGUMENTS. Do NOT
   implement anything. Cover happy path, edge cases, and error conditions."*
   Then run the test command yourself.
   **GATE:** the new tests MUST fail *because the behavior is missing*. If the test
   command instead errors for a toolchain/setup reason (missing interpreter, no
   virtualenv, uninstalled deps), STOP and report the raw error to the user — do
   not treat a broken runner as a valid RED.

4. **GREEN.** Dispatch the matching `{lang}-expert` — a genuinely different agent
   from the `test-architect` that wrote the tests, giving identity-based RED/GREEN
   separation — with:
   *"Make the failing tests pass with the minimal correct implementation. You may
   NOT edit any test file."* Then run the test command.
   **GATE:** all tests must pass. If the runner errors for a toolchain reason
   rather than an assertion failure, stop and report it. Otherwise, if tests fail,
   dispatch again with the failure output.

5. **REVIEW.** Dispatch `code-reviewer` on the diff.
   **GATE:** if the verdict is REQUEST CHANGES (any 🔴 or 🟠), summarize the
   findings, dispatch the `{lang}-expert` to address them (tests still off-limits),
   re-run tests, and re-review. Loop until APPROVE.

6. **DOCS.** Dispatch `documentation-agent` to add/update docstrings, public-API
   docs, and a changelog entry for the feature.

7. **REPORT.** Show the user: the final diff summary, the passing test output, and
   the code-reviewer verdict. State plainly whether every gate passed.

## Asana sync (optional side-channel)
If an Asana project is configured (see the `asana-sync` subrecipe), dispatch `asana-sync`
to mirror this run: `start` (task → In Progress) at step 1, a `comment` after each gate
(RED / GREEN / REVIEW), and `done` (+ PR link) at REPORT. It preflights availability and
**degrades gracefully** — if Asana isn't configured or is unreachable it's a silent no-op
and the run is unaffected. An Asana error must never fail the build.
