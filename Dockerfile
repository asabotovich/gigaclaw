# syntax=docker/dockerfile:1.4
FROM node:22

ARG HIMALAYA_VERSION=1.2.0
ARG GOGCLI_VERSION=0.12.0
ARG GLAB_VERSION=1.92.1

# npm registry connections drop on flaky links (Docker Desktop vpnkit, corp
# VPN, etc). These env vars apply to every npm call in this image: longer
# fetch timeouts, more retries, fewer parallel sockets so each request gets
# more bandwidth and is less likely to hit a connection cap.
ENV NPM_CONFIG_FETCH_RETRIES=10
ENV NPM_CONFIG_FETCH_RETRY_MINTIMEOUT=20000
ENV NPM_CONFIG_FETCH_RETRY_MAXTIMEOUT=300000
ENV NPM_CONFIG_FETCH_TIMEOUT=600000
ENV NPM_CONFIG_MAXSOCKETS=2

# Force apt metadata fetches over HTTPS so corp network middleboxes that
# rewrite plain-HTTP traffic can't invalidate GPG signatures. ca-certificates
# and curl are already in node:22 (full), so HTTPS works from the first call.
RUN sed -i 's|http://deb.debian.org|https://deb.debian.org|g' /etc/apt/sources.list.d/debian.sources && \
    apt-get update && \
    apt-get install -y --no-install-recommends python3 python3-requests python3-dotenv jq gettext-base && \
    rm -rf /var/lib/apt/lists/*

# Install OpenClaw
RUN npm install -g openclaw@2026.4.14

# Install Himalaya
RUN ARCH=$(uname -m) && \
    case "$ARCH" in \
      x86_64)  HA="x86_64-linux" ;; \
      aarch64) HA="aarch64-linux" ;; \
      *) echo "Unsupported arch: $ARCH" && exit 1 ;; \
    esac && \
    curl -fsSL "https://github.com/pimalaya/himalaya/releases/download/v${HIMALAYA_VERSION}/himalaya.${HA}.tgz" \
      | tar xz -C /usr/local/bin himalaya

# Install gog (Google Workspace CLI)
RUN ARCH=$(uname -m) && \
    case "$ARCH" in \
      x86_64)  GA="linux_amd64" ;; \
      aarch64) GA="linux_arm64" ;; \
      *) echo "Unsupported arch: $ARCH" && exit 1 ;; \
    esac && \
    curl -fsSL "https://github.com/steipete/gogcli/releases/download/v${GOGCLI_VERSION}/gogcli_${GOGCLI_VERSION}_${GA}.tar.gz" \
      | tar xz -C /usr/local/bin gog

# Install glab (GitLab CLI) — skill workspace/skills/glab uses it
RUN ARCH=$(uname -m) && \
    case "$ARCH" in \
      x86_64)  DA="amd64" ;; \
      aarch64) DA="arm64" ;; \
      *) echo "Unsupported arch: $ARCH" && exit 1 ;; \
    esac && \
    curl -fsSL -o /tmp/glab.deb "https://gitlab.com/api/v4/projects/gitlab-org%2Fcli/packages/generic/glab/${GLAB_VERSION}/glab_${GLAB_VERSION}_linux_${DA}.deb" && \
    dpkg -i /tmp/glab.deb && rm /tmp/glab.deb

# OpenClaw bundles the mattermost plugin internally — no separate install needed.
# Installing it additionally via "openclaw plugins install" creates a duplicate
# that causes double-handling of events (two parallel sessions per message).

# Templates & skills baked into the image — materialized per-user by `provision` subcommand
COPY configs/patches.jq               /opt/gigaclaw/patches.jq
COPY configs/himalaya-config.toml.tpl /opt/gigaclaw/templates/himalaya-config.toml
COPY workspace/AGENTS.md              /opt/gigaclaw/templates/AGENTS.md
COPY workspace/TOOLS.md               /opt/gigaclaw/templates/TOOLS.md
COPY workspace/SOUL.md                /opt/gigaclaw/templates/SOUL.md
COPY workspace/USER.md.tpl            /opt/gigaclaw/templates/USER.md
COPY workspace/BOOT.md                /opt/gigaclaw/templates/BOOT.md
COPY workspace/skills                 /opt/gigaclaw/skills

# Custom OpenClaw channel plugin that bridges outbound messages to the
# gigaclaw-orchestrator /push endpoint. See plugins.load.paths in patches.jq.
# Plugin ships as TypeScript; compile here against the already-global
# openclaw install (it's huge, so we symlink instead of re-installing it
# per-plugin). Only dev deps (typescript, @types/node) land in node_modules.
COPY packages/openclaw-orchestrator-channel /opt/gigaclaw/extensions/orchestrator-channel
# BuildKit cache mount on /root/.npm survives across `docker build` runs, so a
# transient ECONNRESET mid-install doesn't lose already-downloaded tarballs.
# `--maxsockets=2` gentles parallel TCP — Docker Desktop's vpnkit/qemu network
# tends to drop sustained registry connections on flaky links. The fetch-*
# flags wait minutes instead of seconds before giving up.
RUN --mount=type=cache,target=/root/.npm \
    cd /opt/gigaclaw/extensions/orchestrator-channel && \
    npm install --no-audit --no-fund --prefer-offline \
      --fetch-retries=10 \
      --fetch-retry-mintimeout=20000 \
      --fetch-retry-maxtimeout=300000 \
      --fetch-timeout=600000 \
      --maxsockets=2 && \
    mkdir -p node_modules && \
    ln -s /usr/local/lib/node_modules/openclaw node_modules/openclaw && \
    npm run build && \
    rm -rf node_modules

COPY scripts/provision.sh    /usr/local/bin/provision
COPY scripts/entrypoint.sh   /usr/local/bin/entrypoint
COPY scripts/self-pair-cli.sh /usr/local/bin/self-pair-cli
RUN chmod +x /usr/local/bin/provision /usr/local/bin/entrypoint /usr/local/bin/self-pair-cli

EXPOSE 18789

ENTRYPOINT ["/usr/local/bin/entrypoint"]
CMD ["gateway"]
