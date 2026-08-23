#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────
# Agent Recipes — Setup Script
# Installs Claude Code agents and/or Goose recipes on a new machine.
# ──────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors (disabled when not a terminal)
if [[ -t 1 ]]; then
    BOLD='\033[1m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    CYAN='\033[0;36m'
    RED='\033[0;31m'
    RESET='\033[0m'
else
    BOLD='' GREEN='' YELLOW='' CYAN='' RED='' RESET=''
fi

info()  { printf "${CYAN}[info]${RESET}  %s\n" "$*"; }
ok()    { printf "${GREEN}[ok]${RESET}    %s\n" "$*"; }
warn()  { printf "${YELLOW}[warn]${RESET}  %s\n" "$*"; }
err()   { printf "${RED}[error]${RESET} %s\n" "$*" >&2; }

usage() {
    cat <<EOF
${BOLD}Agent Recipes Setup${RESET}

Usage: ./setup.sh [OPTIONS]

Options:
  --claude            Install Claude Code agents (user-level)
  --claude-project    Install Claude Code agents (project-level, into .claude/)
  --goose             Configure Goose recipe path in shell profile
  --all               Install everything (Claude user-level + Goose)
  --dry-run           Show what would be done without making changes
  --uninstall         Remove installed agents and configuration
  -h, --help          Show this help

Examples:
  ./setup.sh --all              # Full setup for both platforms
  ./setup.sh --claude           # Claude agents only (available in all projects)
  ./setup.sh --claude-project   # Claude agents for current project only
  ./setup.sh --goose            # Goose recipe path only
  ./setup.sh --uninstall        # Remove everything

EOF
}

# ── Defaults ──────────────────────────────────────────────────
INSTALL_CLAUDE=false
INSTALL_CLAUDE_PROJECT=false
INSTALL_GOOSE=false
DRY_RUN=false
UNINSTALL=false

# ── Parse args ────────────────────────────────────────────────
if [[ $# -eq 0 ]]; then
    usage
    exit 0
fi

while [[ $# -gt 0 ]]; do
    case "$1" in
        --claude)          INSTALL_CLAUDE=true ;;
        --claude-project)  INSTALL_CLAUDE_PROJECT=true ;;
        --goose)           INSTALL_GOOSE=true ;;
        --all)             INSTALL_CLAUDE=true; INSTALL_GOOSE=true ;;
        --dry-run)         DRY_RUN=true ;;
        --uninstall)       UNINSTALL=true ;;
        -h|--help)         usage; exit 0 ;;
        *)                 err "Unknown option: $1"; usage; exit 1 ;;
    esac
    shift
done

# ── Helpers ───────────────────────────────────────────────────
copy_agents() {
    local dest="$1"
    local src="${SCRIPT_DIR}/claude/agents"

    if [[ ! -d "$src" ]]; then
        err "Source directory not found: $src"
        exit 1
    fi

    local dirs=("$dest" "$dest/languages" "$dest/specialized" "$dest/subrecipes")
    for d in "${dirs[@]}"; do
        if $DRY_RUN; then
            info "[dry-run] mkdir -p $d"
        else
            mkdir -p "$d"
        fi
    done

    local count=0
    local pairs=(
        "$src/*.md:$dest/"
        "$src/languages/*.md:$dest/languages/"
        "$src/specialized/*.md:$dest/specialized/"
        "$src/subrecipes/*.md:$dest/subrecipes/"
    )

    for pair in "${pairs[@]}"; do
        local pattern="${pair%%:*}"
        local target="${pair##*:}"
        # shellcheck disable=SC2086
        for f in $pattern; do
            [[ -f "$f" ]] || continue
            if $DRY_RUN; then
                info "[dry-run] cp $f -> $target"
            else
                cp "$f" "$target"
            fi
            count=$((count + 1))
        done
    done

    ok "Copied $count agent files to $dest"
}

copy_commands() {
    local dest="$1"
    local src="${SCRIPT_DIR}/claude/commands"

    if [[ ! -d "$src" ]]; then
        warn "No commands directory at $src — skipping workflow commands"
        return
    fi

    if $DRY_RUN; then
        info "[dry-run] mkdir -p $dest"
    else
        mkdir -p "$dest"
    fi

    local count=0
    # wf-*.md workflows plus the wf.md router (exact name — never a user's own command)
    for f in "$src"/wf-*.md "$src/wf.md"; do
        [[ -f "$f" ]] || continue
        if $DRY_RUN; then
            info "[dry-run] cp $f -> $dest/"
        else
            cp "$f" "$dest/"
        fi
        count=$((count + 1))
    done

    if $DRY_RUN; then
        info "[dry-run] would copy $count workflow command(s) to $dest"
    else
        ok "Copied $count workflow command(s) to $dest"
    fi
}

# Ensure Claude does NOT add itself as a git co-author. Merges
# `includeCoAuthoredBy: false` into the given settings.json, preserving every
# other key; creates the file if absent; leaves an unparseable file untouched.
set_no_coauthor() {
    local settings="$1"

    if ! command -v python3 >/dev/null 2>&1; then
        warn "python3 not found — skipping includeCoAuthoredBy in $settings"
        return
    fi

    if $DRY_RUN; then
        info "[dry-run] set includeCoAuthoredBy=false in $settings"
        return
    fi

    mkdir -p "$(dirname "$settings")"
    if python3 - "$settings" <<'PY'
import json, os, sys
f = sys.argv[1]
try:
    d = json.load(open(f)) if os.path.exists(f) and os.path.getsize(f) else {}
except Exception as e:
    sys.stderr.write("parse error: %s\n" % e)
    sys.exit(3)
d["includeCoAuthoredBy"] = False
json.dump(d, open(f, "w"), indent=2)
open(f, "a").write("\n")
PY
    then
        ok "Set includeCoAuthoredBy=false in $settings (no Claude co-author trailer)"
    else
        warn "Left $settings untouched (not valid JSON) — add '\"includeCoAuthoredBy\": false' manually"
    fi
}

remove_commands() {
    local dest="$1"
    if [[ ! -d "$dest" ]]; then
        info "No commands to remove at $dest"
        return
    fi

    local count=0
    for f in "$dest"/wf-*.md "$dest/wf.md"; do
        [[ -f "$f" ]] || continue
        if $DRY_RUN; then
            info "[dry-run] rm $f"
        else
            rm -f "$f"
        fi
        count=$((count + 1))
    done

    # Drop the directory only if our removal left it empty (tolerate a race).
    if ! $DRY_RUN && [[ -d "$dest" ]] && [[ -z "$(ls -A "$dest" 2>/dev/null)" ]]; then
        rmdir "$dest" 2>/dev/null || true
    fi

    if $DRY_RUN; then
        info "[dry-run] would remove $count workflow command(s) from $dest"
    else
        ok "Removed $count workflow command(s) from $dest"
    fi
}

remove_agents() {
    local dest="$1"
    if [[ -d "$dest" ]]; then
        if $DRY_RUN; then
            info "[dry-run] rm -rf $dest"
        else
            rm -rf "$dest"
        fi
        ok "Removed $dest"
    else
        info "Nothing to remove at $dest"
    fi
}

detect_shell_profile() {
    local shell_name
    shell_name="$(basename "${SHELL:-/bin/bash}")"
    case "$shell_name" in
        zsh)  echo "${HOME}/.zshrc" ;;
        bash)
            if [[ -f "${HOME}/.bash_profile" ]]; then
                echo "${HOME}/.bash_profile"
            else
                echo "${HOME}/.bashrc"
            fi
            ;;
        fish) echo "${HOME}/.config/fish/config.fish" ;;
        *)    echo "${HOME}/.profile" ;;
    esac
}

GOOSE_MARKER="# agent-recipes: goose config"

add_goose_config() {
    local profile
    profile="$(detect_shell_profile)"
    local recipe_path="${SCRIPT_DIR}/goose/general"
    local shell_name
    shell_name="$(basename "${SHELL:-/bin/bash}")"

    if [[ ! -d "$recipe_path" ]]; then
        err "Goose recipes not found at: $recipe_path"
        exit 1
    fi

    if grep -qF "$GOOSE_MARKER" "$profile" 2>/dev/null; then
        warn "Goose config already present in $profile — skipping"
        return
    fi

    local config_block
    if [[ "$shell_name" == "fish" ]]; then
        config_block="
$GOOSE_MARKER
set -gx GOOSE_RECIPE_PATH \"${recipe_path}\""
    else
        config_block="
$GOOSE_MARKER
export GOOSE_RECIPE_PATH=\"${recipe_path}\""
    fi

    if $DRY_RUN; then
        info "[dry-run] Would append to $profile:"
        printf '%s\n' "$config_block"
    else
        printf '%s\n' "$config_block" >> "$profile"
    fi

    ok "Added GOOSE_RECIPE_PATH to $profile"
    info "Run 'source $profile' or open a new terminal to activate"
}

remove_goose_config() {
    local profile
    profile="$(detect_shell_profile)"

    if ! grep -qF "$GOOSE_MARKER" "$profile" 2>/dev/null; then
        info "No Goose config found in $profile"
        return
    fi

    if $DRY_RUN; then
        info "[dry-run] Would remove Goose config block from $profile"
    else
        # Remove the marker line and the export/set line after it
        local tmp="${profile}.agent-recipes-bak"
        cp "$profile" "$tmp"
        grep -v "$GOOSE_MARKER" "$tmp" | grep -v 'GOOSE_RECIPE_PATH' > "$profile"
        rm -f "$tmp"
    fi

    ok "Removed Goose config from $profile"
}

# ── Uninstall ─────────────────────────────────────────────────
if $UNINSTALL; then
    printf "\n${BOLD}Uninstalling agent recipes...${RESET}\n\n"

    remove_agents "${HOME}/.claude/agents"
    remove_agents ".claude/agents"
    remove_commands "${HOME}/.claude/commands"
    remove_commands ".claude/commands"
    remove_goose_config

    printf "\n${GREEN}${BOLD}Uninstall complete.${RESET}\n"
    exit 0
fi

# ── Install ───────────────────────────────────────────────────
printf "\n${BOLD}Setting up agent recipes...${RESET}\n\n"

if $INSTALL_CLAUDE; then
    info "Installing Claude Code agents (user-level -> ~/.claude/agents/)"
    copy_agents "${HOME}/.claude/agents"
    info "Installing workflow commands (user-level -> ~/.claude/commands/)"
    copy_commands "${HOME}/.claude/commands"
    info "Ensuring Claude is not added as a git co-author (user-level)"
    set_no_coauthor "${HOME}/.claude/settings.json"
    printf "\n"
fi

if $INSTALL_CLAUDE_PROJECT; then
    info "Installing Claude Code agents (project-level -> .claude/agents/)"
    copy_agents ".claude/agents"
    info "Installing workflow commands (project-level -> .claude/commands/)"
    copy_commands ".claude/commands"
    info "Ensuring Claude is not added as a git co-author (project-level)"
    set_no_coauthor ".claude/settings.json"
    printf "\n"
fi

if $INSTALL_GOOSE; then
    info "Configuring Goose recipe path"
    add_goose_config
    printf "\n"
fi

# ── Summary ───────────────────────────────────────────────────
printf "${GREEN}${BOLD}Setup complete!${RESET}\n\n"

if $INSTALL_CLAUDE || $INSTALL_CLAUDE_PROJECT; then
    printf "  ${BOLD}Claude Code:${RESET} Agents are ready. Start claude and describe your task.\n"
    printf "  List agents:  ${CYAN}/agents${RESET}  or  ${CYAN}claude agents${RESET}\n\n"
fi

if $INSTALL_GOOSE; then
    printf "  ${BOLD}Goose:${RESET} Run recipes with:\n"
    printf "  ${CYAN}goose run --recipe goose/general/code-reviewer.yaml${RESET}\n\n"
fi
