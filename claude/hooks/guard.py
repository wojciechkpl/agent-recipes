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
"""
import json
import re
import sys

# ── secret / private-key path tokens ──────────────────────────────────────────
KEY = re.compile(
    r"(id_rsa|id_ed25519|id_ecdsa|id_dsa"
    r"|\.pem\b|\.ppk\b|\.p12\b|\.pfx\b"
    r"|(^|[\s/='\"])\.ssh/"
    r"|\.aws/credentials"
    r"|(^|[\s/='\"])\.gnupg/)",
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


def block(reason):
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

    # secret read / exfiltration
    if READER.search(cmd) and touches_secret(cmd):
        block("reading or copying a secret / private-key file")

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
