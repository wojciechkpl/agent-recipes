#!/usr/bin/env bash
# Contract test for cross-device state sync (claude/scripts/state-sync.sh).
#
# Simulates two devices (two HOME directories) sharing one bare git remote.
#
# Asserts:
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
# Run: tests/test_state_sync.sh   (exit 0 = pass, non-zero = fail)
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYNC="${REPO}/claude/scripts/state-sync.sh"

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
git init -q --bare "$workdir/remote.git"
A="$workdir/homeA"; B="$workdir/homeB"
mkdir -p "$A/.claude/agent-memory/rust-expert" "$B/.claude/agent-memory/bash-expert"

# on <home> <args...> — run state-sync as that "device"
on() {
    local home="$1"; shift
    HOME="$home" STATE_SYNC_FOREGROUND=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
        env -u CLAUDE_CONFIG_DIR -u STATE_SYNC_DIR "$SYNC" "$@"
}
tracked() { git -C "$A/.claude-state" ls-files | grep -qx "$1"; }

echo "── not initialized: hooks are silent no-ops ──"
check "pull exits 0 with no output" bash -c "[[ -z \"\$(HOME='$A' '$SYNC' pull 2>&1)\" ]]"
check "push exits 0 with no output" bash -c "[[ -z \"\$(HOME='$A' '$SYNC' push 2>&1)\" ]]"
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
check "settings.json not tracked"   bash -c "! git -C '$A/.claude-state' ls-files | grep -q settings"
check "remote received the push"    bash -c "git -C '$workdir/remote.git' log --oneline | grep -q 'sync('"

echo "── device B: init merges, loses nothing ──"
printf 'quote every expansion\n' > "$B/.claude/agent-memory/bash-expert/MEMORY.md"
on "$B" init "$workdir/remote.git" >/dev/null
check "B got A's memory"            grep -q thiserror "$B/.claude/agent-memory/rust-expert/MEMORY.md"
check "B kept its own memory"       grep -q "quote every" "$B/.claude/agent-memory/bash-expert/MEMORY.md"
check "B got A's CLAUDE.md"         grep -q tersely "$B/.claude/CLAUDE.md"
check "B's old copy was backed up"  bash -c "ls '$B/.claude/.state-sync-backup'/*/agent-memory/bash-expert/MEMORY.md >/dev/null"

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
for dev in "$A" "$B"; do
    check "$(basename "$dev") has A's line" grep -q "line from A" "$dev/.claude/agent-memory/rust-expert/MEMORY.md"
    check "$(basename "$dev") has B's line" grep -q "line from B" "$dev/.claude/agent-memory/rust-expert/MEMORY.md"
done
check "no rebase left in progress"  bash -c "[[ ! -d '$B/.claude-state/.git/rebase-merge' && ! -d '$B/.claude-state/.git/rebase-apply' ]]"

echo "── pull announces a changed CLAUDE.md, and only that ──"
# Claude Code loads the user CLAUDE.md before SessionStart hooks finish, so a pull
# that changes it must say so on stdout (which SessionStart adds to the context).
printf 'New rule from A.\n' >> "$A/.claude/CLAUDE.md"
on "$A" push
on "$B" pull >"$workdir/pull.out"
check "B's CLAUDE.md has A's new rule"        grep -q "New rule from A" "$B/.claude/CLAUDE.md"
check "pull printed exactly one line"         test "$(wc -l < "$workdir/pull.out" | tr -d ' ')" -eq 1
check "the line names CLAUDE.md"              grep -q "CLAUDE.md was updated" "$workdir/pull.out"
check "a second pull is silent"               bash -c "[[ -z \"\$(HOME='$B' STATE_SYNC_FOREGROUND=1 '$SYNC' pull 2>/dev/null)\" ]]"
printf 'Rule written on B itself.\n' >> "$B/.claude/CLAUDE.md"
check "a LOCAL CLAUDE.md edit is not announced" bash -c "[[ -z \"\$(HOME='$B' STATE_SYNC_FOREGROUND=1 '$SYNC' pull 2>/dev/null)\" ]]"
on "$B" push; on "$A" pull >/dev/null
printf 'memory-only change\n' >> "$A/.claude/agent-memory/rust-expert/MEMORY.md"
on "$A" push
check "a memory-only pull is silent"          bash -c "[[ -z \"\$(HOME='$B' STATE_SYNC_FOREGROUND=1 '$SYNC' pull 2>/dev/null)\" ]]"
check "…and still delivered the memory"       grep -q "memory-only change" "$B/.claude/agent-memory/rust-expert/MEMORY.md"

echo "── offline: nothing breaks, nothing is lost ──"
real_remote="$(git -C "$A/.claude-state" remote get-url origin)"
git -C "$A/.claude-state" remote set-url origin "$workdir/unreachable.git"
printf 'written while offline\n' >> "$A/.claude/agent-memory/rust-expert/MEMORY.md"
check "offline pull exits 0 and is silent"    bash -c "[[ -z \"\$(HOME='$A' STATE_SYNC_FOREGROUND=1 '$SYNC' pull 2>&1)\" ]]"
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
on "$B" pull
check "pull aborted the half-done rebase"     bash -c "[[ ! -d '$B/.claude-state/.git/rebase-merge' && ! -d '$B/.claude-state/.git/rebase-apply' ]]"
check "B's edit survived"                     grep -q "B2" "$B/.claude/agent-memory/rust-expert/data.json"
touch -t 202001010000 "$A/.claude-state/.git/index.lock"
printf 'after a stale lock\n' >> "$A/.claude/agent-memory/rust-expert/MEMORY.md"
on "$A" push
check "a stale index.lock is cleared"         test ! -e "$A/.claude-state/.git/index.lock"
check "…and the edit was committed"           bash -c "git -C '$A/.claude-state' show HEAD:agent-memory/rust-expert/MEMORY.md | grep -q 'after a stale lock'"
touch "$A/.claude-state/.git/index.lock"
check "a fresh lock is left alone, push exits 0" bash -c "HOME='$A' STATE_SYNC_FOREGROUND=1 '$SYNC' push 2>/dev/null; rc=\$?; [[ \$rc -eq 0 && -e '$A/.claude-state/.git/index.lock' ]]"
rm -f "$A/.claude-state/.git/index.lock"
on "$A" push; on "$B" pull; on "$B" push; on "$A" pull

echo "── hooks stay silent on stdout ──"
check "pull prints nothing on stdout" bash -c "[[ -z \"\$(HOME='$A' STATE_SYNC_FOREGROUND=1 '$SYNC' pull 2>/dev/null)\" ]]"
check "push prints nothing on stdout" bash -c "[[ -z \"\$(HOME='$A' STATE_SYNC_FOREGROUND=1 '$SYNC' push 2>/dev/null)\" ]]"

echo "── secrets are held back ──"
printf 'note\n-----BEGIN OPENSSH PRIVATE KEY-----\nabc\n' > "$A/.claude/agent-memory/rust-expert/leak.md"
printf 'token ghp_%s\n' "$(printf 'a%.0s' $(seq 36))" > "$A/.claude/agent-memory/rust-expert/tok.md"
printf 'harmless\n' > "$A/.claude/agent-memory/rust-expert/ok.md"
on "$A" push 2>/dev/null
check "private-key content not committed" bash -c "! git -C '$A/.claude-state' ls-files | grep -q leak.md"
check "token-shaped content not committed" bash -c "! git -C '$A/.claude-state' ls-files | grep -q tok.md"
check "ordinary file still committed"     tracked agent-memory/rust-expert/ok.md
check "hold-back is logged"               grep -q "HELD BACK" "$A/.claude-state/.sync.log"
check "the log itself is not tracked"     bash -c "! git -C '$A/.claude-state' ls-files | grep -q sync.log"
printf 'API_KEY=x\n' > "$A/.claude/agent-memory/rust-expert/.env"
printf 'where the team keeps logins\n' > "$A/.claude/agent-memory/rust-expert/notes-credentials.md"
on "$A" push 2>/dev/null
on "$A" push 2>/dev/null
check "secret-NAMED files are not committed" bash -c "! git -C '$A/.claude-state' ls-files | grep -qE '/\.env$|credentials'"
check "a name-based hold-back is logged"     grep -q "HELD BACK.*notes-credentials.md" "$A/.claude-state/.sync.log"
check "each held-back file is logged once"   test "$(grep -c 'HELD BACK.*notes-credentials.md' "$A/.claude-state/.sync.log")" -eq 1
check "status lists what is held back"       bash -c "HOME='$A' '$SYNC' status | grep -q 'notes-credentials.md'"

echo "── status / off ──"
check "status reports ON"           bash -c "HOME='$A' '$SYNC' status | grep -q 'state sync: ON'"
on "$A" off >/dev/null
check "off: agent-memory is a real dir" bash -c "[[ -d '$A/.claude/agent-memory' && ! -L '$A/.claude/agent-memory' ]]"
check "off: content preserved"      grep -q nextest "$A/.claude/agent-memory/rust-expert/MEMORY.md"
check "off: repo left in place"     test -d "$A/.claude-state/.git"
check "off: status reports OFF"     bash -c "HOME='$A' '$SYNC' status | grep -q 'state sync: OFF'"
head_before="$(git -C "$A/.claude-state" rev-parse HEAD)"
printf 'written while sync is off\n' > "$A/.claude/agent-memory/rust-expert/while-off.md"
printf 'stray edit inside the repo\n' >> "$A/.claude-state/CLAUDE.md"
check "off: pull is a silent no-op" bash -c "[[ -z \"\$(HOME='$A' STATE_SYNC_FOREGROUND=1 '$SYNC' pull 2>&1)\" ]]"
check "off: push is a silent no-op" bash -c "[[ -z \"\$(HOME='$A' STATE_SYNC_FOREGROUND=1 '$SYNC' push 2>&1)\" ]]"
check "off: hooks committed nothing" test "$(git -C "$A/.claude-state" rev-parse HEAD)" = "$head_before"
git -C "$A/.claude-state" checkout -q -- CLAUDE.md
check "init with a different remote is refused" bash -c "! HOME='$A' '$SYNC' init '$workdir/other.git' >/dev/null 2>&1"
on "$A" init "$real_remote" >/dev/null
check "init again: status reports ON"   bash -c "HOME='$A' '$SYNC' status | grep -q 'state sync: ON'"
check "init again: relinked"            test -L "$A/.claude/agent-memory"
check "init again: file written while off is now synced" tracked agent-memory/rust-expert/while-off.md

echo "── /sync-state command ──"
CMD="${REPO}/claude/commands/sync-state.md"
check "/sync-state runs the script via CLAUDE_PLUGIN_ROOT" \
  grep -qF 'bash "${CLAUDE_PLUGIN_ROOT}/scripts/state-sync.sh" $ARGUMENTS' "$CMD"
check "/sync-state tells the user the repo must be private" grep -qi "private" "$CMD"
check "sync directory is not a plugin option" \
  bash -c "! grep -q 'CLAUDE_PLUGIN_OPTION' '$SYNC' && ! grep -q 'sync_dir' '${REPO}/claude/.claude-plugin/plugin.json'"

echo "── wiring: hooks.json ──"
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
