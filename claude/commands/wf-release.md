---
description: "Cut a release: pre-flight gate → changelog → version bump → tag (with confirmation)"
argument-hint: "<version, e.g. 1.4.0 | major|minor|patch | auto>"
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent
---

# Workflow: Release

**Version:** $ARGUMENTS

You are the **orchestrator**. A release is outward-facing and hard to undo — so it
passes a quality gate first, and you **confirm with the user before tagging or
pushing**. You dispatch specialists and own the gates.

## Subagents you will dispatch
- `dependency-auditor` + `security-auditor` — pre-release risk gate.
- `documentation-agent` — changelog from commits since the last release.
- `sre` — (optional) build/publish the release artifact.
- the `git-best-practices` subrecipe — conventional tag/commit hygiene.

## Steps
1. **PRE-FLIGHT.** Run the full test suite (must be green). Dispatch `security-auditor`
   and `dependency-auditor` on the release.
   **GATE:** any 🔴 (unpatched CVE, secret, critical finding) **BLOCKS** the release —
   report and stop. Tests failing or analyzers that couldn't run also block.
2. **RESOLVE VERSION.** From $ARGUMENTS (explicit, or bump level, or `auto` from
   conventional commits since the last tag). Confirm the resulting version with the user.
3. **CHANGELOG.** Dispatch `documentation-agent` to generate/append the changelog
   entry from commits since the last tag (grouped: features / fixes / breaking).
4. **BUMP.** Update the version in the canonical place(s) (`pyproject.toml`,
   `package.json`, `Cargo.toml`, etc.) and the changelog.
5. **BUILD (optional).** Dispatch `sre` to build/validate the artifact (image, wheel)
   if the project ships one.
6. **TAG & COMMIT.** Per `git-best-practices`, prepare the release commit + annotated
   tag. **Do NOT push or publish without explicit user confirmation** — present the
   exact commands and what they will do, and wait.
7. **REPORT.** The version, the gate results, the changelog, and the precise
   tag/push/publish commands the user can run (or that you ran once confirmed).

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
   {"workflow": "wf-release", "task": "<original $ARGUMENTS>",
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
