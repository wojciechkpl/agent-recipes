#!/usr/bin/env bash
# Toggle Claude Code "autonomous mode" — OPTIONAL, reversible, global or per-project.
#
# Merges settings.autonomous.json (defaultMode:acceptEdits + broad dev-toolchain allow +
# safety deny) into the target settings.json, preserving your other keys (model, statusLine,
# plugins, ...). Reduces mid-session permission prompts; the deny list still blocks
# catastrophic / secret-exfil operations. `off` restores the exact pre-autonomous settings.
#
# Usage:
#   claude/autonomous-mode.sh on              # GLOBAL: ~/.claude/settings.json (all projects)
#   claude/autonomous-mode.sh on --project    # PROJECT: ./.claude/settings.json (cwd only)
#   claude/autonomous-mode.sh off [--project]
#   claude/autonomous-mode.sh status [--project]
#
# Per-session alternative (no files): `claude --permission-mode acceptEdits`
# (or the stronger `claude --dangerously-skip-permissions`). In-session: Shift+Tab cycles modes.
#
# Takes effect on the NEXT Claude Code session (settings load at start).
set -euo pipefail

PROFILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/settings.autonomous.json"

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
    if is_on; then echo "✅ Autonomous mode already ON ($SCOPE)."; exit 0; fi
    [[ -f "$SETTINGS" ]] && cp "$SETTINGS" "$BACKUP" && echo "📦 Backed up → $BACKUP"
    python3 - "$SETTINGS" "$PROFILE" <<'EOF'
import json,os,sys
sp,pp=sys.argv[1],sys.argv[2]
base=json.load(open(sp)) if os.path.exists(sp) else {}
prof=json.load(open(pp))["permissions"]
perm=base.setdefault("permissions",{})
perm["defaultMode"]=prof["defaultMode"]
perm["allow"]=sorted(set(perm.get("allow",[]))|set(prof["allow"]))
perm["deny"]=sorted(set(perm.get("deny",[]))|set(prof.get("deny",[])))
json.dump(base,open(sp,"w"),indent=2)
print(f"merged autonomous profile into {sp}")
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
json.dump(d,open(sys.argv[1],"w"),indent=2)
EOF
      echo "🔵 Cleared defaultMode ($SCOPE; no backup to restore). Restart to apply."
    fi
    ;;
  status)
    if is_on; then echo "🟢 Autonomous mode is ON ($SCOPE: $SETTINGS)"; else echo "⚪ Autonomous mode is OFF ($SCOPE)"; fi
    ;;
  *)
    echo "Usage: $0 {on|off|status} [--project]"; exit 2;;
esac
