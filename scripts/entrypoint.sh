#!/bin/bash
# Dispatcher: `provision` renders templates once, `gateway` (default) runs OpenClaw.
set -euo pipefail

case "${1:-gateway}" in
  provision)
    exec /usr/local/bin/provision
    ;;
  gateway)
    # Onboarding marker — deterministic gate for the boot-md hook.
    #   Marker absent → keep BOOT.md, boot-md runs, bot greets owner.
    #   Marker present → remove BOOT.md, boot-md becomes a no-op (no greeting).
    # We drop the marker ourselves 60s after startup, which is well past the
    # window in which boot-md fires. That way BOOT.md stays focused on "what
    # to say" and doesn't need shell plumbing inside the agent prompt.
    MARKER=/root/.openclaw/workspace/.onboarding-greeted
    if [ -f "$MARKER" ]; then
      rm -f /root/.openclaw/workspace/BOOT.md
    else
      ( sleep 60 && touch "$MARKER" ) &
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
