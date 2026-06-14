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
