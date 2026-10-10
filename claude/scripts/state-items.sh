#!/usr/bin/env bash
# state-items.sh — sourced by state-sync.sh. Which tools are active on this device,
# what each one links into the store, the shared INSTRUCTIONS.md, and Claude's
# per-project auto memory. Nothing here runs git; state-sync.sh owns the repository.
#
# Expects from the caller: SYNC_DIR, CLAUDE_HOME, OFF_MARK, STATE_TOOLS (may be empty:
# detect), STATE_CLAUDE_AUTO_MEMORY (yes|no).
#
# Items (native path -> path inside the store), per tool:
#   claude  ~/.claude/agent-memory            claude/agent-memory
#           ~/.claude/CLAUDE.md               INSTRUCTIONS.md
#           ~/.claude/projects/<p>/memory     claude/auto-memory/<p>   (one per project)
#   goose   ~/.config/goose/memory            goose/memory
#           ~/.config/goose/.goosehints       INSTRUCTIONS.md
#   hermes  ~/.hermes/memories                hermes/memories
#   codex   ~/.codex/AGENTS.md                INSTRUCTIONS.md   (memory store NOT synced:
#                                             it carries its own .git, and the user opted out)
# INSTRUCTIONS.md is one file for every tool; each tool's own instruction file links to it.

GOOSE_CONFIG_DIR="${GOOSE_CONFIG_DIR:-$HOME/.config/goose}"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
INSTRUCTIONS="INSTRUCTIONS.md"
SHARED_MARK='<!-- agent-recipes:shared-notes -->'
HERMES_MEMORY_CAP=2200   # chars: Hermes refuses a larger MEMORY.md write
HERMES_USER_CAP=1375     # chars: the same for USER.md
BACKUP_ROOT="$CLAUDE_HOME/.state-sync-backup"

tool_home() {
    case "$1" in
        goose)  echo "$GOOSE_CONFIG_DIR" ;;
        hermes) echo "$HERMES_HOME" ;;
        codex)  echo "$CODEX_HOME" ;;
    esac
}

# claude is always on; goose, hermes and codex when their home exists or their CLI is on PATH.
detect_tools() {
    local tools=claude t
    for t in goose hermes codex; do
        if [[ -d "$(tool_home "$t")" ]] || command -v "$t" >/dev/null 2>&1; then
            tools="$tools $t"
        fi
    done
    echo "$tools"
}
ALL_TOOLS=0   # 1 = every tool counts as active (used by `off`: unlink whatever is linked)
active_tools() { if (( ALL_TOOLS )); then echo "claude goose hermes codex"; else echo "${STATE_TOOLS:-$(detect_tools)}"; fi; }
tool_active()  { case " $(active_tools) " in *" $1 "*) return 0 ;; esac; return 1; }

# items: tool<TAB>kind<TAB>native path<TAB>store path, one line per item of each active tool.
items() {
    printf 'claude\tdir\t%s\tclaude/agent-memory\n' "$CLAUDE_HOME/agent-memory"
    printf 'claude\tfile\t%s\t%s\n' "$CLAUDE_HOME/CLAUDE.md" "$INSTRUCTIONS"
    if tool_active goose; then
        printf 'goose\tdir\t%s\tgoose/memory\n' "$GOOSE_CONFIG_DIR/memory"
        printf 'goose\tfile\t%s\t%s\n' "$GOOSE_CONFIG_DIR/.goosehints" "$INSTRUCTIONS"
    fi
    if tool_active hermes; then
        printf 'hermes\tdir\t%s\thermes/memories\n' "$HERMES_HOME/memories"
    fi
    if tool_active codex; then
        printf 'codex\tfile\t%s\t%s\n' "$CODEX_HOME/AGENTS.md" "$INSTRUCTIONS"
    fi
    return 0
}

# auto_memory_items [all]: Claude's per-project auto memory — every
# $CLAUDE_HOME/projects/<project>/memory that exists (plain, or already a link).
# Without "all", nothing when STATE_CLAUDE_AUTO_MEMORY is no.
auto_memory_items() {
    [[ "${1:-}" == all || "${STATE_CLAUDE_AUTO_MEMORY:-yes}" == yes ]] || return 0
    local d
    for d in "$CLAUDE_HOME"/projects/*/memory; do
        [[ -d "$d" || -L "$d" ]] || continue
        printf 'claude\tdir\t%s\tclaude/auto-memory/%s\n' "$d" "$(basename "$(dirname "$d")")"
    done
    return 0
}

realpath_of() { python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1"; }
# in_store <path>: the link target lives inside the store (both sides resolved: on
# macOS a temp directory resolves to /private/..., so string prefixes do not do).
in_store() { case "$(realpath_of "$1")" in "$(realpath_of "$SYNC_DIR")"/*) return 0 ;; esac; return 1; }

# backup_path <store path> <native basename>: where a replaced copy goes —
# <backup root>/<timestamp>/<basename>, except per-project auto memory, which would
# all be called "memory": those keep their project under auto-memory/<project>/.
backup_path() {
    local dir sub=""
    case "$1" in claude/auto-memory/*) sub="/auto-memory/${1#claude/auto-memory/}" ;; esac
    dir="$BACKUP_ROOT/$(date -u +%Y%m%dT%H%M%SZ)$sub"
    mkdir -p "$dir"
    echo "$dir/$2"
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

# unlink_foreign <path>: a symlink that already points INTO the store is simply
# re-pointed by the caller (returns 1); one that points elsewhere (a dotfiles repo) is
# replaced by a plain copy of its target first, so nothing is lost and nothing dangles.
unlink_foreign() {
    local path="$1" target
    in_store "$path" && return 1
    target="$(realpath_of "$path")"
    rm "$path"
    if [[ -e "$target" ]]; then
        cp -R "$target" "$path"
        echo "  note: $path was a link to $target; that content now lives in the sync repo"
    fi
    return 0
}

# local_wins <native path> <store path> <tool>: a file edited after `off` goes into
# the store. The first such file replaces the store's copy; a SECOND one in the same
# run (another tool's instruction file, also edited while off) must not overwrite the
# first, so its lines that the store lacks are folded in under a heading instead.
ADOPTED_LOCAL=" "
local_wins() {
    local local_path="$1" item="$2" tool="$3" repo_path="$SYNC_DIR/$2" extra
    case "$ADOPTED_LOCAL" in
        *" $item "*)
            extra="$(grep -vxFf "$repo_path" "$local_path" || true)"
            if [[ -n "$extra" ]]; then
                [[ -n "$(tail -c1 "$repo_path")" ]] && echo >> "$repo_path"
                printf '\n## From %s (edited while sync was off)\n\n%s\n' "$tool" "$extra" >> "$repo_path"
            fi
            rm "$local_path"
            echo "  folded this device's edits to $(basename "$local_path") into $item under '## From $tool'" ;;
        *)
            cp "$local_path" "$repo_path"; rm "$local_path"
            ADOPTED_LOCAL="$ADOPTED_LOCAL$item "
            echo "  kept this device's newer $item and replaced the repo's copy (previous version: git history)" ;;
    esac
}

# adopt <native path> <store path> <dir|file> [tool]: move/merge the local item into
# the store, then leave a symlink. Rules when both sides exist: a directory merges
# (repo wins on collisions, local-only files added); a file edited after `off` wins
# (the off marker is older than the file); identical content needs no decision;
# otherwise the repo's version replaces the local one. Replaced copies are backed up.
adopt() {
    local local_path="$1" item="$2" kind="$3" tool="${4:-claude}" repo_path="$SYNC_DIR/$2" backup
    if [[ -L "$local_path" ]] && ! unlink_foreign "$local_path"; then
        ln -sfn "$repo_path" "$local_path"; return 0
    fi
    mkdir -p "$(dirname "$repo_path")" "$(dirname "$local_path")"
    if [[ -e "$local_path" ]]; then
        if [[ -e "$repo_path" && "$kind" == dir ]]; then
            copy_missing "$local_path" "$repo_path"
            backup="$(backup_path "$item" "$(basename "$local_path")")"
            mv "$local_path" "$backup"
            echo "  merged $item: local-only files added, the repo's version replaced yours on collisions (your previous copy: $backup)"
        elif [[ -e "$repo_path" ]] && cmp -s "$local_path" "$repo_path"; then
            rm "$local_path"
        elif [[ -e "$repo_path" && -e "$OFF_MARK" && ! "$OFF_MARK" -nt "$local_path" ]]; then
            local_wins "$local_path" "$item" "$tool"
        elif [[ -e "$repo_path" ]]; then
            backup="$(backup_path "$item" "$(basename "$local_path")")"
            mv "$local_path" "$backup"
            echo "  replaced your $(basename "$local_path") with the repo's $item (your previous copy: $backup)"
        else
            mv "$local_path" "$repo_path"
        fi
    elif [[ ! -e "$repo_path" ]]; then
        if [[ "$kind" == dir ]]; then mkdir -p "$repo_path"; else : > "$repo_path"; fi
    fi
    ln -s "$repo_path" "$local_path"
    echo "  linked $local_path -> $repo_path"
}

adopt_items() {
    local t k n r
    while IFS=$'\t' read -r t k n r; do adopt "$n" "$r" "$k" "$t"; done < <(items)
}
adopt_auto_memory() {
    local t k n r
    while IFS=$'\t' read -r t k n r; do adopt "$n" "$r" "$k"; done < <(auto_memory_items)
}

# build_instructions: on the FIRST init only (the store has no INSTRUCTIONS.md yet),
# assemble it from the user's CLAUDE.md, then fold in a differing .goosehints or
# AGENTS.md under "## From <tool>" and back the originals up.
build_instructions() {
    local out="$SYNC_DIR/$INSTRUCTIONS" t native backup
    [[ -e "$out" ]] && return 0
    native="$CLAUDE_HOME/CLAUDE.md"
    if [[ -L "$native" ]]; then unlink_foreign "$native" || rm -f "$native"; fi
    if [[ -f "$native" ]]; then cp "$native" "$out"; rm "$native"; else : > "$out"; fi
    for t in goose codex; do
        tool_active "$t" || continue
        case "$t" in goose) native="$GOOSE_CONFIG_DIR/.goosehints" ;; codex) native="$CODEX_HOME/AGENTS.md" ;; esac
        if [[ -L "$native" ]]; then unlink_foreign "$native" || rm -f "$native"; fi
        [[ -f "$native" ]] || continue
        if cmp -s "$native" "$out"; then rm "$native"; continue; fi
        [[ -s "$out" && -n "$(tail -c1 "$out")" ]] && echo >> "$out"
        printf '\n## From %s\n\n' "$t" >> "$out"
        cat "$native" >> "$out"
        backup="$(backup_path "$INSTRUCTIONS" "$(basename "$native")")"
        mv "$native" "$backup"
        echo "  folded $native into $INSTRUCTIONS under '## From $t' (original: $backup)"
    done
}

# ensure_shared_paragraph: the one fixed paragraph every tool reads, added once.
ensure_shared_paragraph() {
    local out="$SYNC_DIR/$INSTRUCTIONS"
    grep -qsF "$SHARED_MARK" "$out" && return 0
    [[ -s "$out" && -n "$(tail -c1 "$out")" ]] && echo >> "$out"
    {
        echo
        echo "$SHARED_MARK"
        echo "## Shared notes (every assistant)"
        echo
        echo "Durable facts about this user's work that any assistant may need live in the"
        echo "\`shared/\` folder of the state repository this file belongs to ($SYNC_DIR/shared"
        echo "on the device that wrote this line). Read them at the start of a task that needs"
        echo "context about the user's projects or preferences. When you learn something durable,"
        echo "add a short Markdown file there rather than keeping it only in tool-specific memory."
        echo "Never store secrets there. Sections headed \`## Claude Code\`, \`## Goose\` or"
        echo "\`## Codex\` apply to that tool only."
    } >> "$out"
}

write_shared_readme() {
    local f="$SYNC_DIR/shared/README.md"
    [[ -e "$f" ]] && return 0
    mkdir -p "$SYNC_DIR/shared"
    {
        echo "# Shared notes"
        echo
        echo "Tool-neutral, durable notes that every assistant (Claude Code, Goose, Codex,"
        echo "Hermes) reads and may add to — one short Markdown file per topic, no secrets."
        echo "The instruction file next to this folder (INSTRUCTIONS.md) tells each tool to use it."
    } > "$f"
}

# hermes_cap_warnings: Hermes enforces size caps; a union merge can push a file over
# them, and then Hermes' next write fails. Say so instead of trimming memory silently.
hermes_cap_warnings() {
    tool_active hermes || return 0
    local spec f cap n
    for spec in "MEMORY.md:$HERMES_MEMORY_CAP" "USER.md:$HERMES_USER_CAP"; do
        f="$SYNC_DIR/hermes/memories/${spec%%:*}"; cap="${spec##*:}"
        [[ -f "$f" ]] || continue
        n="$(wc -c < "$f" | tr -d ' ')"
        if (( n > cap )); then
            echo "  WARNING hermes/memories/${spec%%:*} is $n chars, over Hermes' limit of $cap; its next memory write would fail — trim it"
        fi
    done
    return 0
}

# unlink_all: every link into the store becomes a plain copy (used by `off`) — for
# every tool, whatever STATE_TOOLS says now: a tool dropped from the list after it
# was linked must not keep a link into a store that is being switched off.
unlink_all() {
    local t k n r
    ALL_TOOLS=1
    local target
    while IFS=$'\t' read -r t k n r; do
        [[ -L "$n" ]] && in_store "$n" || continue
        target="$(realpath_of "$n")"      # the link's own target: right in any layout
        rm "$n"
        [[ -e "$target" ]] && cp -R "$target" "$n"
        echo "  unlinked $n (plain copy restored)"
    done < <(items; auto_memory_items all)
    ALL_TOOLS=0
}

# list_items: human-readable plan of what init would link (setup.sh --dry-run).
list_items() {
    local t k n r
    while IFS=$'\t' read -r t k n r; do
        printf '  %-6s %s -> %s\n' "$t" "$n" "$r"
    done < <(items; auto_memory_items)
}
