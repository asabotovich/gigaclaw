#!/usr/bin/env bash
# Upgrade all managed users to a new image.
# Usage: ./upgrade.sh [image-tag]
#   Default image: $GIGACLAW_IMAGE or gigaclaw:latest
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${1:-${GIGACLAW_IMAGE:-gigaclaw:latest}}"

echo "==> Pulling $IMAGE"
docker pull "$IMAGE" || echo "(pull skipped — using local image)"

echo "==> Inspecting current users"
mapfile -t users < <(docker ps -a --filter "label=gigaclaw.user" --format '{{.Label "gigaclaw.user"}}')

if [ ${#users[@]} -eq 0 ]; then
  echo "No users to upgrade."
  exit 0
fi

echo "Users: ${users[*]}"
echo ""

failed=()
for user in "${users[@]}"; do
  env_file="$SCRIPT_DIR/.env.$user"
  [ -f "$env_file" ] || { echo "!! .env.$user not found, skipping"; failed+=("$user"); continue; }

  echo "==> Upgrading $user"
  if GIGACLAW_IMAGE="$IMAGE" (cd "$SCRIPT_DIR/orchestrator" && npx clawfarm reset "$user" --env "../$env_file"); then
    echo "   ok"
  else
    echo "   FAILED"
    failed+=("$user")
  fi
done

echo ""
if [ ${#failed[@]} -eq 0 ]; then
  echo "=== All users upgraded to $IMAGE ==="
else
  echo "=== Partial success. Failed: ${failed[*]} ==="
  exit 1
fi
