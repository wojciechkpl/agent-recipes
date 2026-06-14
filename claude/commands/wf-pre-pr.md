---
description: "Pre-merge gate: static analysis + review + security + deps; any 🔴 blocks"
argument-hint: "[target: path or git ref, default = current diff]"
allowed-tools: Bash, Read, Glob, Grep, Agent
---

# Workflow: Pre-PR Gate

**Target:** $ARGUMENTS  *(if empty, default to the working diff: `git diff` plus staged changes; if not a git repo, use the whole project)*

You are the **orchestrator** running a read-only **merge gate**. You do NOT fix
anything here — you run independent analyses, consolidate them, and return a single
PASS / BLOCK verdict. Fixing is a separate workflow (`/wf-bugfix` or a language
expert). Keep this run non-destructive: no file edits.

## Subagents you will dispatch
- `static-analysis` — linters, formatters, type checkers for the detected stack.
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
If an Asana project is configured, dispatch the `asana-sync` subrecipe to reflect this
run on the relevant Asana task — typically `start`, a `comment` at each gate/finding, and
`done` (with links) on completion, or `blocked` if a gate stops it. Best-effort and
non-blocking: a silent no-op if Asana isn't configured or reachable.
