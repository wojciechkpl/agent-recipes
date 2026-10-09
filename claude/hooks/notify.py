#!/usr/bin/env python3
"""Signal notifier for Claude Code hooks (agent-recipes plugin).

Usage (hook JSON on stdin):
  notify.py mark          UserPromptSubmit — record when the turn started
  notify.py stop          Stop             — "finished" ping for long turns
  notify.py notification  Notification     — "waiting on you" ping
  notify.py test          no stdin needed  — send a test message, print the result

Transport: one JSON-RPC `send` call to a local signal-cli daemon
(`signal-cli daemon --http 127.0.0.1:18080`). Stdlib only.

Configuration comes from plugin options, exported to hook processes as
CLAUDE_PLUGIN_OPTION_<KEY> (only for options the user has set — defaults live here):
  NOTIFY_ENABLED          true|false (default false — nothing is sent until opted in)
  NOTIFY_SIGNAL_RPC_URL   default http://127.0.0.1:18080/api/v1/rpc
  NOTIFY_SIGNAL_ACCOUNT   account the daemon sends from (needed only for multi-account daemons)
  NOTIFY_RECIPIENT        number/username to notify; empty = Note to Self (silent on the phone)
  NOTIFY_MIN_SECONDS      Stop pings only for turns at least this long (default 120)
  NOTIFY_INCLUDE_SUMMARY  true = append the first 200 chars of Claude's last message
  NOTIFY_ALLOW_REMOTE     true = permit a non-loopback RPC URL

Contract: ALWAYS exits 0 for hook events. A Stop hook that exits 2 would stop
Claude from stopping; a notifier must never influence the session.
"""
import json
import os
import re
import socket
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

DEFAULT_URL = "http://127.0.0.1:18080/api/v1/rpc"
DEFAULT_MIN_SECONDS = 120  # keep both in step with userConfig in plugin.json
DEDUPE_SECONDS = 300      # idle_prompt right after a Stop ping is the same news
RATE_LIMIT_SECONDS = 30   # same kind, same session
STALE_STATE_SECONDS = 7 * 86400
LOOPBACK = {"127.0.0.1", "localhost", "::1"}
ATTENTION_TYPES = {"permission_prompt", "idle_prompt", "agent_needs_input",
                   "elicitation_dialog", "elicitation_url_dialog"}


def opt(key, default=""):
    """A plugin option. Hooks get CLAUDE_PLUGIN_OPTION_<KEY> only for options the user
    has set; the /notify-test command passes '${user_config.<key>}', which Claude Code
    leaves as literal text when the option is unset. Both mean "use the default"."""
    value = os.environ.get("CLAUDE_PLUGIN_OPTION_" + key, "").strip()
    if not value or value.startswith("${user_config."):
        return default
    return value


def truthy(value):
    return str(value).strip().lower() in ("1", "true", "yes", "on")


def state_dir():
    base = os.environ.get("CLAUDE_PLUGIN_DATA") or os.path.join(
        os.path.expanduser("~"), ".claude", "plugins", "data", "agent-recipes")
    path = Path(base) / "notify"
    path.mkdir(parents=True, exist_ok=True)
    return path


def state_file(session_id):
    safe = re.sub(r"[^A-Za-z0-9_-]", "_", session_id or "nosession")[:80]
    return state_dir() / (safe + ".json")


def load_state(session_id):
    try:
        return json.loads(state_file(session_id).read_text())
    except (OSError, ValueError):
        return {}


def save_state(session_id, state):
    state_file(session_id).write_text(json.dumps(state))


def prune_stale():
    cutoff = time.time() - STALE_STATE_SECONDS
    for path in state_dir().glob("*.json"):
        try:
            if path.stat().st_mtime < cutoff:
                path.unlink()
        except OSError:
            pass


def log(line):
    try:
        path = state_dir() / "notify.log"
        if path.exists() and path.stat().st_size > 200_000:
            path.write_text("")
        with path.open("a") as handle:
            handle.write(time.strftime("%Y-%m-%dT%H:%M:%S ") + line + "\n")
    except OSError:
        pass


def rpc_url():
    url = opt("NOTIFY_SIGNAL_RPC_URL", DEFAULT_URL)
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme not in ("http", "https"):
        raise ValueError("RPC URL must be http(s): " + url)
    if parsed.hostname not in LOOPBACK and not truthy(opt("NOTIFY_ALLOW_REMOTE")):
        raise ValueError("refusing non-loopback RPC URL (set notify_allow_remote): " + url)
    return url


def send(text):
    """POST one JSON-RPC send. Returns (ok, detail)."""
    params = {"message": text}
    recipient = opt("NOTIFY_RECIPIENT")
    if recipient:
        # notifySelf: deliver as a normal message even when the recipient is our
        # own account, so the phone raises a notification instead of a silent sync.
        params.update({"recipient": [recipient], "notifySelf": True})
    else:
        params["noteToSelf"] = True
    if opt("NOTIFY_SIGNAL_ACCOUNT"):
        params["account"] = opt("NOTIFY_SIGNAL_ACCOUNT")
    body = json.dumps({"jsonrpc": "2.0", "method": "send", "params": params,
                       "id": int(time.time())}).encode()
    try:
        request = urllib.request.Request(
            rpc_url(), data=body, headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(request, timeout=5) as response:
            reply = json.loads(response.read() or b"{}")
    except Exception as exc:  # network, URL, JSON — all reported the same way
        return False, "%s: %s" % (type(exc).__name__, exc)
    if "error" in reply:
        return False, "signal-cli error: %s" % json.dumps(reply["error"])
    return True, "sent"


def headline(payload):
    project = os.path.basename((payload.get("cwd") or os.getcwd()).rstrip("/")) or "?"
    return "[%s] %s" % (socket.gethostname().split(".")[0], project)


def fmt_duration(seconds):
    seconds = int(seconds)
    return "%dm%02ds" % divmod(seconds, 60) if seconds >= 60 else "%ds" % seconds


def summary(text):
    if not truthy(opt("NOTIFY_INCLUDE_SUMMARY")) or not text:
        return ""
    flat = " ".join(str(text).split())
    return "\n" + (flat[:200] + ("…" if len(flat) > 200 else ""))


def on_mark(payload):
    prune_stale()
    state = load_state(payload.get("session_id"))
    state["turn_start"] = time.time()
    save_state(payload.get("session_id"), state)


def on_stop(payload):
    session = payload.get("session_id")
    state = load_state(session)
    started = state.get("turn_start")
    if not started:
        return None                      # no marker: cannot tell how long it ran
    elapsed = time.time() - started
    if elapsed < float(opt("NOTIFY_MIN_SECONDS", DEFAULT_MIN_SECONDS)):
        return None
    text = "%s: finished after %s%s" % (
        headline(payload), fmt_duration(elapsed), summary(payload.get("last_assistant_message")))
    return deliver(session, state, "stop", text)


def on_notification(payload):
    kind = payload.get("notification_type") or "notification"
    if kind != "notification" and kind not in ATTENTION_TYPES:
        return None                      # auth_success, quota notices, … are not asks
    session = payload.get("session_id")
    state = load_state(session)
    since = time.time() - state.get("last_sent", 0)
    if kind == "idle_prompt" and state.get("last_kind") == "stop" and since < DEDUPE_SECONDS:
        return None
    message = " ".join(str(payload.get("message") or "needs your attention").split())[:200]
    return deliver(session, state, kind, "%s: waiting — %s" % (headline(payload), message))


def deliver(session, state, kind, text):
    since = time.time() - state.get("last_sent", 0)
    if state.get("last_kind") == kind and since < RATE_LIMIT_SECONDS:
        return None
    ok, detail = send(text)
    log("%s %s %s" % (kind, "ok" if ok else "FAIL", detail))
    if ok:
        state.update({"last_sent": time.time(), "last_kind": kind})
        save_state(session, state)
    return ok


def main(argv):
    event = argv[1] if len(argv) > 1 else ""
    if event == "test":
        ok, detail = send("[%s] agent-recipes: test notification" % socket.gethostname().split(".")[0])
        print(("OK  " if ok else "FAIL ") + detail)
        if ok and not truthy(opt("NOTIFY_ENABLED")):
            print("note: notify_enabled is off, so hooks will not send until you turn it on")
        return 0 if ok else 1
    try:
        raw = sys.stdin.read()           # always drain, so the caller never sees EPIPE
        if not truthy(opt("NOTIFY_ENABLED")):
            return 0
        payload = json.loads(raw) if raw.strip() else {}
        handler = {"mark": on_mark, "stop": on_stop, "notification": on_notification}.get(event)
        if handler:
            handler(payload)
    except Exception as exc:  # never let a notifier affect the session
        log("error %s: %s" % (type(exc).__name__, exc))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
