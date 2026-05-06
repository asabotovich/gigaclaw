  del(.channels.mattermost)
| .models.mode                                  = "replace"
| .models.providers.openrouter.baseUrl          = "https://openrouter.ai/api/v1"
| .models.providers.openrouter.apiKey           = env.OPENROUTER_API_KEY
| .models.providers.openrouter.api              = "openai-completions"
| .models.providers.openrouter.models           = [
    {id: env.LLM_MODEL,                           name: env.LLM_MODEL},
    {id: env.LLM_VISION_MODEL,                    name: env.LLM_VISION_MODEL,                    input: ["text", "image"]},
    {id: "qwen/qwen3-vl-32b-instruct",            name: "qwen/qwen3-vl-32b-instruct",            input: ["text", "image"]},
    {id: "nvidia/nemotron-nano-12b-v2-vl:free",   name: "nvidia/nemotron-nano-12b-v2-vl:free",   input: ["text", "image"]},
    {id: "qwen/qwen3-next-80b-a3b-instruct",      name: "qwen/qwen3-next-80b-a3b-instruct"},
    {id: "qwen/qwen3-235b-a22b-2507",             name: "qwen/qwen3-235b-a22b-2507"}
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
# Pinned to BAAI/bge-m3 (1024-dim, multilingual, 8k ctx) — solid Russian
# retrieval, deployed by half the open-source RAG ecosystem.
# Embeddings provider: cloud.ru Evolution Foundation Models. We migrated
# off OpenRouter because its bge-m3 is routed through Parasail, which
# drops connections under the 4-way concurrent batches openclaw issues
# during session-delta sync, blocking session indexing entirely (see
# upstream #71522, #56815). cloud.ru hosts the same model directly,
# 1024-dim → existing SQLite index stays valid, no reindex needed.
# Chat-side LLM still goes through OpenRouter (separate concern); when
# we move chat to cloud.ru too, only the active-memory model id and the
# openrouter providers block change.
# `provider: "openai"` selects the OpenAI-compatible adapter; the
# `remote` block points it at cloud.ru's /v1/embeddings endpoint
# independently of the chat-side `models.providers.*` config.
# NOTE: cloud.ru is case-sensitive on the model id — must be
# "BAAI/bge-m3" (capital BAAI), lowercase "baai/bge-m3" returns 404.
# Together with `experimental.sessionMemory` + `sources: ["memory",
# "sessions"]` the agent semantically recalls MEMORY.md, memory/*.md,
# AND past session transcripts ("о чём говорили про CISO" finds the
# thread). MMR removes near-duplicate hits; temporal decay (30-day
# half-life) keeps recent context above stale notes — MEMORY.md is
# evergreen and never decayed.
# Sync + query tuning addresses two bugs observed empirically (см. ниже):
#
# Bug A — session-delta sync ленится. Дефолты deltaBytes=100KB и
# deltaMessages=50 — пока сессия не накопит столько, sessionsDirty=false и
# sync пропускается. Mattermost-турн обычно 0.5-2KB → дельта тригерится
# раз в 30-50 сообщений. До тех пор новые чанки в индекс не попадают.
# Хук session-memory тут НЕ при чём — он только для /new и /reset.
#
# Bug B — memory_search tool возвращает меньше/хуже результатов чем CLI.
# Корень: long-lived gateway держит MemoryManager в памяти, а
# startAsyncSearchSync — fire-and-forget (kick + не дожидается).
# Итог: tool бьёт по stale snapshot пока async sync догоняет диск.
# CLI спавнит свежий процесс → первый sync блокирующий → видит свежее.
# См. openclaw issues #52115, #4868, #19913, #12633.
#
# Лекарство — заставить sessionsDirty взводиться часто (deltaBytes=1,
# deltaMessages=1) + добавить periodic safety-net (intervalMinutes=5)
# + расширить query-pool и понизить minScore чтобы релевант не отсекался.
| .agents.defaults.memorySearch = {
    provider: "openai",
    model: "BAAI/bge-m3",
    remote: {
      baseUrl: "https://foundation-models.api.cloud.ru/v1",
      apiKey: env.CLOUDRU_API_KEY
    },
    experimental: { sessionMemory: true },
    sources: ["memory", "sessions"],
    sync: {
      onSessionStart: true,
      onSearch: true,
      watch: true,
      watchDebounceMs: 250,
      intervalMinutes: 5,
      sessions: {
        deltaBytes: 1,
        deltaMessages: 1,
        postCompactionForce: true
      }
    },
    query: {
      maxResults: 10,
      minScore: 0.2,
      hybrid: {
        candidateMultiplier: 8,
        mmr: { enabled: true, lambda: 0.7 },
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
# Pinned to Qwen3-Next-80B-A3B-Instruct because:
# 1. The default (session primary) glm-4.7 was timing out 100% of runs
#    in pilot logs — it's a reasoning model that burned the entire 15s
#    budget on internal <thinking> before getting to summary.
# 2. We need a non-reasoning Instruct model that answers directly.
# 3. The model has to exist on BOTH OpenRouter (we use now) AND
#    cloud.ru Evolution (planned migration target). gemini/claude/gpt
#    are openrouter-only — pinning to them would force a model swap
#    when we migrate. Qwen3 family is on both.
# 4. MoE architecture (80B params, 3B activated) gives ~2s response
#    time at very low cost — perfect fit for "find relevant chunks
#    and summarize in 220 chars".
# 5. 262K context easily fits workspace files + memory chunks.
# 6. Strong Russian language coverage (verified against bot prompts).
# When migrating to cloud.ru: drop the "openrouter/" prefix and use
# "Qwen3-Next-80B-A3B-Instruct" (cloud.ru's model id form). Same model.
| .plugins.entries["active-memory"].config = {
    enabled: true,
    agents: ["main"],
    allowedChatTypes: ["direct", "group", "channel"],
    model: "openrouter/qwen/qwen3-next-80b-a3b-instruct",
    modelFallback: "openrouter/qwen/qwen3-235b-a22b-2507",
    modelFallbackPolicy: "default-remote",
    # queryMode "message" вместо "recent" — отрезаем от запроса хвост
    # из последних turn'ов, в котором уже есть наши собственные
    # <active_memory_plugin>-инъекции; они засоряют embedding-поиск
    # и заставляют sub-agent'а выбирать прошлый recall вместо
    # реального факта из MEMORY.md/sessions.
    queryMode: "message",
    # recall-heavy — несмотря на название — содержит инструкцию
    # "if the connection is weak, broad, reply with NONE", и
    # qwen3-next-instruct (non-reasoning) читает её буквально.
    # promptOverride переопределяет дефолт целиком на агрессивно
    # recall-ориентированный текст, который форсит вызов
    # memory_search/memory_get и НЕ позволяет вернуть NONE без
    # хотя бы одной попытки поиска.
    promptStyle: "recall-heavy",
    promptOverride: "You are a memory recall agent. Another model is preparing the user-facing reply and depends on you to surface relevant memory.\n\nMandatory procedure for every request:\n1. Call memory_search with the user's latest message as the query (translate Russian queries 1:1, do not paraphrase).\n2. If the top hit has score >= 0.30 OR contains a name, number, code-word, project, preference, habit, or personal fact — call memory_get to read the full chunk.\n3. Summarize the recovered fact in one compact plain-text line under 220 characters, written as a third-person memory note about the user (e.g. \"User's favorite number is 731 and code word синий-кит\").\n\nReturn NONE only when memory_search returns zero results OR the top hit is clearly off-topic (different domain, different entity, score below 0.20). Do not return NONE just because the match feels soft — soft matches are exactly what you should surface.\n\nDo not answer the user. Do not explain reasoning. Do not output bullets, JSON, XML, markdown, or labels. Output is either the literal token NONE or one plain-text sentence — nothing else.",
    # 25s — sub-agent делает search + (возможно) get + summarize.
    # На builtin backend с 86 чанками + холодным embedding-кэшем
    # 15s ловит timeout (видели один кейс 29061ms).
    timeoutMs: 25000,
    maxSummaryChars: 220,
    # thinking off — qwen3-next-instruct и так non-reasoning;
    # включение reasoning гарантированно выжжет budget.
    thinking: "off",
    persistTranscripts: false,
    logging: true
  }
| .plugins.load.paths                     = ["/opt/gigaclaw/extensions"]

| .channels.orchestrator.enabled          = true
| .channels.orchestrator.pushUrl          = env.ORCHESTRATOR_URL
| .channels.orchestrator.pushSecret       = env.ORCHESTRATOR_PUSH_SECRET
# accountId is the per-container key the orchestrator's poll endpoint uses
# to look up this user's inbound queue. Pinned to ADMIN_USERNAME so each
# container drains exactly its owner's events.
| .channels.orchestrator.accountId        = env.ADMIN_USERNAME

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
