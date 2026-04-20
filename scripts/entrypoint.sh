#!/bin/bash
# Dispatcher: `provision` renders templates once, `gateway` (default) runs OpenClaw.
set -euo pipefail

case "${1:-gateway}" in
  provision)
    exec /usr/local/bin/provision
    ;;
  gateway)
    # If boot-md has fired at least once in the past (evidenced by any
    # boot-*.jsonl session file on disk), disable the hook before the gateway
    # reads the config. Keeps restarts silent without asking the agent prompt
    # to manage this state. provision.sh re-enables it on every reset, so
    # a fresh provision always greets the owner exactly once.
    if compgen -G '/root/.openclaw/agents/main/sessions/boot-*.jsonl' > /dev/null; then
      OC=/root/.openclaw/openclaw.json
      if [ -f "$OC" ]; then
        jq '.hooks.internal.entries["boot-md"].enabled = false' "$OC" > "$OC.new" \
          && mv "$OC.new" "$OC"
      fi
    fi

    # Self-pair the CLI with operator.write in background (idempotent, non-fatal).
    # Must run after gateway is listening — the script waits internally.
    /usr/local/bin/self-pair-cli &
    exec openclaw gateway
    ;;
  *)
    exec "$@"
    ;;
esac
