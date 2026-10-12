#!/usr/bin/env bash
# signal-setup.sh — install signal-cli, give it a Signal identity, run it as a local
# daemon and point the agent-recipes plugin at it, so Claude Code can message your
# phone when a session needs you or has finished. The manual version of every step is
# docs/TUTORIAL-notifications-sync.md §3.
#
# Usage:
#   signal-setup.sh --account +48BOTNUMBER --recipient +48YOURNUMBER   # dedicated number (recommended)
#   signal-setup.sh --mode link --account +48YOURNUMBER                 # link to your own account
#   signal-setup.sh --status | --uninstall | --dry-run
#
# Options:
#   --mode dedicated|link   dedicated: a second number is registered as the bot (default)
#                           link: signal-cli becomes a linked device of your own account
#   --account +NUM          the number signal-cli holds (bot number, or yours when linking)
#   --recipient +NUM        the number to notify; link mode defaults to the account itself
#   --port N                daemon port on 127.0.0.1 (default 18080)
#   --no-install            skip the install step
#   --dry-run               print every command, change nothing
#   --status                what is installed, registered, running and configured
#   --uninstall             stop and remove the daemon, turn notifications off
#
# Never uses sudo; on Linux signal-cli goes to ~/.local/opt with a link in ~/.local/bin.
# Test hooks (not for users): SIGNAL_SETUP_OS=darwin|linux, SIGNAL_SETUP_RETRY_SLEEP=<s>.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NOTIFY_PY="$HERE/../hooks/notify.py"
PLUGIN_ID="agent-recipes@agent-recipes"
OS="${SIGNAL_SETUP_OS:-$(uname -s | tr '[:upper:]' '[:lower:]')}"
RETRY_SLEEP="${SIGNAL_SETUP_RETRY_SLEEP:-1}"
RELEASES="https://github.com/AsamK/signal-cli/releases"
CAPTCHA_WIKI="https://github.com/AsamK/signal-cli/wiki/Registration-with-captcha"
LINK_NAME="claude-notify"
PLIST="$HOME/Library/LaunchAgents/org.signal-cli.daemon.plist"
UNIT="$HOME/.config/systemd/user/signal-cli.service"
NOTIFY_LOG="$HOME/.claude/plugins/data/agent-recipes-agent-recipes/notify/notify.log"

MODE=dedicated ACCOUNT="" RECIPIENT="" PORT=18080
DRY_RUN=false NO_INSTALL=false ACTION=setup

usage() { sed -n '2,24p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
info() { printf '[info]  %s\n' "$*"; }
ok()   { printf '[ok]    %s\n' "$*"; }
err()  { printf '[error] %s\n' "$*" >&2; }
step() { printf '\n[step %s/6] %s\n' "$1" "$2"; }

need_value() { [[ $# -ge 2 && "$2" != --* ]] || { err "$1 needs a value"; exit 1; }; }
while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)       need_value "$@"; MODE="$2"; shift ;;
        --account)    need_value "$@"; ACCOUNT="$2"; shift ;;
        --recipient)  need_value "$@"; RECIPIENT="$2"; shift ;;
        --port)       need_value "$@"; PORT="$2"; shift ;;
        --no-install) NO_INSTALL=true ;;
        --dry-run)    DRY_RUN=true ;;
        --status)     ACTION=status ;;
        --uninstall)  ACTION=uninstall ;;
        -h|--help)    usage; exit 0 ;;
        *)            err "Unknown option: $1"; usage; exit 1 ;;
    esac
    shift
done

RPC_URL="http://127.0.0.1:$PORT/api/v1/rpc"
CHECK_URL="http://127.0.0.1:$PORT/api/v1/check"

# run <cmd...>: run it, or print it under --dry-run (`sig` shown as the real binary).
run() {
    if $DRY_RUN; then
        if [[ "$1" == sig ]]; then shift; printf '  would run: %s %s\n' "${SIG:-signal-cli}" "$*"
        else printf '  would run: %s\n' "$*"; fi
        return 0
    fi
    "$@"
}

validate() {
    case "$MODE" in dedicated|link) ;; *) err "--mode must be dedicated or link"; exit 1 ;; esac
    [[ -n "$ACCOUNT" ]] || { err "--account +NUMBER is required"; exit 1; }
    if [[ "$MODE" == link ]]; then RECIPIENT="${RECIPIENT:-$ACCOUNT}"; fi
    [[ -n "$RECIPIENT" ]] || { err "--recipient +NUMBER is required (dedicated mode)"; exit 1; }
    for n in "$ACCOUNT" "$RECIPIENT"; do
        [[ "$n" == +* ]] || { err "numbers must be in international format, starting with +: $n"; exit 1; }
    done
    [[ "$PORT" =~ ^[0-9]+$ ]] || { err "--port must be a number"; exit 1; }
}

# The signal-cli binary: on PATH, or where the Linux install puts it (~/.local/bin may
# not be on PATH yet). Every call goes through $SIG so that case works too.
LOCAL_BIN="$HOME/.local/bin/signal-cli"
signal_path() {
    command -v signal-cli 2>/dev/null && return 0
    [[ -x "$LOCAL_BIN" ]] && echo "$LOCAL_BIN"
    return 0
}
SIG="$(signal_path)"
sig() { "${SIG:-signal-cli}" "$@"; }

# ── 1. install ────────────────────────────────────────────────
install_signal_cli() {
    step 1 "install signal-cli"
    if $NO_INSTALL; then
        [[ -n "$SIG" ]] || { err "signal-cli is not installed and --no-install was given; install it ($RELEASES) or drop the flag"; exit 1; }
        info "skipped (--no-install): using $SIG"; return 0
    fi
    if [[ -n "$SIG" ]]; then ok "already installed: $SIG"; return 0; fi
    case "$OS" in
        darwin) run brew install signal-cli ;;
        linux)  install_linux_native ;;
        *)      err "unsupported OS: $OS — install signal-cli yourself ($RELEASES) and re-run with --no-install"; exit 1 ;;
    esac
    hash -r 2>/dev/null || true
    SIG="$(signal_path)"
    [[ -n "$SIG" ]] || $DRY_RUN || { err "signal-cli is still not on PATH after installing"; exit 1; }
    ok "installed: ${SIG:-signal-cli}"
}
install_linux_native() {
    local version url dest="$HOME/.local/opt/signal-cli" tarball bin
    if $DRY_RUN; then
        info "would download the latest $RELEASES/download/v<version>/signal-cli-<version>-Linux-native.tar.gz"
        info "would unpack it under $dest and link $LOCAL_BIN (no sudo)"
        return 0
    fi
    version="$(curl -Ls -o /dev/null -w '%{url_effective}' "$RELEASES/latest" | sed 's#.*/v##')"
    [[ -n "$version" ]] || { err "could not find the latest release at $RELEASES"; exit 1; }
    url="$RELEASES/download/v${version}/signal-cli-${version}-Linux-native.tar.gz"
    tarball="${TMPDIR:-/tmp}/signal-cli-${version}-Linux-native.tar.gz"
    info "latest release: $version — $url"
    mkdir -p "$dest" "$HOME/.local/bin"
    curl -L -o "$tarball" "$url"
    tar xzf "$tarball" -C "$dest"
    bin="$(find "$dest" -type f -name signal-cli | head -1)"   # top-level, or <ver>/bin/signal-cli
    [[ -n "$bin" ]] || { err "no signal-cli binary inside $tarball"; exit 1; }
    chmod +x "$bin"
    ln -sfn "$bin" "$LOCAL_BIN"
    case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) info "add $HOME/.local/bin to your PATH to run sig by hand" ;; esac
}

# ── 2. identity ───────────────────────────────────────────────
registered() { sig listAccounts 2>/dev/null | grep -qF -- "$ACCOUNT"; }
setup_identity() {
    local out code
    step 2 "give signal-cli a Signal identity ($MODE)"
    if ! $DRY_RUN && registered; then ok "already registered: $ACCOUNT"; return 0; fi
    if [[ "$MODE" == link ]]; then
        info "a QR code follows — on your phone: Signal > Settings > Linked devices > Link new device"
        run sig link -n "$LINK_NAME"
        return 0
    fi
    if $DRY_RUN; then
        run sig -a "$ACCOUNT" register
        run sig -a "$ACCOUNT" verify '<code from SMS>'
        return 0
    fi
    out="$(sig -a "$ACCOUNT" register 2>&1)" || true
    printf '%s\n' "$out"
    if grep -qi captcha <<<"$out"; then
        err "registration needs a captcha. Follow $CAPTCHA_WIKI, then run:"
        err "  signal-cli -a $ACCOUNT register --captcha <token>   and re-run this script"
        exit 1
    fi
    printf 'Verification code: '
    read -r code || true
    [[ -n "$code" ]] || { err "no verification code given"; exit 1; }
    sig -a "$ACCOUNT" verify "$code"
    ok "registered $ACCOUNT"
}

# ── 3. hand test ──────────────────────────────────────────────
send_by_hand() {
    step 3 "send one message by hand"
    if [[ "$MODE" == link ]]; then
        run sig -a "$ACCOUNT" send --notify-self -m "agent-recipes: signal-cli works" "$RECIPIENT"
    else
        run sig -a "$ACCOUNT" send -m "agent-recipes: signal-cli works" "$RECIPIENT"
        info "first time: accept the message request on your phone, or later messages stay hidden"
    fi
}

# ── 4. daemon ─────────────────────────────────────────────────
daemon_args() { printf '%s\n' -a "$ACCOUNT" daemon --http "127.0.0.1:$PORT" --no-receive-stdout --ignore-attachments --ignore-stories; }
write_plist() {
    local bin="$1" arg
    {
        echo '<?xml version="1.0" encoding="UTF-8"?>'
        echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
        echo '<plist version="1.0">'
        echo '<dict>'
        echo '  <key>Label</key><string>org.signal-cli.daemon</string>'
        echo '  <key>ProgramArguments</key>'
        echo '  <array>'
        printf '    <string>%s</string>\n' "$bin"
        while IFS= read -r arg; do printf '    <string>%s</string>\n' "$arg"; done < <(daemon_args)
        echo '  </array>'
        echo '  <key>RunAtLoad</key><true/>'
        echo '  <key>KeepAlive</key><true/>'
        echo '</dict>'
        echo '</plist>'
    } > "$PLIST"
}
write_unit() {
    local bin="$1"
    {
        echo '[Unit]'
        echo 'Description=signal-cli JSON-RPC daemon for agent-recipes notifications'
        echo 'After=network-online.target'
        echo 'Wants=network-online.target'
        echo
        echo '[Service]'
        printf 'ExecStart=%s %s\n' "$bin" "$(daemon_args | tr '\n' ' ' | sed 's/ $//')"
        echo 'Restart=on-failure'
        echo 'RestartSec=10'
        echo
        echo '[Install]'
        echo 'WantedBy=default.target'
    } > "$UNIT"
}
daemon_up() { [[ "$(curl -s -o /dev/null -w '%{http_code}' "$CHECK_URL" 2>/dev/null || true)" == 200 ]]; }
wait_for_daemon() {
    local tries=30
    while (( tries-- > 0 )); do
        daemon_up && return 0
        sleep "$RETRY_SLEEP"
    done
    return 1
}
start_daemon() {
    local bin
    step 4 "run the daemon on 127.0.0.1:$PORT"
    bin="${SIG:-signal-cli}"
    case "$OS" in
        darwin)
            if $DRY_RUN; then
                info "would write $PLIST with ProgramArguments: $bin $(daemon_args | tr '\n' ' ')"
            else
                mkdir -p "$(dirname "$PLIST")"; write_plist "$bin"; ok "wrote $PLIST"
            fi
            run launchctl unload "$PLIST" 2>/dev/null || true
            run launchctl load -w "$PLIST" ;;
        linux)
            if $DRY_RUN; then
                info "would write $UNIT with ExecStart=$bin $(daemon_args | tr '\n' ' ')"
            else
                mkdir -p "$(dirname "$UNIT")"; write_unit "$bin"; ok "wrote $UNIT"
            fi
            run systemctl --user daemon-reload
            run systemctl --user enable --now signal-cli
            run loginctl enable-linger "${USER:-$(id -un)}" ;;
        *) err "unsupported OS: $OS"; exit 1 ;;
    esac
    $DRY_RUN && { info "would wait for $CHECK_URL to answer 200"; return 0; }
    if wait_for_daemon; then ok "daemon answers on port $PORT"
    else err "the daemon did not answer on port $PORT within 30 s (check: curl -s -o /dev/null -w '%{http_code}' $CHECK_URL)"; exit 1; fi
}

# ── 5. plugin options ─────────────────────────────────────────
configure_json() {
    printf '{"notify_enabled":"true","notify_recipient":"%s","notify_signal_rpc_url":"%s"}\n' "$1" "$2"
}
configure_plugin() {
    step 5 "point the agent-recipes plugin at the daemon"
    local json; json="$(configure_json "$RECIPIENT" "$RPC_URL")"
    if ! command -v claude >/dev/null 2>&1; then
        info "claude is not on PATH; set the options yourself, then restart Claude Code:"
        printf "  echo '%s' | claude plugin configure %s --values-stdin\n" "$json" "$PLUGIN_ID"
        return 0
    fi
    if $DRY_RUN; then printf '  would run: claude plugin configure %s --values-stdin <<< %s\n' "$PLUGIN_ID" "$json"; return 0; fi
    printf '%s\n' "$json" | claude plugin configure "$PLUGIN_ID" --values-stdin
    ok "notify_enabled=true, notify_recipient=$RECIPIENT, notify_signal_rpc_url=$RPC_URL"
}

# ── 6. test through the plugin ────────────────────────────────
plugin_test() {
    step 6 "send a test message the way the hooks do"
    if $DRY_RUN; then info "would run: python3 $NOTIFY_PY test (with the options above)"; return 0; fi
    CLAUDE_PLUGIN_OPTION_NOTIFY_ENABLED=true \
    CLAUDE_PLUGIN_OPTION_NOTIFY_RECIPIENT="$RECIPIENT" \
    CLAUDE_PLUGIN_OPTION_NOTIFY_SIGNAL_RPC_URL="$RPC_URL" \
        python3 "$NOTIFY_PY" test
}

cmd_setup() {
    validate
    install_signal_cli
    setup_identity
    send_by_hand
    start_daemon
    configure_plugin
    plugin_test
    echo
    ok "done — restart Claude Code; then /notify-test inside it should say 'OK  sent'"
}

cmd_status() {
    local bin; bin="$SIG"
    echo "signal-cli:  ${bin:-not installed}"
    if [[ -n "$bin" ]]; then
        echo "registered:  $(sig listAccounts 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"
        [[ -n "$(sig listAccounts 2>/dev/null)" ]] || echo "             not registered yet"
    fi
    if daemon_up; then echo "daemon:      reachable at $CHECK_URL"; else echo "daemon:      not reachable at $CHECK_URL"; fi
    case "$OS" in
        darwin) [[ -f "$PLIST" ]] && echo "service:     $PLIST" || echo "service:     no launch agent" ;;
        linux)  [[ -f "$UNIT" ]]  && echo "service:     $UNIT"  || echo "service:     no systemd unit" ;;
    esac
    if command -v claude >/dev/null 2>&1; then
        echo "plugin:      $(claude plugin configure "$PLUGIN_ID" 2>/dev/null | grep -iE 'notify' | tr '\n' ' ' | sed 's/ $//')"
    else
        echo "plugin:      claude not on PATH"
    fi
    if [[ -f "$NOTIFY_LOG" ]]; then echo "notify.log:"; tail -3 "$NOTIFY_LOG" | sed 's/^/  /'; fi
    return 0
}

cmd_uninstall() {
    case "$OS" in
        darwin)
            if [[ -f "$PLIST" ]]; then
                run launchctl unload "$PLIST" 2>/dev/null || true
                $DRY_RUN || rm -f "$PLIST"
                ok "daemon stopped, $PLIST removed"
            else info "no launch agent to remove"; fi ;;
        linux)
            if [[ -f "$UNIT" ]]; then
                run systemctl --user disable --now signal-cli 2>/dev/null || true
                $DRY_RUN || rm -f "$UNIT"
                run systemctl --user daemon-reload 2>/dev/null || true
                ok "daemon stopped, $UNIT removed"
            else info "no systemd unit to remove"; fi ;;
    esac
    if command -v claude >/dev/null 2>&1; then
        if $DRY_RUN; then info 'would run: claude plugin configure ... --values-stdin <<< {"notify_enabled":"false"}'
        else printf '{"notify_enabled":"false"}\n' | claude plugin configure "$PLUGIN_ID" --values-stdin; ok "notify_enabled=false"; fi
    fi
    echo "Kept: signal-cli and its account. To remove them:"
    echo "  signal-cli -a +NUMBER unregister        # dedicated number"
    echo "  Signal > Settings > Linked devices       # remove '$LINK_NAME' (link mode)"
    case "$OS" in
        darwin) echo "  brew uninstall signal-cli" ;;
        linux)  echo "  rm -rf ~/.local/opt/signal-cli ~/.local/bin/signal-cli" ;;
    esac
    echo "  rm -rf ~/.local/share/signal-cli         # account data"
}

case "$ACTION" in
    setup)     cmd_setup ;;
    status)    cmd_status ;;
    uninstall) cmd_uninstall ;;
esac
