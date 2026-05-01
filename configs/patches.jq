  del(.channels.mattermost)
| .models.mode                                  = "replace"
| .models.providers.openrouter.baseUrl          = "https://openrouter.ai/api/v1"
| .models.providers.openrouter.apiKey           = env.OPENROUTER_API_KEY
| .models.providers.openrouter.api              = "openai-completions"
| .models.providers.openrouter.models           = [
    {id: env.LLM_MODEL,                           name: env.LLM_MODEL},
    {id: env.LLM_VISION_MODEL,                    name: env.LLM_VISION_MODEL,                    input: ["text", "image"]},
    {id: "qwen/qwen3-vl-32b-instruct",            name: "qwen/qwen3-vl-32b-instruct",            input: ["text", "image"]},
    {id: "nvidia/nemotron-nano-12b-v2-vl:free",   name: "nvidia/nemotron-nano-12b-v2-vl:free",   input: ["text", "image"]}
  ]
| .agents.defaults.model.primary                = ("openrouter/" + env.LLM_MODEL)
| .agents.defaults.models                       = {
    ("openrouter/" + env.LLM_MODEL):                               {alias: env.LLM_MODEL},
    ("openrouter/" + env.LLM_VISION_MODEL):                        {alias: env.LLM_VISION_MODEL},
    "openrouter/qwen/qwen3-vl-32b-instruct":                       {alias: "qwen3-vl-32b"},
    "openrouter/nvidia/nemotron-nano-12b-v2-vl:free":              {alias: "nemotron-vl-free"}
  }

# Workaround for openclaw issue #8096 — built-in openrouter image path
# returns "Image model returned no text" even when the model itself works.
# Our orchestrator-channel plugin registers a parallel media-understanding
# provider with id="openrouter-direct" that hits /chat/completions itself.
# Clone the provider config so model resolution succeeds and route imageModel
# to it; primary text routing keeps using the built-in "openrouter".
| .models.providers["openrouter-direct"]        = .models.providers.openrouter
| .agents.defaults.imageModel.primary           = ("openrouter-direct/" + env.LLM_VISION_MODEL)
| .agents.defaults.imageModel.fallbacks         = [
    "openrouter-direct/qwen/qwen3-vl-32b-instruct",
    "openrouter-direct/nvidia/nemotron-nano-12b-v2-vl:free"
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
| .agents.defaults.timeoutSeconds         = 1800

# Memory search: hybrid BM25 + vector embeddings.
# We pin to BAAI's bge-m3 (1024-dim, multilingual, 8k ctx) — solid
# Russian retrieval, deployed by half the open-source RAG ecosystem,
# and present in BOTH OpenRouter (used here) AND cloud.ru Evolution
# Foundation Models. So when the project migrates off OpenRouter to
# cloud.ru's Sber-perimeter inference, only `model` (drop the `baai/`
# vendor prefix) and `remote.baseUrl` change — the index format and
# vector dimensions stay identical.
# `provider: "openai"` selects the OpenAI-compatible adapter; the
# `remote` block points it at OpenRouter's /v1/embeddings endpoint
# without touching the chat-side `models.providers.openrouter` config.
# Together with `experimental.sessionMemory` + `sources: ["memory",
# "sessions"]` the agent semantically recalls MEMORY.md, memory/*.md,
# AND past session transcripts ("о чём говорили про CISO" finds the
# thread). MMR removes near-duplicate hits; temporal decay (30-day
# half-life) keeps recent context above stale notes — MEMORY.md is
# evergreen and never decayed.
| .agents.defaults.memorySearch = {
    provider: "openai",
    model: "baai/bge-m3",
    remote: {
      baseUrl: "https://openrouter.ai/api/v1",
      apiKey: env.OPENROUTER_API_KEY
    },
    experimental: { sessionMemory: true },
    sources: ["memory", "sessions"],
    query: {
      hybrid: {
        mmr: { enabled: true },
        temporalDecay: { enabled: true }
      }
    }
  }

| .messages.ackReactionScope              = "group-mentions"
| .commands.native                        = "auto"
| .commands.nativeSkills                  = "auto"
| .commands.restart                       = true
| .commands.ownerDisplay                  = "raw"

| .hooks.internal.enabled                 = true
| .hooks.internal.entries["bootstrap-extra-files"].enabled = true
| .hooks.internal.entries["session-memory"].enabled        = true
| .hooks.internal.entries["boot-md"].enabled               = true

| .plugins.allow                          = ["orchestrator", "openrouter", "perplexity", "memory-core", "active-memory"]
| .plugins.entries.orchestrator.enabled   = true
| .plugins.entries["memory-core"].enabled = true
| .plugins.entries["active-memory"].enabled = true
# Active memory: blocking sub-agent runs before every reply where the
# bot is engaged (DM and @-mention in groups/channels), queries
# MEMORY.md / memory/*.md / session transcripts and injects relevant
# bits into the main agent's context. Cuts the "the bot doesn't think
# to recall what we discussed" problem at the root.
# In channels/groups the bot only replies on @-mentions, so the
# sub-agent fires only on those — bounded fan-out, no per-message
# overhead on every channel post.
# Inherits the session's primary model (no modelFallback) — switch to
# a cheaper model here if per-message latency/cost becomes an issue.
| .plugins.entries["active-memory"].config = {
    enabled: true,
    agents: ["main"],
    allowedChatTypes: ["direct", "group", "channel"],
    queryMode: "recent",
    promptStyle: "balanced",
    timeoutMs: 15000,
    maxSummaryChars: 220,
    persistTranscripts: false,
    logging: true
  }
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
