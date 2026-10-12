#!/usr/bin/env bash
# Contract test for claude/scripts/signal-setup.sh — the script that automates §3 of
# docs/TUTORIAL-notifications-sync.md (install signal-cli, give it an identity, send one
# message by hand, run the daemon, turn the plugin options on, test the plugin).
#
# Nothing real is touched. HOME is redirected, PATH is sanitized, and every external
# program the script may call is a stub in $workdir that appends "<name> <argv>" to
# $workdir/calls.log and behaves as the test needs:
#   brew        `install signal-cli` drops a signal-cli stub into $workdir/bin (so a
#               later `command -v signal-cli` finds it); `--prefix` prints $workdir
#   signal-cli  listAccounts prints the numbers in $workdir/accounts; register fails with
#               "Captcha invalid or required…" on STDERR, exit 1, when $workdir/captcha
#               exists (the script must look at both streams, case-insensitively);
#               verify appends the account to the file; link/send/daemon succeed
#   claude      `… --values-stdin` saves stdin to $workdir/claude_values.json;
#               `plugin configure agent-recipes@agent-recipes` alone prints two
#               "key: value" option lines (what --status shows)
#   curl        releases/latest -> prints the v0.13.12 tag URL (or the api.github.com
#               JSON); a Linux-native URL -> writes a fake tarball holding one top-level
#               `signal-cli` executable (the real layout); /api/v1/check -> prints 000
#               (exit 7) $workdir/curl_fail times, then 200
#   launchctl   `unload` always fails (exit 1, as it does when nothing is loaded — the
#               script must ignore that); `load` succeeds.  systemctl, loginctl: succeed
#   sudo        logs and fails: the script must never need it
# The plugin test (step 6) is real: notify.py runs against tests/stub_signal_rpc.py on
# an ephemeral port, which the test passes as --port, so the daemon URL the script
# configures is the stub's.
#
# Test hooks the script must honour (never documented for users):
#   SIGNAL_SETUP_OS=darwin|linux     instead of `uname -s`
#   SIGNAL_SETUP_RETRY_SLEEP=0       no pause between the ~30 daemon-check attempts
#   AGENT_RECIPES_ASSUME_TTY=1       as in setup.sh: stdin counts as a terminal; the
#                                    verification code is read from it
#
# Asserts:
#   1. the script exists, --help lists every flag, bad input exits 1 before any call
#   2. darwin, dedicated, nothing installed: brew install -> listAccounts -> register ->
#      prompt + verify -> send -> plist written + launchctl -> curl check retried ->
#      plugin options via --values-stdin -> notify.py test reached the RPC stub once
#   3. darwin, already installed + registered: steps 1 and 2 are skipped and say so
#   4. linux, dedicated, nothing installed: tarball to ~/.local, unit file, systemctl,
#      loginctl, no sudo, no brew/launchctl
#   5. link mode: `link -n claude-notify`, send --notify-self, recipient = account
#   6. captcha -> wiki URL, exit 1, nothing further; daemon never up -> exit 1 naming
#      the port; `claude` missing -> prints the command + JSON, still exits 0
#   7. --dry-run prints every command and writes/calls nothing; --no-install skips
#      step 1 even when that leaves nothing to run (clean exit 1, no install attempt)
#   8. --status reports installed/registered/reachable/options/log tail, always exit 0
#   9. --uninstall removes the service and sets notify_enabled=false, keeps the
#      account and signal-cli, exit 0 even with nothing installed
#
# Run: tests/test_signal_setup.sh   (exit 0 = pass, non-zero = fail)
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${REPO}/claude/scripts/signal-setup.sh"
RPC_STUB="${REPO}/tests/stub_signal_rpc.py"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

workdir="$(mktemp -d)"
stub_pid=""
cleanup() { [[ -n "$stub_pid" ]] && kill "$stub_pid" 2>/dev/null; rm -rf "$workdir"; }
trap cleanup EXIT
export HOME="$workdir/home-unused"      # nothing below may reach the real home
mkdir -p "$HOME" "$workdir/bin" "$workdir/sigbin" "$workdir/claudebin" "$workdir/tarroot"
ln -s "$(command -v git)"     "$workdir/bin/git"
ln -s "$(command -v python3)" "$workdir/bin/python3"

CALLS="$workdir/calls.log"
ACCOUNTS="$workdir/accounts"
REQUESTS="$workdir/requests"
VALUES="$workdir/claude_values.json"
ACCT="+15550001111"      # the bot's number (dedicated mode)
ME="+15551234567"        # the number to notify
MINE="+15557654321"      # my own account (link mode)

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

# ── stubs ──────────────────────────────────────────────────────────────────────────
cat > "$workdir/stubrc" <<EOF
CALLS=$CALLS
ACCOUNTS=$ACCOUNTS
CAPTCHA=$workdir/captcha
VALUES=$VALUES
CURL_FAIL=$workdir/curl_fail
TARBALL=$workdir/fake-signal-cli.tar.gz
STUB_SIGNAL=$workdir/sigbin/signal-cli
BREW_BIN=$workdir/bin
EOF
mkstub() {  # mkstub <dir> <name>  (body on stdin) — logs "<name> <argv>" then runs the body
    { printf '#!/bin/bash\n. "%s"\nprintf "%%s\\n" "${0##*/} $*" >> "$CALLS"\n' "$workdir/stubrc"; cat; } > "$1/$2"
    chmod +x "$1/$2"
}
mkstub "$workdir/sigbin" signal-cli <<'EOF'
acct=""; prev=""
for a in "$@"; do [[ "$prev" == "-a" ]] && acct="$a"; prev="$a"; done
case " $* " in
    *" listAccounts "*)
        while read -r n; do [[ -n "$n" ]] && printf 'Number: %s ACI: 00000000-0000-0000-0000-000000000000\n' "$n"; done < "$ACCOUNTS"
        exit 0 ;;
    *" register "*)
        if [[ -e "$CAPTCHA" ]]; then echo "Captcha invalid or required for verification, use --captcha CODE" >&2; exit 1; fi
        exit 0 ;;
    *" verify "*)  echo "$acct" >> "$ACCOUNTS"; exit 0 ;;
    *" link "*)    echo "sgnl://linkdevice?uuid=stub&pub_key=stub"; exit 0 ;;
    *" send "*)    echo 1700000000000; exit 0 ;;
    *" --version "*) echo "signal-cli 0.13.12"; exit 0 ;;
esac
exit 0
EOF
: > "$ACCOUNTS"
cp "$workdir/sigbin/signal-cli" "$workdir/tarroot/signal-cli"
tar czf "$workdir/fake-signal-cli.tar.gz" -C "$workdir/tarroot" signal-cli

mkstub "$workdir/bin" brew <<'EOF'
case " $* " in
    *" --prefix "*)             echo "${BREW_BIN%/bin}" ;;
    *" install signal-cli "*)   cp "$STUB_SIGNAL" "$BREW_BIN/signal-cli" ;;
esac
exit 0
EOF
mkstub "$workdir/claudebin" claude <<'EOF'
if [[ " $* " == *" --values-stdin "* ]]; then cat > "$VALUES"; exit 0; fi
if [[ " $* " == *" plugin configure "* ]]; then printf 'notify_enabled: true\nnotify_recipient: +15551234567\n'; fi
exit 0
EOF
mkstub "$workdir/bin" curl <<'EOF'
url=""; out=""; remote=0; w=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o|--output)     out="$2"; shift ;;
        -O|--remote-name) remote=1 ;;
        -w|--write-out)  w="$2"; shift ;;
        http://*|https://*) url="$1" ;;
    esac
    shift
done
emit() { if [[ -n "$out" && "$out" != /dev/null ]]; then cat > "$out"; elif [[ "$remote" -eq 1 ]]; then cat > "${url##*/}"; else cat; fi; }
case "$url" in
    *api.github.com*)
        printf '{"tag_name":"v0.13.12","assets":[{"name":"signal-cli-0.13.12-Linux-native.tar.gz","browser_download_url":"https://github.com/AsamK/signal-cli/releases/download/v0.13.12/signal-cli-0.13.12-Linux-native.tar.gz"}]}\n' | emit
        exit 0 ;;
    *releases/latest*)
        [[ "$w" == *url_effective* ]] && printf 'https://github.com/AsamK/signal-cli/releases/tag/v0.13.12'
        exit 0 ;;
    *Linux-native*)
        emit < "$TARBALL"; exit 0 ;;
    */api/v1/check*)
        left="$(cat "$CURL_FAIL" 2>/dev/null || echo 0)"
        if [[ "$left" -gt 0 ]]; then
            echo $((left - 1)) > "$CURL_FAIL"
            [[ "$w" == *http_code* ]] && printf '000'
            exit 7
        fi
        [[ "$w" == *http_code* ]] && printf '200'
        exit 0 ;;
esac
exit 0
EOF
mkstub "$workdir/bin" launchctl <<'EOF'
if [[ "$1" == "unload" ]]; then echo "Unload failed: 113: Could not find specified service" >&2; exit 1; fi
exit 0
EOF
mkstub "$workdir/bin" systemctl <<'EOF'
exit 0
EOF
mkstub "$workdir/bin" loginctl <<'EOF'
exit 0
EOF
mkstub "$workdir/bin" sudo <<'EOF'
echo "sudo: refused by the test" >&2
exit 1
EOF

# ── the RPC stub that notify.py talks to in step 6 ─────────────────────────────────
: > "$REQUESTS"; rm -f "$workdir/port"
python3 "$RPC_STUB" "$workdir/port" "$REQUESTS" &
stub_pid=$!
disown "$stub_pid" 2>/dev/null || true
for _ in $(seq 50); do [[ -s "$workdir/port" ]] && break; sleep 0.1; done
PORT="$(cat "$workdir/port")"
[[ -n "$PORT" ]] || { echo "could not start stub_signal_rpc.py"; exit 1; }

# ── helpers ────────────────────────────────────────────────────────────────────────
# run <home> <darwin|linux> "<bins>" [VAR=value ...] <args...>
# <bins> is a space-separated subset of "sig claude": which extra stub dirs are on PATH
# (signal-cli, claude). brew/curl/launchctl/systemctl/loginctl/sudo/python3/git are
# always there. Nothing of the developer's environment is inherited. stdin and the
# output redirection are the caller's.
run() {
    local home="$1" os="$2" bins="$3" p="$workdir/bin:/usr/bin:/bin" b; shift 3
    for b in $bins; do p="$workdir/${b}bin:$p"; done
    local pre=()
    while [[ $# -gt 0 && "$1" == *=* ]]; do pre+=("$1"); shift; done
    mkdir -p "$home"
    HOME="$home" SHELL=/bin/bash PATH="$p" SIGNAL_SETUP_OS="$os" SIGNAL_SETUP_RETRY_SLEEP=0 \
    AGENT_RECIPES_ASSUME_TTY=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
        /usr/bin/env -u CLAUDE_CONFIG_DIR -u XDG_CONFIG_HOME -u CLAUDE_PLUGIN_DATA -u CLAUDE_PLUGIN_ROOT \
               -u CLAUDE_PLUGIN_OPTION_NOTIFY_ENABLED -u CLAUDE_PLUGIN_OPTION_NOTIFY_RECIPIENT \
               -u CLAUDE_PLUGIN_OPTION_NOTIFY_SIGNAL_RPC_URL -u CLAUDE_PLUGIN_OPTION_NOTIFY_SIGNAL_ACCOUNT \
               -u CLAUDE_PLUGIN_OPTION_NOTIFY_MIN_SECONDS -u CLAUDE_PLUGIN_OPTION_NOTIFY_INCLUDE_SUMMARY \
               -u CLAUDE_PLUGIN_OPTION_NOTIFY_ALLOW_REMOTE \
               ${pre[@]+"${pre[@]}"} "$SCRIPT" "$@"
}
# fresh: empty call log, RPC requests, saved options, registered accounts; no captcha;
# the daemon check answers 000 twice, then 200; no brew-installed signal-cli left over.
fresh() {
    : > "$CALLS"; : > "$REQUESTS"; : > "$ACCOUNTS"; rm -f "$VALUES" "$workdir/captcha" "$workdir/bin/signal-cli"
    echo 2 > "$workdir/curl_fail"
}
not()       { ! "$@"; }
called()    { grep -qE -- "$1" "$CALLS"; }
ncalls()    { grep -cE -- "$1" "$CALLS" || true; }
says()      { grep -qiE -- "$2" "$1"; }                 # says <file> <pattern>
says_line() { grep -iE -- "$2" "$1" | grep -qivE -- "$3"; }  # a line matching $2 but not $3
no_calls()  { test ! -s "$CALLS"; }
# with_rc <n> <test...>: the last run exited <n> AND the test holds — negative checks
# ("no brew call") are only evidence when the run actually happened.
with_rc()   { local want="$1"; shift; [[ "$rc" -eq "$want" ]] && "$@"; }
# in_order <pattern>...: the first line matching each pattern comes after the previous one's
in_order() {
    local prev=0 n pat
    for pat in "$@"; do
        n="$(grep -nE -- "$pat" "$CALLS" | head -1 | cut -d: -f1)"
        [[ -n "$n" && "$n" -gt "$prev" ]] || return 1
        prev="$n"
    done
}
requests()  { wc -l < "$REQUESTS" | tr -d ' '; }
last_req()  {  # last_req <python-expr over r> — r is the last request the RPC stub saw
    python3 -c "import json,sys;r=[json.loads(l) for l in open(sys.argv[1])][-1];assert $1, r" "$REQUESTS"
}
values_is() {  # values_is <python-expr over d> — d is the JSON fed to --values-stdin
    python3 -c "import json,sys;d=json.load(open(sys.argv[1]));assert $1, d" "$VALUES"
}
plist_is()  {  # plist_is <plist> <python-expr over d>
    python3 -c "import plistlib,sys;d=plistlib.load(open(sys.argv[1],'rb'));assert $2, d" "$1"
}
plist()     { echo "$1/Library/LaunchAgents/org.signal-cli.daemon.plist"; }
unit()      { echo "$1/.config/systemd/user/signal-cli.service"; }
lint_plist() { if command -v plutil >/dev/null 2>&1; then plutil -lint "$1" >/dev/null; else plist_is "$1" 'True'; fi; }

echo "── the script ──"
check "claude/scripts/signal-setup.sh exists"             test -f "$SCRIPT"
check "...and is executable"                               test -x "$SCRIPT"

echo "── help and validation ──"
fresh
rc=0; run "$workdir/h0" darwin "sig claude" --help >"$workdir/help.out" 2>&1 </dev/null || rc=$?
check "--help exits 0"                                     test "$rc" -eq 0
for flag in --mode --account --recipient --port --dry-run --no-install --status --uninstall; do
    check "--help lists $flag"                             says "$workdir/help.out" "$flag"
done
check "--help mentions dedicated and link"                 bash -c "grep -q dedicated '$workdir/help.out' && grep -q link '$workdir/help.out'"
check "--help makes no calls"                              with_rc 0 no_calls
rc=0; run "$workdir/h0" darwin "sig claude" >"$workdir/v1.out" 2>&1 </dev/null || rc=$?
check "no flags: exits 1 (dedicated needs --account)"     test "$rc" -eq 1
check "...and names --account"                             says "$workdir/v1.out" "--account"
rc=0; run "$workdir/h0" darwin "sig claude" --account "$ACCT" >"$workdir/v2.out" 2>&1 </dev/null || rc=$?
check "dedicated without --recipient: exits 1"            test "$rc" -eq 1
check "...and names --recipient"                           says "$workdir/v2.out" "--recipient"
rc=0; run "$workdir/h0" darwin "sig claude" --mode link >"$workdir/v3.out" 2>&1 </dev/null || rc=$?
check "link without --account: exits 1"                   test "$rc" -eq 1
rc=0; run "$workdir/h0" darwin "sig claude" --mode sms --account "$ACCT" --recipient "$ME" >"$workdir/v4.out" 2>&1 </dev/null || rc=$?
check "--mode sms: exits 1"                                test "$rc" -eq 1
rc=0; run "$workdir/h0" darwin "sig claude" --bogus --account "$ACCT" --recipient "$ME" >"$workdir/v5.out" 2>&1 </dev/null || rc=$?
check "unknown flag: exits 1"                              test "$rc" -eq 1
check "...saying 'Unknown option'"                         says "$workdir/v5.out" 'Unknown option'
rc=0; run "$workdir/h0" darwin "sig claude" --account 15550001111 --recipient "$ME" >"$workdir/v6.out" 2>&1 </dev/null || rc=$?
check "--account without +: exits 1"                      test "$rc" -eq 1
rc=0; run "$workdir/h0" darwin "sig claude" --account "$ACCT" --recipient 5551234567 >"$workdir/v7.out" 2>&1 </dev/null || rc=$?
check "--recipient without +: exits 1"                    test "$rc" -eq 1
rc=0; run "$workdir/h0" darwin "sig claude" --mode link --account mynumber >"$workdir/v8.out" 2>&1 </dev/null || rc=$?
check "link --account without +: exits 1"                 test "$rc" -eq 1
check "validation failures make no calls"                 with_rc 1 no_calls
check "...and write nothing under HOME"                   with_rc 1 test ! -e "$(plist "$workdir/h0")"

echo "── darwin, dedicated, nothing installed: the full run ──"
fresh
H1="$workdir/h1"
rc=0; printf '123456\n\n\n' | run "$H1" darwin "claude" --account "$ACCT" --recipient "$ME" --port "$PORT" >"$workdir/h1.out" 2>&1 || rc=$?
check "exits 0"                                            test "$rc" -eq 0
check "prints the step headings 1/6 .. 6/6"                bash -c "grep -q '\[step 1/6\]' '$workdir/h1.out' && grep -q '\[step 6/6\]' '$workdir/h1.out'"
check "step 1: brew install signal-cli"                    called '^brew install signal-cli'
check "step 2: listAccounts asked first"                   called '^signal-cli .*listAccounts'
check "step 2: register for the account"                   called "^signal-cli .*-a \\$ACCT register"
check "step 2: prompted 'Verification code:'"              says "$workdir/h1.out" 'Verification code:'
check "step 2: verify with the code read from stdin"       called "^signal-cli .*-a \\$ACCT verify 123456"
check "step 3: one message by hand to the recipient"       called "^signal-cli .*-a \\$ACCT send .*-m .*\\$ME"
check "step 3: dedicated mode does not use --notify-self"  with_rc 0 not called '^signal-cli .*send .*--notify-self'
check "step 4: plist written"                              test -f "$(plist "$H1")"
check "step 4: plist is valid"                             lint_plist "$(plist "$H1")"
check "step 4: Label org.signal-cli.daemon"                plist_is "$(plist "$H1")" 'd["Label"]=="org.signal-cli.daemon"'
check "step 4: ProgramArguments = resolved path -a ACCOUNT daemon --http 127.0.0.1:PORT --no-receive-stdout --ignore-attachments --ignore-stories" \
    plist_is "$(plist "$H1")" "d['ProgramArguments']==['$workdir/bin/signal-cli','-a','$ACCT','daemon','--http','127.0.0.1:$PORT','--no-receive-stdout','--ignore-attachments','--ignore-stories']"
check "step 4: RunAtLoad and KeepAlive true"               plist_is "$(plist "$H1")" 'd["RunAtLoad"] is True and d["KeepAlive"] is True'
check "step 4: launchctl unload (its failure ignored)"     called "^launchctl unload .*$(plist "$H1")"
check "step 4: launchctl load -w the plist"                called "^launchctl load -w $(plist "$H1")"
check "step 4: waits on /api/v1/check for the port"        called "^curl .*http://127\\.0\\.0\\.1:$PORT/api/v1/check"
check "step 4: retried until 200 (000, 000, 200)"          test "$(ncalls '/api/v1/check')" -ge 3
check "step 5: claude plugin configure … --values-stdin"   called '^claude plugin configure agent-recipes@agent-recipes --values-stdin'
check "step 5: notify_enabled = \"true\""                  values_is 'd["notify_enabled"]=="true"'
check "step 5: notify_recipient = the recipient"           values_is "d['notify_recipient']=='$ME'"
check "step 5: notify_signal_rpc_url = the daemon's /api/v1/rpc" values_is "d['notify_signal_rpc_url']=='http://127.0.0.1:$PORT/api/v1/rpc'"
check "step 6: exactly one request reached the RPC stub"  test "$(requests)" -eq 1
check "step 6: it is a JSON-RPC send"                      last_req 'r["path"]=="/api/v1/rpc" and r["body"]["method"]=="send"'
check "step 6: the message mentions agent-recipes"         last_req '"agent-recipes" in r["body"]["params"]["message"]'
check "step 6: sent to the recipient"                      last_req "r['body']['params']['recipient']==['$ME']"
check "step 6: ran with notify_enabled on (no 'is off' note)" with_rc 0 not says "$workdir/h1.out" 'notify_enabled is off'
check "ends with 'restart Claude Code'"                    says "$workdir/h1.out" 'restart Claude Code'
check "the steps ran in order"                             in_order '^brew install signal-cli' '^signal-cli .*listAccounts' \
    '^signal-cli .*register' '^signal-cli .*verify 123456' '^signal-cli .*send ' '^launchctl unload ' '^launchctl load -w ' \
    '/api/v1/check' '^claude plugin configure agent-recipes@agent-recipes --values-stdin'
check "no systemd on darwin"                               with_rc 0 not called '^(systemctl|loginctl) '
check "no sudo, ever"                                      with_rc 0 not called '^sudo '
check "no tarball download on darwin"                      with_rc 0 not called '^curl .*Linux-native'

echo "── darwin, already installed and registered: steps 1 and 2 skipped ──"
fresh; echo "$ACCT" > "$ACCOUNTS"
H2="$workdir/h2"
rc=0; run "$H2" darwin "sig claude" --account "$ACCT" --recipient "$ME" --port "$PORT" >"$workdir/h2.out" 2>&1 </dev/null || rc=$?
check "exits 0"                                            test "$rc" -eq 0
check "says 'already installed'"                           says "$workdir/h2.out" 'already installed'
check "no brew call"                                       with_rc 0 not called '^brew '
check "says 'already registered'"                          says "$workdir/h2.out" 'already registered'
check "no register"                                        with_rc 0 not called '^signal-cli .*register'
check "no verify"                                          with_rc 0 not called '^signal-cli .*verify'
check "no verification prompt"                             with_rc 0 not says "$workdir/h2.out" 'Verification code:'
check "still sends the hand test"                          called "^signal-cli .*send .*\\$ME"
check "plist names the signal-cli found on PATH"           plist_is "$(plist "$H2")" "d['ProgramArguments'][0]=='$workdir/sigbin/signal-cli'"
check "plist loaded"                                       called '^launchctl load -w '
check "options configured"                                 values_is "d['notify_recipient']=='$ME' and d['notify_enabled']=='true'"
check "one test notification"                              test "$(requests)" -eq 1

echo "── linux, dedicated, nothing installed ──"
fresh
H3="$workdir/h3"
rc=0; printf '654321\n\n\n' | run "$H3" linux "claude" --account "$ACCT" --recipient "$ME" --port "$PORT" >"$workdir/h3.out" 2>&1 || rc=$?
check "exits 0"                                            test "$rc" -eq 0
check "step 1: downloaded the Linux-native signal-cli tarball" called '^curl .*signal-cli.*Linux-native'
check "step 1: unpacked under ~/.local/opt/signal-cli"     test -e "$H3/.local/opt/signal-cli"
check "step 1: ~/.local/bin/signal-cli runs"               test -x "$H3/.local/bin/signal-cli"
check "step 1: no brew on linux"                           with_rc 0 not called '^brew '
check "no sudo, ever"                                      with_rc 0 not called '^sudo '
check "step 2: register + verify with the code"            called "^signal-cli .*-a \\$ACCT verify 654321"
check "step 3: hand test sent"                             called "^signal-cli .*send .*\\$ME"
check "step 4: unit file written"                          test -f "$(unit "$H3")"
check "step 4: [Service] and [Install] sections"           bash -c "grep -q '^\[Service\]' '$(unit "$H3")' && grep -q '^\[Install\]' '$(unit "$H3")'"
check "step 4: ExecStart=<absolute path> -a ACCOUNT daemon --http 127.0.0.1:PORT --no-receive-stdout --ignore-attachments --ignore-stories" \
    grep -qE "^ExecStart=$H3/\.local/[^ ]*signal-cli -a \\$ACCT daemon --http 127\.0\.0\.1:$PORT --no-receive-stdout --ignore-attachments --ignore-stories\$" "$(unit "$H3")"
check "step 4: WantedBy=default.target"                    grep -q '^WantedBy=default.target' "$(unit "$H3")"
check "step 4: systemctl --user daemon-reload"             called '^systemctl --user daemon-reload'
check "step 4: systemctl --user enable --now signal-cli"   called '^systemctl --user enable --now signal-cli'
check "step 4: loginctl enable-linger"                     called '^loginctl enable-linger'
check "step 4: no launchctl on linux"                      with_rc 0 not called '^launchctl '
check "step 4: daemon check retried"                       test "$(ncalls '/api/v1/check')" -ge 3
check "step 5: options configured"                         values_is "d['notify_signal_rpc_url']=='http://127.0.0.1:$PORT/api/v1/rpc'"
check "step 6: one test notification"                      test "$(requests)" -eq 1
check "the steps ran in order"                             in_order '^curl .*Linux-native' '^signal-cli .*listAccounts' '^signal-cli .*register' \
    '^signal-cli .*verify 654321' '^signal-cli .*send ' '^systemctl --user daemon-reload' '^systemctl --user enable --now signal-cli' \
    '/api/v1/check' '^claude plugin configure agent-recipes@agent-recipes --values-stdin'

echo "── link mode ──"
fresh
H4="$workdir/h4"
rc=0; run "$H4" darwin "sig claude" --mode link --account "$MINE" --port "$PORT" >"$workdir/h4.out" 2>&1 </dev/null || rc=$?
check "exits 0"                                            test "$rc" -eq 0
check "signal-cli link -n claude-notify"                   called '^signal-cli .*link .*-n claude-notify'
check "no register"                                        with_rc 0 not called '^signal-cli .*register'
check "hand test uses --notify-self"                       called '^signal-cli .*send .*--notify-self'
check "hand test goes to my own number"                    called "^signal-cli .*-a \\$MINE send .*\\$MINE"
check "plist account is mine"                              plist_is "$(plist "$H4")" "d['ProgramArguments'][1:3]==['-a','$MINE']"
check "notify_recipient defaults to the account"           values_is "d['notify_recipient']=='$MINE'"
check "test notification went to my number"                last_req "r['body']['params']['recipient']==['$MINE']"

echo "── captcha ──"
fresh; touch "$workdir/captcha"
H5="$workdir/h5"
rc=0; printf '123456\n' | run "$H5" darwin "sig claude" --account "$ACCT" --recipient "$ME" --port "$PORT" >"$workdir/h5.out" 2>&1 || rc=$?
check "exits 1"                                            test "$rc" -eq 1
check "prints the captcha wiki URL"                        says "$workdir/h5.out" 'https://github.com/AsamK/signal-cli/wiki/Registration-with-captcha'
check "no verify"                                          with_rc 1 not called '^signal-cli .*verify'
check "no send"                                            with_rc 1 not called '^signal-cli .*send'
check "no plist"                                           with_rc 1 test ! -e "$(plist "$H5")"
check "no options written"                                 with_rc 1 test ! -e "$VALUES"
check "no test notification"                               with_rc 1 test "$(requests)" -eq 0

echo "── daemon never reachable ──"
fresh; echo "$ACCT" > "$ACCOUNTS"; echo 9999 > "$workdir/curl_fail"
H6="$workdir/h6"
rc=0; run "$H6" darwin "sig claude" --account "$ACCT" --recipient "$ME" >"$workdir/h6.out" 2>&1 </dev/null || rc=$?
check "exits 1"                                            test "$rc" -eq 1
check "checked the default port 18080"                     called '^curl .*http://127\.0\.0\.1:18080/api/v1/check'
check "retried more than once"                             test "$(ncalls '/api/v1/check')" -ge 3
check "...but gave up (not forever)"                       with_rc 1 test "$(ncalls '/api/v1/check')" -le 120
check "the message names the port"                         says "$workdir/h6.out" '18080'
check "no options written"                                 with_rc 1 test ! -e "$VALUES"
check "no test notification"                               with_rc 1 test "$(requests)" -eq 0

echo "── claude not on PATH: print the command, continue, exit 0 ──"
fresh; echo "$ACCT" > "$ACCOUNTS"
H7="$workdir/h7"
rc=0; run "$H7" darwin "sig" --account "$ACCT" --recipient "$ME" --port "$PORT" >"$workdir/h7.out" 2>&1 </dev/null || rc=$?
check "exits 0"                                            test "$rc" -eq 0
check "prints the configure command"                       says "$workdir/h7.out" 'claude plugin configure agent-recipes@agent-recipes --values-stdin'
check "prints the JSON: notify_enabled"                    says "$workdir/h7.out" '"notify_enabled" *: *"true"'
check "prints the JSON: notify_recipient"                  says "$workdir/h7.out" "\"notify_recipient\" *: *\"\\$ME\""
check "prints the JSON: notify_signal_rpc_url"             says "$workdir/h7.out" "\"notify_signal_rpc_url\" *: *\"http://127.0.0.1:$PORT/api/v1/rpc\""
check "step 6 still ran"                                   test "$(requests)" -eq 1
check "ends with 'restart Claude Code'"                    says "$workdir/h7.out" 'restart Claude Code'

echo "── --dry-run: prints everything, does nothing ──"
fresh
H8="$workdir/h8"
rc=0; run "$H8" darwin "claude" --dry-run --account "$ACCT" --recipient "$ME" >"$workdir/h8.out" 2>&1 </dev/null || rc=$?
check "darwin: exits 0"                                    test "$rc" -eq 0
check "darwin: no stub call recorded"                      with_rc 0 no_calls
check "darwin: no plist written"                           with_rc 0 test ! -e "$(plist "$H8")"
check "darwin: no options written"                         with_rc 0 test ! -e "$VALUES"
check "darwin: no test notification"                       with_rc 0 test "$(requests)" -eq 0
check "darwin: prints brew install signal-cli"             says "$workdir/h8.out" 'brew install signal-cli'
check "darwin: prints the register command"                says "$workdir/h8.out" "signal-cli .*-a \\$ACCT register"
check "darwin: prints the verify command"                  says "$workdir/h8.out" "signal-cli .*-a \\$ACCT verify"
check "darwin: prints the send command"                    says "$workdir/h8.out" "signal-cli .*-a \\$ACCT send .*\\$ME"
check "darwin: prints the plist path"                      says "$workdir/h8.out" "$(plist "$H8")"
check "darwin: prints the daemon arguments (default port 18080)" says "$workdir/h8.out" "-a \\$ACCT daemon --http 127\\.0\\.0\\.1:18080 --no-receive-stdout --ignore-attachments --ignore-stories"
check "darwin: prints launchctl load -w"                   says "$workdir/h8.out" 'launchctl load -w'
check "darwin: prints the configure JSON"                  says "$workdir/h8.out" '"notify_signal_rpc_url" *: *"http://127.0.0.1:18080/api/v1/rpc"'
check "darwin: prints the configure command"               says "$workdir/h8.out" 'claude plugin configure agent-recipes@agent-recipes --values-stdin'
fresh
H9="$workdir/h9"
rc=0; run "$H9" linux "claude" --dry-run --account "$ACCT" --recipient "$ME" --port 18090 >"$workdir/h9.out" 2>&1 </dev/null || rc=$?
check "linux: exits 0"                                     test "$rc" -eq 0
check "linux: no stub call recorded"                       with_rc 0 no_calls
check "linux: no unit written"                             with_rc 0 test ! -e "$(unit "$H9")"
check "linux: prints the download (Linux-native)"          says "$workdir/h9.out" 'Linux-native'
check "linux: prints the unit path"                        says "$workdir/h9.out" "$(unit "$H9")"
check "linux: prints ExecStart with the port"              says "$workdir/h9.out" "ExecStart=.*-a \\$ACCT daemon --http 127\\.0\\.0\\.1:18090"
check "linux: prints systemctl --user enable --now"        says "$workdir/h9.out" 'systemctl --user enable --now signal-cli'
check "linux: prints the configure JSON with the port"     says "$workdir/h9.out" '"notify_signal_rpc_url" *: *"http://127.0.0.1:18090/api/v1/rpc"'
check "linux: no sudo in what it would run"                with_rc 0 not says "$workdir/h9.out" '(^| )sudo '

echo "── --no-install with nothing installed: step 1 skipped, so step 2 cannot run — clean exit 1 ──"
fresh
H10="$workdir/h10"
rc=0; run "$H10" darwin "claude" --no-install --account "$ACCT" --recipient "$ME" >"$workdir/h10.out" 2>&1 </dev/null || rc=$?
check "darwin: exits 1"                                    test "$rc" -eq 1
check "darwin: says signal-cli is missing"                 says "$workdir/h10.out" 'signal-cli'
check "darwin: no brew call"                               with_rc 1 not called '^brew '
check "darwin: no 'already installed'"                     with_rc 1 not says "$workdir/h10.out" 'already installed'
fresh
rc=0; run "$H10" linux "claude" --no-install --account "$ACCT" --recipient "$ME" >"$workdir/h10b.out" 2>&1 </dev/null || rc=$?
check "linux: exits 1"                                     test "$rc" -eq 1
check "linux: no download"                                 with_rc 1 not called '^curl .*Linux-native'
check "linux: nothing under ~/.local"                      with_rc 1 test ! -e "$H10/.local/bin/signal-cli"

echo "── --status ──"
fresh; echo 9999 > "$workdir/curl_fail"
H11="$workdir/h11"
rc=0; run "$H11" darwin "" --status >"$workdir/h11.out" 2>&1 </dev/null || rc=$?
check "bare machine: exits 0"                              test "$rc" -eq 0
check "bare machine: 'not installed'"                      says "$workdir/h11.out" 'not installed'
check "bare machine: 'not reachable'"                      says "$workdir/h11.out" 'not reachable'
check "bare machine: checks the default port"              called '^curl .*127\.0\.0\.1:18080/api/v1/check'
check "bare machine: no prompt, nothing written"           with_rc 0 test ! -e "$(plist "$H11")"
# H1 was fully set up on darwin: signal-cli (on PATH now), the account, the plist.
fresh; echo "$ACCT" > "$ACCOUNTS"; echo 0 > "$workdir/curl_fail"
mkdir -p "$H1/.claude/plugins/data/agent-recipes-agent-recipes/notify"
printf 'log-entry-1\nlog-entry-2\nlog-entry-3\nlog-entry-4\nlog-entry-5\n' > "$H1/.claude/plugins/data/agent-recipes-agent-recipes/notify/notify.log"
rc=0; run "$H1" darwin "sig claude" --status >"$workdir/h1-status.out" 2>&1 </dev/null || rc=$?
check "set-up machine: exits 0"                            test "$rc" -eq 0
check "set-up machine: shows the signal-cli path"          says "$workdir/h1-status.out" "$workdir/sigbin/signal-cli"
check "set-up machine: account registered (from listAccounts)" says_line "$workdir/h1-status.out" "registered.*\\$ACCT|\\$ACCT.*registered" 'not registered'
check "set-up machine: daemon 'reachable'"                 says_line "$workdir/h1-status.out" 'reachable' 'not reachable'
check "set-up machine: plugin options line"                says "$workdir/h1-status.out" 'notify_recipient'
check "set-up machine: last 3 log lines"                   bash -c "grep -q log-entry-3 '$workdir/h1-status.out' && grep -q log-entry-4 '$workdir/h1-status.out' && grep -q log-entry-5 '$workdir/h1-status.out'"
check "set-up machine: not the older log lines"            with_rc 0 not says "$workdir/h1-status.out" 'log-entry-1'
check "--status sends nothing"                             with_rc 0 test "$(requests)" -eq 0
check "--status registers nothing"                         with_rc 0 not called '^signal-cli .*(register|verify|link|send)'
check "--status writes no options"                         with_rc 0 test ! -e "$VALUES"

echo "── --uninstall ──"
fresh; echo "$ACCT" > "$ACCOUNTS"
rc=0; run "$H1" darwin "sig claude" --uninstall >"$workdir/h1-un.out" 2>&1 </dev/null || rc=$?
check "darwin: exits 0"                                    test "$rc" -eq 0
check "darwin: launchctl unload the plist"                 called "^launchctl unload .*$(plist "$H1")"
check "darwin: plist removed"                              with_rc 0 test ! -e "$(plist "$H1")"
check "darwin: notify_enabled set to \"false\""            values_is 'd=={"notify_enabled":"false"}'
check "darwin: says how to remove the account"             says "$workdir/h1-un.out" 'unregister|deleteLocalAccountData'
check "darwin: says how to remove signal-cli"              says "$workdir/h1-un.out" 'brew uninstall signal-cli'
check "darwin: but does neither"                           with_rc 0 not called '^signal-cli .*(unregister|deleteLocalAccountData)'
check "darwin: signal-cli still there"                     with_rc 0 test -x "$workdir/sigbin/signal-cli"
fresh; echo "$ACCT" > "$ACCOUNTS"
rc=0; run "$H3" linux "sig claude" --uninstall >"$workdir/h3-un.out" 2>&1 </dev/null || rc=$?
check "linux: exits 0"                                     test "$rc" -eq 0
check "linux: systemctl --user disable --now signal-cli"   called '^systemctl --user disable --now signal-cli'
check "linux: unit removed"                                with_rc 0 test ! -e "$(unit "$H3")"
check "linux: notify_enabled set to \"false\""             values_is 'd=={"notify_enabled":"false"}'
check "linux: says how to remove signal-cli (~/.local)"    says "$workdir/h3-un.out" '\.local/(opt|bin)/signal-cli'
check "linux: ~/.local/bin/signal-cli kept"                with_rc 0 test -x "$H3/.local/bin/signal-cli"
fresh
H12="$workdir/h12"
rc=0; run "$H12" darwin "" --uninstall >"$workdir/h12.out" 2>&1 </dev/null || rc=$?
check "nothing installed, no claude: exits 0"              test "$rc" -eq 0
check "...and nothing written under HOME"                  with_rc 0 test ! -e "$H12/Library"

echo "── nothing reached the (redirected) real home ──"
check "the script ran and the test's HOME stayed empty"    with_rc 0 test -z "$(ls -A "$HOME" 2>/dev/null)"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
