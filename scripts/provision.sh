#!/bin/bash
# Renders templates from /opt/gigaclaw/templates into /root/.openclaw using env vars.
# Intended to be called as a one-shot container: `docker run --rm ... gigaclaw provision`.
set -euo pipefail

TPL="/opt/gigaclaw/templates"
OC="/root/.openclaw"
WS="$OC/workspace"

mkdir -p "$WS/memory" "$WS/skills" "$OC/agents" "$OC/cron" /root/.config/himalaya

# System config & prompts: always overwrite (env may have changed)
envsubst < "$TPL/openclaw.json"            > "$OC/openclaw.json"
envsubst < "$TPL/AGENTS.md"                > "$WS/AGENTS.md"
envsubst < "$TPL/TOOLS.md"                 > "$WS/TOOLS.md"
envsubst < "$TPL/himalaya-config.toml"     > /root/.config/himalaya/config.toml

# User data: seed on first run only (user/bot may edit later)
if [ ! -f "$WS/USER.md" ]; then
  envsubst < "$TPL/USER.md" > "$WS/USER.md"
fi

# Skills: copy from image. Runtime state files (e.g. issues.json) not in source are preserved.
for skill_dir in /opt/gigaclaw/skills/*/; do
  [ -d "$skill_dir" ] || continue
  skill_name=$(basename "$skill_dir")
  mkdir -p "$WS/skills/$skill_name"
  cp -r "$skill_dir"* "$WS/skills/$skill_name/" 2>/dev/null || true
done

echo "[provision] done"
