#!/usr/bin/env bash
# Toggle Claude Code "autonomous mode" — OPTIONAL, reversible, global or per-project.
#
# Merges settings.autonomous.json into the target settings.json, preserving your other
# keys (model, statusLine, plugins, ...):
#   * defaultMode:acceptEdits
#   * a broad dev-toolchain allow-list
#   * a safety deny-list
#   * the profile's other top-level keys (autoUpdatesChannel, verbose, ...) — profile
#     value wins, also on re-sync; `off` without a backup drops the ones still
#     equal to the profile value
#   * a PreToolUse guard hook (claude/hooks/guard.sh) — the REAL safety net: it inspects
#     the actual command and blocks secret-exfil / catastrophic deletes / force-push /
#     RCE-pipes that brittle string-prefix deny patterns cannot reliably catch.
#     guard.sh is a fast pre-filter that skips the ~16 ms Python start for the ~90%
#     of calls that cannot trip any rule; guard.py remains the decision authority.
# `off` restores the exact pre-autonomous settings from a one-time backup.
#
# Usage:
#   claude/autonomous-mode.sh on              # GLOBAL: ~/.claude/settings.json (all projects)
#   claude/autonomous-mode.sh on --project    # PROJECT: ./.claude/settings.json (cwd only)
#   claude/autonomous-mode.sh off [--project]
#   claude/autonomous-mode.sh status [--project]
#   ... --plugin   (used by the /autonomous-mode plugin command) merge permissions only;
#                  the guard is the plugin's own hooks/hooks.json entry, so no hook is
#                  written to settings.json and a legacy absolute-path entry is removed.
#
# Re-running `on` re-syncs the profile (picks up edits to allow/deny/hooks) WITHOUT
# clobbering the pre-autonomous backup. Note: without --plugin the guard hook is
# referenced by ABSOLUTE path — keep this repo where it is, or re-run `on` after
# moving it.
#
# Per-session alternative (no files): `claude --permission-mode acceptEdits`
# (or the stronger `claude --dangerously-skip-permissions`). In-session: Shift+Tab cycles modes.
#
# Takes effect on the NEXT Claude Code session (settings load at start).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE="$HERE/settings.autonomous.json"
GUARD="$HERE/hooks/guard.sh"

USAGE="Usage: $0 {on|off|status} [--project] [--plugin]"
ACTION="status"
SCOPE="global"
PLUGIN=0   # --plugin: the guard comes from the plugin's hooks/hooks.json, not settings.json
for arg in "$@"; do
  case "$arg" in
    on|off|status) ACTION="$arg" ;;
    --project|-p)  SCOPE="project" ;;
    --plugin)      PLUGIN=1 ;;
    *)             echo "$USAGE"; exit 2 ;;
  esac
done

if [[ "$SCOPE" == "project" ]]; then DIR="$(pwd)/.claude"; else DIR="$HOME/.claude"; fi
SETTINGS="$DIR/settings.json"
BACKUP="$DIR/settings.pre-autonomous.json"
mkdir -p "$DIR"

is_on() {
  [[ -f "$SETTINGS" ]] && python3 - "$SETTINGS" <<'EOF' 2>/dev/null
import json,sys
d=json.load(open(sys.argv[1]))
sys.exit(0 if d.get("permissions",{}).get("defaultMode")=="acceptEdits" else 1)
EOF
}

# An autonomous state `on` produced: acceptEdits AND a trace of our profile — either
# our guard hook (guard.sh or legacy guard.py; settings.json installs) or the
# profile's complete allow-list (plugin installs write no hook, so the merged
# allow-list is the only fingerprint). acceptEdits alone can be the user's own
# pre-autonomous setup and must not count.
is_autonomous() {
  is_on && python3 - "$SETTINGS" "$PROFILE" <<'EOF' 2>/dev/null
import json,sys
d=json.load(open(sys.argv[1]))
if "hooks/guard." in json.dumps(d.get("hooks",{})): sys.exit(0)
try:
    allow=set(json.load(open(sys.argv[2]))["permissions"]["allow"])
except Exception:
    sys.exit(1)
sys.exit(0 if allow and allow<=set(d.get("permissions",{}).get("allow",[])) else 1)
EOF
}

case "$ACTION" in
  on)
    [[ -f "$PROFILE" ]] || { echo "❌ Missing $PROFILE"; exit 1; }
    [[ -f "$GUARD" ]]   || { echo "❌ Missing guard hook: $GUARD"; exit 1; }
    if is_on; then
      echo "🔄 Autonomous mode already ON ($SCOPE) — re-syncing profile (allow/deny/hooks/keys)."
    fi
    # Back up whenever no backup exists — even if already "on" (e.g. the user set
    # acceptEdits themselves) — so the keys the merge overwrites stay recoverable.
    # Never snapshot an autonomous state (e.g. re-running `on` after the backup was
    # lost): `off` restoring it would leave autonomous mode on.
    if [[ -f "$SETTINGS" && ! -f "$BACKUP" ]] && ! is_autonomous; then
      cp "$SETTINGS" "$BACKUP" && echo "📦 Backed up → $BACKUP"
    fi
    python3 - "$SETTINGS" "$PROFILE" "$GUARD" "$PLUGIN" <<'EOF'
import json,os,sys
sp,pp,guard,plugin=sys.argv[1],sys.argv[2],sys.argv[3],sys.argv[4]=="1"
base=json.load(open(sp)) if os.path.exists(sp) else {}
prof=json.load(open(pp))
p=prof["permissions"]
perm=base.setdefault("permissions",{})
perm["defaultMode"]=p["defaultMode"]
perm["allow"]=sorted(set(perm.get("allow",[]))|set(p["allow"]))
perm["deny"]=sorted(set(perm.get("deny",[]))|set(p.get("deny",[])))
# Every other top-level profile key (skip "//" doc keys): profile value wins.
for k,v in prof.items():
    if k not in ("permissions","hooks") and not k.startswith("//"):
        base[k]=v
# Merge hooks, substituting the guard placeholder with its absolute path.
# Idempotent: drop any prior guard entry for the same matcher before re-adding.
# Matches "hooks/guard." so it also recognises pre-guard.sh installs that still
# point straight at guard.py — those get upgraded in place, not duplicated.
GUARD_MARK="hooks/guard."
for event,entries in prof.get("hooks",{}).items():
    cur=base.setdefault("hooks",{}).setdefault(event,[])
    for entry in entries:
        e=json.loads(json.dumps(entry).replace("__GUARD__",guard))
        cur[:]=[c for c in cur if not (c.get("matcher")==e.get("matcher") and GUARD_MARK in json.dumps(c))]
        # --plugin: the plugin's hooks/hooks.json already runs the guard, and the
        # plugin root moves on every update, so an absolute path here would go stale.
        # Any legacy entry was just removed above; add nothing.
        if not plugin:
            cur.append(e)
    if not cur: del base["hooks"][event]
if "hooks" in base and not base["hooks"]: del base["hooks"]
json.dump(base,open(sp,"w"),indent=2)
print(f"merged autonomous profile ({'guard: plugin hook' if plugin else '+guard hook'}) into {sp}")
EOF
    echo "🟢 Autonomous mode ON ($SCOPE). Restart Claude Code to apply."
    if [[ "$PLUGIN" == 1 ]]; then
      echo "🛡  Guard: provided by the agent-recipes plugin (option guard_mode, default auto)."
      echo "   Run '/autonomous-mode off' BEFORE disabling or uninstalling the plugin."
    fi
    ;;
  off)
    if ! is_on; then echo "⚪ Autonomous mode already OFF ($SCOPE)."; exit 0; fi
    restored=0
    if [[ -f "$BACKUP" ]]; then
      mv "$BACKUP" "$SETTINGS"; restored=1
      echo "🔵 Restored pre-autonomous settings ($SCOPE). Restart to apply."
    fi
    # No backup — or a backup that was itself taken while autonomous (older
    # versions of this script did that) — so strip surgically.
    if [[ "$restored" == 0 ]] || is_autonomous; then
      python3 - "$SETTINGS" "$PROFILE" <<'EOF'
import json,sys
d=json.load(open(sys.argv[1]))
try:
    prof=json.load(open(sys.argv[2]))
except (OSError,ValueError):
    prof={}  # missing/broken profile: still turn autonomous mode off
d.get("permissions",{}).pop("defaultMode",None)
# Drop top-level keys `on` set, unless the user has since changed their value.
for k,v in prof.items():
    if k not in ("permissions","hooks") and not k.startswith("//") and d.get(k,object())==v:
        del d[k]
# Strip our guard hook; drop now-empty hook events / the hooks key entirely.
# "hooks/guard." covers both the guard.sh entrypoint and older guard.py installs.
hk=d.get("hooks",{})
for event in list(hk):
    hk[event]=[c for c in hk[event] if "hooks/guard." not in json.dumps(c)]
    if not hk[event]: del hk[event]
if "hooks" in d and not d["hooks"]: del d["hooks"]
json.dump(d,open(sys.argv[1],"w"),indent=2)
EOF
      echo "🔵 Cleared defaultMode + guard hook ($SCOPE; no backup to restore). Restart to apply."
    fi
    ;;
  status)
    if is_on; then echo "🟢 Autonomous mode is ON ($SCOPE: $SETTINGS)"; else echo "⚪ Autonomous mode is OFF ($SCOPE)"; fi
    if [[ "$PLUGIN" == 1 ]]; then
      # The /autonomous-mode command passes the option itself (Bash-tool commands get
      # no plugin options); an option the user never set arrives as the placeholder.
      mode="${CLAUDE_PLUGIN_OPTION_GUARD_MODE:-}"
      [[ -z "$mode" || "$mode" == '${user_config.'* ]] && mode="auto (default)"
      echo "🛡  Guard: agent-recipes plugin hook, guard_mode=$mode"
    fi
    ;;
esac
