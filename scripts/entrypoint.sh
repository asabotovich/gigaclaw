#!/bin/bash
# Dispatcher: `provision` renders templates once, `gateway` (default) runs OpenClaw.
set -euo pipefail

case "${1:-gateway}" in
  provision)
    exec /usr/local/bin/provision
    ;;
  gateway)
    # Self-pair the CLI with operator.write in background (idempotent, non-fatal).
    # Must run after gateway is listening — the script waits internally.
    /usr/local/bin/self-pair-cli &
    exec openclaw gateway
    ;;
  *)
    exec "$@"
    ;;
esac
