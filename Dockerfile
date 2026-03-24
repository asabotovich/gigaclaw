FROM node:22-slim

ARG HIMALAYA_VERSION=1.2.0

RUN apt-get update && \
    apt-get install -y curl ca-certificates python3 git && \
    rm -rf /var/lib/apt/lists/*

# Install OpenClaw (pinned to last known good version before 2026.3.22 streaming changes)
RUN npm install -g openclaw@2026.3.13

# Install Himalaya
RUN ARCH=$(uname -m) && \
    case "$ARCH" in \
      x86_64)  HA="x86_64-linux" ;; \
      aarch64) HA="aarch64-linux" ;; \
      *) echo "Unsupported arch: $ARCH" && exit 1 ;; \
    esac && \
    curl -fsSL "https://github.com/pimalaya/himalaya/releases/download/v${HIMALAYA_VERSION}/himalaya.${HA}.tgz" \
      | tar xz -C /usr/local/bin himalaya

# OpenClaw bundles the mattermost plugin internally — no separate install needed.
# Installing it additionally via "openclaw plugins install" creates a duplicate
# that causes double-handling of events (two parallel sessions per message).

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 18789

ENTRYPOINT ["/entrypoint.sh"]
