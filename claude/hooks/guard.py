#!/usr/bin/env python3
"""PreToolUse safety guard for Claude Code autonomous mode.

Autonomous mode allows `bash`/`sh`, so the granular per-tool allow-list is
effectively advisory — the *deny* list is the real boundary, and string-prefix
deny patterns in settings.json cannot reason about a shell command (flag order,
alternate readers, redirections). This hook inspects the actual command and
blocks a small, high-signal set of operations those patterns miss:

  * reading / exfiltrating private keys & secrets via ANY shell reader
    (cat/grep/sed/awk/scp/base64/... of *.pem, id_rsa, ~/.ssh, .env, ...)
  * recursive deletes of dangerous roots regardless of flag order
    (rm -rf /, rm -fr ~, rm --recursive ., find -delete, find -exec rm)
  * disk-destroying ops (mkfs, dd of=/dev/...)
  * remote-code-execution pipes (curl ... | sh)
  * history-destroying git ops (push --force / -f, reset --hard, clean -fdx)
  * privilege escalation (sudo) and fork bombs

Contract (Claude Code PreToolUse hook):
  stdin  = JSON  {"tool_name": ..., "tool_input": {...}}
  exit 0 = allow;  exit 2 = block (stderr is shown back to Claude)

Fails OPEN (exit 0) on unexpected input so it can never wedge a session.
`git push --force-with-lease` is intentionally allowed (it is the safe form).

Modes (environment variable GUARD_MODE, set by guard.sh; default "always"):
  always  every violation blocks (exit 2)
  auto    a violation blocks when the session runs commands without asking; in a
          prompting permission mode (default, plan) it returns
          permissionDecision "ask" instead, so the user decides and nothing that
          an allow-list would have waved through runs silently. A payload with no
          permission_mode blocks (fail safe).
"""
import json
import os
import re
import shlex
import sys

PROMPTING_MODES = ("default", "plan")
SOFT = False  # set in main(): True = ask the user instead of blocking

# ── secret / private-key path tokens ──────────────────────────────────────────
KEY = re.compile(
    r"(id_rsa|id_ed25519|id_ecdsa|id_dsa"
    r"|\.pem\b|\.ppk\b|\.p12\b|\.pfx\b"
    r"|(^|[\s/='\"])\.ssh(?![\w-])"      # ~/.ssh/… and ~/.ssh itself (tar, cp -r)
    r"|\.aws/credentials"
    r"|(^|[\s/='\"])\.gnupg(?![\w-]))",
    re.IGNORECASE,
)
ENV = re.compile(r"(^|[\s/='\"])\.env(\.[\w.]+)?\b", re.IGNORECASE)
EXAMPLE = re.compile(r"\.(example|sample|template|dist)\b", re.IGNORECASE)

# commands that read/copy/exfiltrate file contents
READER = re.compile(
    r"\b(cat|less|more|tac|nl|head|tail|strings|xxd|od|base64|"
    r"grep|egrep|fgrep|rg|ag|sed|awk|cut|tee|"
    r"cp|scp|rsync|curl|wget|nc|ncat|ssh|dd|open)\b"
)

# ── per-word secret rule ───────────────────────────────────────────────────────
# The READER rule above needs a known reader verb. Anything else that names a
# secret file (jq, sort, tar, git diff, a python one-liner, `< .env`) is blocked
# too, unless the command only touches the file's metadata or writes to it.
# Decided per shell WORD, so `.env.example` exempts only itself, never a sibling
# `.env` in the same command.
SAFE_CMDS = frozenset((
    "ls", "stat", "test", "[", "touch", "mkdir", "chmod", "chown", "rm",
    "echo", "printf", "source", ".",
))
SAFE_GIT_SUBCMDS = frozenset(("add", "commit", "status", "check-ignore", "rm", "mv"))
DEST_ONLY_CMDS = frozenset(("cp", "mv", "ln"))   # a secret word only as the destination
SHELL_WORDS = frozenset((           # not commands: skipped when looking for one
    "do", "done", "then", "else", "elif", "fi", "{", "}", "(", ")", "!",
    "time", "exec", "nohup", "command", "builtin",
))
ASSIGNMENT = re.compile(r"^[A-Za-z_]\w*=")
# A token that can be a file argument: no whitespace, no shell or jq/sed operators.
# `'.env // {} | keys'` (a jq filter) and `s|.env|PROD|g` (a sed script) are not.
PATHLIKE = re.compile(r"^[^\s|;&<>()'\"`]+$")
# A secret named as a string literal INSIDE a program (`python3 -c "...('.env')..."`).
QUOTED = re.compile(r"""['"]([^'"\s]+)['"]""")


def _secret_token(text):
    return bool(KEY.search(text) or (ENV.search(text) and not EXAMPLE.search(text)))


def secret_word(word):
    if PATHLIKE.match(word):
        return _secret_token(word)
    return any(_secret_token(literal) for literal in QUOTED.findall(word))


def _tokens(cmd):
    """Quote-aware shell tokens; operators (`;`, `|`, `&&`, `<`, `(`, …) come out as
    their own tokens, quoted strings as one token without the quotes."""
    lexer = shlex.shlex(cmd, posix=True, punctuation_chars=True)
    lexer.whitespace_split = True
    lexer.commenters = ""           # a `# .env.example` comment must not hide `.env`
    try:
        return list(lexer)
    except ValueError:               # unbalanced quotes: fall back to plain words
        return cmd.split()


def _is_operator(token):
    return token and all(ch in ";|&()`$" for ch in token)


def _segments(cmd):
    """Token lists between command separators (`;`, `|`, `&&`, `(`, `$(`, backticks)."""
    segment, out = [], []
    for token in _tokens(cmd):
        if _is_operator(token) or token.startswith("<("):
            out.append(segment)
            segment = []
        else:
            segment.append(token)
    out.append(segment)
    return out


def _command_of(words):
    """(command, subcommand) of a segment: skips env assignments and shell keywords."""
    rest = [w for w in words if not ASSIGNMENT.match(w)]
    while rest and rest[0] in SHELL_WORDS:
        rest = rest[1:]
    if not rest:
        return "", ""
    cmd = rest[0].rsplit("/", 1)[-1]
    sub = next((w for w in rest[1:] if not w.startswith("-")), "")
    return cmd, sub


def _segment_reads_secret(words):
    """The secret word this segment reads, or None when it only names one safely."""
    secrets = [w for w in words if secret_word(w)]
    if not secrets:
        return None
    for i, w in enumerate(words):                      # `< .env` and `<.env`
        if w == "<" and i + 1 < len(words) and secret_word(words[i + 1]):
            return words[i + 1]
        if w.startswith("<") and secret_word(w[1:]):
            return w[1:]
    cmd, sub = _command_of(words)
    if cmd in SAFE_CMDS or (cmd == "git" and sub in SAFE_GIT_SUBCMDS):
        return None
    if cmd in DEST_ONLY_CMDS and secrets == [words[-1]]:
        return None
    return secrets[0]


def reads_secret_word(cmd):
    for words in _segments(cmd):
        word = _segment_reads_secret(words)
        if word:
            return word
    return None


def block(reason):
    if SOFT:
        json.dump({"hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "ask",
            "permissionDecisionReason": "agent-recipes guard: " + reason,
        }}, sys.stdout)
        sys.exit(0)
    sys.stderr.write("BLOCKED by autonomous-mode guard: " + reason + "\n")
    sys.exit(2)


def touches_secret(text):
    if KEY.search(text):
        return True
    if ENV.search(text) and not EXAMPLE.search(text):
        return True
    return False


def _protected_target(t):
    """True if `t` is a catastrophic recursive-delete target (system/home root
    or a shallow path directly under one). Named subdirs like build/ pass."""
    t = t.strip().strip("\"'")
    if t.endswith("/*"):
        t = t[:-2]
    t = t.rstrip("/")
    if t in ("", "/", "*", ".", "~", "$HOME", "${HOME}", ".git"):
        return True
    if t.startswith("/"):
        segs = [s for s in t.split("/") if s]
        return len(segs) <= 2  # /, /etc, /Users/alice — but not /Users/alice/proj/x
    if re.match(r"^(~|\$HOME|\$\{HOME\})", t):
        rest = re.sub(r"^(~|\$HOME|\$\{HOME\})", "", t).strip("/")
        segs = [s for s in rest.split("/") if s]
        return len(segs) <= 1  # ~ or ~/Documents — but not ~/proj/build
    return False


def check_bash(cmd):
    # privilege escalation
    if re.search(r"(^|[;&|(]|\s)sudo\b", cmd):
        block("sudo is not permitted in autonomous mode")

    # fork bomb
    if re.search(r":\s*\(\s*\)\s*\{\s*:\s*\|\s*:", cmd):
        block("fork bomb pattern")

    # secret read / exfiltration — a known reader verb anywhere in the command…
    if READER.search(cmd) and touches_secret(cmd):
        block("reading or copying a secret / private-key file")
    # …or any other command that names a secret file, decided per shell word
    word = reads_secret_word(cmd)
    if word:
        block("reading a secret / private-key file (%s) — only metadata or write "
              "operations on it are allowed" % word)

    # remote code execution: a real download (has a URL) piped into an interpreter.
    # Requiring a scheme/host avoids flagging a mere mention of "curl|bash" in text
    # (e.g. a commit message or an echo).
    if re.search(
        r"\b(curl|wget|fetch)\b[^|]*(://|www\.)[^|]*\|\s*(sudo\s+)?(bash|sh|zsh|python3?|perl|ruby|node)\b",
        cmd,
    ):
        block("piping a remote download into a shell (remote-code-execution risk)")

    # filesystem-destroying ops
    if re.search(r"\bmkfs(\.\w+)?\b", cmd):
        block("mkfs would format a filesystem")
    if re.search(r"\bdd\b", cmd) and re.search(r"\bof=/dev/", cmd):
        block("dd writing directly to a block device")

    # recursive delete of a protected root (flag-order independent)
    for m in re.finditer(r"\brm\b([^\n;&|]*)", cmd):
        seg = m.group(1)
        recursive = False
        for tok in re.findall(r"(?:^|\s)(--?[A-Za-z-]+)", seg):
            if tok == "--recursive":
                recursive = True
            elif tok.startswith("-") and not tok.startswith("--"):
                if "r" in tok or "R" in tok:
                    recursive = True
        if not recursive:
            continue
        for t in re.findall(r"(?:^|\s)((?!-)[^\s;&|]+)", seg):
            if _protected_target(t):
                block("recursive delete of a protected path: rm ... %s" % t)

    # find that mass-deletes
    if re.search(r"\bfind\b", cmd) and re.search(r"(-delete\b|-exec\s+rm\b|-execdir\s+rm\b)", cmd):
        block("find with -delete / -exec rm can mass-delete files")

    # chmod 777 on a system/home path
    if re.search(r"\bchmod\b[^\n;&|]*\b777\b", cmd) and re.search(
        r"(?:^|\s)(/|~|\$HOME|\$\{HOME\}|/Users|/etc)(?:\s|/|$)", cmd
    ):
        block("chmod 777 on a system/home path")

    # history / work-destroying git ops
    if re.search(r"\bgit\s+push\b", cmd):
        if re.search(r"--force(?!-with-lease)", cmd) or re.search(r"(?<!\S)-f\b", cmd) or re.search(r"\s\+[\w./-]+:", cmd):
            block("force push — use `git push --force-with-lease` if you must")
    if re.search(r"\bgit\s+reset\b[^\n;&|]*--hard", cmd):
        block("git reset --hard discards uncommitted work (stash or commit first)")
    if re.search(r"\bgit\s+clean\b", cmd) and re.search(r"-\w*f", cmd) and re.search(r"-\w*[dx]", cmd):
        block("git clean -fd/-fdx deletes untracked files")


def main():
    try:
        payload = json.loads(sys.stdin.read())
    except Exception:
        sys.exit(0)  # fail open — never wedge a session on bad input

    global SOFT
    SOFT = (os.environ.get("GUARD_MODE", "always") == "auto"
            and payload.get("permission_mode") in PROMPTING_MODES)

    tool = payload.get("tool_name", "")
    ti = payload.get("tool_input", {}) or {}

    if tool == "Read":
        if touches_secret(str(ti.get("file_path", ""))):
            block("attempt to read a secret / private-key file")
        sys.exit(0)

    if tool == "Bash":
        check_bash(str(ti.get("command", "")))

    sys.exit(0)


if __name__ == "__main__":
    main()
