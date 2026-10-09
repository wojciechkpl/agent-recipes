#!/usr/bin/env bash
# Contract test for tools/check_manifests.py (Phase 4, Track D rules 1a–1e and
# Track E rule 2): the manifests, README counts, plugin-root references and skill
# frontmatter cannot drift.
#
# CLI shape this test pins down:
#   python3 tools/check_manifests.py [--root <dir>] [--base <git-ref>]
#     --root <dir>   repo root to check (default: the repo the script lives in,
#                    i.e. the parent of tools/ — CI runs it from the repo root)
#     --base <ref>   additionally require `version` in claude/.claude-plugin/plugin.json
#                    to be greater than at <ref> when `git diff --name-only <ref>...HEAD
#                    -- claude/` is non-empty (git runs inside --root)
#   exit 0 and NO output (stdout+stderr) on a correct tree
#   exit 1 with exactly ONE line per problem; each line names the file at fault
#   stdlib only (also run under `python3 -I -S`, which disables site-packages)
#
# Every rule is proven with a deliberately broken temp COPY of the repo. The live
# tree is never checked here — CI runs the script on it directly — so this file
# stays green regardless of whether the live data is currently right.
#
# Asserts:
#   1a. A/S/W counts (agents/skills/wf-* commands) are stated correctly in README.md
#       ("N specialist agents + N skills + N evidence-gated", "### The N workflows")
#       and in claude/README.md ("N agents", "N skills", "N workflow commands");
#       a reworded sentence FAILS (anchored pattern must match); subtotals like
#       "14 core agents" are left alone; the counts come from the tree (adding an
#       agent file makes both READMEs stale)
#   1b. `description` in marketplace.json and plugin.json contains no counts
#   1c. marketplace.json has a non-empty metadata.description
#   1d. every ${CLAUDE_PLUGIN_ROOT}/<path> in claude/commands/*.md and
#       claude/hooks/hooks.json names an existing file under claude/
#   1e. --base <ref>: a change under claude/ needs a version bump; no change under
#       claude/ needs none; a downgrade is not a bump; without --base no bump needed
#   E2. every claude/skills/*/SKILL.md has name == its directory and a non-empty
#       description
#   +   exit 0 / silent on a correct tree; exit 1 / one line per problem; --root
#       honoured from another cwd; default root = the script's own repo
#
# Run: tests/test_check_manifests.sh   (exit 0 = pass, non-zero = fail)
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${REPO}/tools/check_manifests.py"

HOME="$(mktemp -d)"; export HOME          # never touch the real $HOME (git config)
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir" "$HOME"' EXIT
OUT="$workdir/out"
cd "$workdir"                             # every --root run happens from OUTSIDE the fixture

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

# ── fixture helpers ───────────────────────────────────────────────────────────
# make_fixture <dir> — copies the parts of the repo the checker reads, then makes
# the copy CORRECT regardless of the live tree's state: marketplace.json gets a
# count-free description + metadata.description, every SKILL.md gets
# `name: <dir>` as its first frontmatter key if it lacks one. Idempotent.
make_fixture() {
    local fx="$1"
    mkdir -p "$fx"
    cp "$REPO/README.md" "$fx/README.md"
    cp -R "$REPO/claude" "$fx/claude"
    cp -R "$REPO/.claude-plugin" "$fx/.claude-plugin"
    cp -R "$REPO/tools" "$fx/tools"
    python3 - "$fx" <<'EOF'
import json, os, re, sys
fx = sys.argv[1]
mp = os.path.join(fx, ".claude-plugin", "marketplace.json")
d = json.load(open(mp))
d["plugins"][0]["description"] = ("Specialist agents, skills and evidence-gated "
                                  "TDD workflows for Claude Code.")
d.setdefault("metadata", {})["description"] = "Agents and workflows for Claude Code."
json.dump(d, open(mp, "w"), indent=2); open(mp, "a").write("\n")
skills = os.path.join(fx, "claude", "skills")
for name in sorted(os.listdir(skills)):
    p = os.path.join(skills, name, "SKILL.md")
    if not os.path.isfile(p):
        continue
    text = open(p).read()
    assert text.startswith("---\n"), p
    end = text.index("\n---", 4)
    fm = text[4:end]
    if not re.search(r"^name:", fm, re.M):
        text = "---\nname: %s\n%s%s" % (name, fm, text[end:])
    open(p, "w").write(text)
EOF
}

# replace_in <file> <old> <new> — literal in-place replace; ABORTS (set -e) when
# <old> is absent, so a "broken" fixture can never silently be an unbroken one.
replace_in() {
    python3 - "$1" "$2" "$3" <<'EOF'
import sys
p, old, new = sys.argv[1:4]
t = open(p).read()
assert old in t, "fixture bug: %r not in %s" % (old, p)
open(p, "w").write(t.replace(old, new))
EOF
}

# jedit <json-file> <python statement over `d`> — e.g. jedit f 'd["x"]=1'
jedit() {
    python3 - "$1" "$2" <<'EOF'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
exec(sys.argv[2])
json.dump(d, open(p, "w"), indent=2); open(p, "a").write("\n")
EOF
}

# ── runner + predicates ───────────────────────────────────────────────────────
rc=0
run_mc() {  # run_mc <args...> — sets $rc, captures stdout+stderr in $OUT
    rc=0
    python3 "$SCRIPT" "$@" >"$OUT" 2>&1 || rc=$?
}
dump_out() { sed 's/^/       | /' "$OUT"; }
# clean — exit 0 and no output at all
clean() {
    if [[ "$rc" -eq 0 && ! -s "$OUT" ]]; then return 0; fi
    printf '       | rc=%s\n' "$rc"; dump_out; return 1
}
# problems <n> <grep-pattern> — exit 1, exactly <n> lines, pattern present
problems() {
    local n="$1" pat="$2" lines
    lines="$(wc -l < "$OUT" | tr -d ' ')"
    if [[ "$rc" -eq 1 && "$lines" -eq "$n" ]] && grep -q -- "$pat" "$OUT"; then return 0; fi
    printf '       | rc=%s lines=%s want=%s pattern=%s\n' "$rc" "$lines" "$n" "$pat"; dump_out; return 1
}
# fresh <name> — makes a fixture at $workdir/<name>, echoes its path
fresh() { make_fixture "$workdir/$1"; echo "$workdir/$1"; }

echo "── script exists and is stdlib-only ──"
check "tools/check_manifests.py exists" test -f "$SCRIPT"

fx="$(fresh good)"
run_mc --root "$fx"
check "correct tree: exit 0 and silent (--root from another cwd)" clean
rc=0; python3 -I -S "$SCRIPT" --root "$fx" >"$OUT" 2>&1 || rc=$?
check "correct tree: still passes under python3 -I -S (no site-packages)" clean
rc=0; (cd "$fx" && python3 "tools/check_manifests.py") >"$OUT" 2>&1 || rc=$?
check "correct tree: no --root -> checks the repo the script lives in" clean

echo "── 1a. README counts ──"
fx="$(fresh readme_agents)"
replace_in "$fx/README.md" "22 specialist agents + 7 skills + 15 evidence-gated" "23 specialist agents + 7 skills + 15 evidence-gated"
run_mc --root "$fx"
check "README.md agents count wrong -> 1 problem naming README.md" problems 1 "README.md"

fx="$(fresh readme_workflows_heading)"
replace_in "$fx/README.md" "### The 15 workflows" "### The 16 workflows"
run_mc --root "$fx"
check "README.md '### The N workflows' wrong -> 1 problem" problems 1 "README.md"

fx="$(fresh readme_reworded)"
replace_in "$fx/README.md" "22 specialist agents + 7 skills + 15 evidence-gated" "22 expert agents and 7 skills and 15 evidence-gated"
run_mc --root "$fx"
check "README.md sentence reworded (anchor gone) -> fails, does not escape" problems 1 "README.md"

fx="$(fresh claude_readme_skills)"
replace_in "$fx/claude/README.md" "**7 skills**" "**8 skills**"
run_mc --root "$fx"
check "claude/README.md roster skills count wrong -> 1 problem naming claude/README.md" problems 1 "claude/README.md"

fx="$(fresh claude_readme_reworded)"
replace_in "$fx/claude/README.md" "**15 workflow commands**" "**15 workflows**"
run_mc --root "$fx"
check "claude/README.md roster reworded (anchor gone) -> fails" problems 1 "claude/README.md"

fx="$(fresh subtotals)"
replace_in "$fx/README.md" "14 core agents" "13 core agents"
run_mc --root "$fx"
check "subtotal '14 core agents' changed -> still clean (other numbers left alone)" clean

fx="$(fresh extra_agent)"
printf -- '---\nname: zig-expert\ndescription: test fixture\n---\nbody\n' > "$fx/claude/agents/languages/zig-expert.md"
run_mc --root "$fx"
check "new agent file, READMEs untouched -> both READMEs stale (2 problems)" problems 2 "README.md"
check "  ...one of them is claude/README.md" grep -q "claude/README.md" "$OUT"

fx="$(fresh missing_wf)"
rm "$fx/claude/commands/wf-perf.md"
run_mc --root "$fx"
check "wf-* command removed, READMEs untouched -> stale (3 problems: 2 README.md + 1 claude/README.md)" problems 3 "claude/README.md"

echo "── 1b. descriptions carry no counts ──"
fx="$(fresh mp_counts)"
jedit "$fx/.claude-plugin/marketplace.json" 'd["plugins"][0]["description"]="22 specialist agents + 15 TDD workflows."'
run_mc --root "$fx"
check "marketplace.json plugin description with a count -> 1 problem" problems 1 "marketplace.json"

fx="$(fresh plugin_counts)"
jedit "$fx/claude/.claude-plugin/plugin.json" 'd["description"]="Bundles 7 skills for Claude Code."'
run_mc --root "$fx"
check "plugin.json description with a count -> 1 problem" problems 1 "plugin.json"

echo "── 1c. marketplace.json metadata.description ──"
fx="$(fresh mp_no_metadata)"
jedit "$fx/.claude-plugin/marketplace.json" 'd.pop("metadata", None)'
run_mc --root "$fx"
check "metadata missing entirely -> 1 problem" problems 1 "marketplace.json"

fx="$(fresh mp_empty_metadata_desc)"
jedit "$fx/.claude-plugin/marketplace.json" 'd["metadata"]["description"]=""'
run_mc --root "$fx"
check "metadata.description empty -> 1 problem" problems 1 "marketplace.json"

echo "── 1d. \${CLAUDE_PLUGIN_ROOT} references resolve ──"
fx="$(fresh cmd_dangling)"
printf -- '---\ndescription: fixture\n---\nRun: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/does-not-exist.sh"`\n' > "$fx/claude/commands/fixture-cmd.md"
run_mc --root "$fx"
check "command .md pointing at a missing file -> 1 problem naming the path" problems 1 "scripts/does-not-exist.sh"

fx="$(fresh hooks_dangling)"
replace_in "$fx/claude/hooks/hooks.json" '${CLAUDE_PLUGIN_ROOT}/hooks/guard.sh' '${CLAUDE_PLUGIN_ROOT}/hooks/guard-x.sh'
run_mc --root "$fx"
check "hooks.json pointing at a missing file -> 1 problem naming the path" problems 1 "hooks/guard-x.sh"

echo "── E2. skill frontmatter ──"
fx="$(fresh skill_no_name)"
replace_in "$fx/claude/skills/tdd-generic/SKILL.md" "name: tdd-generic" "x-name: tdd-generic"
run_mc --root "$fx"
check "SKILL.md without name -> 1 problem naming the skill" problems 1 "tdd-generic"

fx="$(fresh skill_wrong_name)"
replace_in "$fx/claude/skills/tdd-generic/SKILL.md" "name: tdd-generic" "name: tdd"
run_mc --root "$fx"
check "SKILL.md name != directory -> 1 problem naming the skill" problems 1 "tdd-generic"

fx="$(fresh skill_empty_desc)"
python3 - "$fx/claude/skills/static-analysis/SKILL.md" <<'EOF'
import re, sys
p = sys.argv[1]; t = open(p).read()
t2 = re.sub(r"^description:.*$", 'description: ""', t, count=1, flags=re.M)
assert t2 != t, "fixture bug: no description line"
open(p, "w").write(t2)
EOF
run_mc --root "$fx"
check "SKILL.md with empty description -> 1 problem naming the skill" problems 1 "static-analysis"

fx="$(fresh skill_no_desc)"
python3 - "$fx/claude/skills/static-analysis/SKILL.md" <<'EOF'
import re, sys
p = sys.argv[1]; t = open(p).read()
t2 = re.sub(r"^description:.*\n", "", t, count=1, flags=re.M)
assert t2 != t, "fixture bug: no description line"
open(p, "w").write(t2)
EOF
run_mc --root "$fx"
check "SKILL.md without description -> 1 problem naming the skill" problems 1 "static-analysis"

echo "── one line per problem ──"
fx="$(fresh three_problems)"
replace_in "$fx/README.md" "22 specialist agents + 7 skills + 15 evidence-gated" "21 specialist agents + 7 skills + 15 evidence-gated"
jedit "$fx/.claude-plugin/marketplace.json" 'd["plugins"][0]["description"]="30 agents."'
replace_in "$fx/claude/hooks/hooks.json" '${CLAUDE_PLUGIN_ROOT}/hooks/guard.sh' '${CLAUDE_PLUGIN_ROOT}/hooks/gone.sh'
run_mc --root "$fx"
check "three independent problems -> exit 1 with exactly 3 lines" problems 3 "hooks/gone.sh"
check "  ...README.md named"        grep -q "README.md" "$OUT"
check "  ...marketplace.json named" grep -q "marketplace.json" "$OUT"

echo "── 1e. --base <ref>: version bump when claude/ changed ──"
gfx="$(fresh gitrepo)"
g() { git -C "$gfx" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false "$@"; }
g init -q
g add -A
g commit -qm base
g tag base
run_mc --root "$gfx" --base base
check "--base with no commits since -> clean" clean

printf '\nfixture change\n' >> "$gfx/claude/agents/architect.md"
g commit -qam "change under claude/"
run_mc --root "$gfx" --base base
check "claude/ changed, version not bumped -> 1 problem mentioning version" problems 1 "version"
run_mc --root "$gfx"
check "same tree WITHOUT --base -> clean (rule only applies with --base)" clean

jedit "$gfx/claude/.claude-plugin/plugin.json" 'a=d["version"].split("."); a[-1]=str(int(a[-1])+1); d["version"]=".".join(a)'
g commit -qam "bump"
run_mc --root "$gfx" --base base
check "claude/ changed AND patch version bumped -> clean" clean

jedit "$gfx/claude/.claude-plugin/plugin.json" 'd["version"]="0.0.1"'
g commit -qam "downgrade"
run_mc --root "$gfx" --base base
check "claude/ changed, version LOWER than base -> 1 problem (not a bump)" problems 1 "version"

g checkout -q base
g checkout -q -b docs-only
printf '\nextra line outside claude/\n' >> "$gfx/README.md"
g commit -qam "docs only"
run_mc --root "$gfx" --base base
check "only README.md changed since base, no bump -> clean" clean

# Pre-release versions must compare, not crash: "0.5.0-rc1" is above "0.4.0" (a
# bump) but below "0.5.0" (not a bump).
g checkout -q base
g checkout -q -b prerelease
jedit "$gfx/claude/.claude-plugin/plugin.json" 'd["version"]="0.4.0"'
g commit -q --allow-empty -am "base at 0.4.0"
g tag base040
jedit "$gfx/claude/.claude-plugin/plugin.json" 'd["version"]="0.5.0-rc1"'
printf '\nrc change\n' >> "$gfx/claude/agents/architect.md"
g commit -qam "0.5.0-rc1"
run_mc --root "$gfx" --base base040
check "claude/ changed, 0.4.0 -> 0.5.0-rc1 -> clean (pre-release is a bump, no traceback)" clean
jedit "$gfx/claude/.claude-plugin/plugin.json" 'd["version"]="0.5.0"'
g commit -qam "0.5.0"
g tag base050
jedit "$gfx/claude/.claude-plugin/plugin.json" 'd["version"]="0.5.0-rc1"'
printf '\nrc again\n' >> "$gfx/claude/agents/architect.md"
g commit -qam "back to 0.5.0-rc1"
run_mc --root "$gfx" --base base050
check "claude/ changed, 0.5.0 -> 0.5.0-rc1 -> 1 problem (pre-release is below the release)" problems 1 "version"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
