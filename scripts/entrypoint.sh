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

    # Render himalaya config from template. Must happen here (not in provision)
    # because /root/.config/himalaya/ is outside the bind mount — a one-shot
    # provision container's filesystem is discarded on exit.
    if [ -f /opt/gigaclaw/templates/himalaya-config.toml ]; then
      mkdir -p /root/.config/himalaya
      envsubst '${EMAIL_ADDRESS} ${EMAIL_PASSWORD} ${IMAP_HOST} ${SMTP_HOST}' \
        < /opt/gigaclaw/templates/himalaya-config.toml \
        > /root/.config/himalaya/config.toml
    fi

    # Bootstrap shared Google Workspace OAuth from 3 env vars (set in
    # orchestrator's .env.template). All pilot users share one Google account;
    # the refresh token never expires unless revoked, so containers start with
    # working gog config — no per-user OAuth ritual.
    #
    # Skipped if /root/.config/gogcli/client_secret.json already exists
    # (legacy docker-compose flow mounts ./data/gog there and keeps refreshed
    # tokens on the host between restarts).
    : "${GOG_KEYRING_PASSWORD:=openclaw}"          # internal keyring encryption
    : "${GOG_ACCOUNT:=gigamegaclaw@gmail.com}"     # shared bot Google account
    export GOG_KEYRING_PASSWORD GOG_ACCOUNT
    if [ -n "${GOG_OAUTH_CLIENT_ID:-}" ] \
       && [ -n "${GOG_OAUTH_CLIENT_SECRET:-}" ] \
       && [ -n "${GOG_OAUTH_REFRESH_TOKEN:-}" ] \
       && [ ! -f /root/.config/gogcli/client_secret.json ]; then
      GOGD=/root/.config/gogcli
      mkdir -p "$GOGD/keyring"
      cat > "$GOGD/client_secret.json" <<JSON
{"installed":{"client_id":"$GOG_OAUTH_CLIENT_ID","client_secret":"$GOG_OAUTH_CLIENT_SECRET","auth_uri":"https://accounts.google.com/o/oauth2/auth","token_uri":"https://oauth2.googleapis.com/token","redirect_uris":["http://localhost"]}}
JSON
      chmod 600 "$GOGD/client_secret.json"
      gog auth credentials set "$GOGD/client_secret.json" >/dev/null
      # gog encrypts the refresh token into keyring with $GOG_KEYRING_PASSWORD.
      TOK=$(mktemp)
      cat > "$TOK" <<JSON
{"email":"$GOG_ACCOUNT","client":"default","refresh_token":"$GOG_OAUTH_REFRESH_TOKEN"}
JSON
      gog auth tokens import "$TOK" >/dev/null
      rm -f "$TOK"
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
