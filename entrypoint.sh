#!/bin/bash
set -euo pipefail

WORKSPACE="/root/.openclaw/workspace"
INITIAL_WORKSPACE="/initial-workspace"

# Copy openclaw.json on every start so openclaw can modify it freely
cp /root/.openclaw-config/openclaw.json /root/.openclaw/openclaw.json

BUILD_FILES="/build-files"

# On first run, copy workspace template files into the volume
if [ ! -f "$WORKSPACE/.initialized" ]; then
  echo "[entrypoint] Initializing workspace for the first time..."
  mkdir -p "$WORKSPACE/memory"
  mkdir -p "$WORKSPACE/skills/himalaya"

  # Rendered files (AGENTS.md, TOOLS.md, USER.md) come from /build-files
  cp -n "$BUILD_FILES/AGENTS.md"  "$WORKSPACE/AGENTS.md"  2>/dev/null || true
  cp -n "$BUILD_FILES/TOOLS.md"   "$WORKSPACE/TOOLS.md"   2>/dev/null || true
  cp -n "$BUILD_FILES/USER.md"    "$WORKSPACE/USER.md"    2>/dev/null || true

  # Static files from the raw workspace
  cp -n "$INITIAL_WORKSPACE/SOUL.md"    "$WORKSPACE/SOUL.md"    2>/dev/null || true
  cp -n "$INITIAL_WORKSPACE/skills/himalaya/SKILL.md" "$WORKSPACE/skills/himalaya/SKILL.md" 2>/dev/null || true

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
