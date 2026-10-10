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
  --all               Install everything (Claude user-level + Goose + state sync)
  --state             Set up the state store: one private git repo holding agent
                      memory and instructions for Claude Code, Goose, Hermes and
                      Codex. On a terminal it asks where the store lives, which
                      remote syncs it and which tools to include; otherwise it
                      uses the defaults (~/.agent-state, local-only, detected tools)
  --state-dir <path>      Store location (default ~/.agent-state)
  --state-remote <url>    Private git remote; empty = this machine only
  --state-tools <list>    Tools to include, e.g. "claude goose" (default: detected)
  --no-state          Skip the state store (with --all)
  --dry-run           Show what would be done without making changes
  --uninstall         Remove installed agents, configuration and the state links
                      (the store itself is kept)
  -h, --help          Show this help

Examples:
  ./setup.sh --all              # Full setup for both platforms + state store
  ./setup.sh --claude           # Claude agents only (available in all projects)
  ./setup.sh --claude-project   # Claude agents for current project only
  ./setup.sh --goose            # Goose recipe path only
  ./setup.sh --state            # State store only (asks where, on a terminal)
  ./setup.sh --uninstall        # Remove everything

EOF
}

# ── Defaults ──────────────────────────────────────────────────
INSTALL_CLAUDE=false
INSTALL_CLAUDE_PROJECT=false
INSTALL_GOOSE=false
INSTALL_STATE=false
NO_STATE=false
STATE_DIR_OPT=""
STATE_REMOTE_OPT=""
STATE_TOOLS_OPT=""
DRY_RUN=false
UNINSTALL=false
STATE_SYNC="${SCRIPT_DIR}/claude/scripts/state-sync.sh"
STATE_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/agent-recipes/state.conf"

# ── Parse args ────────────────────────────────────────────────
if [[ $# -eq 0 ]]; then
    usage
    exit 0
fi

need_value() { [[ $# -ge 2 && "$2" != --* ]] || { err "$1 needs a value"; exit 1; }; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --claude)          INSTALL_CLAUDE=true ;;
        --claude-project)  INSTALL_CLAUDE_PROJECT=true ;;
        --goose)           INSTALL_GOOSE=true ;;
        --all)             INSTALL_CLAUDE=true; INSTALL_GOOSE=true; INSTALL_STATE=true ;;
        --state)           INSTALL_STATE=true ;;
        --state-dir)       need_value "$@"; STATE_DIR_OPT="$2"; shift ;;
        --state-remote)    need_value "$@"; STATE_REMOTE_OPT="$2"; shift ;;
        --state-tools)     need_value "$@"; STATE_TOOLS_OPT="$2"; shift ;;
        --no-state)        NO_STATE=true ;;
        --dry-run)         DRY_RUN=true ;;
        --uninstall)       UNINSTALL=true ;;
        -h|--help)         usage; exit 0 ;;
        *)                 err "Unknown option: $1"; usage; exit 1 ;;
    esac
    shift
done
if $NO_STATE; then INSTALL_STATE=false; fi

# ── Helpers ───────────────────────────────────────────────────
copy_agents() {
    local dest="$1"
    local src="${SCRIPT_DIR}/claude/agents"

    if [[ ! -d "$src" ]]; then
        err "Source directory not found: $src"
        exit 1
    fi

    local dirs=("$dest" "$dest/languages" "$dest/specialized")
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

copy_skills() {
    local dest="$1"
    local src="${SCRIPT_DIR}/claude/skills"

    if [[ ! -d "$src" ]]; then
        warn "No skills directory at $src — skipping skills"
        return
    fi

    local count=0
    local d name
    for d in "$src"/*/; do
        [[ -f "${d}SKILL.md" ]] || continue
        name="$(basename "$d")"
        if $DRY_RUN; then
            info "[dry-run] cp ${d}SKILL.md -> $dest/$name/"
        else
            mkdir -p "$dest/$name"
            cp "${d}SKILL.md" "$dest/$name/"
        fi
        count=$((count + 1))
    done

    if $DRY_RUN; then
        info "[dry-run] would copy $count skill(s) to $dest"
    else
        ok "Copied $count skill(s) to $dest"
    fi
}

# Remove ONLY the skills this repo ships (named in claude/skills/), preserving
# any skills the user created themselves.
remove_skills() {
    local dest="$1"
    local src="${SCRIPT_DIR}/claude/skills"
    if [[ ! -d "$dest" ]]; then
        info "No skills to remove at $dest"
        return
    fi

    local count=0
    local d name
    for d in "$src"/*/; do
        [[ -d "$d" ]] || continue
        name="$(basename "$d")"
        if [[ -d "$dest/$name" ]]; then
            if $DRY_RUN; then
                info "[dry-run] rm -rf $dest/$name"
            else
                rm -rf "${dest:?}/${name:?}"
            fi
            count=$((count + 1))
        fi
    done

    # Drop the directory only if our removal left it empty (tolerate a race).
    if ! $DRY_RUN && [[ -d "$dest" ]] && [[ -z "$(ls -A "$dest" 2>/dev/null)" ]]; then
        rmdir "$dest" 2>/dev/null || true
    fi

    if $DRY_RUN; then
        info "[dry-run] would remove $count skill(s) from $dest"
    else
        ok "Removed $count skill(s) from $dest"
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

# ── State store (agent memory + instructions, all tools) ──────
# "Interactive" = stdin is a terminal. AGENT_RECIPES_ASSUME_TTY=1 is a test hook that
# lets a test pipe the answers in; it is not documented for users.
state_interactive() { [[ -t 0 || "${AGENT_RECIPES_ASSUME_TTY:-}" == 1 ]]; }

# ask <prompt> <default>: one line from the user, Enter (or EOF) keeps the default.
ask() {
    local answer=""
    printf "%s" "$1" >&2
    read -r answer || true
    echo "${answer:-$2}"
}

# yes_no <prompt> <y|n>: y/n with a default.
yes_no() {
    local answer
    answer="$(ask "$1" "$2")"
    case "$answer" in [Yy]*) echo y ;; *) echo n ;; esac
}

# conf_get <KEY>: the value already in state.conf (a re-run keeps earlier answers).
conf_get() { "$STATE_SYNC" config 2>/dev/null | sed -n "s/^$1=\"\(.*\)\"\$/\1/p"; }

# expand_home <path>: ~ and ~/x become absolute; a relative path is taken from here.
expand_home() {
    case "$1" in
        \~)    echo "$HOME" ;;
        \~/*)  echo "$HOME/${1#\~/}" ;;
        /*)    echo "$1" ;;
        *)     echo "$PWD/$1" ;;
    esac
}

setup_state() {
    local detected dir remote tools auto t answer had_conf=false
    detected="$("$STATE_SYNC" detect)"
    [[ -f "$STATE_CONF" ]] && had_conf=true
    # Precedence: flag, then what state.conf already says, then the default.
    dir="${STATE_DIR_OPT:-$(conf_get STATE_DIR)}"; [[ -n "$dir" ]] || dir="${HOME}/.agent-state"
    dir="$(expand_home "$dir")"
    remote="${STATE_REMOTE_OPT:-$(conf_get STATE_REMOTE)}"
    tools="${STATE_TOOLS_OPT:-$(conf_get STATE_TOOLS)}"; [[ -n "$tools" ]] || tools="$detected"
    auto="$(conf_get STATE_CLAUDE_AUTO_MEMORY)"; [[ -n "$auto" ]] || auto=yes
    if state_interactive; then
        printf "\n${BOLD}State store${RESET} — one private git repo for agent memory and instructions.\n" >&2
        printf "Detected tools: %s\n\n" "$detected" >&2
        if [[ -z "$STATE_DIR_OPT" ]]; then
            answer="$(ask "Where should agent memory and instructions live? [$dir] " "$dir")"
            dir="$(expand_home "$answer")"
        fi
        [[ -n "$STATE_REMOTE_OPT" ]] || remote="$(ask "Private git remote to sync it (Enter = ${remote:-this machine only}): " "$remote")"
        if [[ -z "$STATE_TOOLS_OPT" ]] && ! $had_conf; then
            tools=claude
            for t in $detected; do
                [[ "$t" == claude ]] && continue
                [[ "$(yes_no "Include $t? [Y/n] " y)" == y ]] && tools="$tools $t"
            done
        fi
        [[ "$(yes_no "Also sync Claude's per-project auto memory (~/.claude/projects/*/memory)? [$( [[ "$auto" == yes ]] && echo Y/n || echo y/N )] " "$auto")" == y ]] && auto=yes || auto=no
        printf "\n" >&2
    fi

    if $DRY_RUN; then
        info "[dry-run] would write $STATE_CONF:"
        printf '  STATE_DIR=%s\n  STATE_REMOTE=%s\n  STATE_TOOLS="%s"\n  STATE_CLAUDE_AUTO_MEMORY=%s\n' \
            "$dir" "$remote" "$tools" "$auto"
        info "[dry-run] would link into $dir:"
        STATE_DIR="$dir" STATE_TOOLS="$tools" STATE_CLAUDE_AUTO_MEMORY="$auto" "$STATE_SYNC" items
        return 0
    fi
    "$STATE_SYNC" config dir="$dir" remote="$remote" tools="$tools" auto_memory="$auto"
    ok "Wrote $STATE_CONF"
    "$STATE_SYNC" init
    ok "State store ready at $dir (tools: $tools)"
}

# remove_state: links back to plain copies, state.conf removed, the store kept.
remove_state() {
    local store
    store="$("$STATE_SYNC" config 2>/dev/null | sed -n 's/^STATE_DIR="\(.*\)"$/\1/p')"
    store="${store:-${HOME}/.agent-state}"
    if [[ ! -f "$STATE_CONF" && ! -d "$store/.git" && ! -d "${HOME}/.claude-state/.git" ]]; then
        return 0
    fi
    if $DRY_RUN; then
        info "[dry-run] state-sync.sh off (links -> plain copies; the store is kept)"
        info "[dry-run] rm $STATE_CONF"
        return 0
    fi
    "$STATE_SYNC" off
    rm -f "$STATE_CONF"
    ok "State links restored to plain copies; removed $STATE_CONF (the store itself is kept)"
}

# ── Uninstall ─────────────────────────────────────────────────
if $UNINSTALL; then
    printf "\n${BOLD}Uninstalling agent recipes...${RESET}\n\n"

    remove_state
    remove_agents "${HOME}/.claude/agents"
    remove_agents ".claude/agents"
    remove_commands "${HOME}/.claude/commands"
    remove_commands ".claude/commands"
    remove_skills "${HOME}/.claude/skills"
    remove_skills ".claude/skills"
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
    info "Installing skills (user-level -> ~/.claude/skills/)"
    copy_skills "${HOME}/.claude/skills"
    info "Ensuring Claude is not added as a git co-author (user-level)"
    set_no_coauthor "${HOME}/.claude/settings.json"
    printf "\n"
fi

if $INSTALL_CLAUDE_PROJECT; then
    info "Installing Claude Code agents (project-level -> .claude/agents/)"
    copy_agents ".claude/agents"
    info "Installing workflow commands (project-level -> .claude/commands/)"
    copy_commands ".claude/commands"
    info "Installing skills (project-level -> .claude/skills/)"
    copy_skills ".claude/skills"
    info "Ensuring Claude is not added as a git co-author (project-level)"
    set_no_coauthor ".claude/settings.json"
    printf "\n"
fi

if $INSTALL_GOOSE; then
    info "Configuring Goose recipe path"
    add_goose_config
    printf "\n"
fi

if $INSTALL_STATE; then
    info "Setting up the state store (agent memory + instructions)"
    setup_state
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

if $INSTALL_STATE && ! $DRY_RUN; then
    printf "  ${BOLD}State store:${RESET} ${CYAN}claude/scripts/state-sync.sh status${RESET} shows what is linked;\n"
    printf "  run ${CYAN}./setup.sh --state${RESET} on every other device with the same remote.\n\n"
fi
