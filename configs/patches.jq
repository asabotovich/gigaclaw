  del(.channels.mattermost)
| .models.mode                                  = "replace"
| .models.providers.openrouter.baseUrl          = "https://openrouter.ai/api/v1"
| .models.providers.openrouter.apiKey           = env.OPENROUTER_API_KEY
| .models.providers.openrouter.models           = [
    {id: env.LLM_MODEL,                           name: env.LLM_MODEL},
    {id: env.LLM_VISION_MODEL,                    name: env.LLM_VISION_MODEL,                    input: ["text", "image"]},
    {id: "nvidia/nemotron-nano-12b-v2-vl:free",   name: "nvidia/nemotron-nano-12b-v2-vl:free",   input: ["text", "image"]}
  ]
| .agents.defaults.model.primary                = ("openrouter/" + env.LLM_MODEL)
| .agents.defaults.models                       = {
    ("openrouter/" + env.LLM_MODEL):                               {alias: env.LLM_MODEL},
    ("openrouter/" + env.LLM_VISION_MODEL):                        {alias: env.LLM_VISION_MODEL},
    "openrouter/nvidia/nemotron-nano-12b-v2-vl:free":              {alias: "nemotron-vl-free"}
  }
| .agents.defaults.imageModel.primary           = ("openrouter/" + env.LLM_VISION_MODEL)
| .agents.defaults.imageModel.fallbacks         = [
    "openrouter/nvidia/nemotron-nano-12b-v2-vl:free"
  ]

| .gateway.port                                         = 18789
| .gateway.mode                                         = "local"
| .gateway.bind                                         = "lan"
| .gateway.auth.mode                                    = "token"
| .gateway.auth.token                                   = env.OPENCLAW_GATEWAY_TOKEN
| .gateway.http.endpoints.responses.enabled             = true
| .gateway.controlUi.allowedOrigins                     = [
    env.PUBLIC_ORIGIN,
    env.PUBLIC_ORIGIN_LOCALHOST,
    "http://127.0.0.1",
    "http://localhost"
  ]
| .gateway.controlUi.dangerouslyDisableDeviceAuth       = (env.CONTROL_UI_DISABLE_DEVICE_AUTH == "true")

| .tools.web.search.enabled               = true
| .tools.web.search.provider              = "perplexity"
| .tools.web.search.perplexity.apiKey     = env.OPENROUTER_API_KEY
| .tools.web.search.perplexity.baseUrl    = "https://openrouter.ai/api/v1"
| .tools.web.search.perplexity.model      = "perplexity/sonar-pro"

| .session.dmScope                        = "per-channel-peer"
| .agents.defaults.workspace              = "/root/.openclaw/workspace"
| .agents.defaults.skipBootstrap          = true
| .agents.defaults.userTimezone           = "Europe/Moscow"
| .agents.defaults.envelopeTimezone       = "Europe/Moscow"
| .agents.defaults.compaction.mode        = "safeguard"
| .agents.defaults.maxConcurrent          = 4
| .agents.defaults.subagents.maxConcurrent = 8

| .messages.ackReactionScope              = "group-mentions"
| .commands.native                        = "auto"
| .commands.nativeSkills                  = "auto"
| .commands.restart                       = true
| .commands.ownerDisplay                  = "raw"

| .hooks.internal.enabled                 = true
| .hooks.internal.entries["bootstrap-extra-files"].enabled = true
| .hooks.internal.entries["session-memory"].enabled        = true
| .hooks.internal.entries["boot-md"].enabled               = true

| .plugins.allow                          = ["orchestrator"]
| .plugins.entries.orchestrator.enabled   = true
| .plugins.load.paths                     = ["/opt/gigaclaw/extensions"]

| .channels.orchestrator.enabled          = true
| .channels.orchestrator.pushUrl          = env.ORCHESTRATOR_URL
| .channels.orchestrator.pushSecret       = env.ORCHESTRATOR_PUSH_SECRET

| .skills.entries.atlassian.enabled = true
| .skills.entries.glab.enabled      = true
| .skills.entries.himalaya.enabled  = true
| .skills.entries.gog.enabled       = true

| (if (env.JIRA_URL // "") != ""           then .skills.entries.atlassian.env.JIRA_URL           = env.JIRA_URL           else . end)
| (if (env.JIRA_PAT_TOKEN // "") != ""     then .skills.entries.atlassian.env.JIRA_PAT_TOKEN     = env.JIRA_PAT_TOKEN     else . end)
| (if (env.JIRA_API_TOKEN // "") != ""     then .skills.entries.atlassian.env.JIRA_API_TOKEN     = env.JIRA_API_TOKEN     else . end)
| (if (env.JIRA_USERNAME // "") != ""      then .skills.entries.atlassian.env.JIRA_USERNAME      = env.JIRA_USERNAME      else . end)
| (if (env.JIRA_SSL_VERIFY // "") != ""    then .skills.entries.atlassian.env.JIRA_SSL_VERIFY    = env.JIRA_SSL_VERIFY    else . end)
| (if (env.CONFLUENCE_URL // "") != ""     then .skills.entries.atlassian.env.CONFLUENCE_URL     = env.CONFLUENCE_URL     else . end)
| (if (env.CONFLUENCE_PAT_TOKEN // "") != "" then .skills.entries.atlassian.env.CONFLUENCE_PAT_TOKEN = env.CONFLUENCE_PAT_TOKEN else . end)
| (if (env.CONFLUENCE_SSL_VERIFY // "") != "" then .skills.entries.atlassian.env.CONFLUENCE_SSL_VERIFY = env.CONFLUENCE_SSL_VERIFY else . end)

| (if (env.GITLAB_HOST // "") != ""        then .skills.entries.glab.env.GITLAB_HOST  = env.GITLAB_HOST  else . end)
| (if (env.GITLAB_TOKEN // "") != ""       then .skills.entries.glab.env.GITLAB_TOKEN = env.GITLAB_TOKEN else . end)
