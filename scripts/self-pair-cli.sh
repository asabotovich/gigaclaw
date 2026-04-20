#!/bin/bash
# Self-pair the in-container CLI with full operator scope.
#
# OpenClaw's gateway auto-pairs itself (as `clientMode=backend`) with only
# `operator.read` for channels.status polling. Any CLI invocation (`openclaw
# cron add`, etc.) runs as a separate `clientMode=cli` client that, by default,
# creates a pending pairing request and gets blocked with "pairing required".
#
# In prod (OpenShift Orchestrator) that approval would be issued by the outer
# harness. In our single-user container there's no outer harness — so we
# self-approve here using OpenClaw's local loopback pairing fallback:
# `openclaw devices approve` on 127.0.0.1 works without a prior paired device
# holding operator.pairing scope.
#
# This is safe in our model: the container is fully owned by one user; the CLI
# running inside it cannot be invoked by anyone except the bot we already trust.
set -euo pipefail

PAIRED=/root/.openclaw/devices/paired.json
PENDING=/root/.openclaw/devices/pending.json
LOG="[self-pair-cli]"

# Wait for gateway to be ready
for i in $(seq 1 30); do
  if curl -sf -o /dev/null -m 1 "http://127.0.0.1:18789/__openclaw__/health" 2>/dev/null; then
    break
  fi
  sleep 1
done

# Idempotent: skip if a CLI-mode device is already paired with operator.write
if [ -f "$PAIRED" ] && jq -e '
  to_entries[] | select(
    (.value.clientMode // .value.clientId) == "cli"
    and (.value.approvedScopes // [] | contains(["operator.write"]))
  )
' "$PAIRED" >/dev/null 2>&1; then
  echo "$LOG already paired, skipping" >&2
  exit 0
fi

# Trigger a CLI connection so it registers a pending request.
# We expect this call to fail with "pairing required" — that's fine, we only
# need it to create a pending entry.
echo "$LOG triggering CLI pairing request…" >&2
openclaw cron list >/dev/null 2>&1 || true

# Brief settle so the pending.json write completes
sleep 1

# Find the pending request ID for a cli-mode operator
if [ ! -f "$PENDING" ]; then
  echo "$LOG no pending.json created, skipping" >&2
  exit 0
fi

REQ=$(jq -r '
  to_entries[]
  | select(
      (.value.clientMode // .value.clientId) == "cli"
      and (.value.roles // [] | contains(["operator"]))
    )
  | .key
' "$PENDING" | head -1)

if [ -z "$REQ" ] || [ "$REQ" = "null" ]; then
  echo "$LOG no CLI operator pending request found, skipping" >&2
  exit 0
fi

echo "$LOG approving request $REQ" >&2
if openclaw devices approve "$REQ" 2>&1; then
  echo "$LOG success — CLI is now paired with full operator scope" >&2
else
  echo "$LOG approve failed (non-fatal)" >&2
fi
