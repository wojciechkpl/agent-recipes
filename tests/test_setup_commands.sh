#!/usr/bin/env bash
# Contract test for setup.sh command installation (Phase 1 workflow layer).
#
# Asserts:
#   1. --claude-project installs wf-*.md slash commands into .claude/commands/
#   2. --uninstall removes ONLY wf-*.md, preserving the user's own commands
#
# Run: tests/test_setup_commands.sh   (exit 0 = pass, non-zero = fail)
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETUP="${REPO}/setup.sh"

pass=0
fail=0
check() {  # check <description> <test-expression...>
    local desc="$1"; shift
    if "$@"; then
        printf '  ok   %s\n' "$desc"; pass=$((pass + 1))
    else
        printf '  FAIL %s\n' "$desc"; fail=$((fail + 1))
    fi
}
exists()    { [[ -f "$1" ]]; }
notexists() { [[ ! -f "$1" ]]; }

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
cd "$workdir"

# A pre-existing user command that uninstall must NOT delete.
mkdir -p .claude/commands
printf 'my own command\n' > .claude/commands/my-own.md

# ── Install (project-level) ───────────────────────────────────
"$SETUP" --claude-project >/dev/null

check "wf-feature.md installed" exists .claude/commands/wf-feature.md
check "wf-bugfix.md installed"  exists .claude/commands/wf-bugfix.md
check "agents still installed"  exists .claude/agents/code-reviewer.md
check "test-architect installed" exists .claude/agents/test-architect.md
check "architect installed"      exists .claude/agents/architect.md
check "analyst installed"        exists .claude/agents/analyst.md
check "data-engineer installed"  exists .claude/agents/data-engineer.md
check "sre installed"            exists .claude/agents/sre.md
check "typescript-expert installed" exists .claude/agents/languages/typescript-expert.md

# The glob must install EVERY wf-*.md from source (guards new commands like
# wf-pre-pr / wf-api / wf-perf added without touching setup.sh).
src_count=$(find "${REPO}/claude/commands" -maxdepth 1 -name 'wf-*.md' | wc -l | tr -d ' ')
inst_count=$(find .claude/commands -maxdepth 1 -name 'wf-*.md' | wc -l | tr -d ' ')
check "all ${src_count} wf-* commands installed" test "$src_count" -eq "$inst_count"
check "full workflow set present (phase 5)" test "$src_count" -ge 15

# ── Uninstall (precise: wf-* only) ────────────────────────────
"$SETUP" --uninstall >/dev/null

check "wf-feature.md removed"   notexists .claude/commands/wf-feature.md
check "wf-bugfix.md removed"    notexists .claude/commands/wf-bugfix.md
check "user command preserved"  exists    .claude/commands/my-own.md

# ── Plugin packaging: claude/ is a valid plugin bundling agents + commands ─────
check "plugin manifest exists"  exists "${REPO}/claude/.claude-plugin/plugin.json"
check "plugin manifest is valid JSON" \
  python3 -c "import json,sys; json.load(open('${REPO}/claude/.claude-plugin/plugin.json'))"
check "plugin root has agents/"   test -d "${REPO}/claude/agents"
check "plugin root has commands/" test -d "${REPO}/claude/commands"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
