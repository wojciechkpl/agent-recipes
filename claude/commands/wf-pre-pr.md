---
description: "Pre-merge gate: static analysis + review + security + deps; any 🔴 blocks"
argument-hint: "[target: path or git ref, default = current diff]"
allowed-tools: Bash, Read, Glob, Grep, Agent, Skill
---

# Workflow: Pre-PR Gate

**Target:** $ARGUMENTS  *(if empty, default to the working diff: `git diff` plus staged changes; if not a git repo, use the whole project)*

You are the **orchestrator** running a read-only **merge gate**. You do NOT fix
anything here — you run independent analyses, consolidate them, and return a single
PASS / BLOCK verdict. Fixing is a separate workflow (`/wf-bugfix` or a language
expert). Keep this run non-destructive: no file edits.

## Subagents you will dispatch
- the `static-analysis` **skill** (run inline via the Skill tool) — linters, formatters, type checkers for the detected stack.
- `code-reviewer` — correctness, design, maintainability.
- `security-auditor` — OWASP Top 10, secret detection, dependency CVEs.
- `dependency-auditor` — vulnerable / unused / outdated / oversized deps.

## Steps

1. **SCOPE.** Resolve the target. If a git ref/diff, extract the changed files with
   `git diff --name-only`; pass the concrete scope to every analyzer so they review
   the same surface.

2. **ANALYZE (parallel).** Dispatch all four analyzers concurrently — they are
   independent and read-only. Give each the same scope. Ask every analyzer to label
   findings with the shared severity scale (🔴 critical, 🟠 major, 🟡 minor,
   🔵 suggestion, ℹ️ info) — see `shared/severity-scale.md`. Require each analyzer to
   return an explicit status (`completed` vs `could-not-run`). Treat a missing,
   errored, or status-less result as `could-not-run` — never as "no findings".

3. **CONSOLIDATE.** Merge findings into one report. De-duplicate where two analyzers
   flag the same line. Group by severity, then by file.

4. **GATE.**
   - **BLOCK (inconclusive)** if any analyzer is `could-not-run` — never PASS on
     partial coverage.
   - **BLOCK** if there is **any 🔴** (or any 🟠, only if the invocation in
     $ARGUMENTS explicitly asked to block on majors).
   - **PASS** only when all four analyzers completed and produced no blocking
     finding. 🟡/🔵 are reported but never block.

5. **REPORT.** Emit:
   - One-line verdict: `PASS` or `BLOCK`.
   - A counts line (e.g. `🔴 1  🟠 2  🟡 4`).
   - The grouped findings with `file:line` references.
   - If BLOCK, the minimal set of 🔴 items that must be resolved, and a suggested
     next step (`/wf-bugfix` for a defect, the matching language expert for a fix).
   Do not claim PASS if any analyzer failed to run — report the failure instead.

## Asana sync (optional)
If an Asana project is configured, invoke the `asana-sync` skill (Skill tool) to reflect this
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
   {"workflow": "wf-pre-pr", "task": "<original $ARGUMENTS>",
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
