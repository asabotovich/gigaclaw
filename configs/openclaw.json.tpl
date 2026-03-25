{
  "models": {
    "mode": "replace",
    "providers": {
{{#gigachat}}
      "gigachat": {
        "baseUrl": "http://gpt2giga:8090/v1",
        "apiKey": "any",
        "api": "openai-completions",
        "models": [
          { "id": "{{LLM_MODEL}}", "name": "{{LLM_MODEL}}" }
        ]
      }
{{/gigachat}}
{{#openrouter}}
      "openrouter": {
        "baseUrl": "https://openrouter.ai/api/v1",
        "apiKey": "{{OPENROUTER_API_KEY}}",
        "models": [
          { "id": "{{LLM_MODEL}}", "name": "{{LLM_MODEL}}" }
        ]
      }
{{/openrouter}}
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "{{LLM_PROVIDER}}/{{LLM_MODEL}}"
      },
      "workspace": "/root/.openclaw/workspace",
      "userTimezone": "Europe/Moscow",
      "envelopeTimezone": "Europe/Moscow",
      "compaction": { "mode": "safeguard" },
      "maxConcurrent": 4,
      "subagents": { "maxConcurrent": 8 },
      "models": {
        "{{LLM_PROVIDER}}/{{LLM_MODEL}}": { "alias": "{{LLM_MODEL}}" }
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
      "replyToMode": "first",
      "blockStreaming": false
    }
  },
  "gateway": {
    "port": 18789,
    "mode": "local",
    "bind": "lan",
    "auth": { "mode": "password", "password": "{{GATEWAY_PASSWORD}}" },
    "controlUi": {
      "allowedOrigins": [
        "http://127.0.0.1:18789",
        "http://localhost:18789",
        "http://127.0.0.1",
        "http://localhost",
        "{{PUBLIC_ORIGIN}}"
      ],
      "dangerouslyDisableDeviceAuth": {{CONTROL_UI_DISABLE_DEVICE_AUTH}}
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
