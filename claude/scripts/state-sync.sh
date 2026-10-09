#!/usr/bin/env bash
# state-sync.sh — keep Claude Code *user* state in a private git repo so it follows
# you across devices. OPTIONAL and reversible; does nothing until `init` is run.
#
# What is synced (and nothing else):
#   <claude-home>/agent-memory/   memory of agents declared `memory: user`
#   <claude-home>/CLAUDE.md       your user-level instructions
# Never synced: settings*.json, credentials, plugins/, projects/ (transcripts).
#
# How: the state repo is cloned to $SYNC_DIR and the two items above become
# symlinks into it. Hooks keep it current:
#   SessionStart -> state-sync.sh pull   (commit local edits, then pull --rebase)
#   SessionEnd   -> state-sync.sh push   (commit, then pull --rebase + push in background)
#
# Usage:
#   state-sync.sh init <git-url>   clone/adopt, link, first push
#   state-sync.sh pull | push      hook entrypoints — silent, always exit 0
#   state-sync.sh status           what is linked, ahead/behind, recent log
#   state-sync.sh off              replace the symlinks with plain copies and stop
#                                  the hooks on this device (init turns it back on)
#
# Hook contract: `pull` and `push` never fail the session, and print NOTHING on stdout
# (SessionStart stdout is added to Claude's context) — with one deliberate exception:
# when a pull brings in a CLAUDE.md change from another device, `pull` prints a
# single line saying so. Claude Code
# loads the user CLAUDE.md before SessionStart hooks finish, so without that line the
# session would silently run on the previous version.
set -euo pipefail

CLAUDE_HOME="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
# One fixed location on every device. STATE_SYNC_DIR exists for tests; it is NOT a
# plugin option on purpose: hooks and the /sync-state command must always agree on
# the directory, and Bash-tool commands do not receive plugin options.
SYNC_DIR="${STATE_SYNC_DIR:-$HOME/.claude-state}"
LOG="$SYNC_DIR/.sync.log"
DIR_ITEMS=(agent-memory)
FILE_ITEMS=(CLAUDE.md)

# File names that must never be committed, and high-signal secret shapes in content.
SECRET_NAMES='(^|/)(\.env(\..*)?|id_(rsa|ed25519|ecdsa|dsa)|.*\.(pem|ppk|p12|pfx)|.*credentials.*|settings.*\.json)$'
SECRET_CONTENT='-----BEGIN [A-Z ]*PRIVATE KEY-----|AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{36}|sk-ant-[A-Za-z0-9_-]{20}|xox[baprs]-[A-Za-z0-9-]{10}'

export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes -o ConnectTimeout=5}"

g() { git -C "$SYNC_DIR" -c commit.gpgsign=false "$@"; }
OFF_MARK="$SYNC_DIR/.git/state-sync-off"   # inside .git: per device, never committed
initialized() { [[ -d "$SYNC_DIR/.git" ]]; }
active() { initialized && [[ ! -e "$OFF_MARK" ]]; }
logline() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "$LOG"; }

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
    g add -A
    hold_back_secrets || true
    if ! g diff --cached --quiet; then
        g commit -q -m "sync($(hostname -s 2>/dev/null || hostname)): $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        logline "committed local changes"
    fi
}

# A hook killed by its timeout can leave a rebase half-done or a lock behind; every
# later git call would then fail. Undo both before doing anything else. Only a lock
# older than two minutes is removed — a fresh one belongs to a git that is running
# right now (another Claude session starting at the same moment).
rebase_in_progress() { [[ -d "$SYNC_DIR/.git/rebase-merge" || -d "$SYNC_DIR/.git/rebase-apply" ]]; }
abort_rebase() { ! rebase_in_progress || g rebase --abort >>"$LOG" 2>&1 || true; }

heal() {
    if rebase_in_progress; then
        abort_rebase
        logline "aborted a rebase left half-done by an interrupted run"
    fi
    if [[ -n "$(find "$SYNC_DIR/.git/index.lock" -mmin +2 2>/dev/null)" ]]; then
        rm -f "$SYNC_DIR/.git/index.lock"
        logline "removed a stale index.lock"
    fi
}

# Fetch (the only network step), then rebase local commits onto the remote.
# *.md files union-merge and cannot conflict. For anything else a second attempt
# keeps THIS device's version of the conflicting lines, so two devices always
# converge instead of one of them silently falling out of sync.
# --autostash: a held-back secret is an UNSTAGED change to a tracked file, and a
# plain rebase refuses to start with one; without it that device would stop
# syncing in both directions until the secret was removed.
pull_rebase() {
    local upstream
    if ! g fetch --quiet origin >>"$LOG" 2>&1; then
        logline "FETCH FAILED (offline?) — local state kept, will retry next session"
        return 1
    fi
    upstream="$(g rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)" || return 0
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

sync_remote() { pull_rebase && g push --quiet >>"$LOG" 2>&1 && logline "pushed" || logline "PUSH SKIPPED/FAILED"; }

claude_md_rev() { g rev-parse -q --verify HEAD:CLAUDE.md 2>/dev/null || true; }

cmd_pull() {
    active || return 0
    local before
    { heal; commit_local; } >>"$LOG" 2>&1 || true
    before="$(claude_md_rev)"   # after the local commit: only a REMOTE change counts
    pull_rebase >>"$LOG" 2>&1 || true
    if [[ "$(claude_md_rev)" != "$before" ]]; then
        echo "state-sync: $CLAUDE_HOME/CLAUDE.md was updated from another device during startup. Read that file now; the copy loaded at the start of this session is out of date."
    fi
}

cmd_push() {
    active || return 0
    { heal; commit_local; } >>"$LOG" 2>&1 || true
    if [[ "${STATE_SYNC_FOREGROUND:-}" == 1 ]]; then
        sync_remote || true
    else
        ( trap '' HUP; sync_remote ) >/dev/null 2>&1 &
        disown 2>/dev/null || true
    fi
}

# copy_missing <src-dir> <dst-dir>: copy files that do not exist in dst (never overwrite).
copy_missing() {
    local src="$1" dst="$2" f
    while IFS= read -r -d '' f; do
        [[ -e "$dst/$f" ]] && continue
        mkdir -p "$(dirname "$dst/$f")"
        cp -p "$src/$f" "$dst/$f"
    done < <(cd "$src" && find . -type f -print0)
}

# adopt <item> <dir|file>: move/merge the local item into the repo, then symlink it.
adopt() {
    local item="$1" kind="$2" local_path="$CLAUDE_HOME/$1" repo_path="$SYNC_DIR/$1" backup
    if [[ -L "$local_path" ]]; then
        ln -sfn "$repo_path" "$local_path"; return 0
    fi
    if [[ -e "$local_path" ]]; then
        if [[ -e "$repo_path" ]]; then
            # Both sides have it: repo wins on collisions; local-only files are added.
            [[ "$kind" == dir ]] && copy_missing "$local_path" "$repo_path"
            backup="$CLAUDE_HOME/.state-sync-backup/$(date -u +%Y%m%dT%H%M%SZ)"
            mkdir -p "$backup"; mv "$local_path" "$backup/"
            echo "  merged $item (your previous copy: $backup/$item)"
        else
            mv "$local_path" "$repo_path"
        fi
    elif [[ ! -e "$repo_path" ]]; then
        if [[ "$kind" == dir ]]; then mkdir -p "$repo_path"; else : > "$repo_path"; fi
    fi
    ln -s "$repo_path" "$local_path"
    echo "  linked $local_path -> $repo_path"
}

write_repo_files() {
    [[ -f "$SYNC_DIR/.gitattributes" ]] || printf '*.md merge=union\n' > "$SYNC_DIR/.gitattributes"
    [[ -f "$SYNC_DIR/.gitignore" ]] || printf '.sync.log\n' > "$SYNC_DIR/.gitignore"
    # A box with no global git identity must still be able to commit.
    g config user.name  >/dev/null 2>&1 || g config user.name  "state-sync"
    g config user.email >/dev/null 2>&1 || g config user.email "state-sync@$(hostname)"
}

cmd_init() {
    local url="${1:-}" item
    [[ -n "$url" ]] || { echo "usage: state-sync.sh init <git-url>" >&2; exit 2; }
    mkdir -p "$CLAUDE_HOME"
    if ! initialized; then
        [[ ! -e "$SYNC_DIR" ]] || { echo "error: $SYNC_DIR exists and is not a git repo" >&2; exit 1; }
        git clone -q "$url" "$SYNC_DIR"
    elif [[ "$(g remote get-url origin 2>/dev/null)" != "$url" ]]; then
        echo "error: $SYNC_DIR already syncs with $(g remote get-url origin 2>/dev/null); remove it first to use another repository" >&2
        exit 1
    fi
    rm -f "$OFF_MARK"
    write_repo_files
    for item in "${DIR_ITEMS[@]}";  do adopt "$item" dir;  done
    for item in "${FILE_ITEMS[@]}"; do adopt "$item" file; done
    commit_local
    g push -q -u origin HEAD
    echo "state sync is ON: $SYNC_DIR -> $(g remote get-url origin)"
    echo "Keep that repository PRIVATE: agent memory can contain details of your work."
}

cmd_off() {
    local item
    for item in "${DIR_ITEMS[@]}" "${FILE_ITEMS[@]}"; do
        if [[ -L "$CLAUDE_HOME/$item" ]]; then
            rm "$CLAUDE_HOME/$item"
            [[ -e "$SYNC_DIR/$item" ]] && cp -R "$SYNC_DIR/$item" "$CLAUDE_HOME/$item"
            echo "  unlinked $item (plain copy restored)"
        fi
    done
    if initialized; then : > "$OFF_MARK"; fi
    echo "state sync is OFF on this device. The repo at $SYNC_DIR is untouched; 'init <git-url>' turns sync back on, or delete the directory if it is unwanted."
}

cmd_status() {
    local item
    if ! initialized; then echo "state sync: OFF (no repo at $SYNC_DIR)"; return 0; fi
    if ! active; then
        echo "state sync: OFF on this device (repo kept at $SYNC_DIR; 'init <git-url>' turns it back on)"
        return 0
    fi
    echo "state sync: ON  $SYNC_DIR -> $(g remote get-url origin 2>/dev/null || echo '(no remote)')"
    for item in "${DIR_ITEMS[@]}" "${FILE_ITEMS[@]}"; do
        if [[ -L "$CLAUDE_HOME/$item" ]]; then echo "  linked    $item"; else echo "  NOT linked $item (run init again)"; fi
    done
    g status -sb | head -1
    if grep -qsF "$HELD_NOTE" "$LOG"; then
        echo "held back, never committed (they look like secrets):"
        grep -F "$HELD_NOTE" "$LOG" | sed "s/.*$HELD_NOTE /  /" | sort -u
    fi
    [[ -f "$LOG" ]] && { echo "recent log:"; tail -5 "$LOG" | sed 's/^/  /'; }
    return 0
}

case "${1:-status}" in
    init)   shift; cmd_init "$@" ;;
    pull)   cmd_pull ;;
    push)   cmd_push ;;
    off)    cmd_off ;;
    status) cmd_status ;;
    *)      echo "usage: state-sync.sh {init <git-url>|pull|push|status|off}" >&2; exit 2 ;;
esac
