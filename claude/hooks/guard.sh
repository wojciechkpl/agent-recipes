#!/bin/sh
# Fast entrypoint for the PreToolUse safety guard.
#
# WHY THIS EXISTS
# The guard runs on EVERY Bash and Read tool call. Starting CPython costs ~16 ms
# no matter what the guard then decides — measured against `python3 -c pass`, ~90%
# of that is interpreter startup, not guard logic. Over a busy session (~10k tool
# calls) that is minutes of blocking wall-clock spent proving `cargo build` is fine.
#
# So: a byte-level pre-filter answers the only question that can skip the
# interpreter — "could this payload possibly trip ANY of guard.py's rules?" If not,
# exit 0 immediately. If it might, hand off to guard.py, which remains the sole
# authority on what is actually blocked.
#
# Measured on the author's machine (median per call):
#   python3 guard.py     17.5 ms          (every call)
#   this script           3.9 ms fast path / 20.8 ms delegated
# On a real 8k-command corpus the fast path takes 90.5% of calls -> ~5.5 ms
# effective, ~3.2x faster overall. The delegated path is ~5 ms slower than before;
# that is the trade, and it only applies to the ~9% of calls that could be unsafe.
#
# THE INVARIANT
# TRIGGERS must be a strict SUPERSET of every condition guard.py can block on.
# Over-matching is free (you just pay the interpreter, exactly as before).
# Under-matching is a silent security hole. Every trigger below is annotated with
# the guard.py rule it covers; if you add a rule there, add its token here.
# tests/test_autonomous_mode.sh asserts both entrypoints return identical verdicts,
# on hand-written cases and on a mixed corpus.
#
# Contract (unchanged from guard.py):
#   stdin  = JSON  {"tool_name": ..., "tool_input": {...}}
#   exit 0 = allow;  exit 2 = block (stderr is shown back to Claude)
#
# Unlike guard.py — which fails OPEN on malformed input so it can never wedge a
# session — this wrapper fails CLOSED on its own infrastructure being broken
# (missing guard.py, grep unusable). Those are never normal conditions, and by
# then stdin is consumed, so there is nothing left to delegate.
#
# GUARD_TRACE=1 prints which path was taken (fastpath|delegated) to stderr — tests only.
# GUARD_PY overrides the guard.py location — tests only.

HERE=$(dirname "$0")
: "${GUARD_PY:=$HERE/guard.py}"

# A bare `python3 missing.py` exits 2, so blocking here preserves the pre-existing
# behaviour rather than silently degrading to "allow everything".
if [ ! -f "$GUARD_PY" ]; then
    printf 'BLOCKED by autonomous-mode guard: guard.py not found at %s\n' "$GUARD_PY" >&2
    exit 2
fi

# Each alternative maps to a guard.py rule. Keep in sync with check_bash() and
# touches_secret(). Deliberately loose — precision is guard.py's job, not ours.
# ('su''do' is split so this file does not trip a guard scanning its own source.)
TRIGGERS='id_rsa|id_ed25519|id_ecdsa|id_dsa'      # KEY: private keys
TRIGGERS="$TRIGGERS"'|\.pem|\.ppk|\.p12|\.pfx'    # KEY: cert/key bundles
TRIGGERS="$TRIGGERS"'|\.ssh/|\.gnupg/'            # KEY: credential dirs
TRIGGERS="$TRIGGERS"'|\.aws/credentials'          # KEY: cloud creds
TRIGGERS="$TRIGGERS"'|\.env'                      # ENV: dotenv files
TRIGGERS="$TRIGGERS"'|su''do'                     # privilege escalation
TRIGGERS="$TRIGGERS"'|mkfs'                       # filesystem format
TRIGGERS="$TRIGGERS"'|of=/dev/'                   # dd to a block device
TRIGGERS="$TRIGGERS"'|chmod'                      # chmod 777 on system/home
TRIGGERS="$TRIGGERS"'|-delete|-exec'              # find -delete / -exec(dir) rm
TRIGGERS="$TRIGGERS"'|curl|wget|fetch'            # RCE: download piped to a shell
TRIGGERS="$TRIGGERS"'|(^|[^A-Za-z0-9_])rm([^A-Za-z0-9_]|$)'   # recursive delete
TRIGGERS="$TRIGGERS"'|git[[:space:]]+(push|reset|clean)'      # history-destroying git
TRIGGERS="$TRIGGERS"'|\([[:space:]]*\)[[:space:]]*\{'         # fork bomb shape

# One process does both jobs: it reads stdin and re-emits the payload only when a
# trigger matches, so the fast path costs a single fork rather than cat + grep.
#   -z  treat the whole payload as ONE record, so patterns still match across
#       newlines in a pretty-printed payload (plain grep is line-based and would
#       miss `git\npush`)
#   -a  never treat the payload as binary
payload=$(LC_ALL=C grep -zaiE "$TRIGGERS")
rc=$?

if [ "$rc" -eq 1 ]; then
    # Definitive "no trigger present" — the only case that earns the fast path.
    [ "${GUARD_TRACE:-}" = 1 ] && printf 'guard: fastpath\n' >&2
    exit 0
fi

if [ "$rc" -gt 1 ]; then
    # grep itself failed. stdin is already consumed, so we cannot delegate; the
    # only safe answer is to block and say why.
    printf 'BLOCKED by autonomous-mode guard: pre-filter failed (grep exit %s)\n' "$rc" >&2
    exit 2
fi

[ "${GUARD_TRACE:-}" = 1 ] && printf 'guard: delegated\n' >&2
printf '%s' "$payload" | python3 "$GUARD_PY"
exit $?
