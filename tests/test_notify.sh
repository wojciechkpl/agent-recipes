#!/usr/bin/env bash
# Contract test for the Signal notifier (claude/hooks/notify.py).
#
# Asserts:
#   1. disabled by default — no request leaves the machine until notify_enabled=true
#   2. Notification -> one JSON-RPC `send` to /api/v1/rpc with the expected params
#   3. Stop pings only when the turn ran at least notify_min_seconds
#   4. idle_prompt right after a Stop ping is de-duplicated; non-ask types are ignored
#   5. every hook event exits 0 even when the daemon is down or returns an error
#   6. non-loopback RPC URLs are refused unless notify_allow_remote=true
#   7. `test` prints OK/FAIL and exits non-zero on failure
#
# Run: tests/test_notify.sh   (exit 0 = pass, non-zero = fail)
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NOTIFY="${REPO}/claude/hooks/notify.py"
STUB="${REPO}/tests/stub_signal_rpc.py"

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
stub_pid=""
cleanup() { [[ -n "$stub_pid" ]] && kill "$stub_pid" 2>/dev/null; rm -rf "$workdir"; }
trap cleanup EXIT

start_stub() {  # start_stub [error]
    [[ -n "$stub_pid" ]] && kill "$stub_pid" 2>/dev/null && wait "$stub_pid" 2>/dev/null || true
    : > "$workdir/requests"; rm -f "$workdir/port"
    python3 "$STUB" "$workdir/port" "$workdir/requests" "${1:-}" &
    stub_pid=$!
    for _ in $(seq 50); do [[ -s "$workdir/port" ]] && break; sleep 0.1; done
    local port
    port="$(cat "$workdir/port")"
    export CLAUDE_PLUGIN_OPTION_NOTIFY_SIGNAL_RPC_URL="http://127.0.0.1:${port}/api/v1/rpc"
}
requests() { wc -l < "$workdir/requests" | tr -d ' '; }
last() {     # last <python-expr over r> — r is the last recorded request
    python3 -c "import json,sys;r=[json.loads(l) for l in open(sys.argv[1])][-1];assert $1, r" "$workdir/requests"
}
hook() {     # hook <event> <json> — runs the notifier, echoes its exit code
    local rc=0
    printf '%s' "$2" | python3 "$NOTIFY" "$1" >/dev/null 2>&1 || rc=$?
    echo "$rc"
}
set_turn_start() {  # set_turn_start <session> <seconds-ago>
    python3 - "$CLAUDE_PLUGIN_DATA/notify/$1.json" "$2" <<'EOF'
import json,sys,time,os
p=sys.argv[1]; s=json.load(open(p)) if os.path.exists(p) else {}
s["turn_start"]=time.time()-float(sys.argv[2]); json.dump(s,open(p,"w"))
EOF
}

export CLAUDE_PLUGIN_DATA="$workdir/data"
unset CLAUDE_PLUGIN_OPTION_NOTIFY_ENABLED CLAUDE_PLUGIN_OPTION_NOTIFY_RECIPIENT \
      CLAUDE_PLUGIN_OPTION_NOTIFY_SIGNAL_ACCOUNT CLAUDE_PLUGIN_OPTION_NOTIFY_MIN_SECONDS \
      CLAUDE_PLUGIN_OPTION_NOTIFY_INCLUDE_SUMMARY CLAUDE_PLUGIN_OPTION_NOTIFY_ALLOW_REMOTE 2>/dev/null || true
start_stub

N1='{"session_id":"s1","cwd":"/home/u/proj-a","hook_event_name":"Notification","notification_type":"permission_prompt","message":"Claude needs your permission to use Bash"}'

echo "── disabled by default ──"
check "notification exits 0 when disabled"   test "$(hook notification "$N1")" -eq 0
check "nothing sent when disabled"           test "$(requests)" -eq 0

export CLAUDE_PLUGIN_OPTION_NOTIFY_ENABLED=true

echo "── Notification -> JSON-RPC send ──"
check "notification exits 0"                 test "$(hook notification "$N1")" -eq 0
check "exactly one request"                  test "$(requests)" -eq 1
check "POSTs to /api/v1/rpc"                 last 'r["path"]=="/api/v1/rpc"'
check "method is send, JSON-RPC 2.0"         last 'r["body"]["method"]=="send" and r["body"]["jsonrpc"]=="2.0"'
check "no recipient -> noteToSelf"           last 'r["body"]["params"].get("noteToSelf") is True and "recipient" not in r["body"]["params"]'
check "message names the project"            last '"proj-a" in r["body"]["params"]["message"]'
check "message carries Claude Code text"     last '"permission to use Bash" in r["body"]["params"]["message"]'
check "same kind within 30s is rate-limited" bash -c "[[ \$(printf '%s' '$N1' | python3 '$NOTIFY' notification; wc -l < '$workdir/requests' | tr -d ' ') -eq 1 ]]"

echo "── recipient + account ──"
export CLAUDE_PLUGIN_OPTION_NOTIFY_RECIPIENT="+15550100" CLAUDE_PLUGIN_OPTION_NOTIFY_SIGNAL_ACCOUNT="+15550100"
N2="${N1/s1/s2}"
check "notification (new session) exits 0"   test "$(hook notification "$N2")" -eq 0
check "recipient list + notifySelf"          last 'r["body"]["params"]["recipient"]==["+15550100"] and r["body"]["params"]["notifySelf"] is True'
check "account passed through"               last 'r["body"]["params"]["account"]=="+15550100"'
check "noteToSelf not set with a recipient"  last '"noteToSelf" not in r["body"]["params"]'

echo "── Stop: only long turns ──"
S3='{"session_id":"s3","cwd":"/home/u/proj-b","hook_event_name":"Stop","last_assistant_message":"All 42 tests pass. token=abc"}'
before="$(requests)"
check "stop without a turn marker sends nothing" bash -c "[[ \$(printf '%s' '$S3' | python3 '$NOTIFY' stop; wc -l < '$workdir/requests' | tr -d ' ') -eq $before ]]"
check "mark exits 0"                         test "$(hook mark '{"session_id":"s3"}')" -eq 0
check "short turn sends nothing"             bash -c "[[ \$(printf '%s' '$S3' | python3 '$NOTIFY' stop; wc -l < '$workdir/requests' | tr -d ' ') -eq $before ]]"
set_turn_start s3 300
check "long turn exits 0"                    test "$(hook stop "$S3")" -eq 0
check "long turn sends one ping"             test "$(requests)" -eq $((before + 1))
check "ping says finished + duration"        last '"finished after 5m" in r["body"]["params"]["message"]'
check "summary is off by default"            last '"42 tests" not in r["body"]["params"]["message"]'

echo "── de-dup and filtering ──"
I3='{"session_id":"s3","cwd":"/home/u/proj-b","notification_type":"idle_prompt","message":"Claude is waiting for your input"}'
before="$(requests)"
hook notification "$I3" >/dev/null
check "idle_prompt after a Stop ping is dropped" test "$(requests)" -eq "$before"
hook notification '{"session_id":"s4","notification_type":"auth_success","message":"Logged in"}' >/dev/null
check "non-ask notification types are ignored"  test "$(requests)" -eq "$before"

echo "── opt-in summary ──"
export CLAUDE_PLUGIN_OPTION_NOTIFY_INCLUDE_SUMMARY=true
hook mark '{"session_id":"s5"}' >/dev/null; set_turn_start s5 200
hook stop "${S3/s3/s5}" >/dev/null
check "summary included when opted in"       last '"42 tests" in r["body"]["params"]["message"]'
unset CLAUDE_PLUGIN_OPTION_NOTIFY_INCLUDE_SUMMARY

echo "── failure never affects the session ──"
start_stub error
check "JSON-RPC error -> hook still exits 0" test "$(hook notification "${N1/s1/s6}")" -eq 0
check "failure is logged"                    grep -q "FAIL signal-cli error" "$CLAUDE_PLUGIN_DATA/notify/notify.log"
kill "$stub_pid" 2>/dev/null; wait "$stub_pid" 2>/dev/null || true; stub_pid=""
check "daemon down -> hook still exits 0"    test "$(hook notification "${N1/s1/s7}")" -eq 0
check "malformed stdin -> exits 0"           test "$(hook stop 'not json')" -eq 0
check "unknown event -> exits 0"             test "$(hook bogus '{}')" -eq 0

echo "── loopback only ──"
export CLAUDE_PLUGIN_OPTION_NOTIFY_SIGNAL_RPC_URL="http://203.0.113.9:18080/api/v1/rpc"
check "remote URL refused (test exits 1)"    bash -c "! python3 '$NOTIFY' test >'$workdir/out' 2>&1"
check "refusal is explained"                 grep -q "non-loopback" "$workdir/out"

echo "── test subcommand ──"
start_stub
check "test prints OK and exits 0"           bash -c "python3 '$NOTIFY' test | grep -q '^OK'"
check "test works even when notify_enabled is unset" bash -c "env -u CLAUDE_PLUGIN_OPTION_NOTIFY_ENABLED python3 '$NOTIFY' test | grep -q '^OK'"

echo "── /notify-test: unfilled \${user_config.*} placeholders count as unset ──"
# Claude Code substitutes ${user_config.KEY} in a command body only for options the
# user has set; an unset one arrives as the literal placeholder text.
export CLAUDE_PLUGIN_OPTION_NOTIFY_RECIPIENT='${user_config.notify_recipient}' \
       CLAUDE_PLUGIN_OPTION_NOTIFY_SIGNAL_ACCOUNT='${user_config.notify_signal_account}' \
       CLAUDE_PLUGIN_OPTION_NOTIFY_ALLOW_REMOTE='${user_config.notify_allow_remote}'
check "test succeeds with placeholder options"  bash -c "python3 '$NOTIFY' test | grep -q '^OK'"
check "placeholder recipient -> noteToSelf"     last 'r["body"]["params"].get("noteToSelf") is True and "recipient" not in r["body"]["params"]'
check "placeholder account is not sent"         last '"account" not in r["body"]["params"]'
check "no note while notify_enabled is on"      bash -c "! python3 '$NOTIFY' test | grep -q '^note:'"
check "note when notify_enabled is off"         bash -c "env -u CLAUDE_PLUGIN_OPTION_NOTIFY_ENABLED python3 '$NOTIFY' test | grep -q '^note: notify_enabled is off'"
check "placeholder allow_remote is not truthy"  bash -c "! CLAUDE_PLUGIN_OPTION_NOTIFY_SIGNAL_RPC_URL=http://203.0.113.9:1/api/v1/rpc python3 '$NOTIFY' test >/dev/null 2>&1"

CMD="${REPO}/claude/commands/notify-test.md"
check "/notify-test runs notify.py via CLAUDE_PLUGIN_ROOT" \
  grep -q 'python3 "${CLAUDE_PLUGIN_ROOT}/hooks/notify.py" test' "$CMD"
for key in notify_enabled notify_signal_rpc_url notify_signal_account notify_recipient notify_allow_remote; do
    upper="$(printf '%s' "$key" | tr '[:lower:]' '[:upper:]')"
    check "/notify-test passes $key (single-quoted)" \
      grep -qF "CLAUDE_PLUGIN_OPTION_${upper}='\${user_config.${key}}'" "$CMD"
done

echo "── wiring: hooks.json + plugin options ──"
check "hooks call notify.py with the right event; Stop is synchronous" \
  python3 - "${REPO}/claude/hooks/hooks.json" <<'PY'
import json,sys
h=json.load(open(sys.argv[1]))["hooks"]
def only(event):
    (group,)=h[event]; (hook,)=group["hooks"]; return hook
for event,arg in (("UserPromptSubmit","mark"),("Stop","stop"),("Notification","notification")):
    hook=only(event)
    assert hook["command"]=="python3", hook
    assert hook["args"]==["${CLAUDE_PLUGIN_ROOT}/hooks/notify.py",arg], hook
# mark + notification must never add latency to a prompt or a permission dialog
assert only("UserPromptSubmit").get("async") is True and only("Notification").get("async") is True
# A headless run (`claude -p`) exits right after Stop and kills async hooks
# mid-flight, so the "finished" ping has to be synchronous, with a short timeout.
stop=only("Stop")
assert not stop.get("async") and 5 < stop["timeout"] <= 10, stop
PY
check "option defaults in plugin.json match the defaults in notify.py" \
  python3 - "${REPO}/claude/.claude-plugin/plugin.json" "$NOTIFY" <<'PY'
import json,re,sys
uc=json.load(open(sys.argv[1]))["userConfig"]; src=open(sys.argv[2]).read()
# Claude Code exports nothing for an option the user never set, so every default is
# written twice — in the manifest (what /config shows) and in the script (what runs).
assert uc["notify_enabled"]["type"]=="boolean" and uc["notify_enabled"]["default"] is False
assert uc["notify_include_summary"]["default"] is False
assert uc["notify_allow_remote"]["default"] is False
assert uc["notify_signal_rpc_url"]["default"]==re.search(r'DEFAULT_URL = "([^"]+)"',src).group(1)
assert uc["notify_min_seconds"]["default"]==int(re.search(r"DEFAULT_MIN_SECONDS = (\d+)",src).group(1))
for key in ("notify_recipient","notify_signal_account"):
    assert uc[key]["type"]=="string" and "default" not in uc[key], key
PY

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
