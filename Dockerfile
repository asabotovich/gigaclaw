FROM node:22-slim

ARG HIMALAYA_VERSION=1.2.0

RUN apt-get update && \
    apt-get install -y curl ca-certificates python3 git && \
    rm -rf /var/lib/apt/lists/*

# Install OpenClaw
RUN npm install -g openclaw

# Install Himalaya
RUN ARCH=$(uname -m) && \
    case "$ARCH" in \
      x86_64)  HA="x86_64-linux" ;; \
      aarch64) HA="aarch64-linux" ;; \
      *) echo "Unsupported arch: $ARCH" && exit 1 ;; \
    esac && \
    curl -fsSL "https://github.com/pimalaya/himalaya/releases/download/v${HIMALAYA_VERSION}/himalaya.${HA}.tgz" \
      | tar xz -C /usr/local/bin himalaya

# Pre-install plugins during build
RUN mkdir -p /root/.openclaw && \
    echo '{"models":{"mode":"merge"},"agents":{"defaults":{"model":{"primary":"gigachat/GigaChat-3-Ultra"},"workspace":"/root/.openclaw/workspace"}},"plugins":{"allow":["mattermost"]}}' \
      > /root/.openclaw/openclaw.json && \
    openclaw plugins install @openclaw/mattermost 2>/dev/null || true && \
    rm /root/.openclaw/openclaw.json

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 18789

ENTRYPOINT ["/entrypoint.sh"]
