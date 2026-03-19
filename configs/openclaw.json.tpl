{
  "models": {
    "mode": "replace",
    "providers": {
      "gigachat": {
        "baseUrl": "http://gpt2giga:8090/v1",
        "apiKey": "any",
        "api": "openai-completions",
        "models": [
          { "id": "GigaChat-3-Ultra", "name": "GigaChat 3 Ultra" },
          { "id": "GigaChat-2-Max", "name": "GigaChat 2 Max" },
          { "id": "GigaChat-Pro", "name": "GigaChat Pro" },
          { "id": "GigaChat", "name": "GigaChat" }
        ]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "gigachat/GigaChat-3-Ultra"
      },
      "workspace": "/root/.openclaw/workspace",
      "compaction": { "mode": "safeguard" },
      "maxConcurrent": 4,
      "subagents": { "maxConcurrent": 8 },
      "models": {
        "gigachat/GigaChat-3-Ultra": { "alias": "GigaChat 3 Ultra" },
        "gigachat/GigaChat-2-Max":   { "alias": "GigaChat 2 Max" },
        "gigachat/GigaChat-Pro":     { "alias": "GigaChat Pro" },
        "gigachat/GigaChat":         { "alias": "GigaChat" }
      }
    }
  },
  "session": {
    "dmScope": "per-channel-peer"
  },
  "tools": {
    "deny": ["apply_patch", "process"],
    "web": {
      "search": {
        "enabled": true,
        "provider": "perplexity",
        "perplexity": {
          "apiKey": "{{OPENROUTER_API_KEY}}",
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
      "botToken": "{{MM_BOT_TOKEN}}",
      "baseUrl": "{{MM_BASE_URL}}",
      "dmPolicy": "open",
      "groupPolicy": "open",
      "chatmode": "oncall",
      "replyToMode": "first"
    }
  },
  "gateway": {
    "port": 18789,
    "mode": "local",
    "bind": "lan",
    "auth": { "mode": "password", "password": "{{GATEWAY_PASSWORD}}" },
    "controlUi": { }
  },
  "skills": {
    "entries": {
      "himalaya": { "enabled": true }
    }
  },
  "plugins": {
    "allow": ["mattermost"],
    "entries": {
      "mattermost": { "enabled": true }
    }
  }
}
