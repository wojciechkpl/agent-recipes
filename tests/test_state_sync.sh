#!/usr/bin/env bash
# Contract test for cross-device state sync (claude/scripts/state-sync.sh).
#
# Simulates several devices (HOME directories) sharing bare git remotes. Every run of
# the script happens on a sanitized PATH (git + python3 only) with no CLAUDE_CONFIG_DIR,
# GOOSE_CONFIG_DIR, HERMES_HOME, CODEX_HOME or STATE_SYNC_DIR inherited: phase 5 detects
# tools by looking at PATH and the home directory, and only this test may decide what a
# "device" has installed.
#
# Asserts (phase 4, store pinned to <home>/.claude-state through STATE_SYNC_DIR):
#   1. before `init`, pull/push are silent no-ops that exit 0
#   2. init adopts existing agent-memory + CLAUDE.md, symlinks them, pushes
#   3. a second device's init merges its own memory in without losing either side
#   4. an edit on A reaches B through push (A) + pull (B)
#   5. concurrent edits to the same memory file keep BOTH lines (union merge)
#   6. pull/push print nothing on stdout (SessionStart stdout enters Claude's context),
#      except one line from pull when CLAUDE.md itself changed
#   7. files that look like secrets are never committed
#   8. settings.json is never synced
#   9. `off` replaces symlinks with plain copies, keeps the content, and stops the
#      hooks on this device until `init` is run again
#  10. offline: hooks exit 0, edits are committed locally and arrive once back online
#  11. conflicting edits to a non-Markdown file converge (the later sync wins)
#  12. a half-done rebase or a stale index.lock left by a killed hook heals itself
#
# Asserts (phase 5):
#  13. Track A — $HOME/.config/agent-recipes/state.conf (KEY=VALUE, sourced by bash):
#      `config` prints/writes it; store precedence STATE_SYNC_DIR env > STATE_DIR in the
#      file > $HOME/.agent-state; `init` with no URL uses STATE_REMOTE; with neither the
#      store is local-only (git init on main, commits on push, never fetches or pushes)
#  14. migration — a phase-4 ~/.claude-state (agent-memory/, CLAUDE.md at the root) is
#      moved to the new location, converted to claude/agent-memory/ + INSTRUCTIONS.md
#      with history kept, and relinked
#  15. Track B — items for goose (memory/, .goosehints), hermes (memories/), codex
#      (AGENTS.md only, no memory sync) and Claude's per-project auto memory; env
#      overrides for every native path; *.txt union-merges; hermes size caps warn in
#      `status`; a tool absent on one device is not linked there and its repo folder
#      rides along; `off` unlinks every tool
#  16. Track C — INSTRUCTIONS.md is assembled once from CLAUDE.md + differing
#      .goosehints / AGENTS.md (originals backed up), ends with the shared-notes
#      paragraph exactly once (also after a second init), shared/README.md exists; a
#      later device gets the repo's version and keeps a backup
#  17. wiring — plugin.json at 0.6.0, /sync-state documents `config`
#
# Run: tests/test_state_sync.sh   (exit 0 = pass, non-zero = fail)
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYNC="${REPO}/claude/scripts/state-sync.sh"
# Several checks call git directly (not through the dev() wrapper); none of them may
# read the developer's real ~/.gitconfig or the system config.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

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

# A PATH on which NO agent CLI exists. The developer's machine may well have goose,
# hermes or codex installed; a "device" in this test has only what the test gives it.
mkdir -p "$workdir/bin"
ln -s "$(command -v git)"     "$workdir/bin/git"
ln -s "$(command -v python3)" "$workdir/bin/python3"
CLEAN_PATH="$workdir/bin:/usr/bin:/bin"

# dev <home> [VAR=value ...] <subcommand> [args...] — run state-sync.sh as that "device"
# with nothing inherited from the developer's environment. VAR=value pairs before the
# subcommand are added to the script's environment (e.g. a PATH with fake CLIs, or an
# explicit GOOSE_CONFIG_DIR).
dev() {
    local home="$1"; shift
    local pre=()
    while [[ $# -gt 0 && "$1" == *=* ]]; do pre+=("$1"); shift; done
    HOME="$home" STATE_SYNC_FOREGROUND=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 PATH="$CLEAN_PATH" \
        /usr/bin/env -u CLAUDE_CONFIG_DIR -u STATE_SYNC_DIR -u GOOSE_CONFIG_DIR -u HERMES_HOME -u CODEX_HOME \
        ${pre[@]+"${pre[@]}"} "$SYNC" "$@"
}
# on <home> <args...> — the phase-4 devices: their store is pinned to <home>/.claude-state
# through the STATE_SYNC_DIR override (the top of the phase-5 precedence order), so the
# sections written for phase 4 keep running unchanged on either tree.
on() { local home="$1"; shift; dev "$home" STATE_SYNC_DIR="$home/.claude-state" "$@"; }

# Small predicates for check():
quiet()     { "$@" >/dev/null 2>&1; }                       # exit status only
fails()     { ! "$@" >/dev/null 2>&1; }                     # must exit non-zero
not()       { ! "$@"; }                                     # negate a predicate
no_stdout() { [[ -z "$("$@" 2>/dev/null)" ]]; }             # nothing on stdout
no_output() { [[ -z "$("$@" 2>&1)" ]]; }                    # nothing on stdout or stderr
says()      { local pat="$1" out; shift; out="$("$@" 2>/dev/null)" || return 1; grep -qiE -- "$pat" <<<"$out"; }
rp()        { python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1"; }
links_to()  { [[ -L "$1" ]] && [[ "$(rp "$1")" == "$(rp "$2")" ]]; }   # <link> <target>
blob()      { git -C "$1" show "$2:$3"; }                   # blob <repo> <rev> <path>
tree_has()  { grep -qx -- "$2" <<<"$(git -C "$1" ls-tree -r --name-only HEAD 2>/dev/null)"; }
tree_grep() { grep -qE -- "$2" <<<"$(git -C "$1" ls-tree -r --name-only HEAD 2>/dev/null)"; }

# Repo-side paths of the two Claude items in the phase-4 sections. Phase 5 moves them to
# claude/agent-memory/ and INSTRUCTIONS.md — pinned exactly in the phase-5 sections
# below — so these helpers resolve whichever layout the repo has and the phase-4 checks
# keep testing what they always did: that content is committed, pushed and delivered.
repo_name() {  # repo_name <repo> <item-path>
    local n
    case "$2" in CLAUDE.md) n=INSTRUCTIONS.md ;; *) n="claude/$2" ;; esac
    if [[ -e "$1/$n" ]] || git -C "$1" rev-parse -q --verify "HEAD:$n" >/dev/null 2>&1; then echo "$n"; else echo "$2"; fi
}
in_rev()    { blob "$1" "$2" "$(repo_name "$1" "$3")"; }           # in_rev <repo> <rev> <item-path>
in_tree()   { tree_has "$1" "$(repo_name "$1" "$2")"; }            # committed at HEAD
repo_file() { echo "$1/$(repo_name "$1" "$2")"; }

git init -q --bare "$workdir/remote.git"
A="$workdir/homeA"; B="$workdir/homeB"
mkdir -p "$A/.claude/agent-memory/rust-expert" "$B/.claude/agent-memory/bash-expert"
tracked() { in_tree "$A/.claude-state" "$1"; }

echo "── not initialized: hooks are silent no-ops ──"
check "pull exits 0 with no output" no_output on "$A" pull
check "push exits 0 with no output" no_output on "$A" push
check "no repo was created"         test ! -e "$A/.claude-state"

echo "── device A: init adopts existing state ──"
printf 'prefer thiserror over anyhow in libraries\n' > "$A/.claude/agent-memory/rust-expert/MEMORY.md"
printf 'Always answer tersely.\n' > "$A/.claude/CLAUDE.md"
printf '{"model":"opus"}\n' > "$A/.claude/settings.json"
on "$A" init "$workdir/remote.git" >/dev/null
check "agent-memory is a symlink"   test -L "$A/.claude/agent-memory"
check "CLAUDE.md is a symlink"      test -L "$A/.claude/CLAUDE.md"
check "memory readable via link"    grep -q thiserror "$A/.claude/agent-memory/rust-expert/MEMORY.md"
check "memory is tracked"           tracked agent-memory/rust-expert/MEMORY.md
check "settings.json left in place" test -f "$A/.claude/settings.json"
check "settings.json not tracked"   not tree_grep "$A/.claude-state" settings
check "remote received the push"    bash -c "git -C '$workdir/remote.git' log --oneline | grep -q 'sync('"

echo "── device B: init merges, loses nothing ──"
printf 'quote every expansion\n' > "$B/.claude/agent-memory/bash-expert/MEMORY.md"
on "$B" init "$workdir/remote.git" >/dev/null
check "B got A's memory"            grep -q thiserror "$B/.claude/agent-memory/rust-expert/MEMORY.md"
check "B kept its own memory"       grep -q "quote every" "$B/.claude/agent-memory/bash-expert/MEMORY.md"
check "B got A's CLAUDE.md"         grep -q tersely "$B/.claude/CLAUDE.md"
check "B's old copy was backed up"  bash -c "ls '$B/.claude/.state-sync-backup'/*/agent-memory/bash-expert/MEMORY.md >/dev/null"

echo "── device C: init adopts state that is ALREADY a symlink (dotfiles) ──"
# A user who keeps ~/.claude/CLAUDE.md and agent-memory as symlinks into a dotfiles
# checkout must end up with the CONTENT in the sync repo, not a dangling link.
C="$workdir/homeC"
mkdir -p "$C/.claude" "$C/dotfiles/memory/python-expert"
printf 'from dotfiles\n' > "$C/dotfiles/claude.md"
printf 'memory from dotfiles\n' > "$C/dotfiles/memory/python-expert/MEMORY.md"
ln -s "$C/dotfiles/claude.md" "$C/.claude/CLAUDE.md"
ln -s "$C/dotfiles/memory" "$C/.claude/agent-memory"
git init -q --bare "$workdir/remote2.git"
init_rc=0
on "$C" init "$workdir/remote2.git" >/dev/null 2>&1 || init_rc=$?
check "init with symlinked state exits 0"          test "$init_rc" -eq 0
check "CLAUDE.md resolves to an existing file"     test -e "$C/.claude/CLAUDE.md"
check "CLAUDE.md content survived"                 grep -q "from dotfiles" "$C/.claude/CLAUDE.md"
check "repo holds CLAUDE.md with that content"     grep -q "from dotfiles" "$(repo_file "$C/.claude-state" CLAUDE.md)"
check "CLAUDE.md is committed"                     says "from dotfiles" in_rev "$C/.claude-state" HEAD CLAUDE.md
check "CLAUDE.md was pushed"                       says "from dotfiles" in_rev "$workdir/remote2.git" HEAD CLAUDE.md
check "agent-memory resolves to an existing dir"   test -d "$C/.claude/agent-memory"
check "memory content survived"                    grep -q "memory from dotfiles" "$C/.claude/agent-memory/python-expert/MEMORY.md"
check "memory file is committed"                   says "memory from dotfiles" in_rev "$C/.claude-state" HEAD agent-memory/python-expert/MEMORY.md
check "memory file was pushed"                     says "memory from dotfiles" in_rev "$workdir/remote2.git" HEAD agent-memory/python-expert/MEMORY.md

echo "── A -> B propagation ──"
on "$A" pull
check "A received B's memory on pull" grep -q "quote every" "$A/.claude/agent-memory/bash-expert/MEMORY.md"
printf 'use cargo nextest in CI\n' >> "$A/.claude/agent-memory/rust-expert/MEMORY.md"
on "$A" push
on "$B" pull
check "B sees A's new line"         grep -q nextest "$B/.claude/agent-memory/rust-expert/MEMORY.md"

echo "── concurrent edits: union merge keeps both ──"
printf 'line from A\n' >> "$A/.claude/agent-memory/rust-expert/MEMORY.md"
printf 'line from B\n' >> "$B/.claude/agent-memory/rust-expert/MEMORY.md"
on "$A" push
on "$B" push
on "$A" pull
for d in "$A" "$B"; do
    check "$(basename "$d") has A's line" grep -q "line from A" "$d/.claude/agent-memory/rust-expert/MEMORY.md"
    check "$(basename "$d") has B's line" grep -q "line from B" "$d/.claude/agent-memory/rust-expert/MEMORY.md"
done
check "no rebase left in progress"  bash -c "[[ ! -d '$B/.claude-state/.git/rebase-merge' && ! -d '$B/.claude-state/.git/rebase-apply' ]]"

echo "── pull announces a changed CLAUDE.md, and only that ──"
# Claude Code loads the user CLAUDE.md before SessionStart hooks finish, so a pull
# that changes it must say so on stdout (which SessionStart adds to the context). The
# NATIVE path is what the user knows, so the line names CLAUDE.md whatever the repo
# calls the file.
printf 'New rule from A.\n' >> "$A/.claude/CLAUDE.md"
on "$A" push
on "$B" pull >"$workdir/pull.out"
check "B's CLAUDE.md has A's new rule"        grep -q "New rule from A" "$B/.claude/CLAUDE.md"
check "pull printed exactly one line"         test "$(wc -l < "$workdir/pull.out" | tr -d ' ')" -eq 1
check "the line names CLAUDE.md"              grep -q "CLAUDE.md was updated" "$workdir/pull.out"
check "a second pull is silent"               no_stdout on "$B" pull
printf 'Rule written on B itself.\n' >> "$B/.claude/CLAUDE.md"
check "a LOCAL CLAUDE.md edit is not announced" no_stdout on "$B" pull
on "$B" push; on "$A" pull >/dev/null
printf 'memory-only change\n' >> "$A/.claude/agent-memory/rust-expert/MEMORY.md"
on "$A" push
check "a memory-only pull is silent"          no_stdout on "$B" pull
check "…and still delivered the memory"       grep -q "memory-only change" "$B/.claude/agent-memory/rust-expert/MEMORY.md"

echo "── offline: nothing breaks, nothing is lost ──"
real_remote="$(git -C "$A/.claude-state" remote get-url origin)"
git -C "$A/.claude-state" remote set-url origin "$workdir/unreachable.git"
printf 'written while offline\n' >> "$A/.claude/agent-memory/rust-expert/MEMORY.md"
check "offline pull exits 0 and is silent"    no_output on "$A" pull
check "offline push exits 0"                  on "$A" push
check "offline edit is committed locally"     bash -c "git -C '$A/.claude-state' log -1 --format=%s | grep -q '^sync('"
check "offline failure is logged"             grep -q "FETCH FAILED" "$A/.claude-state/.sync.log"
git -C "$A/.claude-state" remote set-url origin "$real_remote"
on "$A" push
on "$B" pull
check "back online: the offline edit arrives" grep -q "written while offline" "$B/.claude/agent-memory/rust-expert/MEMORY.md"

echo "── conflicting edits to a non-Markdown file converge ──"
# *.md files union-merge; anything else can truly conflict. The device that syncs
# second keeps its version of the conflicting lines, and neither device gets stuck.
printf '{"v": 0}\n' > "$A/.claude/agent-memory/rust-expert/data.json"
on "$A" push; on "$B" pull
printf '{"v": "from-A"}\n' > "$A/.claude/agent-memory/rust-expert/data.json"
printf '{"v": "from-B"}\n' > "$B/.claude/agent-memory/rust-expert/data.json"
on "$A" push
on "$B" push
on "$A" pull
check "both devices hold the same content"    cmp -s "$A/.claude/agent-memory/rust-expert/data.json" "$B/.claude/agent-memory/rust-expert/data.json"
check "the later sync (B) won the conflict"   grep -q "from-B" "$A/.claude/agent-memory/rust-expert/data.json"
check "the resolution is logged on B"         grep -q "conflict resolved" "$B/.claude-state/.sync.log"
check "B is not left mid-rebase"              bash -c "[[ ! -d '$B/.claude-state/.git/rebase-merge' && ! -d '$B/.claude-state/.git/rebase-apply' ]]"
check "B has nothing unpushed"                bash -c "[[ -z \"\$(git -C '$B/.claude-state' log '@{u}..HEAD' --oneline)\" ]]"

echo "── interrupted git operations heal on the next run ──"
# A hook that is killed by its timeout can leave a rebase half-done or a stale lock.
printf '{"v": "A2"}\n' > "$A/.claude/agent-memory/rust-expert/data.json"
on "$A" push
printf '{"v": "B2"}\n' > "$B/.claude/agent-memory/rust-expert/data.json"
git -C "$B/.claude-state" add -A
git -C "$B/.claude-state" -c user.name=t -c user.email=t@t commit -q -m "local edit"
git -C "$B/.claude-state" pull --rebase --quiet >/dev/null 2>&1 || true   # stops on the conflict
check "setup: B is stuck mid-rebase"          test -d "$B/.claude-state/.git/rebase-merge"
# Mirrors the index.lock rule below: a rebase younger than two minutes belongs to a
# git that may still be running (another session starting at the same moment) and
# is left alone; only an OLD one is the debris of a killed hook.
rc=0; on "$B" pull >/dev/null 2>&1 || rc=$?
check "a FRESH rebase in progress is left alone, pull exits 0" test "$rc" -eq 0
check "…and the fresh rebase state is untouched" test -d "$B/.claude-state/.git/rebase-merge"
[[ -d "$B/.claude-state/.git/rebase-merge" ]] && touch -t 202001010000 "$B/.claude-state/.git/rebase-merge" || true
on "$B" pull
check "pull aborted the OLD half-done rebase" bash -c "[[ ! -d '$B/.claude-state/.git/rebase-merge' && ! -d '$B/.claude-state/.git/rebase-apply' ]]"
check "B's edit survived"                     grep -q "B2" "$B/.claude/agent-memory/rust-expert/data.json"
touch -t 202001010000 "$A/.claude-state/.git/index.lock"
printf 'after a stale lock\n' >> "$A/.claude/agent-memory/rust-expert/MEMORY.md"
on "$A" push
check "a stale index.lock is cleared"         test ! -e "$A/.claude-state/.git/index.lock"
check "…and the edit was committed"           says "after a stale lock" in_rev "$A/.claude-state" HEAD agent-memory/rust-expert/MEMORY.md
touch "$A/.claude-state/.git/index.lock"
rc=0; on "$A" push >/dev/null 2>&1 || rc=$?
check "a fresh lock is left alone, push exits 0" test "$rc" -eq 0
check "…and the fresh lock is still there"    test -e "$A/.claude-state/.git/index.lock"
rm -f "$A/.claude-state/.git/index.lock"
on "$A" push; on "$B" pull; on "$B" push; on "$A" pull

echo "── hooks stay silent on stdout ──"
check "pull prints nothing on stdout" no_stdout on "$A" pull
check "push prints nothing on stdout" no_stdout on "$A" push

echo "── secrets are held back ──"
printf 'note\n-----BEGIN OPENSSH PRIVATE KEY-----\nabc\n' > "$A/.claude/agent-memory/rust-expert/leak.md"
printf 'token ghp_%s\n' "$(printf 'a%.0s' $(seq 36))" > "$A/.claude/agent-memory/rust-expert/tok.md"
printf 'harmless\n' > "$A/.claude/agent-memory/rust-expert/ok.md"
on "$A" push 2>/dev/null
check "private-key content not committed" not tree_grep "$A/.claude-state" leak.md
check "token-shaped content not committed" not tree_grep "$A/.claude-state" tok.md
check "ordinary file still committed"     tracked agent-memory/rust-expert/ok.md
check "hold-back is logged"               grep -q "HELD BACK" "$A/.claude-state/.sync.log"
check "the log itself is not tracked"     not tree_grep "$A/.claude-state" sync.log
printf 'API_KEY=x\n' > "$A/.claude/agent-memory/rust-expert/.env"
printf 'where the team keeps logins\n' > "$A/.claude/agent-memory/rust-expert/notes-credentials.md"
on "$A" push 2>/dev/null
on "$A" push 2>/dev/null
check "secret-NAMED files are not committed" not tree_grep "$A/.claude-state" '/\.env$|credentials'
check "a name-based hold-back is logged"     grep -q "HELD BACK.*notes-credentials.md" "$A/.claude-state/.sync.log"
check "each held-back file is logged once"   test "$(grep -c 'HELD BACK.*notes-credentials.md' "$A/.claude-state/.sync.log")" -eq 1
check "status lists what is held back"       says 'notes-credentials.md' on "$A" status

echo "── a secret appended to an ALREADY-TRACKED file does not stop sync ──"
# Holding back a tracked file leaves an UNSTAGED change behind. A plain rebase
# refuses to start on top of one, which would freeze this device in both
# directions until the secret was removed; --autostash keeps the sync flowing.
# AKIAIOSFODNN7EXAMPLE is AWS's documented example access key.
printf 'clean notes\n' > "$A/.claude/agent-memory/rust-expert/notes.md"
on "$A" push; on "$B" pull
check "setup: notes.md is tracked"            tracked agent-memory/rust-expert/notes.md
printf 'Rule from B while A holds a secret.\n' >> "$B/.claude/CLAUDE.md"
on "$B" push
printf 'key AKIAIOSFODNN7EXAMPLE\n' >> "$A/.claude/agent-memory/rust-expert/notes.md"
printf 'written next to the secret\n' > "$A/.claude/agent-memory/rust-expert/clean.md"
pull_rc=0
on "$A" pull >"$workdir/heldpull.out" 2>/dev/null || pull_rc=$?
check "pull exits 0 with an unstaged held-back change" test "$pull_rc" -eq 0
check "pull still delivered B's CLAUDE.md line" grep -q "Rule from B while A holds" "$A/.claude/CLAUDE.md"
check "pull announced the CLAUDE.md change (one line)" test "$(wc -l < "$workdir/heldpull.out" | tr -d ' ')" -eq 1
check "HEAD's notes.md has no AKIA key"       not says AKIA in_rev "$A/.claude-state" HEAD agent-memory/rust-expert/notes.md
check "the working copy still has the key"    grep -q AKIAIOSFODNN7EXAMPLE "$A/.claude/agent-memory/rust-expert/notes.md"
on "$A" push
check "push delivered clean.md to the remote" in_tree "$workdir/remote.git" agent-memory/rust-expert/clean.md
check "the tracked file's hold-back is logged" grep -q "HELD BACK.*agent-memory/rust-expert/notes\.md" "$A/.claude-state/.sync.log"
check "no rebase failed along the way"        not grep -q 'REBASE FAILED' "$A/.claude-state/.sync.log"

echo "── status / off ──"
check "status reports ON"           says 'state sync: ON' on "$A" status
on "$A" off >/dev/null
check "off: agent-memory is a real dir" bash -c "[[ -d '$A/.claude/agent-memory' && ! -L '$A/.claude/agent-memory' ]]"
check "off: content preserved"      grep -q nextest "$A/.claude/agent-memory/rust-expert/MEMORY.md"
check "off: repo left in place"     test -d "$A/.claude-state/.git"
check "off: status reports OFF"     says 'state sync: OFF' on "$A" status
head_before="$(git -C "$A/.claude-state" rev-parse HEAD)"
printf 'written while sync is off\n' > "$A/.claude/agent-memory/rust-expert/while-off.md"
printf 'Edited while sync was off.\n' >> "$A/.claude/CLAUDE.md"   # the plain copy, newer than the repo's
printf 'stray edit inside the repo\n' >> "$(repo_file "$A/.claude-state" CLAUDE.md)"
check "off: pull is a silent no-op" no_output on "$A" pull
check "off: push is a silent no-op" no_output on "$A" push
check "off: hooks committed nothing" test "$(git -C "$A/.claude-state" rev-parse HEAD)" = "$head_before"
git -C "$A/.claude-state" checkout -q -- "$(repo_name "$A/.claude-state" CLAUDE.md)"
check "init with a different remote is refused" fails on "$A" init "$workdir/other.git"
on "$A" init "$real_remote" >"$workdir/reinit.out"
check "init again: status reports ON"   says 'state sync: ON' on "$A" status
check "init again: relinked"            test -L "$A/.claude/agent-memory"
check "init again: file written while off is now synced" tracked agent-memory/rust-expert/while-off.md
# The local plain copy was edited AFTER off, so it is newer than the repo's copy:
# it must win, land in the repo and be committed — not be overwritten by the repo.
check "init again: the newer local CLAUDE.md edit wins"  grep -q "Edited while sync was off" "$A/.claude/CLAUDE.md"
check "init again: ...and is committed"                  says "Edited while sync was off" in_rev "$A/.claude-state" HEAD CLAUDE.md
check "init again: no 'merged' claim without saying the repo copy was replaced" \
  bash -c "! grep -q 'merged CLAUDE.md' '$workdir/reinit.out' || grep -qi 'replac' '$workdir/reinit.out'"

# ═════════════════════════════════════════════════════════════════════════════════════
# Phase 5. The devices below are NOT pinned with STATE_SYNC_DIR: the store location
# comes from state.conf or the default, which is what these sections test.
# ═════════════════════════════════════════════════════════════════════════════════════
MARK='<!-- agent-recipes:shared-notes -->'      # marks the one fixed paragraph in INSTRUCTIONS.md
count_of()     { local n; n="$(grep -c -- "$1" "$2" 2>/dev/null)" || true; echo "${n:-0}"; }   # lines matching, 0 if no file
marker_count() { count_of "$MARK" "$1"; }
line_of()      { local n; n="$(grep -n -- "$1" "$2" 2>/dev/null | head -1 | cut -d: -f1)" || true; echo "${n:-0}"; }

echo "── phase 5 / Track A: state.conf, store location, local-only mode ──"
# $HOME/.config/agent-recipes/state.conf holds KEY=VALUE lines that bash can source:
# STATE_DIR, STATE_REMOTE, STATE_TOOLS (space-separated), STATE_CLAUDE_AUTO_MEMORY.
L="$workdir/homeL"; CONF_L="$L/.config/agent-recipes/state.conf"
mkdir -p "$L/.claude/agent-memory/x"
printf 'local memory\n' > "$L/.claude/agent-memory/x/MEMORY.md"
printf 'Local rules.\n'  > "$L/.claude/CLAUDE.md"
check "config with no file yet exits 0"                 quiet dev "$L" config
check "config with no file yet prints nothing on stdout" no_stdout dev "$L" config
check "'config dir= remote= tools= auto_memory=' exits 0" quiet dev "$L" config dir="$L/store" remote= tools=claude auto_memory=no
check "it wrote state.conf, creating the directory"     test -f "$CONF_L"
check "state.conf is plain KEY=VALUE lines"             not grep -qvE '^(#|$|STATE_[A-Z_]+=)' "$CONF_L"
check "state.conf sources back into the four keys" \
  bash -c ". '$CONF_L' && [[ \$STATE_DIR == '$L/store' && -z \${STATE_REMOTE:-} && \$STATE_TOOLS == claude && \$STATE_CLAUDE_AUTO_MEMORY == no ]]"
check "config with no args prints the file"             says "STATE_DIR=.*$L/store" dev "$L" config
check "config updates one key"                          quiet dev "$L" config auto_memory=yes
check "...and keeps the others" \
  bash -c ". '$CONF_L' && [[ \$STATE_DIR == '$L/store' && \$STATE_TOOLS == claude && \$STATE_CLAUDE_AUTO_MEMORY == yes ]]"
check "config refuses an unknown key"                   fails dev "$L" config bogus=1
check "config refuses auto_memory=maybe"                fails dev "$L" config auto_memory=maybe
check "...and left the file unchanged"                  bash -c ". '$CONF_L' && [[ \$STATE_CLAUDE_AUTO_MEMORY == yes && \$STATE_DIR == '$L/store' ]]"

# No URL and no STATE_REMOTE: local-only. A git repo with history, nothing on the network.
rc=0; dev "$L" init >"$workdir/L-init.out" 2>&1 || rc=$?
check "init with no URL and no STATE_REMOTE exits 0 (local-only)" test "$rc" -eq 0
check "the store is at STATE_DIR from the file"        test -d "$L/store/.git"
check "...and not at the default location"             test ! -e "$L/.agent-state"
check "local-only: branch is main"                     test "$(git -C "$L/store" symbolic-ref --short HEAD 2>/dev/null)" = main
check "local-only: no remote configured"               fails git -C "$L/store" remote get-url origin
check "local-only: agent-memory -> claude/agent-memory" links_to "$L/.claude/agent-memory" "$L/store/claude/agent-memory"
check "local-only: CLAUDE.md -> INSTRUCTIONS.md"       links_to "$L/.claude/CLAUDE.md" "$L/store/INSTRUCTIONS.md"
check "local-only: the first commit holds the memory"  says 'local memory' blob "$L/store" HEAD claude/agent-memory/x/MEMORY.md
check "status reports ON"                              says 'state sync: ON' dev "$L" status
check "status says local-only"                         says 'local-only' dev "$L" status
printf 'appended offline\n' >> "$L/.claude/agent-memory/x/MEMORY.md"
check "local-only push is silent"                      no_output dev "$L" push
check "local-only push exits 0"                        dev "$L" push
check "local-only push committed the edit"             says 'appended offline' blob "$L/store" HEAD claude/agent-memory/x/MEMORY.md
check "local-only pull is a silent no-op"              no_output dev "$L" pull
check "local-only never touches the network (no fetch/push attempted)" \
  not grep -qE 'FETCH FAILED|PUSH SKIPPED' "$L/store/.sync.log"

# Precedence: STATE_SYNC_DIR env > STATE_DIR in the file > $HOME/.agent-state.
check "STATE_SYNC_DIR env beats the file"              says "no repo at $L/envstore" dev "$L" STATE_SYNC_DIR="$L/envstore" status
N="$workdir/homeN"; mkdir -p "$N/.claude"
check "default store is ~/.agent-state when there is no file" says "no repo at $N/.agent-state" dev "$N" status

# init with no URL reads STATE_REMOTE; init <url> on a device without a file stores nothing.
R="$workdir/homeR"; mkdir -p "$R/.claude"
printf 'R rules.\n' > "$R/.claude/CLAUDE.md"
git init -q --bare "$workdir/remote3.git"
quiet dev "$R" config remote="$workdir/remote3.git" || true
check "init with no URL uses STATE_REMOTE from the file" quiet dev "$R" init
check "...the store is at the default ~/.agent-state"    test -d "$R/.agent-state/.git"
check "...origin is STATE_REMOTE"                        test "$(git -C "$R/.agent-state" remote get-url origin 2>/dev/null)" = "$workdir/remote3.git"
check "...and the first push happened"                   says 'R rules' blob "$workdir/remote3.git" HEAD INSTRUCTIONS.md
check "init <url> on a device without state.conf exits 0" quiet dev "$N" init "$workdir/remote3.git"
check "...it stores nothing (the remote lives in the repo)" test ! -e "$N/.config/agent-recipes/state.conf"
check "...and the second device got the instructions"   grep -q 'R rules' "$N/.claude/CLAUDE.md"

echo "── phase 5 / migration: a phase-4 ~/.claude-state moves and converts ──"
# Phase 4 kept agent-memory/ and CLAUDE.md at the repo root in ~/.claude-state. When the
# configured store does not exist yet and ~/.claude-state is a git repo, init moves it,
# converts the layout (history kept) and relinks.
M="$workdir/homeM"; mkdir -p "$M/.claude" "$M/.claude-state/agent-memory/old-agent"
printf 'old memory\n' > "$M/.claude-state/agent-memory/old-agent/MEMORY.md"
printf 'Old rules.\n'  > "$M/.claude-state/CLAUDE.md"
printf '*.md merge=union\n' > "$M/.claude-state/.gitattributes"
printf '.sync.log\n'        > "$M/.claude-state/.gitignore"
git -C "$M/.claude-state" init -q
git -C "$M/.claude-state" add -A
git -C "$M/.claude-state" -c user.name=t -c user.email=t@t commit -q -m "phase 4 state"
git init -q --bare "$workdir/remote4.git"
git -C "$M/.claude-state" remote add origin "$workdir/remote4.git"
git -C "$M/.claude-state" push -q -u origin HEAD
ln -s "$M/.claude-state/agent-memory" "$M/.claude/agent-memory"
ln -s "$M/.claude-state/CLAUDE.md"    "$M/.claude/CLAUDE.md"
old_head="$(git -C "$M/.claude-state" rev-parse HEAD)"
rc=0; dev "$M" init "$workdir/remote4.git" >"$workdir/M-init.out" 2>&1 || rc=$?
check "migration: init exits 0"                          test "$rc" -eq 0
check "migration: the store now lives at ~/.agent-state" test -d "$M/.agent-state/.git"
check "migration: ~/.claude-state is gone"               test ! -e "$M/.claude-state"
check "migration: history is kept"                       git -C "$M/.agent-state" merge-base --is-ancestor "$old_head" HEAD
check "migration: agent-memory/ became claude/agent-memory/" says 'old memory' blob "$M/.agent-state" HEAD claude/agent-memory/old-agent/MEMORY.md
check "migration: CLAUDE.md became INSTRUCTIONS.md"      says 'Old rules' blob "$M/.agent-state" HEAD INSTRUCTIONS.md
check "migration: no CLAUDE.md left at the repo root"    fails git -C "$M/.agent-state" rev-parse -q --verify HEAD:CLAUDE.md
check "migration: no agent-memory/ left at the repo root" fails git -C "$M/.agent-state" rev-parse -q --verify HEAD:agent-memory
check "migration: agent-memory relinked"                 links_to "$M/.claude/agent-memory" "$M/.agent-state/claude/agent-memory"
check "migration: CLAUDE.md relinked"                    links_to "$M/.claude/CLAUDE.md" "$M/.agent-state/INSTRUCTIONS.md"
check "migration: content readable through the links"   grep -q 'old memory' "$M/.claude/agent-memory/old-agent/MEMORY.md"
check "migration: the shared-notes paragraph was added once" test "$(marker_count "$M/.agent-state/INSTRUCTIONS.md")" -eq 1
check "migration: the new layout was pushed"             says 'old memory' blob "$workdir/remote4.git" HEAD claude/agent-memory/old-agent/MEMORY.md
check "migration: status reports ON"                     says 'state sync: ON' dev "$M" status
# STATE_DIR explicitly set to the old location: convert in place, no move.
M2="$workdir/homeM2"; mkdir -p "$M2/.claude" "$M2/.claude-state/agent-memory/old-agent"
printf 'old memory 2\n' > "$M2/.claude-state/agent-memory/old-agent/MEMORY.md"
printf 'Old rules 2.\n'  > "$M2/.claude-state/CLAUDE.md"
git -C "$M2/.claude-state" init -q
git -C "$M2/.claude-state" add -A
git -C "$M2/.claude-state" -c user.name=t -c user.email=t@t commit -q -m "phase 4 state"
ln -s "$M2/.claude-state/agent-memory" "$M2/.claude/agent-memory"
ln -s "$M2/.claude-state/CLAUDE.md"    "$M2/.claude/CLAUDE.md"
quiet dev "$M2" config dir="$M2/.claude-state" || true
check "in-place: init exits 0 (local-only, STATE_DIR is the old location)" quiet dev "$M2" init
check "in-place: the store stayed where STATE_DIR points"  test -d "$M2/.claude-state/.git"
check "in-place: nothing was created at the default"       test ! -e "$M2/.agent-state"
check "in-place: layout converted (claude/agent-memory/)"  says 'old memory 2' blob "$M2/.claude-state" HEAD claude/agent-memory/old-agent/MEMORY.md
check "in-place: layout converted (INSTRUCTIONS.md)"       says 'Old rules 2' blob "$M2/.claude-state" HEAD INSTRUCTIONS.md
check "in-place: relinked"                                 links_to "$M2/.claude/CLAUDE.md" "$M2/.claude-state/INSTRUCTIONS.md"

echo "── phase 5 / Tracks B+C: goose, hermes, codex and the shared INSTRUCTIONS.md ──"
# Device D has every tool: claude, goose (~/.config/goose), hermes (~/.hermes), codex
# (~/.codex), plus one Claude project with auto memory and a transcript next to it.
D="$workdir/homeD"; SD="$D/.agent-state"; INS_D="$SD/INSTRUCTIONS.md"
mkdir -p "$D/.claude/agent-memory/py" "$D/.claude/projects/-Users-me-proj/memory" \
         "$D/.config/goose/memory" "$D/.hermes/memories" "$D/.codex/memories"
printf 'Claude rules.\n'      > "$D/.claude/CLAUDE.md"
printf 'py memory\n'          > "$D/.claude/agent-memory/py/MEMORY.md"
printf 'auto note\n'          > "$D/.claude/projects/-Users-me-proj/memory/MEMORY.md"
printf '{"type":"user"}\n'    > "$D/.claude/projects/-Users-me-proj/abc.jsonl"
printf 'Goose hints.\n'       > "$D/.config/goose/.goosehints"
printf '# python\nuse uv\n'   > "$D/.config/goose/memory/dev.txt"
printf 'hermes memory\n'      > "$D/.hermes/memories/MEMORY.md"
printf 'hermes user\n'        > "$D/.hermes/memories/USER.md"
printf 'Soul.\n'              > "$D/.hermes/SOUL.md"
printf 'Codex rules.\n'       > "$D/.codex/AGENTS.md"
printf 'codex memory\n'       > "$D/.codex/memories/MEMORY.md"
git init -q --bare "$workdir/remote5.git"
rc=0; dev "$D" init "$workdir/remote5.git" >"$workdir/D-init.out" 2>&1 || rc=$?
check "init with every tool present exits 0"            test "$rc" -eq 0
check "the store is at the default ~/.agent-state"      test -d "$SD/.git"
check "claude: agent-memory -> claude/agent-memory"     links_to "$D/.claude/agent-memory" "$SD/claude/agent-memory"
check "claude: CLAUDE.md -> INSTRUCTIONS.md"            links_to "$D/.claude/CLAUDE.md" "$INS_D"
check "claude: memory tracked under claude/"            says 'py memory' blob "$SD" HEAD claude/agent-memory/py/MEMORY.md
check "goose: memory -> goose/memory"                   links_to "$D/.config/goose/memory" "$SD/goose/memory"
check "goose: .goosehints -> INSTRUCTIONS.md"           links_to "$D/.config/goose/.goosehints" "$INS_D"
check "goose: memory category tracked"                  says 'use uv' blob "$SD" HEAD goose/memory/dev.txt
check "hermes: memories -> hermes/memories"             links_to "$D/.hermes/memories" "$SD/hermes/memories"
check "hermes: MEMORY.md tracked"                       says 'hermes memory' blob "$SD" HEAD hermes/memories/MEMORY.md
check "hermes: USER.md tracked"                         says 'hermes user' blob "$SD" HEAD hermes/memories/USER.md
check "hermes: SOUL.md is not linked"                   test ! -L "$D/.hermes/SOUL.md"
check "hermes: SOUL.md is not tracked"                  not tree_grep "$SD" 'SOUL\.md'
check "codex: AGENTS.md -> INSTRUCTIONS.md"             links_to "$D/.codex/AGENTS.md" "$INS_D"
check "codex: memories are NOT linked"                  test ! -L "$D/.codex/memories"
check "codex: memories are NOT in the repo"             not tree_grep "$SD" '^codex/'
check "codex: memory left in place"                     grep -q 'codex memory' "$D/.codex/memories/MEMORY.md"
check "auto memory: projects/<p>/memory -> claude/auto-memory/<p>" \
  links_to "$D/.claude/projects/-Users-me-proj/memory" "$SD/claude/auto-memory/-Users-me-proj"
check "auto memory: the note is tracked"                says 'auto note' blob "$SD" HEAD claude/auto-memory/-Users-me-proj/MEMORY.md
check "auto memory: projects/ itself is not a link"     test ! -L "$D/.claude/projects"
check "auto memory: the project dir is not a link"      test ! -L "$D/.claude/projects/-Users-me-proj"
check "auto memory: the transcript next to it is untouched" bash -c "[[ -f '$D/.claude/projects/-Users-me-proj/abc.jsonl' && ! -L '$D/.claude/projects/-Users-me-proj/abc.jsonl' ]]"
check "auto memory: transcripts never enter the repo"   not tree_grep "$SD" 'jsonl'
check ".gitattributes: *.md merge=union"                grep -qx '\*\.md merge=union' "$SD/.gitattributes"
check ".gitattributes: *.txt merge=union"               grep -qx '\*\.txt merge=union' "$SD/.gitattributes"
check "status names goose"                              says goose  dev "$D" status
check "status names hermes"                             says hermes dev "$D" status
check "status names codex"                              says codex  dev "$D" status
# Track C: INSTRUCTIONS.md assembled on the first init.
check "INSTRUCTIONS.md starts with CLAUDE.md's content"  test "$(head -1 "$INS_D" 2>/dev/null)" = "Claude rules."
check "INSTRUCTIONS.md has '## From goose' + the hints"  bash -c "grep -A2 '^## From goose' '$INS_D' | grep -q 'Goose hints'"
check "INSTRUCTIONS.md has '## From codex' + AGENTS.md"  bash -c "grep -A2 '^## From codex' '$INS_D' | grep -q 'Codex rules'"
check "no '## From claude' (CLAUDE.md IS the body)"      not grep -q '^## From claude' "$INS_D"
check "the shared-notes marker appears exactly once"     test "$(marker_count "$INS_D")" -eq 1
check "the paragraph points at shared/*.md"              bash -c "sed -n '/agent-recipes:shared-notes/,\$p' '$INS_D' | grep -q 'shared/'"
check "the paragraph comes after the From sections"      test "$(line_of "$MARK" "$INS_D")" -gt "$(line_of '^## From codex' "$INS_D")"
check "original .goosehints backed up"                   bash -c "find '$D/.claude/.state-sync-backup' -name .goosehints 2>/dev/null | grep -q ."
check "original AGENTS.md backed up"                     bash -c "find '$D/.claude/.state-sync-backup' -name AGENTS.md 2>/dev/null | grep -q ."
check "all three native files read the same text" \
  bash -c "cmp -s '$D/.claude/CLAUDE.md' '$D/.config/goose/.goosehints' && cmp -s '$D/.claude/CLAUDE.md' '$D/.codex/AGENTS.md'"
check "shared/README.md created and tracked"             tree_has "$SD" shared/README.md
check "a second init exits 0"                            quiet dev "$D" init "$workdir/remote5.git"
check "second init: marker still exactly once"           test "$(marker_count "$INS_D")" -eq 1
check "second init: '## From goose' still once"          test "$(count_of '^## From goose' "$INS_D")" -eq 1

# Device E joins later with goose only (no hermes, no codex) and a differing .goosehints.
E="$workdir/homeE"; SE="$E/.agent-state"
mkdir -p "$E/.claude" "$E/.config/goose/memory"
printf 'E has its own goose hints.\n' > "$E/.config/goose/.goosehints"
check "later device: init exits 0"                       quiet dev "$E" init "$workdir/remote5.git"
check "later device: goose memory linked and delivered"  grep -q 'use uv' "$E/.config/goose/memory/dev.txt"
check "later device: .goosehints -> INSTRUCTIONS.md"     links_to "$E/.config/goose/.goosehints" "$SE/INSTRUCTIONS.md"
check "later device: the repo's INSTRUCTIONS.md wins over a differing .goosehints" not grep -q 'E has its own' "$E/.config/goose/.goosehints"
check "later device: ...and the old .goosehints is backed up" \
  bash -c "find '$E/.claude/.state-sync-backup' -name .goosehints -exec grep -l 'E has its own' {} + 2>/dev/null | grep -q ."
check "later device: no second '## From goose'"          test "$(count_of '^## From goose' "$SE/INSTRUCTIONS.md")" -eq 1
check "later device: CLAUDE.md -> INSTRUCTIONS.md"       links_to "$E/.claude/CLAUDE.md" "$SE/INSTRUCTIONS.md"
check "a tool absent here (hermes) is neither linked nor created" test ! -e "$E/.hermes"
check "...but its folder rides along in the repo"        grep -q 'hermes memory' "$SE/hermes/memories/MEMORY.md"
check "codex absent here: nothing created"               test ! -e "$E/.codex"
check "status here does not claim hermes is linked"      not says 'linked.*hermes' dev "$E" status

# Goose memory is plain text: two devices appending to the same category both survive.
printf 'entry from D\n' >> "$D/.config/goose/memory/dev.txt"
printf 'entry from E\n' >> "$E/.config/goose/memory/dev.txt"
dev "$D" push; dev "$E" push; dev "$D" pull
check "goose *.txt union: D has E's entry"               grep -q 'entry from E' "$D/.config/goose/memory/dev.txt"
check "goose *.txt union: D kept its own entry"          grep -q 'entry from D' "$D/.config/goose/memory/dev.txt"
check "goose *.txt union: E has D's entry"               grep -q 'entry from D' "$E/.config/goose/memory/dev.txt"
check "goose *.txt union: E kept its own entry"          grep -q 'entry from E' "$E/.config/goose/memory/dev.txt"
check "E's push left hermes/ untouched in the repo"      says 'hermes memory' blob "$workdir/remote5.git" HEAD hermes/memories/MEMORY.md

# A Claude project that appears after init is adopted by the next pull/push — silently.
mkdir -p "$D/.claude/projects/-Users-me-later/memory"
printf 'later note\n' > "$D/.claude/projects/-Users-me-later/memory/MEMORY.md"
check "a project appearing later is adopted by pull, silently" no_stdout dev "$D" pull
check "...it is now a link"                              links_to "$D/.claude/projects/-Users-me-later/memory" "$SD/claude/auto-memory/-Users-me-later"
dev "$D" push
check "...and its note reached the remote"               says 'later note' blob "$workdir/remote5.git" HEAD claude/auto-memory/-Users-me-later/MEMORY.md
mkdir -p "$E/.claude/projects/-Users-me-later/memory"
printf 'E extra\n' > "$E/.claude/projects/-Users-me-later/memory/extra.md"
check "push adopts a new project too, silently"          no_stdout dev "$E" push
check "E's project memory is now a link"                 links_to "$E/.claude/projects/-Users-me-later/memory" "$SE/claude/auto-memory/-Users-me-later"
check "E's local-only file was added"                    test -f "$SE/claude/auto-memory/-Users-me-later/extra.md"
check "E sees D's note through the link"                 grep -q 'later note' "$E/.claude/projects/-Users-me-later/memory/MEMORY.md"

# Hermes enforces size caps (MEMORY.md 2200 chars, USER.md 1375 chars); an oversized
# file after a union merge would make Hermes' next write fail, so status must say so.
head -c 2201 /dev/zero | tr '\0' a > "$D/.hermes/memories/MEMORY.md"
check "status warns when hermes MEMORY.md exceeds 2200 chars" says 'MEMORY\.md.*2200|2200.*MEMORY\.md' dev "$D" status
check "...and still exits 0"                             quiet dev "$D" status
head -c 2200 /dev/zero | tr '\0' a > "$D/.hermes/memories/MEMORY.md"
check "no warning at exactly 2200 chars"                 not says '2200' dev "$D" status
head -c 1376 /dev/zero | tr '\0' a > "$D/.hermes/memories/USER.md"
check "status warns when hermes USER.md exceeds 1375 chars" says 'USER\.md.*1375|1375.*USER\.md' dev "$D" status
printf 'hermes memory\n' > "$D/.hermes/memories/MEMORY.md"
printf 'hermes user\n'   > "$D/.hermes/memories/USER.md"
check "no warning once both are back under the caps"    not says '2200|1375' dev "$D" status

echo "── phase 5 / detection: PATH, home dirs, env overrides, STATE_TOOLS ──"
# claude is always active; goose/hermes/codex when their dir exists OR the CLI is on PATH.
mkdir -p "$workdir/fakebin"
for t in goose hermes codex; do printf '#!/bin/sh\nexit 0\n' > "$workdir/fakebin/$t"; chmod +x "$workdir/fakebin/$t"; done
P="$workdir/homeP"; mkdir -p "$P/.claude"
check "CLIs on PATH, no dirs: init exits 0"              quiet dev "$P" PATH="$workdir/fakebin:$CLEAN_PATH" init
check "goose on PATH: ~/.config/goose/memory linked"     links_to "$P/.config/goose/memory" "$P/.agent-state/goose/memory"
check "goose on PATH: .goosehints linked"                links_to "$P/.config/goose/.goosehints" "$P/.agent-state/INSTRUCTIONS.md"
check "hermes on PATH: ~/.hermes/memories linked"        links_to "$P/.hermes/memories" "$P/.agent-state/hermes/memories"
check "codex on PATH: ~/.codex/AGENTS.md linked"         links_to "$P/.codex/AGENTS.md" "$P/.agent-state/INSTRUCTIONS.md"
check "codex on PATH: still no memory sync"              test ! -L "$P/.codex/memories"
check "nothing detected (device N): no goose/hermes/codex dirs were created" \
  bash -c "[[ ! -e '$N/.config/goose' && ! -e '$N/.hermes' && ! -e '$N/.codex' ]]"
# Native paths honour the tools' own env overrides.
Q="$workdir/homeQ"; mkdir -p "$Q/.claude" "$Q/gcfg/memory" "$Q/hh/memories" "$Q/cx"
printf 'q goose\n'       > "$Q/gcfg/memory/q.txt"
printf 'q hermes\n'      > "$Q/hh/memories/MEMORY.md"
printf 'Q codex rules.\n' > "$Q/cx/AGENTS.md"
check "env overrides: init exits 0"                      quiet dev "$Q" GOOSE_CONFIG_DIR="$Q/gcfg" HERMES_HOME="$Q/hh" CODEX_HOME="$Q/cx" init
check "GOOSE_CONFIG_DIR: detected and linked there"      links_to "$Q/gcfg/memory" "$Q/.agent-state/goose/memory"
check "HERMES_HOME: detected and linked there"           links_to "$Q/hh/memories" "$Q/.agent-state/hermes/memories"
check "CODEX_HOME: AGENTS.md linked there"               links_to "$Q/cx/AGENTS.md" "$Q/.agent-state/INSTRUCTIONS.md"
check "...and its text went into INSTRUCTIONS.md"        bash -c "grep -A2 '^## From codex' '$Q/.agent-state/INSTRUCTIONS.md' | grep -q 'Q codex rules'"
check "the default locations were not created"           bash -c "[[ ! -e '$Q/.config/goose' && ! -e '$Q/.hermes' && ! -e '$Q/.codex' ]]"
Q2="$workdir/homeQ2"; mkdir -p "$Q2/cc/agent-memory/a"
printf 'cc memory\n' > "$Q2/cc/agent-memory/a/MEMORY.md"
check "CLAUDE_CONFIG_DIR: init exits 0"                  quiet dev "$Q2" CLAUDE_CONFIG_DIR="$Q2/cc" init
check "CLAUDE_CONFIG_DIR: agent-memory linked there"     links_to "$Q2/cc/agent-memory" "$Q2/.agent-state/claude/agent-memory"
check "CLAUDE_CONFIG_DIR: ~/.claude not created"         test ! -e "$Q2/.claude"
# STATE_TOOLS in the file overrides detection; auto memory can be switched off.
F="$workdir/homeF"; CONF_F="$F/.config/agent-recipes/state.conf"
mkdir -p "$F/.claude/projects/-p/memory" "$F/.config/goose/memory" "$F/.hermes/memories"
printf 'f auto\n' > "$F/.claude/projects/-p/memory/MEMORY.md"
check "config tools= with a space exits 0"               quiet dev "$F" config tools="claude goose" auto_memory=no
check "...and sources back as one value"                 bash -c ". '$CONF_F' && [[ \$STATE_TOOLS == 'claude goose' ]]"
check "STATE_TOOLS: init exits 0"                        quiet dev "$F" init
check "STATE_TOOLS: goose (listed) is linked"            links_to "$F/.config/goose/memory" "$F/.agent-state/goose/memory"
check "STATE_TOOLS: hermes (present, not listed) is untouched" bash -c "[[ -d '$F/.hermes/memories' && ! -L '$F/.hermes/memories' ]]"
check "STATE_TOOLS: nothing under hermes/ in the repo"   not tree_grep "$F/.agent-state" '^hermes/'
check "auto_memory=no: project memory stays a plain dir" bash -c "[[ -d '$F/.claude/projects/-p/memory' && ! -L '$F/.claude/projects/-p/memory' ]]"
check "auto_memory=no: nothing under claude/auto-memory/" not tree_grep "$F/.agent-state" '^claude/auto-memory/'

echo "── phase 5 / off unlinks every tool ──"
check "off exits 0"                                      quiet dev "$D" off
check "off: agent-memory is a plain dir"                 bash -c "[[ -d '$D/.claude/agent-memory' && ! -L '$D/.claude/agent-memory' ]]"
check "off: CLAUDE.md is a plain file with the shared text" bash -c "[[ -f '$D/.claude/CLAUDE.md' && ! -L '$D/.claude/CLAUDE.md' ]] && grep -q 'Goose hints' '$D/.claude/CLAUDE.md'"
check "off: goose memory is a plain dir with both entries" bash -c "[[ -d '$D/.config/goose/memory' && ! -L '$D/.config/goose/memory' ]] && grep -q 'entry from E' '$D/.config/goose/memory/dev.txt'"
check "off: .goosehints is a plain file"                 bash -c "[[ -f '$D/.config/goose/.goosehints' && ! -L '$D/.config/goose/.goosehints' ]]"
check "off: hermes memories is a plain dir"              bash -c "[[ -d '$D/.hermes/memories' && ! -L '$D/.hermes/memories' ]] && grep -q 'hermes user' '$D/.hermes/memories/USER.md'"
check "off: codex AGENTS.md is a plain file"             bash -c "[[ -f '$D/.codex/AGENTS.md' && ! -L '$D/.codex/AGENTS.md' ]] && grep -q 'Codex rules' '$D/.codex/AGENTS.md'"
check "off: codex memories untouched"                    grep -q 'codex memory' "$D/.codex/memories/MEMORY.md"
check "off: auto-memory dirs are plain dirs with their notes" \
  bash -c "[[ -d '$D/.claude/projects/-Users-me-proj/memory' && ! -L '$D/.claude/projects/-Users-me-proj/memory' && ! -L '$D/.claude/projects/-Users-me-later/memory' ]] && grep -q 'auto note' '$D/.claude/projects/-Users-me-proj/memory/MEMORY.md'"
check "off: no symlink into the store is left behind"    bash -c "! find '$D/.claude' '$D/.config/goose' '$D/.hermes' '$D/.codex' -type l | grep -q ."
check "off: the repo is kept"                            test -d "$SD/.git"
check "off: status reports OFF"                          says 'state sync: OFF' dev "$D" status

echo "── /sync-state command ──"
CMD="${REPO}/claude/commands/sync-state.md"
check "/sync-state runs the script via CLAUDE_PLUGIN_ROOT" \
  grep -qF 'bash "${CLAUDE_PLUGIN_ROOT}/scripts/state-sync.sh" $ARGUMENTS' "$CMD"
check "/sync-state tells the user the repo must be private" grep -qi "private" "$CMD"
check "/sync-state documents the config subcommand"         grep -qw "config" "$CMD"
check "sync directory is not a plugin option" \
  bash -c "! grep -q 'CLAUDE_PLUGIN_OPTION' '$SYNC' && ! grep -q 'sync_dir' '${REPO}/claude/.claude-plugin/plugin.json'"

echo "── wiring: hooks.json, plugin version ──"
check "plugin.json version is 0.6.0" \
  python3 -c "import json,sys; sys.exit(0 if json.load(open('${REPO}/claude/.claude-plugin/plugin.json'))['version'] == '0.6.0' else 1)"
check "SessionStart pulls (synchronous), SessionEnd pushes" \
  python3 - "${REPO}/claude/hooks/hooks.json" <<'PY'
import json,sys
h=json.load(open(sys.argv[1]))["hooks"]
(start,)=h["SessionStart"]; (pull,)=start["hooks"]
# not on clear/compact: nothing new can have arrived mid-session
assert start["matcher"]=="startup|resume", start
assert pull["command"]=="bash" and pull["args"]==["${CLAUDE_PLUGIN_ROOT}/scripts/state-sync.sh","pull"], pull
# synchronous: its stdout (the CLAUDE.md notice) must reach the session's context
assert not pull.get("async") and 0 < pull["timeout"] <= 30, pull
(end,)=h["SessionEnd"]; (push,)=end["hooks"]
assert push["args"]==["${CLAUDE_PLUGIN_ROOT}/scripts/state-sync.sh","push"], push
assert 0 < push["timeout"] <= 60, push   # SessionEnd hooks are capped at 60 s
PY

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
