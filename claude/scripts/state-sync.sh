#!/usr/bin/env bash
# state-sync.sh — keep agent memory and user instructions in a private git repo so
# they follow you across devices and tools. OPTIONAL and reversible; does nothing
# until `init` has run on a device.
#
# What is synced: see state-items.sh — Claude Code (agent memory, per-project auto
# memory, CLAUDE.md), Goose (memory, .goosehints), Hermes (memories), Codex
# (AGENTS.md) — every tool's own instruction file is a link to ONE INSTRUCTIONS.md.
# Never synced: settings, credentials, sessions/transcripts, Codex's memory store.
#
# Where: $STATE_DIR from ~/.config/agent-recipes/state.conf (written by setup.sh or
# `state-sync.sh config`), default ~/.agent-state; STATE_SYNC_DIR in the environment
# overrides both (tests). The hooks and the /sync-state command read the same file,
# so they can never disagree about the directory. A phase-4 ~/.claude-state is
# moved and converted by `init`.
#
# Usage:
#   state-sync.sh config [dir=… remote=… tools=… auto_memory=yes|no]   show / write state.conf
#   state-sync.sh init [git-url]   clone (or create, local-only), adopt, link, first push
#   state-sync.sh pull | push      hook entrypoints — silent, always exit 0
#   state-sync.sh status           what is linked, ahead/behind, warnings, recent log
#   state-sync.sh off              replace the links with plain copies and stop the
#                                  hooks on this device (init turns it back on)
#   state-sync.sh items | detect   what init would link / which tools are detected
#
# Hook contract: `pull` and `push` never fail the session and print NOTHING on stdout
# (SessionStart stdout is added to Claude's context) — with one deliberate exception:
# when a pull brings in an INSTRUCTIONS.md change from another device, `pull` prints a
# single line saying so, because Claude Code loads the user CLAUDE.md before
# SessionStart hooks finish.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_HOME="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/agent-recipes"
CONF="$CONF_DIR/state.conf"
LEGACY_DIR="$HOME/.claude-state"            # phase 4's fixed location
CONF_KEYS="STATE_DIR STATE_REMOTE STATE_TOOLS STATE_CLAUDE_AUTO_MEMORY"

# conf_value <KEY>: the value in state.conf (quotes stripped), empty when absent.
conf_value() {
    local line
    line="$(grep -s "^$1=" "$CONF" | tail -1)" || true
    line="${line#*=}"; line="${line%\"}"; line="${line#\"}"
    printf '%s' "$line"
}
# load_config: the file fills in every STATE_* key the environment did not set.
load_config() {
    local k
    [[ -f "$CONF" ]] || return 0
    for k in $CONF_KEYS; do
        [[ -n "${!k:-}" ]] || printf -v "$k" '%s' "$(conf_value "$k")"
    done
}
load_config
: "${STATE_DIR:=}" "${STATE_REMOTE:=}" "${STATE_TOOLS:=}" "${STATE_CLAUDE_AUTO_MEMORY:=yes}"
SYNC_DIR="${STATE_SYNC_DIR:-${STATE_DIR:-$HOME/.agent-state}}"
LOG="$SYNC_DIR/.sync.log"
OFF_MARK="$SYNC_DIR/.git/state-sync-off"   # inside .git: per device, never committed

# File names that must never be committed, and high-signal secret shapes in content.
SECRET_NAMES='(^|/)(\.env(\..*)?|id_(rsa|ed25519|ecdsa|dsa)|.*\.(pem|ppk|p12|pfx)|.*credentials.*|settings.*\.json)$'
SECRET_CONTENT='-----BEGIN [A-Z ]*PRIVATE KEY-----|AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{36}|sk-ant-[A-Za-z0-9_-]{20}|xox[baprs]-[A-Za-z0-9-]{10}'

export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes -o ConnectTimeout=5}"

g() { git -C "$SYNC_DIR" -c commit.gpgsign=false "$@"; }
initialized() { [[ -d "$SYNC_DIR/.git" ]]; }
active() { initialized && [[ ! -e "$OFF_MARK" ]]; }
has_origin() { g remote get-url origin >/dev/null 2>&1; }
origin_url() { g remote get-url origin 2>/dev/null || true; }
logline() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "$LOG"; }

# shellcheck source=state-items.sh
. "$HERE/state-items.sh"

HELD_NOTE="HELD BACK (looks like a secret, not committed):"

# Unstage anything that looks like a secret — by NAME or by CONTENT. A held-back file
# stays untracked, so it is seen again on every run; it is logged only the first time.
# (Deliberately no name patterns in .gitignore: an ignored file would vanish from
# sync without a trace.) Returns 1 if something was held back.
hold_back_secrets() {
    local f held=0
    while IFS= read -r -d '' f; do
        if [[ "$f" =~ $SECRET_NAMES ]] || { [[ -f "$SYNC_DIR/$f" ]] && grep -Eqa -e "$SECRET_CONTENT" "$SYNC_DIR/$f"; }; then
            g reset -q -- "$f"
            grep -qsF "$HELD_NOTE $f" "$LOG" || logline "$HELD_NOTE $f"
            held=1
        fi
    done < <(g diff --cached --name-only -z)
    return "$held"
}

commit_local() {
    local msg="${1:-sync($(hostname -s 2>/dev/null || hostname)): $(date -u +%Y-%m-%dT%H:%M:%SZ)}"
    g add -A
    hold_back_secrets || true
    if ! g diff --cached --quiet; then
        g commit -q -m "$msg"
        logline "committed local changes"
    fi
}

rebase_in_progress() { [[ -d "$SYNC_DIR/.git/rebase-merge" || -d "$SYNC_DIR/.git/rebase-apply" ]]; }
abort_rebase() { ! rebase_in_progress || g rebase --abort >>"$LOG" 2>&1 || true; }

# A hook killed by its timeout can leave a rebase half-done or a lock behind; every
# later git call would then fail. Undo both before doing anything else — but only when
# they are OLD: a fresh one belongs to a git that is running right now (the background
# push of the session that just ended, another session starting at the same moment).
heal() {
    if [[ -n "$(find "$SYNC_DIR/.git" -maxdepth 1 \( -name rebase-merge -o -name rebase-apply \) -mmin +2 2>/dev/null)" ]]; then
        abort_rebase
        logline "aborted a rebase left half-done by an interrupted run"
    fi
    if [[ -n "$(find "$SYNC_DIR/.git/index.lock" -mmin +2 2>/dev/null)" ]]; then
        rm -f "$SYNC_DIR/.git/index.lock"
        logline "removed a stale index.lock"
    fi
}

# Fetch (the only network step), then rebase local commits onto the remote.
# *.md and *.txt files union-merge and cannot conflict. For anything else a second
# attempt keeps THIS device's version of the conflicting lines, so two devices always
# converge. --autostash: a held-back secret is an UNSTAGED change to a tracked file,
# and a plain rebase refuses to start with one. Local-only stores skip all of this.
pull_rebase() {
    local upstream
    has_origin || return 0
    if ! g fetch --quiet origin >>"$LOG" 2>&1; then
        logline "FETCH FAILED (offline?) — local state kept, will retry next session"
        return 1
    fi
    upstream="$(g rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)" || return 0
    if rebase_in_progress; then
        logline "another sync is still rebasing — skipped this run"
        return 1
    fi
    g rebase --quiet --autostash "$upstream" >>"$LOG" 2>&1 && return 0
    abort_rebase
    if g rebase --quiet --autostash -X theirs "$upstream" >>"$LOG" 2>&1; then
        logline "conflict resolved: kept this device's version of the conflicting lines"
        return 0
    fi
    abort_rebase
    logline "REBASE FAILED — local state kept as-is; run 'state-sync.sh status'"
    return 1
}

sync_remote() {
    has_origin || return 0
    pull_rebase && g push --quiet >>"$LOG" 2>&1 && logline "pushed" || logline "PUSH SKIPPED/FAILED"
}

instructions_rev() { g rev-parse -q --verify "HEAD:$INSTRUCTIONS" 2>/dev/null || true; }

cmd_pull() {
    active || return 0
    local before
    { heal; adopt_auto_memory; commit_local; } >>"$LOG" 2>&1 || true
    before="$(instructions_rev)"   # after the local commit: only a REMOTE change counts
    pull_rebase >>"$LOG" 2>&1 || true
    if [[ "$(instructions_rev)" != "$before" ]]; then
        echo "state-sync: $CLAUDE_HOME/CLAUDE.md was updated from another device during startup (it is the shared $INSTRUCTIONS). Read that file now; the copy loaded at the start of this session is out of date."
    fi
}

cmd_push() {
    active || return 0
    { heal; adopt_auto_memory; commit_local; } >>"$LOG" 2>&1 || true
    if [[ "${STATE_SYNC_FOREGROUND:-}" == 1 ]]; then
        sync_remote || true
    else
        ( trap '' HUP; sync_remote ) >/dev/null 2>&1 &
        disown 2>/dev/null || true
    fi
}

write_repo_files() {
    local attrs="$SYNC_DIR/.gitattributes"
    grep -qsx '\*\.md merge=union'  "$attrs" || echo '*.md merge=union'  >> "$attrs"
    grep -qsx '\*\.txt merge=union' "$attrs" || echo '*.txt merge=union' >> "$attrs"
    [[ -f "$SYNC_DIR/.gitignore" ]] || printf '.sync.log\n' > "$SYNC_DIR/.gitignore"
    # A box with no global git identity must still be able to commit.
    g config user.name  >/dev/null 2>&1 || g config user.name  "state-sync"
    g config user.email >/dev/null 2>&1 || g config user.email "state-sync@$(hostname)"
}

# A phase-4 store at ~/.claude-state moves to the configured location when that does
# not exist yet, and its root-level layout becomes the per-tool one (history kept).
migrate_legacy_store() {
    if ! initialized && [[ "$SYNC_DIR" != "$LEGACY_DIR" && -d "$LEGACY_DIR/.git" && ! -e "$SYNC_DIR" ]]; then
        mkdir -p "$(dirname "$SYNC_DIR")"
        mv "$LEGACY_DIR" "$SYNC_DIR"
        echo "  moved $LEGACY_DIR -> $SYNC_DIR"
    fi
}
convert_legacy_layout() {
    local moved=0
    initialized || return 0
    if [[ -e "$SYNC_DIR/agent-memory" ]]; then
        mkdir -p "$SYNC_DIR/claude"
        g mv -k agent-memory claude/agent-memory 2>/dev/null || mv "$SYNC_DIR/agent-memory" "$SYNC_DIR/claude/agent-memory"
        moved=1
    fi
    if [[ -e "$SYNC_DIR/CLAUDE.md" ]]; then
        g mv -k CLAUDE.md "$INSTRUCTIONS" 2>/dev/null || mv "$SYNC_DIR/CLAUDE.md" "$SYNC_DIR/$INSTRUCTIONS"
        moved=1
    fi
    if (( moved )); then
        commit_local "migrate to the phase 5 layout (claude/, $INSTRUCTIONS)"
        echo "  converted the phase 4 layout: claude/agent-memory, $INSTRUCTIONS"
    fi
}

cmd_init() {
    local url="${1:-$STATE_REMOTE}"
    mkdir -p "$CLAUDE_HOME"
    migrate_legacy_store
    if ! initialized; then
        [[ ! -e "$SYNC_DIR" ]] || { echo "error: $SYNC_DIR exists and is not a git repo" >&2; exit 1; }
        if [[ -n "$url" ]]; then
            git clone -q "$url" "$SYNC_DIR"
        else
            git init -q "$SYNC_DIR"
            git -C "$SYNC_DIR" symbolic-ref HEAD refs/heads/main
        fi
    elif [[ -n "$url" && "$(origin_url)" != "$url" ]]; then
        if has_origin; then
            echo "error: $SYNC_DIR already syncs with $(origin_url); remove it first to use another repository" >&2
            exit 1
        fi
        g remote add origin "$url"
    fi
    convert_legacy_layout
    write_repo_files
    build_instructions
    adopt_items
    adopt_auto_memory
    ensure_shared_paragraph
    write_shared_readme
    rm -f "$OFF_MARK"                 # after adopt(): it dates this device's edits
    commit_local
    if has_origin; then
        g push -q -u origin HEAD
        echo "state sync is ON: $SYNC_DIR -> $(origin_url)"
    else
        echo "state sync is ON (local-only, no remote): $SYNC_DIR"
    fi
    echo "Keep that repository PRIVATE: agent memory can contain details of your work."
}

cmd_off() {
    unlink_all
    if initialized; then : > "$OFF_MARK"; fi
    echo "state sync is OFF on this device. The repo at $SYNC_DIR is untouched; 'init' turns sync back on, or delete the directory if it is unwanted."
}

cmd_status() {
    local k n r
    if ! initialized; then echo "state sync: OFF (no repo at $SYNC_DIR)"; return 0; fi
    if ! active; then
        echo "state sync: OFF on this device (repo kept at $SYNC_DIR; 'init' turns it back on)"
        return 0
    fi
    if has_origin; then echo "state sync: ON  $SYNC_DIR -> $(origin_url)"
    else echo "state sync: ON  $SYNC_DIR (local-only, no remote)"; fi
    echo "tools: $(active_tools)"
    while IFS=$'\t' read -r _ k n r; do
        if [[ -L "$n" ]]; then echo "  linked    $r  <- $n"; else echo "  missing   $r  <- $n (run init again)"; fi
    done < <(items; auto_memory_items)
    hermes_cap_warnings
    g status -sb | head -1
    if grep -qsF "$HELD_NOTE" "$LOG"; then
        echo "held back, never committed (they look like secrets):"
        grep -F "$HELD_NOTE" "$LOG" | sed "s/.*$HELD_NOTE /  /" | sort -u
    fi
    [[ -f "$LOG" ]] && { echo "recent log:"; tail -5 "$LOG" | sed 's/^/  /'; }
    return 0
}

# config [key=value …]: show state.conf, or write it (dir, remote, tools, auto_memory).
cmd_config() {
    local dir remote tools auto kv k v
    if [[ $# -eq 0 ]]; then [[ -f "$CONF" ]] && cat "$CONF"; return 0; fi
    dir="$(conf_value STATE_DIR)"; remote="$(conf_value STATE_REMOTE)"
    tools="$(conf_value STATE_TOOLS)"; auto="$(conf_value STATE_CLAUDE_AUTO_MEMORY)"
    for kv in "$@"; do
        k="${kv%%=*}"; v="${kv#*=}"
        case "$k" in
            dir)    dir="$v" ;;
            remote) remote="$v" ;;
            tools)  tools="$v" ;;
            auto_memory)
                case "$v" in yes|no) auto="$v" ;; *) echo "error: auto_memory must be yes or no" >&2; return 2 ;; esac ;;
            *) echo "error: unknown key '$k' (expected dir=, remote=, tools=, auto_memory=)" >&2; return 2 ;;
        esac
    done
    mkdir -p "$CONF_DIR"
    {
        echo "# agent-recipes state sync: where agent memory and instructions live."
        echo "# Written by setup.sh or 'state-sync.sh config'; read by the hooks and /sync-state."
        printf 'STATE_DIR="%s"\nSTATE_REMOTE="%s"\nSTATE_TOOLS="%s"\nSTATE_CLAUDE_AUTO_MEMORY="%s"\n' \
            "$dir" "$remote" "$tools" "${auto:-yes}"
    } > "$CONF"
}

case "${1:-status}" in
    init)   shift; cmd_init "${1:-}" ;;
    pull)   cmd_pull ;;
    push)   cmd_push ;;
    off)    cmd_off ;;
    status) cmd_status ;;
    config) shift; cmd_config "$@" ;;
    items)  list_items ;;
    detect) detect_tools ;;
    *)      echo "usage: state-sync.sh {init [git-url]|pull|push|status|off|config [key=value…]|items|detect}" >&2; exit 2 ;;
esac
