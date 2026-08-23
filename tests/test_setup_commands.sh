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

# A pre-existing user command and skill that uninstall must NOT delete.
mkdir -p .claude/commands .claude/skills/my-own-skill
printf 'my own command\n' > .claude/commands/my-own.md
printf 'my own skill\n'   > .claude/skills/my-own-skill/SKILL.md

# ── Install (project-level) ───────────────────────────────────
"$SETUP" --claude-project >/dev/null

check "wf-feature.md installed" exists .claude/commands/wf-feature.md
check "wf-bugfix.md installed"  exists .claude/commands/wf-bugfix.md
check "wf.md router installed"  exists .claude/commands/wf.md
check "agents still installed"  exists .claude/agents/code-reviewer.md
check "test-architect installed" exists .claude/agents/test-architect.md
check "architect installed"      exists .claude/agents/architect.md
check "product-manager installed" exists .claude/agents/product-manager.md
check "data-engineer installed"  exists .claude/agents/data-engineer.md
check "sre installed"            exists .claude/agents/sre.md
check "typescript-expert installed" exists .claude/agents/languages/typescript-expert.md

# Phase 3 track B: subrecipes are now SKILLS (claude/skills/<name>/SKILL.md),
# installed to .claude/skills/; the old subrecipe agents must be gone.
check "language-detection skill installed" exists .claude/skills/language-detection/SKILL.md
check "asana-sync skill installed"         exists .claude/skills/asana-sync/SKILL.md
check "tdd-generic skill installed"        exists .claude/skills/tdd-generic/SKILL.md
check "subrecipe agents retired (source)"  bash -c "[[ ! -d '${REPO}/claude/agents/subrecipes' ]]"
check "no subrecipe agents installed"      bash -c "[[ ! -d .claude/agents/subrecipes ]]"
check "no 'subrecipe' wording left in claude/" \
  bash -c "! grep -rli subrecipe '${REPO}/claude/commands' '${REPO}/claude/agents' '${REPO}/claude/CONVENTIONS.md'"
wf_no_skill=0
for f in .claude/commands/wf-*.md; do
    grep -q '^allowed-tools:.*Skill' "$f" || { printf '       Skill tool missing: %s\n' "$f"; wf_no_skill=$((wf_no_skill+1)); }
done
check "all wf-* commands allow the Skill tool" test "$wf_no_skill" -eq 0

# Phase 3 track A: retired in favor of native Claude Code features — must not
# exist in the source tree (and therefore never install).
check "analyst retired (source)"   notexists "${REPO}/claude/agents/analyst.md"
check "analyst retired (install)"  notexists .claude/agents/analyst.md
check "wf-fanout retired (source)" notexists "${REPO}/claude/commands/wf-fanout.md"
check "wf-fanout retired (install)" notexists .claude/commands/wf-fanout.md
check "no lingering analyst dispatch in commands" \
  bash -c "! grep -rl 'Dispatch \`analyst\`' '${REPO}/claude/commands/'"

# Install must disable the Claude git co-author trailer in settings.json.
check "settings.json created"    exists .claude/settings.json
check "includeCoAuthoredBy=false" \
  python3 -c "import json,sys; sys.exit(0 if json.load(open('.claude/settings.json')).get('includeCoAuthoredBy') is False else 1)"

# The glob must install EVERY wf-*.md from source (guards new commands like
# wf-pre-pr / wf-api / wf-perf added without touching setup.sh).
src_count=$(find "${REPO}/claude/commands" -maxdepth 1 -name 'wf-*.md' | wc -l | tr -d ' ')
inst_count=$(find .claude/commands -maxdepth 1 -name 'wf-*.md' | wc -l | tr -d ' ')
check "all ${src_count} wf-* commands installed" test "$src_count" -eq "$inst_count"
check "full workflow set present (phase 5)" test "$src_count" -ge 15

# Every workflow must carry the uniform run-state/bounded-retry protocol AND
# name itself correctly in it (guards new workflows pasted without the block,
# or with another workflow's name left in the copied JSON example).
proto_bad=0
for f in .claude/commands/wf-*.md; do
    name="$(basename "$f" .md)"
    if ! grep -q 'Run state & bounded retries' "$f" || ! grep -q "\"workflow\": \"$name\"" "$f"; then
        printf '       protocol missing/misnamed: %s\n' "$f"
        proto_bad=$((proto_bad + 1))
    fi
done
check "all wf-* declare the run-state protocol" test "$proto_bad" -eq 0
check "router offers to resume in-progress runs" grep -q 'state.json' .claude/commands/wf.md

# ── Uninstall (precise: wf-* only) ────────────────────────────
"$SETUP" --uninstall >/dev/null

check "wf-feature.md removed"   notexists .claude/commands/wf-feature.md
check "wf-bugfix.md removed"    notexists .claude/commands/wf-bugfix.md
check "wf.md router removed"    notexists .claude/commands/wf.md
check "user command preserved"  exists    .claude/commands/my-own.md
check "our skills removed"      notexists .claude/skills/language-detection/SKILL.md
check "asana-sync skill removed" notexists .claude/skills/asana-sync/SKILL.md
check "user skill preserved"    exists    .claude/skills/my-own-skill/SKILL.md

# ── Plugin packaging: claude/ is a valid plugin bundling agents + commands ─────
check "plugin manifest exists"  exists "${REPO}/claude/.claude-plugin/plugin.json"
check "plugin manifest is valid JSON" \
  python3 -c "import json,sys; json.load(open('${REPO}/claude/.claude-plugin/plugin.json'))"
check "plugin root has agents/"   test -d "${REPO}/claude/agents"
check "plugin root has commands/" test -d "${REPO}/claude/commands"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
