{
  "models": {
    "mode": "replace",
    "providers": {
      "openrouter": {
        "baseUrl": "https://openrouter.ai/api/v1",
        "apiKey": "${OPENROUTER_API_KEY}",
        "models": [
          { "id": "${LLM_MODEL}", "name": "${LLM_MODEL}" }
        ]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "openrouter/${LLM_MODEL}"
      },
      "workspace": "/root/.openclaw/workspace",
      "userTimezone": "Europe/Moscow",
      "envelopeTimezone": "Europe/Moscow",
      "compaction": { "mode": "safeguard" },
      "maxConcurrent": 4,
      "subagents": { "maxConcurrent": 8 },
      "models": {
        "openrouter/${LLM_MODEL}": { "alias": "${LLM_MODEL}" }
      }
    }
  },
  "session": {
    "dmScope": "per-channel-peer"
  },
  "tools": {
    "deny": [],
    "web": {
      "search": {
        "enabled": true,
        "provider": "perplexity",
        "perplexity": {
          "apiKey": "${OPENROUTER_API_KEY}",
          "baseUrl": "https://openrouter.ai/api/v1",
          "model": "perplexity/sonar-pro"
        }
      }
    }
  },
  "messages": {
    "ackReactionScope": "group-mentions"
  },
  "commands": {
    "native": "auto",
    "nativeSkills": "auto",
    "restart": true,
    "ownerDisplay": "raw"
  },
  "hooks": {
    "internal": {
      "enabled": true,
      "entries": {
        "bootstrap-extra-files": { "enabled": true },
        "session-memory": { "enabled": true },
        "boot-md": { "enabled": true }
      }
    }
  },
  "channels": {
    "mattermost": {
      "enabled": true,
      "botToken": "${MM_BOT_TOKEN}",
      "baseUrl": "${MM_BASE_URL}",
      "dmPolicy": "allowlist",
      "allowFrom": ["${ADMIN_USERNAME}"],
      "groupPolicy": "allowlist",
      "groupAllowFrom": ["${ADMIN_USERNAME}"],
      "dangerouslyAllowNameMatching": true,
      "chatmode": "oncall",
      "replyToMode": "first",
      "blockStreaming": false
    }
  },
  "gateway": {
    "port": 18789,
    "mode": "local",
    "bind": "lan",
    "auth": { "mode": "password", "password": "${GATEWAY_PASSWORD}" },
    "controlUi": {
      "allowedOrigins": [
        "http://127.0.0.1:18789",
        "http://localhost:18789",
        "http://127.0.0.1",
        "http://localhost",
        "${PUBLIC_ORIGIN}"
      ],
      "dangerouslyDisableDeviceAuth": ${CONTROL_UI_DISABLE_DEVICE_AUTH}
    }
  },
  "skills": {
    "entries": {
      "himalaya": { "enabled": true },
      "gog": { "enabled": true }
    }
  },
  "plugins": {
    "allow": ["mattermost"],
    "entries": {
      "mattermost": { "enabled": true }
    }
  }
}
