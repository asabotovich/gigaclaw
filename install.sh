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

# --- Common required vars ---
common_required_vars=(
  MM_BOT_TOKEN MM_BASE_URL
  EMAIL_ADDRESS EMAIL_PASSWORD IMAP_HOST SMTP_HOST
  ADMIN_USERNAME ADMIN_NAME GATEWAY_PASSWORD
)

for var in "${common_required_vars[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: $var is not set" >&2
    exit 1
  fi
done

# --- LLM_PROVIDER and LLM_MODEL ---
: "${LLM_PROVIDER:=gigachat}"
[[ -z "${LLM_MODEL:-}" ]] && echo "ERROR: LLM_MODEL is not set" >&2 && exit 1

case "$LLM_PROVIDER" in
  gigachat)
    for var in GIGACHAT_CREDENTIALS GIGACHAT_BASE_URL GIGACHAT_AUTH_URL; do
      [[ -z "${!var:-}" ]] && echo "ERROR: $var required for LLM_PROVIDER=gigachat" >&2 && exit 1
    done
    COMPOSE_PROFILES="gigachat"
    ;;
  openrouter)
    [[ -z "${OPENROUTER_API_KEY:-}" ]] \
      && echo "ERROR: OPENROUTER_API_KEY required for LLM_PROVIDER=openrouter" >&2 && exit 1
    COMPOSE_PROFILES=""
    ;;
  *)
    echo "ERROR: unknown LLM_PROVIDER='$LLM_PROVIDER' (gigachat or openrouter)" >&2
    exit 1
    ;;
esac

# OPENROUTER_API_KEY is used for Perplexity web search in both modes; default to empty if not set
: "${OPENROUTER_API_KEY:=}"
# GigaChat vars default to empty when using openrouter
: "${GIGACHAT_CREDENTIALS:=}"
: "${GIGACHAT_BASE_URL:=}"
: "${GIGACHAT_AUTH_URL:=}"

# Public URL for Control UI (nginx / reverse proxy). Browser Origin must match.
: "${PUBLIC_ORIGIN:=http://127.0.0.1:18789}"

# HTTP (non-HTTPS) over a public IP is not a "secure context" — browser blocks device identity.
# Set to true only if you cannot use HTTPS yet (weakens device pairing). Prefer TLS + PUBLIC_ORIGIN=https://...
: "${CONTROL_UI_DISABLE_DEVICE_AUTH:=false}"
if [[ "$CONTROL_UI_DISABLE_DEVICE_AUTH" != "true" && "$CONTROL_UI_DISABLE_DEVICE_AUTH" != "false" ]]; then
  echo "ERROR: CONTROL_UI_DISABLE_DEVICE_AUTH must be true or false" >&2
  exit 1
fi

echo "==> Installing OpenClaw Agent"
echo "    MM:       $MM_BASE_URL"
echo "    Provider: $LLM_PROVIDER / $LLM_MODEL"
echo "    Email:    $EMAIL_ADDRESS"
echo "    Admin:    $ADMIN_NAME ($ADMIN_USERNAME)"
echo "    Control UI origin: $PUBLIC_ORIGIN"
echo "    Control UI disable device auth: $CONTROL_UI_DISABLE_DEVICE_AUTH"

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

  # Substitute variables
  content="${content//\{\{MM_BOT_TOKEN\}\}/$MM_BOT_TOKEN}"
  content="${content//\{\{MM_BASE_URL\}\}/$MM_BASE_URL}"
  content="${content//\{\{LLM_PROVIDER\}\}/$LLM_PROVIDER}"
  content="${content//\{\{LLM_MODEL\}\}/$LLM_MODEL}"
  content="${content//\{\{GIGACHAT_CREDENTIALS\}\}/$GIGACHAT_CREDENTIALS}"
  content="${content//\{\{GIGACHAT_BASE_URL\}\}/$GIGACHAT_BASE_URL}"
  content="${content//\{\{GIGACHAT_AUTH_URL\}\}/$GIGACHAT_AUTH_URL}"
  content="${content//\{\{OPENROUTER_API_KEY\}\}/$OPENROUTER_API_KEY}"
  content="${content//\{\{EMAIL_ADDRESS\}\}/$EMAIL_ADDRESS}"
  content="${content//\{\{EMAIL_PASSWORD\}\}/$EMAIL_PASSWORD}"
  content="${content//\{\{IMAP_HOST\}\}/$IMAP_HOST}"
  content="${content//\{\{SMTP_HOST\}\}/$SMTP_HOST}"
  content="${content//\{\{ADMIN_USERNAME\}\}/$ADMIN_USERNAME}"
  content="${content//\{\{ADMIN_NAME\}\}/$ADMIN_NAME}"
  content="${content//\{\{GATEWAY_PASSWORD\}\}/$GATEWAY_PASSWORD}"
  content="${content//\{\{PUBLIC_ORIGIN\}\}/$PUBLIC_ORIGIN}"
  content="${content//\{\{CONTROL_UI_DISABLE_DEVICE_AUTH\}\}/$CONTROL_UI_DISABLE_DEVICE_AUTH}"

  # Process conditional blocks: {{#provider}}...{{/provider}}
  # Active provider: keep content, strip markers
  # Inactive providers: remove entire block including content
  for p in gigachat openrouter; do
    if [[ "$p" == "$LLM_PROVIDER" ]]; then
      content=$(printf '%s\n' "$content" | grep -v "^{{#${p}}}$\|^{{/${p}}}$")
    else
      content=$(printf '%s\n' "$content" | awk "/^\{\{#${p}\}\}/{skip=1;next} /^\{\{\/${p}\}\}/{skip=0;next} !skip{print}")
    fi
  done

  printf '%s\n' "$content" > "$dst"
}

mkdir -p "$SCRIPT_DIR/build"

render_template "$SCRIPT_DIR/configs/openclaw.json.tpl"        "$SCRIPT_DIR/build/openclaw.json"
render_template "$SCRIPT_DIR/configs/gpt2giga.env.tpl"         "$SCRIPT_DIR/build/.env.gpt2giga"
render_template "$SCRIPT_DIR/configs/himalaya-config.toml.tpl" "$SCRIPT_DIR/build/himalaya-config.toml"
render_template "$SCRIPT_DIR/workspace/AGENTS.md"              "$SCRIPT_DIR/build/AGENTS.md"
render_template "$SCRIPT_DIR/workspace/TOOLS.md"               "$SCRIPT_DIR/build/TOOLS.md"
render_template "$SCRIPT_DIR/workspace/USER.md.tpl"            "$SCRIPT_DIR/build/USER.md"

# Apply local overrides (local/ is gitignored — safe for private prompts)
declare -A LOCAL_TARGETS=(
  [agents]="$SCRIPT_DIR/build/AGENTS.md"
  [tools]="$SCRIPT_DIR/build/TOOLS.md"
  [user]="$SCRIPT_DIR/build/USER.md"
)
for key in "${!LOCAL_TARGETS[@]}"; do
  src="$SCRIPT_DIR/local/${key}.append.md"
  dst="${LOCAL_TARGETS[$key]}"
  if [ -f "$src" ]; then
    echo "    [local] appending ${key}.append.md"
    printf '\n' >> "$dst"
    cat "$src" >> "$dst"
  fi
done

echo "==> Configs generated."

# --- 3. Start services ---
echo "==> Starting services..."
cd "$SCRIPT_DIR"

if [[ -n "$COMPOSE_PROFILES" ]]; then
  DOCKER_COMPOSE_ARGS="--profile $COMPOSE_PROFILES"
else
  DOCKER_COMPOSE_ARGS=""
fi

mkdir -p "$SCRIPT_DIR/data/agents" "$SCRIPT_DIR/data/cron" "$SCRIPT_DIR/data/gog"

# shellcheck disable=SC2086
docker compose $DOCKER_COMPOSE_ARGS pull
# shellcheck disable=SC2086
docker compose $DOCKER_COMPOSE_ARGS up -d --build

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

  # Sync private skills from local/skills/ (gitignored)
  if [ -d "$SCRIPT_DIR/local/skills" ]; then
    echo "==> Syncing local (private) skills..."
    for skill_dir in "$SCRIPT_DIR/local/skills"/*/; do
      [ -f "$skill_dir/SKILL.md" ] || continue
      skill_name=$(basename "$skill_dir")
      docker compose exec openclaw mkdir -p "/root/.openclaw/workspace/skills/$skill_name"
      # Copy all files in the skill directory (not just SKILL.md)
      for skill_file in "$skill_dir"*; do
        [ -f "$skill_file" ] || continue
        fname=$(basename "$skill_file")
        docker compose cp "$skill_file" "openclaw:/root/.openclaw/workspace/skills/$skill_name/$fname"
      done
    done
  fi
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
echo "    Provider: $LLM_PROVIDER / $LLM_MODEL"
echo "    Admins:   $ADMIN_NAME ($ADMIN_USERNAME)"
echo ""
echo "To view logs:    docker compose logs -f openclaw"
echo "To stop:         docker compose down"
echo "To restart:      docker compose restart openclaw"
