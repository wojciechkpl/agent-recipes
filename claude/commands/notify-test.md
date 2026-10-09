---
description: "Send a test Signal notification using this plugin's notification options"
allowed-tools: Bash
---

# Notify test

Send one test message through the same code path the notification hooks use, and
report the result.

Run this exactly as written. Claude Code fills in the `${...}` placeholders; an option
that was never set stays as literal text, which the script treats as "not set" — do
not edit or "fix" those placeholders.

```bash
CLAUDE_PLUGIN_OPTION_NOTIFY_ENABLED='${user_config.notify_enabled}' \
CLAUDE_PLUGIN_OPTION_NOTIFY_SIGNAL_RPC_URL='${user_config.notify_signal_rpc_url}' \
CLAUDE_PLUGIN_OPTION_NOTIFY_SIGNAL_ACCOUNT='${user_config.notify_signal_account}' \
CLAUDE_PLUGIN_OPTION_NOTIFY_RECIPIENT='${user_config.notify_recipient}' \
CLAUDE_PLUGIN_OPTION_NOTIFY_ALLOW_REMOTE='${user_config.notify_allow_remote}' \
python3 "${CLAUDE_PLUGIN_ROOT}/hooks/notify.py" test
```

Report the `OK` / `FAIL` line verbatim, plus any `note:` line.

- `OK` — tell the user to check Signal on their phone.
- `FAIL` with `URLError` / `Connection refused` — the signal-cli daemon is not running
  or the `notify_signal_rpc_url` option points at the wrong port.
- `FAIL` with `signal-cli error` — the daemon answered but could not send; show the
  error text (an unregistered account or an unknown recipient are the usual causes).
- `FAIL` with `non-loopback` — the URL is not on this machine; that needs the
  `notify_allow_remote` option.

Setup steps are in `docs/TUTORIAL-notifications-sync.md` of the agent-recipes repo.
