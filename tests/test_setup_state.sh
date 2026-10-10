#!/usr/bin/env bash
# Contract test for the state-sync part of setup.sh (phase 5, Track D).
#
# HOME is redirected to a temporary directory before anything runs: setup.sh must never
# touch the real home, and every path below lives under $workdir. setup.sh and
# state-sync.sh run on a sanitized PATH (git + python3 only) with no agent CLI on it and
# no CLAUDE_CONFIG_DIR / GOOSE_CONFIG_DIR / HERMES_HOME / CODEX_HOME / STATE_SYNC_DIR
# inherited, so tool detection sees only what a test creates.
#
# Interactive prompts. setup.sh decides "interactive" with [[ -t 0 ]]. The environment
# variable AGENT_RECIPES_ASSUME_TTY=1 bypasses that test — setup.sh then treats stdin as
# a terminal and reads the answers from it — so this test can pipe answers in. It is a
# test hook, never documented for users. Without it, a pipe or /dev/null on stdin is
# non-interactive: nothing is asked and nothing is read.
#
# Prompt order with --state on a terminal: store directory, remote URL, one y/n per
# DETECTED tool except claude (claude is always on; detection order goose, hermes,
# codex), then auto memory y/n. Enter takes the default.
#
# Asserts:
#   1. --help lists the state flags
#   2. --state, non-interactive: defaults (dir ~/.agent-state, no remote = local-only,
#      detected tools, auto memory yes), state.conf written, init run, nothing read
#      from stdin; --state alone installs no agents
#   3. --state --dry-run writes nothing and prints the config and the items
#   4. --state-dir / --state-remote / --state-tools override the defaults
#   5. interactive: answers are read from stdin in the documented order; Enter = default
#   6. --all implies --state; --no-state turns it off
#   7. --uninstall runs `off` (links become plain copies, repo kept) and removes
#      state.conf; --uninstall --dry-run changes nothing; no state at all is fine
#  Review findings (numbered as in the review):
#  R1. an interactive "~/store" answer is stored absolute and the store created there
#  R2. --uninstall on a phase-4 device (~/.claude-state, no state.conf) restores
#      plain copies and leaves the store
#  R5. a re-run of --state keeps the STATE_DIR / STATE_TOOLS / STATE_REMOTE already
#      in state.conf (non-interactive, and interactive with Enter everywhere)
#
# Run: tests/test_setup_state.sh   (exit 0 = pass, non-zero = fail)
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETUP="${REPO}/setup.sh"
SYNC="${REPO}/claude/scripts/state-sync.sh"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT
export HOME="$workdir/home-unused"      # belt and braces: nothing below may reach the real home
mkdir -p "$HOME" "$workdir/cwd" "$workdir/bin"
cd "$workdir/cwd"                        # setup.sh --uninstall also looks at ./.claude
ln -s "$(command -v git)"     "$workdir/bin/git"
ln -s "$(command -v python3)" "$workdir/bin/python3"
CLEAN_PATH="$workdir/bin:/usr/bin:/bin"

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

# run_as <script> <home> [VAR=value ...] <args...> — run setup.sh or state-sync.sh as a
# user whose home is <home>, inheriting nothing from the developer's environment.
# stdin is whatever the caller connects.
run_as() {
    local script="$1" home="$2"; shift 2
    local pre=()
    while [[ $# -gt 0 && "$1" == *=* ]]; do pre+=("$1"); shift; done
    HOME="$home" SHELL=/bin/bash STATE_SYNC_FOREGROUND=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 PATH="$CLEAN_PATH" \
        /usr/bin/env -u CLAUDE_CONFIG_DIR -u STATE_SYNC_DIR -u GOOSE_CONFIG_DIR -u HERMES_HOME -u CODEX_HOME \
               -u AGENT_RECIPES_ASSUME_TTY ${pre[@]+"${pre[@]}"} "$script" "$@"
}
setup() { run_as "$SETUP" "$@"; }
state() { run_as "$SYNC"  "$@"; }

quiet()  { "$@" >/dev/null 2>&1; }
not()    { ! "$@"; }
says()   { local pat="$1" out; shift; out="$("$@" 2>/dev/null)" || return 1; grep -qiE -- "$pat" <<<"$out"; }
rp()     { python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1"; }
links_to() { [[ -L "$1" ]] && [[ "$(rp "$1")" == "$(rp "$2")" ]]; }
conf()   { echo "$1/.config/agent-recipes/state.conf"; }
# conf_is <home> <bash test on STATE_* after sourcing state.conf>
conf_is() { bash -c ". '$(conf "$1")' 2>/dev/null && [[ $2 ]]"; }
# has_tool <home> <tool>: STATE_TOOLS (space-separated) lists the tool
has_tool() { conf_is "$1" "\" \$STATE_TOOLS \" == *' $2 '*"; }
# newhome <name>: a home with a CLAUDE.md and one agent memory, no state yet
newhome() {
    local h="$workdir/$1"
    mkdir -p "$h/.claude/agent-memory/x"
    printf 'memory of x\n' > "$h/.claude/agent-memory/x/MEMORY.md"
    printf 'My rules.\n'   > "$h/.claude/CLAUDE.md"
    echo "$h"
}

echo "── help ──"
check "--help lists --state"          says '--state' setup "$HOME" --help
check "--help lists --state-dir"      says '--state-dir' setup "$HOME" --help
check "--help lists --state-remote"   says '--state-remote' setup "$HOME" --help
check "--help lists --state-tools"    says '--state-tools' setup "$HOME" --help
check "--help lists --no-state"       says '--no-state' setup "$HOME" --help

echo "── --state, non-interactive: defaults, nothing read from stdin ──"
H1="$(newhome h1)"; mkdir -p "$H1/.config/goose"
rc=0; printf '%s\n' "$H1/NOT-an-answer" "" n n | setup "$H1" --state >"$workdir/h1.out" 2>&1 || rc=$?
check "exits 0"                                            test "$rc" -eq 0
check "state.conf written"                                 test -f "$(conf "$H1")"
check "STATE_DIR is ~/.agent-state (piped text was NOT read as an answer)" conf_is "$H1" "\$STATE_DIR == '$H1/.agent-state'"
check "STATE_REMOTE is empty (local-only)"                 conf_is "$H1" "-z \${STATE_REMOTE:-}"
check "STATE_TOOLS lists claude"                           has_tool "$H1" claude
check "STATE_TOOLS lists goose (detected: ~/.config/goose)" has_tool "$H1" goose
check "STATE_TOOLS does not list hermes (not present)"     not has_tool "$H1" hermes
check "STATE_TOOLS does not list codex (not present)"      not has_tool "$H1" codex
check "STATE_CLAUDE_AUTO_MEMORY=yes by default"            conf_is "$H1" "\$STATE_CLAUDE_AUTO_MEMORY == yes"
check "init ran: store at ~/.agent-state"                  test -d "$H1/.agent-state/.git"
check "init ran: agent-memory linked"                      links_to "$H1/.claude/agent-memory" "$H1/.agent-state/claude/agent-memory"
check "init ran: CLAUDE.md -> INSTRUCTIONS.md"             links_to "$H1/.claude/CLAUDE.md" "$H1/.agent-state/INSTRUCTIONS.md"
check "init ran: goose memory linked"                      links_to "$H1/.config/goose/memory" "$H1/.agent-state/goose/memory"
check "state-sync status: ON, local-only"                  says 'local-only' state "$H1" status
check "--state alone installs no agents"                   test ! -e "$H1/.claude/agents"

echo "── --state --dry-run: prints, writes nothing ──"
H2="$(newhome h2)"; mkdir -p "$H2/.config/goose"
rc=0; setup "$H2" --state --dry-run </dev/null >"$workdir/h2.out" 2>&1 || rc=$?
check "exits 0"                                            test "$rc" -eq 0
check "no state.conf"                                      test ! -e "$(conf "$H2")"
check "no store"                                           test ! -e "$H2/.agent-state"
check "nothing linked"                                     test ! -L "$H2/.claude/CLAUDE.md"
check "prints STATE_DIR it would write"                    grep -q "STATE_DIR=.*$H2/.agent-state" "$workdir/h2.out"
check "prints STATE_TOOLS with the detected goose"         grep -qE 'STATE_TOOLS=.*goose' "$workdir/h2.out"
check "prints STATE_CLAUDE_AUTO_MEMORY"                    grep -q 'STATE_CLAUDE_AUTO_MEMORY=' "$workdir/h2.out"
check "prints the items it would link: agent-memory"       grep -q 'agent-memory' "$workdir/h2.out"
check "prints the items it would link: CLAUDE.md"          grep -q 'CLAUDE.md' "$workdir/h2.out"
check "prints the items it would link: goose memory"       grep -qE 'goose.*memory' "$workdir/h2.out"

echo "── flags override the defaults ──"
H3="$(newhome h3)"; mkdir -p "$H3/.config/goose"
git init -q --bare "$workdir/remote.git"
rc=0; setup "$H3" --state --state-dir "$H3/custom" --state-remote "$workdir/remote.git" --state-tools claude </dev/null >"$workdir/h3.out" 2>&1 || rc=$?
check "exits 0"                                            test "$rc" -eq 0
check "--state-dir -> STATE_DIR"                           conf_is "$H3" "\$STATE_DIR == '$H3/custom'"
check "--state-remote -> STATE_REMOTE"                     conf_is "$H3" "\$STATE_REMOTE == '$workdir/remote.git'"
check "--state-tools -> STATE_TOOLS"                       conf_is "$H3" "\$STATE_TOOLS == claude"
check "store at the custom dir"                            test -d "$H3/custom/.git"
check "default location untouched"                         test ! -e "$H3/.agent-state"
check "origin is the remote"                               test "$(git -C "$H3/custom" remote get-url origin 2>/dev/null)" = "$workdir/remote.git"
check "first push happened"                                bash -c "git -C '$workdir/remote.git' log --oneline 2>/dev/null | grep -q 'sync('"
check "agent-memory linked into the custom store"          links_to "$H3/.claude/agent-memory" "$H3/custom/claude/agent-memory"
check "goose present but excluded by --state-tools: not linked" test ! -L "$H3/.config/goose/memory"

echo "── review 5: a re-run honours the existing state.conf ──"
# Running ./setup.sh --state again (a new device setup, an upgrade) must start from the
# values already in state.conf, not from the built-in defaults: H3 keeps its custom
# store and its tool list, and no second store appears at ~/.agent-state.
rc=0; setup "$H3" --state </dev/null >"$workdir/h3-rerun.out" 2>&1 || rc=$?
check "non-interactive re-run exits 0"                     test "$rc" -eq 0
check "re-run keeps STATE_DIR from the file"               conf_is "$H3" "\$STATE_DIR == '$H3/custom'"
check "re-run keeps STATE_TOOLS from the file"             conf_is "$H3" "\$STATE_TOOLS == claude"
check "re-run keeps STATE_REMOTE from the file"            conf_is "$H3" "\$STATE_REMOTE == '$workdir/remote.git'"
check "re-run creates no ~/.agent-state"                   test ! -e "$H3/.agent-state"
check "re-run: CLAUDE.md still links into the custom store" links_to "$H3/.claude/CLAUDE.md" "$H3/custom/INSTRUCTIONS.md"
check "re-run: goose still excluded"                       test ! -L "$H3/.config/goose/memory"
rc=0; printf '\n\n\n\n\n\n' | setup "$H3" AGENT_RECIPES_ASSUME_TTY=1 --state >"$workdir/h3-rerun2.out" 2>&1 || rc=$?
check "interactive re-run (Enter everywhere) exits 0"      test "$rc" -eq 0
check "interactive re-run keeps STATE_DIR"                 conf_is "$H3" "\$STATE_DIR == '$H3/custom'"
check "interactive re-run keeps STATE_TOOLS"               conf_is "$H3" "\$STATE_TOOLS == claude"
check "interactive re-run creates no ~/.agent-state"       test ! -e "$H3/.agent-state"
check "interactive re-run: links still point into the custom store" links_to "$H3/.claude/agent-memory" "$H3/custom/claude/agent-memory"

echo "── interactive: answers from stdin (AGENT_RECIPES_ASSUME_TTY=1) ──"
# Detected here: goose and hermes. Answers: dir, remote (empty), goose=y, hermes=n, auto=n.
H4="$(newhome h4)"; mkdir -p "$H4/.config/goose" "$H4/.hermes/memories"
printf 'hermes memory\n' > "$H4/.hermes/memories/MEMORY.md"
rc=0; printf '%s\n' "$H4/istore" "" y n n | setup "$H4" AGENT_RECIPES_ASSUME_TTY=1 --state >"$workdir/h4.out" 2>&1 || rc=$?
check "exits 0"                                            test "$rc" -eq 0
check "a question was asked for hermes"                    grep -qi 'hermes' "$workdir/h4.out"
check "answer 1 -> STATE_DIR"                              conf_is "$H4" "\$STATE_DIR == '$H4/istore'"
check "answer 2 (empty) -> no remote"                      conf_is "$H4" "-z \${STATE_REMOTE:-}"
check "answer 3 (y) -> goose listed"                       has_tool "$H4" goose
check "answer 4 (n) -> hermes not listed"                  not has_tool "$H4" hermes
check "claude is always listed"                            has_tool "$H4" claude
check "answer 5 (n) -> auto memory off"                    conf_is "$H4" "\$STATE_CLAUDE_AUTO_MEMORY == no"
check "init used the answers: store at istore"             test -d "$H4/istore/.git"
check "goose linked"                                       links_to "$H4/.config/goose/memory" "$H4/istore/goose/memory"
check "hermes left alone"                                  bash -c "[[ -d '$H4/.hermes/memories' && ! -L '$H4/.hermes/memories' ]]"
# Enter on every prompt keeps the defaults.
H5="$(newhome h5)"; mkdir -p "$H5/.config/goose"
rc=0; printf '\n\n\n\n\n\n' | setup "$H5" AGENT_RECIPES_ASSUME_TTY=1 --state >"$workdir/h5.out" 2>&1 || rc=$?
check "Enter everywhere: exits 0"                          test "$rc" -eq 0
check "Enter keeps the default dir"                        conf_is "$H5" "\$STATE_DIR == '$H5/.agent-state'"
check "Enter keeps no remote"                              conf_is "$H5" "-z \${STATE_REMOTE:-}"
check "Enter keeps auto memory on"                         conf_is "$H5" "\$STATE_CLAUDE_AUTO_MEMORY == yes"
check "claude listed"                                      has_tool "$H5" claude
check "store initialised at the default"                   test -d "$H5/.agent-state/.git"
# A flag given on a terminal wins (whether the prompt is skipped or pre-filled with it).
H6="$(newhome h6)"
rc=0; printf '\n\n\n\n\n\n' | setup "$H6" AGENT_RECIPES_ASSUME_TTY=1 --state --state-dir "$H6/flagged" >"$workdir/h6.out" 2>&1 || rc=$?
check "--state-dir on a terminal: exits 0"                 test "$rc" -eq 0
check "--state-dir on a terminal sets STATE_DIR"           conf_is "$H6" "\$STATE_DIR == '$H6/flagged'"
check "...and the store is there"                          test -d "$H6/flagged/.git"

echo "── --all implies --state; --no-state turns it off ──"
H7="$(newhome h7)"
rc=0; setup "$H7" --all </dev/null >"$workdir/h7.out" 2>&1 || rc=$?
check "--all exits 0"                                      test "$rc" -eq 0
check "--all wrote state.conf"                             test -f "$(conf "$H7")"
check "--all initialised the store"                        test -d "$H7/.agent-state/.git"
check "--all still installs agents"                        test -f "$H7/.claude/agents/code-reviewer.md"
H8="$(newhome h8)"
rc=0; setup "$H8" --all --no-state </dev/null >"$workdir/h8.out" 2>&1 || rc=$?
check "--all --no-state exits 0"                           test "$rc" -eq 0
check "--all --no-state: no state.conf"                    test ! -e "$(conf "$H8")"
check "--all --no-state: no store"                         test ! -e "$H8/.agent-state"
check "--all --no-state: CLAUDE.md untouched"              test ! -L "$H8/.claude/CLAUDE.md"
check "--all --no-state: agents still installed"           test -f "$H8/.claude/agents/code-reviewer.md"

echo "── --uninstall: off + remove state.conf ──"
# H3 has a custom STATE_DIR: uninstall must read state.conf to find the repo BEFORE
# deleting the file.
rc=0; setup "$H3" --uninstall --dry-run </dev/null >"$workdir/h3-dry.out" 2>&1 || rc=$?
check "uninstall --dry-run exits 0"                        test "$rc" -eq 0
check "uninstall --dry-run keeps state.conf"               test -f "$(conf "$H3")"
check "uninstall --dry-run keeps the links"                test -L "$H3/.claude/CLAUDE.md"
rc=0; setup "$H3" --uninstall </dev/null >"$workdir/h3-un.out" 2>&1 || rc=$?
check "uninstall exits 0"                                  test "$rc" -eq 0
check "uninstall: agent-memory is a plain dir again"       bash -c "[[ -d '$H3/.claude/agent-memory' && ! -L '$H3/.claude/agent-memory' ]]"
check "uninstall: memory content preserved"                grep -q 'memory of x' "$H3/.claude/agent-memory/x/MEMORY.md"
check "uninstall: CLAUDE.md is a plain file with its text" bash -c "[[ -f '$H3/.claude/CLAUDE.md' && ! -L '$H3/.claude/CLAUDE.md' ]] && grep -q 'My rules' '$H3/.claude/CLAUDE.md'"
check "uninstall: the repo is kept at the custom dir"      test -d "$H3/custom/.git"
check "uninstall: state.conf removed"                      test ! -e "$(conf "$H3")"
check "uninstall: state-sync status reports OFF"           says 'state sync: OFF' state "$H3" status
H9="$(newhome h9)"
rc=0; setup "$H9" --uninstall </dev/null >"$workdir/h9.out" 2>&1 || rc=$?
check "uninstall with no state at all exits 0"             test "$rc" -eq 0
check "...and touched nothing"                             bash -c "[[ -f '$H9/.claude/CLAUDE.md' && ! -L '$H9/.claude/CLAUDE.md' && ! -e '$H9/.agent-state' ]]"

echo "── review 1: a '~/store' answer becomes an absolute STATE_DIR ──"
# No tool detected here, so the prompts are: dir, remote, auto memory.
H10="$(newhome h10)"
tilde='~'   # the answer is the literal, unexpanded "~/store" — exactly what a user types at the prompt
rc=0; printf '%s\n' "$tilde/store" '' '' | setup "$H10" AGENT_RECIPES_ASSUME_TTY=1 --state >"$workdir/h10.out" 2>&1 || rc=$?
check "exits 0"                                            test "$rc" -eq 0
check "STATE_DIR is \$HOME/store (tilde expanded)"         conf_is "$H10" "\$STATE_DIR == '$H10/store'"
check "the store was created there"                        test -d "$H10/store/.git"
check "no directory literally named '~' was created"       test ! -e "$workdir/cwd/~"
check "the CLAUDE.md link target is absolute"              bash -c "[[ \$(readlink '$H10/.claude/CLAUDE.md') == /* ]]"
check "...and resolves"                                    grep -q 'My rules' "$H10/.claude/CLAUDE.md"

echo "── review 2: --uninstall on a phase-4 device with no state.conf ──"
# ~/.claude-state (old layout) with links into it and no state.conf: uninstall must
# still restore plain copies, and leave the store alone.
H11="$workdir/h11"; mkdir -p "$H11/.claude" "$H11/.claude-state/agent-memory/a"
printf 'legacy memory\n' > "$H11/.claude-state/agent-memory/a/MEMORY.md"
printf 'Legacy rules.\n'  > "$H11/.claude-state/CLAUDE.md"
git -C "$H11/.claude-state" init -q
git -C "$H11/.claude-state" add -A
git -C "$H11/.claude-state" -c user.name=t -c user.email=t@t commit -q -m "phase 4 state"
ln -s "$H11/.claude-state/agent-memory" "$H11/.claude/agent-memory"
ln -s "$H11/.claude-state/CLAUDE.md"    "$H11/.claude/CLAUDE.md"
rc=0; setup "$H11" --uninstall </dev/null >"$workdir/h11.out" 2>&1 || rc=$?
check "uninstall on a legacy device exits 0"               test "$rc" -eq 0
check "CLAUDE.md is a plain file with its text"            bash -c "[[ -f '$H11/.claude/CLAUDE.md' && ! -L '$H11/.claude/CLAUDE.md' ]] && grep -q 'Legacy rules' '$H11/.claude/CLAUDE.md'"
check "agent-memory is a plain dir with its content"       bash -c "[[ -d '$H11/.claude/agent-memory' && ! -L '$H11/.claude/agent-memory' ]] && grep -q 'legacy memory' '$H11/.claude/agent-memory/a/MEMORY.md'"
check "the legacy store is left in place"                  test -d "$H11/.claude-state/.git"
check "no ~/.agent-state was created"                      test ! -e "$H11/.agent-state"

echo "── nothing reached the (redirected) real home ──"
check "the test's HOME stayed empty"                       test -z "$(ls -A "$HOME" 2>/dev/null)"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
