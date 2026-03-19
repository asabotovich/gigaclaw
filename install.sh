#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Load .env if present ---
if [ -f "$SCRIPT_DIR/.env" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$SCRIPT_DIR/.env"
  set +a
fi

# --- Required env vars ---
required_vars=(
  MM_BOT_TOKEN MM_BASE_URL
  GIGACHAT_CREDENTIALS GIGACHAT_BASE_URL GIGACHAT_AUTH_URL
  EMAIL_ADDRESS EMAIL_PASSWORD IMAP_HOST SMTP_HOST
  ADMIN_USERNAME ADMIN_NAME GATEWAY_PASSWORD OPENROUTER_API_KEY
)

for var in "${required_vars[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: $var is not set" >&2
    exit 1
  fi
done

echo "==> Installing OpenClaw Agent"
echo "    MM:    $MM_BASE_URL"
echo "    Email: $EMAIL_ADDRESS"
echo "    Admin: $ADMIN_NAME ($ADMIN_USERNAME)"

# --- 1. Check Docker ---
if ! command -v docker &>/dev/null; then
  echo "ERROR: Docker is not installed" >&2
  exit 1
fi
echo "    Docker: $(docker --version)"

# --- 2. Generate configs ---
echo "==> Generating configs..."

render_template() {
  local src="$1" dst="$2"
  local content
  content=$(<"$src")
  content="${content//\{\{MM_BOT_TOKEN\}\}/$MM_BOT_TOKEN}"
  content="${content//\{\{MM_BASE_URL\}\}/$MM_BASE_URL}"
  content="${content//\{\{GIGACHAT_CREDENTIALS\}\}/$GIGACHAT_CREDENTIALS}"
  content="${content//\{\{GIGACHAT_BASE_URL\}\}/$GIGACHAT_BASE_URL}"
  content="${content//\{\{GIGACHAT_AUTH_URL\}\}/$GIGACHAT_AUTH_URL}"
  content="${content//\{\{EMAIL_ADDRESS\}\}/$EMAIL_ADDRESS}"
  content="${content//\{\{EMAIL_PASSWORD\}\}/$EMAIL_PASSWORD}"
  content="${content//\{\{IMAP_HOST\}\}/$IMAP_HOST}"
  content="${content//\{\{SMTP_HOST\}\}/$SMTP_HOST}"
  content="${content//\{\{ADMIN_USERNAME\}\}/$ADMIN_USERNAME}"
  content="${content//\{\{ADMIN_NAME\}\}/$ADMIN_NAME}"
  content="${content//\{\{GATEWAY_PASSWORD\}\}/$GATEWAY_PASSWORD}"
  content="${content//\{\{OPENROUTER_API_KEY\}\}/$OPENROUTER_API_KEY}"
  echo "$content" > "$dst"
}

mkdir -p "$SCRIPT_DIR/build"

render_template "$SCRIPT_DIR/configs/openclaw.json.tpl"        "$SCRIPT_DIR/build/openclaw.json"
render_template "$SCRIPT_DIR/configs/gpt2giga.env.tpl"         "$SCRIPT_DIR/build/.env.gpt2giga"
render_template "$SCRIPT_DIR/configs/himalaya-config.toml.tpl" "$SCRIPT_DIR/build/himalaya-config.toml"
render_template "$SCRIPT_DIR/workspace/AGENTS.md"              "$SCRIPT_DIR/build/AGENTS.md"
render_template "$SCRIPT_DIR/workspace/TOOLS.md"               "$SCRIPT_DIR/build/TOOLS.md"
render_template "$SCRIPT_DIR/workspace/USER.md.tpl"            "$SCRIPT_DIR/build/USER.md"

echo "==> Configs generated."

# --- 3. Start services ---
echo "==> Starting services..."
cd "$SCRIPT_DIR"
docker compose pull
docker compose up -d --build

# Update AGENTS.md and skills in running container (non-destructive)
if docker compose ps openclaw | grep -q "Up"; then
  echo "==> Unlocking workspace files..."
  docker compose exec openclaw sh -c 'chmod -R u+w /root/.openclaw/workspace/' 2>/dev/null || true

  echo "==> Updating AGENTS.md, TOOLS.md, USER.md in container..."
  docker compose cp build/AGENTS.md openclaw:/root/.openclaw/workspace/AGENTS.md
  docker compose cp build/TOOLS.md openclaw:/root/.openclaw/workspace/TOOLS.md
  docker compose cp build/USER.md openclaw:/root/.openclaw/workspace/USER.md
  docker compose exec openclaw chmod 444 /root/.openclaw/workspace/AGENTS.md /root/.openclaw/workspace/TOOLS.md /root/.openclaw/workspace/USER.md

  echo "==> Syncing skills to container (existing data is not overwritten)..."
  for skill_dir in "$SCRIPT_DIR/workspace/skills"/*/; do
    skill_name=$(basename "$skill_dir")
    docker compose exec openclaw mkdir -p "/root/.openclaw/workspace/skills/$skill_name"
    docker compose cp "$skill_dir/SKILL.md" "openclaw:/root/.openclaw/workspace/skills/$skill_name/SKILL.md"
  done
fi

echo "==> Waiting for services to start..."
sleep 10

# --- 4. Verify ---
echo "==> Checking status..."
docker compose ps

echo ""
echo "=== Installation complete ==="
echo "    Gateway:  http://127.0.0.1:18789/"
echo "    Bot connected to: $MM_BASE_URL"
echo "    Admins: $ADMIN_NAME ($ADMIN_USERNAME)"
echo ""
echo "To view logs:    docker compose logs -f openclaw"
echo "To stop:         docker compose down"
echo "To restart:      docker compose restart openclaw"
