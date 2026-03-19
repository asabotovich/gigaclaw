#!/bin/bash
set -euo pipefail

WORKSPACE="/root/.openclaw/workspace"
INITIAL_WORKSPACE="/initial-workspace"

# Copy openclaw.json on every start so openclaw can modify it freely
cp /root/.openclaw-config/openclaw.json /root/.openclaw/openclaw.json

# On first run, copy workspace template files into the volume
if [ ! -f "$WORKSPACE/.initialized" ]; then
  echo "[entrypoint] Initializing workspace for the first time..."
  mkdir -p "$WORKSPACE/memory"
  mkdir -p "$WORKSPACE/skills/himalaya"

  cp -n "$INITIAL_WORKSPACE/AGENTS.md"  "$WORKSPACE/AGENTS.md"  2>/dev/null || true
  cp -n "$INITIAL_WORKSPACE/TOOLS.md"   "$WORKSPACE/TOOLS.md"   2>/dev/null || true
  cp -n "$INITIAL_WORKSPACE/SOUL.md"    "$WORKSPACE/SOUL.md"    2>/dev/null || true
  cp -n "$INITIAL_WORKSPACE/skills/himalaya/SKILL.md" "$WORKSPACE/skills/himalaya/SKILL.md" 2>/dev/null || true

  # Protect prompt files from bot edits
  chmod 444 "$WORKSPACE/AGENTS.md" "$WORKSPACE/TOOLS.md" "$WORKSPACE/USER.md" 2>/dev/null || true

  touch "$WORKSPACE/.initialized"
  echo "[entrypoint] Workspace initialized."
fi

# Set up himalaya config
mkdir -p /root/.config/himalaya
if [ -f /run/secrets/himalaya_config ]; then
  cp /run/secrets/himalaya_config /root/.config/himalaya/config.toml
fi

echo "[entrypoint] Starting openclaw gateway..."
exec openclaw gateway
