#!/usr/bin/env bash
# Contract test for the plugin-native guard (Phase 4, Track A):
# claude/hooks/hooks.json, the guard_mode option, and `autonomous-mode.sh --plugin`.
#
# Asserts:
#   1. legacy entrypoint (no argument) still ALWAYS blocks — settings.json installs
#      made by older versions keep their behaviour
#   2. `guard.sh plugin` defaults to guard_mode=auto:
#        non-prompting permission modes -> block (exit 2)
#        prompting modes (default, plan) -> ask the user (exit 0 + permissionDecision)
#        permission mode missing         -> block (fail safe)
#   3. guard_mode=always blocks everywhere; guard_mode=off never blocks;
#      an unknown value is treated as always
#   4. safe commands stay silent and on the fast path in every mode
#   5. hooks.json is exec-form, references only files that exist, and wires the guard
#      with the `plugin` argument (notifier / sync wiring is asserted by their own tests)
#   6. plugin.json userConfig is well-formed and avoids keys that break older clients
#   7. `autonomous-mode.sh on --plugin` merges permissions WITHOUT injecting a hook,
#      and removes a legacy absolute-path guard entry
#   8. the /autonomous-mode command resolves the toggle through CLAUDE_PLUGIN_ROOT
#
# Run: tests/test_plugin_guard.sh   (exit 0 = pass, non-zero = fail)
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD_SH="${REPO}/claude/hooks/guard.sh"
TOGGLE="${REPO}/claude/autonomous-mode.sh"
HOOKS_JSON="${REPO}/claude/hooks/hooks.json"
PLUGIN_JSON="${REPO}/claude/.claude-plugin/plugin.json"

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

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
unset CLAUDE_PLUGIN_OPTION_GUARD_MODE GUARD_MODE 2>/dev/null || true

# payload <permission_mode|-> <command> — a PreToolUse Bash payload ("-" omits the mode)
payload() {
    python3 -c 'import json,sys
p={"tool_name":"Bash","tool_input":{"command":sys.argv[2]}}
if sys.argv[1]!="-": p["permission_mode"]=sys.argv[1]
print(json.dumps(p))' "$1" "$2"
}
# run <permission_mode> <command> [guard.sh args...] — sets $rc and $workdir/out
run() {
    local mode="$1" cmd="$2"; shift 2
    rc=0
    payload "$mode" "$cmd" | "$GUARD_SH" "$@" >"$workdir/out" 2>"$workdir/err" || rc=$?
}
blocks() { run "$@"; [[ "$rc" -eq 2 ]]; }
allows() { run "$@"; [[ "$rc" -eq 0 && ! -s "$workdir/out" ]]; }
asks() {
    run "$@"
    [[ "$rc" -eq 0 ]] && python3 -c 'import json,sys
o=json.load(open(sys.argv[1]))["hookSpecificOutput"]
assert o["hookEventName"]=="PreToolUse" and o["permissionDecision"]=="ask", o
assert o["permissionDecisionReason"], o' "$workdir/out"
}
BAD='cat ~/.ssh/id_rsa'

echo "── legacy entrypoint (no argument): always enforce ──"
check "blocks in default mode"            blocks default "$BAD"
check "blocks in acceptEdits mode"        blocks acceptEdits "$BAD"
check "blocks with no permission_mode"    blocks - "$BAD"
check "ignores the plugin option"         env CLAUDE_PLUGIN_OPTION_GUARD_MODE=off bash -c "$(declare -f payload run blocks); GUARD_SH='$GUARD_SH' workdir='$workdir' blocks default '$BAD'"

echo "── guard.sh plugin: guard_mode=auto is the default ──"
for mode in acceptEdits auto dontAsk bypassPermissions; do
    check "auto: blocks in $mode"         blocks "$mode" "$BAD" plugin
done
check "auto: asks in default mode"        asks default "$BAD" plugin
check "auto: asks in plan mode"           asks plan "$BAD" plugin
check "auto: ask carries the reason"      grep -q "secret" "$workdir/out"
check "auto: blocks when mode is missing" blocks - "$BAD" plugin
check "auto: sudo asks in default mode"   asks default "sudo apt-get update" plugin
check "auto: force push blocks in auto"   blocks auto "git push --force origin main" plugin

echo "── guard_mode=always / off / unknown ──"
export CLAUDE_PLUGIN_OPTION_GUARD_MODE=always
check "always: blocks in default mode"    blocks default "$BAD" plugin
export CLAUDE_PLUGIN_OPTION_GUARD_MODE=off
check "off: allows in acceptEdits mode"   allows acceptEdits "$BAD" plugin
check "off: allows in bypassPermissions"  allows bypassPermissions "rm -rf /" plugin
export CLAUDE_PLUGIN_OPTION_GUARD_MODE=sometimes
check "unknown value behaves as always"   blocks default "$BAD" plugin
unset CLAUDE_PLUGIN_OPTION_GUARD_MODE

echo "── safe commands: silent, fast path ──"
check "auto + default: silent allow"      allows default "pytest -q" plugin
check "auto + acceptEdits: silent allow"  allows acceptEdits "cargo build --release" plugin
check "fast path still taken in plugin mode" bash -c \
  "payload() { printf '%s' '{\"tool_name\":\"Bash\",\"permission_mode\":\"acceptEdits\",\"tool_input\":{\"command\":\"ls -la\"}}'; }; payload | GUARD_TRACE=1 '$GUARD_SH' plugin 2>&1 | grep -q 'guard: fastpath'"
check "triggered-but-safe stays silent"   allows acceptEdits "rm -rf build/" plugin

echo "── hooks.json ──"
check "hooks.json parses and wires the guard with the plugin argument" python3 - "$HOOKS_JSON" <<'PY'
import json,sys
h=json.load(open(sys.argv[1]))["hooks"]
pre=h["PreToolUse"]
assert len(pre)==1 and pre[0]["matcher"]=="Bash|Read", pre
g=pre[0]["hooks"][0]
assert g["command"]=="sh" and g["args"]==["${CLAUDE_PLUGIN_ROOT}/hooks/guard.sh","plugin"], g
PY
check "every hook is exec-form (args array, no shell string)" python3 - "$HOOKS_JSON" <<'PY'
import json,sys
for event,groups in json.load(open(sys.argv[1]))["hooks"].items():
    for group in groups:
        for hook in group["hooks"]:
            assert hook["type"]=="command" and isinstance(hook.get("args"),list), (event,hook)
            assert " " not in hook["command"] and "$" not in hook["command"], (event,hook)
PY
check "every \${CLAUDE_PLUGIN_ROOT} path exists in claude/" python3 - "$HOOKS_JSON" "$REPO/claude" <<'PY'
import json,os,re,sys
text=open(sys.argv[1]).read()
paths=re.findall(r"\$\{CLAUDE_PLUGIN_ROOT\}/([^\"]+)",text)
assert paths
for p in paths: assert os.path.isfile(os.path.join(sys.argv[2],p)), p
PY
check "no \${user_config.*} interpolation"   bash -c "! grep -q 'user_config\.' '$HOOKS_JSON'"
check "guard hook is NOT async (it must be able to block)" python3 - "$HOOKS_JSON" <<'PY'
import json,sys
g=json.load(open(sys.argv[1]))["hooks"]["PreToolUse"][0]["hooks"][0]
assert not g.get("async"), g
PY

echo "── plugin.json userConfig ──"
check "userConfig entries are well-formed" python3 - "$PLUGIN_JSON" <<'PY'
import json,sys
m=json.load(open(sys.argv[1])); uc=m["userConfig"]
allowed={"type","title","description","required","default","multiple","sensitive","min","max"}
for key,spec in uc.items():
    assert key==key.lower() and key.replace("_","").isalnum(), key
    assert spec["type"] in ("string","number","boolean","directory","file"), key
    assert spec.get("title") and spec.get("description"), key
    assert set(spec)<=allowed, (key,set(spec)-allowed)   # `options` needs CC >= 2.1.271
    assert not spec.get("required"), key                  # every feature is opt-in
assert uc["guard_mode"]["default"]=="auto"   # must equal the fallback in guard.sh
PY

echo "── autonomous-mode.sh on --plugin ──"
# HOME is redirected for every toggle call below. Global scope writes
# $HOME/.claude/settings.json, and a toggle that mis-parses its flags falls back to
# global scope — a test must never be able to reach the developer's real settings.
export HOME="$workdir/home"; mkdir -p "$HOME"
cd "$workdir"; mkdir -p .claude
python3 - "$GUARD_SH" <<'PY'
import json,sys
json.dump({"model":"opus","hooks":{"PreToolUse":[
    {"matcher":"Bash|Read","hooks":[{"type":"command","command":f'"{sys.argv[1]}"'}]},
    {"matcher":"Write","hooks":[{"type":"command","command":"my-own-hook"}]}]}},
    open(".claude/settings.json","w"),indent=2)
PY
"$TOGGLE" on --project --plugin >/dev/null
check "defaultMode = acceptEdits" \
  python3 -c "import json;assert json.load(open('.claude/settings.json'))['permissions']['defaultMode']=='acceptEdits'"
check "legacy absolute-path guard entry removed" \
  bash -c "! grep -q 'hooks/guard\.' .claude/settings.json"
check "user's own hook preserved" \
  python3 -c "import json;h=json.load(open('.claude/settings.json'))['hooks']['PreToolUse'];assert len(h)==1 and h[0]['matcher']=='Write',h"
check "flag order does not matter" bash -c "'$TOGGLE' status --plugin --project | grep -q 'ON'"
check "status names the guard source" bash -c "'$TOGGLE' status --project --plugin | grep -qi 'plugin'"
# The Bash tool gets no plugin options, so the command passes guard_mode itself; an
# option the user never set arrives as the literal placeholder.
check "status shows a configured guard_mode" \
  bash -c "CLAUDE_PLUGIN_OPTION_GUARD_MODE=always '$TOGGLE' status --project --plugin | grep -q 'guard_mode=always'"
check "status treats an unfilled placeholder as the default" \
  bash -c "CLAUDE_PLUGIN_OPTION_GUARD_MODE='\${user_config.guard_mode}' '$TOGGLE' status --project --plugin | grep -q 'guard_mode=auto (default)'"
"$TOGGLE" off --project --plugin >/dev/null
check "off restores the pre-autonomous settings" \
  python3 -c "import json;d=json.load(open('.claude/settings.json'));assert d['model']=='opus' and 'permissions' not in d,d"
rm -rf .claude; mkdir -p .claude
"$TOGGLE" on --project --plugin >/dev/null
check "fresh install: no hooks key written" \
  python3 -c "import json;assert 'hooks' not in json.load(open('.claude/settings.json'))"
check "unknown flag is rejected (exit 2)" bash -c "'$TOGGLE' on --bogus >/dev/null 2>&1; [[ \$? -eq 2 ]]"
check "a rejected call wrote nothing to global settings" test ! -e "$HOME/.claude/settings.json"

echo "── lost backup + re-run on --plugin, then off, really turns autonomous OFF ──"
# Mirrors the "lost backup" case in tests/test_autonomous_mode.sh for plugin installs.
# A plugin install writes NO hook, so the toggle must recognise an already-autonomous
# settings.json by the merged allow-list alone: re-running `on` after the backup
# vanished must not snapshot that autonomous state as "pre-autonomous", or `off`
# would faithfully restore an ON state.
lostbak="$workdir/lostbak"
mkdir -p "$lostbak/.claude"
cd "$lostbak"
printf '{ "model": "opus" }\n' > .claude/settings.json
"$TOGGLE" on --project --plugin >/dev/null
rm -f .claude/settings.pre-autonomous.json
"$TOGGLE" on --project --plugin >"$workdir/reon.out"
check "re-run on --plugin w/o backup: does not back up the autonomous state" \
  bash -c "! grep -q 'Backed up' '$workdir/reon.out'"
"$TOGGLE" off --project --plugin >/dev/null
check "lost backup + re-on + off --plugin: defaultMode is gone" \
  python3 -c "import json;d=json.load(open('.claude/settings.json'));assert 'defaultMode' not in d.get('permissions',{}),d.get('permissions')"
check "lost backup + re-on + off --plugin: user's model stays opus" \
  python3 -c "import json;assert json.load(open('.claude/settings.json')).get('model')=='opus'"
check "lost backup + re-on + off --plugin: status reports OFF" \
  bash -c "'$TOGGLE' status --project --plugin | grep -q 'is OFF'"
cd "$REPO"

echo "── /autonomous-mode command ──"
CMD="${REPO}/claude/commands/autonomous-mode.md"
check "command resolves the toggle via CLAUDE_PLUGIN_ROOT" \
  grep -q 'bash "${CLAUDE_PLUGIN_ROOT}/autonomous-mode.sh"' "$CMD"
check "command passes --plugin"            grep -q -- '--plugin' "$CMD"
check "command passes guard_mode (single-quoted)" \
  grep -qF "CLAUDE_PLUGIN_OPTION_GUARD_MODE='\${user_config.guard_mode}'" "$CMD"
check "no cwd-relative invocation left"    bash -c "! grep -qE '^claude/autonomous-mode\.sh' '$CMD'"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
