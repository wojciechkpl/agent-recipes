#!/usr/bin/env bash
# Toggle Claude Code "autonomous mode" — OPTIONAL, reversible, global or per-project.
#
# Merges settings.autonomous.json into the target settings.json, preserving your other
# keys (model, statusLine, plugins, ...):
#   * defaultMode:acceptEdits
#   * a broad dev-toolchain allow-list
#   * a safety deny-list
#   * a PreToolUse guard hook (claude/hooks/guard.py) — the REAL safety net: it inspects
#     the actual command and blocks secret-exfil / catastrophic deletes / force-push /
#     RCE-pipes that brittle string-prefix deny patterns cannot reliably catch.
# `off` restores the exact pre-autonomous settings from a one-time backup.
#
# Usage:
#   claude/autonomous-mode.sh on              # GLOBAL: ~/.claude/settings.json (all projects)
#   claude/autonomous-mode.sh on --project    # PROJECT: ./.claude/settings.json (cwd only)
#   claude/autonomous-mode.sh off [--project]
#   claude/autonomous-mode.sh status [--project]
#
# Re-running `on` re-syncs the profile (picks up edits to allow/deny/hooks) WITHOUT
# clobbering the pre-autonomous backup. Note: the guard hook is referenced by ABSOLUTE
# path — keep this repo where it is, or re-run `on` after moving it.
#
# Per-session alternative (no files): `claude --permission-mode acceptEdits`
# (or the stronger `claude --dangerously-skip-permissions`). In-session: Shift+Tab cycles modes.
#
# Takes effect on the NEXT Claude Code session (settings load at start).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE="$HERE/settings.autonomous.json"
GUARD="$HERE/hooks/guard.py"

ACTION="${1:-status}"
SCOPE="global"
[[ "${2:-}" == "--project" || "${2:-}" == "-p" ]] && SCOPE="project"

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

case "$ACTION" in
  on)
    [[ -f "$PROFILE" ]] || { echo "❌ Missing $PROFILE"; exit 1; }
    [[ -f "$GUARD" ]]   || { echo "❌ Missing guard hook: $GUARD"; exit 1; }
    if is_on; then
      echo "🔄 Autonomous mode already ON ($SCOPE) — re-syncing profile (allow/deny/hooks)."
    else
      [[ -f "$SETTINGS" ]] && cp "$SETTINGS" "$BACKUP" && echo "📦 Backed up → $BACKUP"
    fi
    python3 - "$SETTINGS" "$PROFILE" "$GUARD" <<'EOF'
import json,os,sys
sp,pp,guard=sys.argv[1],sys.argv[2],sys.argv[3]
base=json.load(open(sp)) if os.path.exists(sp) else {}
prof=json.load(open(pp))
p=prof["permissions"]
perm=base.setdefault("permissions",{})
perm["defaultMode"]=p["defaultMode"]
perm["allow"]=sorted(set(perm.get("allow",[]))|set(p["allow"]))
perm["deny"]=sorted(set(perm.get("deny",[]))|set(p.get("deny",[])))
# Merge hooks, substituting the guard placeholder with its absolute path.
# Idempotent: drop any prior guard.py entry for the same matcher before re-adding.
for event,entries in prof.get("hooks",{}).items():
    cur=base.setdefault("hooks",{}).setdefault(event,[])
    for entry in entries:
        e=json.loads(json.dumps(entry).replace("__GUARD__",guard))
        cur[:]=[c for c in cur if not (c.get("matcher")==e.get("matcher") and "guard.py" in json.dumps(c))]
        cur.append(e)
json.dump(base,open(sp,"w"),indent=2)
print(f"merged autonomous profile (+guard hook) into {sp}")
EOF
    echo "🟢 Autonomous mode ON ($SCOPE). Restart Claude Code to apply."
    ;;
  off)
    if ! is_on; then echo "⚪ Autonomous mode already OFF ($SCOPE)."; exit 0; fi
    if [[ -f "$BACKUP" ]]; then
      mv "$BACKUP" "$SETTINGS"; echo "🔵 Restored pre-autonomous settings ($SCOPE). Restart to apply."
    else
      python3 - "$SETTINGS" <<'EOF'
import json,sys
d=json.load(open(sys.argv[1]))
d.get("permissions",{}).pop("defaultMode",None)
# Strip our guard hook; drop now-empty hook events / the hooks key entirely.
hk=d.get("hooks",{})
for event in list(hk):
    hk[event]=[c for c in hk[event] if "guard.py" not in json.dumps(c)]
    if not hk[event]: del hk[event]
if "hooks" in d and not d["hooks"]: del d["hooks"]
json.dump(d,open(sys.argv[1],"w"),indent=2)
EOF
      echo "🔵 Cleared defaultMode + guard hook ($SCOPE; no backup to restore). Restart to apply."
    fi
    ;;
  status)
    if is_on; then echo "🟢 Autonomous mode is ON ($SCOPE: $SETTINGS)"; else echo "⚪ Autonomous mode is OFF ($SCOPE)"; fi
    ;;
  *)
    echo "Usage: $0 {on|off|status} [--project]"; exit 2;;
esac
