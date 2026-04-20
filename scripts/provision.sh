#!/bin/bash
# Renders per-user workspace + patches openclaw.json with Orchestrator-owned fields.
# Intended to be called as a one-shot container: `docker run --rm ... gigaclaw provision`.
#
# Fields NOT listed in /opt/gigaclaw/patches.jq are never touched — that includes
# tokens the bot saved during onboarding (skills.entries.*.env.*) and any user tweaks.
set -euo pipefail

TPL="/opt/gigaclaw/templates"
OC="/root/.openclaw"
WS="$OC/workspace"

mkdir -p "$WS/memory" "$WS/skills" "$OC/agents" "$OC/cron" /root/.config/himalaya

# --- System prompts (always overwritten — no user content) ---
envsubst < "$TPL/AGENTS.md"            > "$WS/AGENTS.md"
envsubst < "$TPL/TOOLS.md"             > "$WS/TOOLS.md"
envsubst < "$TPL/himalaya-config.toml" > /root/.config/himalaya/config.toml

# --- User data: seed once, never overwrite ---
[ -f "$WS/USER.md" ] || envsubst < "$TPL/USER.md" > "$WS/USER.md"

# --- BOOT.md: always overwrite. Triggers on gateway startup via boot-md hook.
#     Content changes between releases must take effect immediately on reset,
#     so we re-render every provision (no runtime state lives inside BOOT.md).
envsubst < "$TPL/BOOT.md" > "$WS/BOOT.md"

# --- Skills (always overwrite skill *code*; runtime state files not in source are preserved) ---
for skill_dir in /opt/gigaclaw/skills/*/; do
  [ -d "$skill_dir" ] || continue
  skill_name=$(basename "$skill_dir")
  mkdir -p "$WS/skills/$skill_name"
  cp -r "$skill_dir"* "$WS/skills/$skill_name/" 2>/dev/null || true
done

# --- openclaw.json: if absent, seed empty {}; then apply Orchestrator-owned patches ---
[ -f "$OC/openclaw.json" ] || echo '{}' > "$OC/openclaw.json"
jq -f /opt/gigaclaw/patches.jq "$OC/openclaw.json" > "$OC/openclaw.json.new"
mv "$OC/openclaw.json.new" "$OC/openclaw.json"

echo "[provision] done"
