#
# patches.jq — manifest of fields that the Orchestrator owns.
#
# provision.sh applies this on top of /root/.openclaw/openclaw.json at every run.
# Anything NOT in this list is left untouched — that includes:
#   - skills.entries.<skill>.env.*  (tokens saved by the bot during onboarding)
#   - any custom fields added by the user or OpenClaw itself
#
# Add new rules here only for fields you want guaranteed-reset on every deploy.
#

# --- Values from .env (per-user credentials + platform settings) ---

# Mattermost self-attach is OFF: containers do not open a WebSocket of their
# own. All inbound MM traffic goes through the vibe-projects orchestrator,
# which forwards to /v1/responses. The fields below (botToken, baseUrl) stay
# populated because workspace scripts (BOOT.md, AGENTS.md cron recipes,
# skills/mattermost/SKILL.md) read them directly with jq to call the MM REST
# API from inside the container.
  .channels.mattermost.enabled       = false
| .channels.mattermost.botToken      = env.MM_BOT_TOKEN
| .channels.mattermost.baseUrl       = env.MM_BASE_URL
| .channels.mattermost.dmPolicy      = "allowlist"
| .channels.mattermost.groupPolicy   = "allowlist"
| .channels.mattermost.allowFrom     = [env.ADMIN_USERNAME]
| .channels.mattermost.groupAllowFrom = [env.ADMIN_USERNAME]
| .channels.mattermost.dangerouslyAllowNameMatching = true
| .channels.mattermost.chatmode      = "oncall"

| .models.mode                                  = "replace"
| .models.providers.openrouter.baseUrl          = "https://openrouter.ai/api/v1"
| .models.providers.openrouter.apiKey           = env.OPENROUTER_API_KEY
| .models.providers.openrouter.models           = [
    {id: env.LLM_MODEL,        name: env.LLM_MODEL},
    {id: env.LLM_VISION_MODEL, name: env.LLM_VISION_MODEL, input: ["text", "image"]}
  ]
| .agents.defaults.model.primary                = ("openrouter/" + env.LLM_MODEL)
| .agents.defaults.models                       = {
    ("openrouter/" + env.LLM_MODEL):        {alias: env.LLM_MODEL},
    ("openrouter/" + env.LLM_VISION_MODEL): {alias: env.LLM_VISION_MODEL}
  }
| .agents.defaults.imageModel.primary           = ("openrouter/" + env.LLM_VISION_MODEL)

| .gateway.port                                         = 18789
| .gateway.mode                                         = "local"
| .gateway.bind                                         = "lan"
| .gateway.auth.mode                                    = "token"
| .gateway.auth.token                                   = env.OPENCLAW_GATEWAY_TOKEN
# Orchestrator forwards inbound messages to this endpoint; must be enabled
# even when channels.mattermost.enabled = false.
| .gateway.http.endpoints.responses.enabled             = true
| .gateway.controlUi.allowedOrigins                     = [
    "http://127.0.0.1:18789",
    "http://localhost:18789",
    "http://127.0.0.1",
    "http://localhost",
    env.PUBLIC_ORIGIN
  ]
| .gateway.controlUi.dangerouslyDisableDeviceAuth       = (env.CONTROL_UI_DISABLE_DEVICE_AUTH == "true")

| .tools.web.search.enabled               = true
| .tools.web.search.provider              = "perplexity"
| .tools.web.search.perplexity.apiKey     = env.OPENROUTER_API_KEY
| .tools.web.search.perplexity.baseUrl    = "https://openrouter.ai/api/v1"
| .tools.web.search.perplexity.model      = "perplexity/sonar-pro"

# --- Hardcoded policies (not from .env) ---

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

| .plugins.allow                          = ["mattermost"]
| .plugins.entries.mattermost.enabled     = true

# --- Baseline skill registration ---

| .skills.entries.atlassian.enabled = true
| .skills.entries.glab.enabled      = true
| .skills.entries.himalaya.enabled  = true
| .skills.entries.gog.enabled       = true

# --- Skill credentials: conditional mirror from .env → openclaw.json ---
#
# If the env var is provided (non-empty), we mirror it into openclaw.json.
# If it's empty/unset, we leave the existing value alone — that's how
# bot-saved tokens survive a reset when .env has nothing for that field.
#
# Read order used by skills: os.getenv() sees BOTH --env-file values AND
# OpenClaw's skills.entries.*.env injection. But the bot's SKILL.md tells
# it to read ONLY from openclaw.json (single source of truth for onboarding).
# So every skill creds variable that can come from .env must also be
# mirrored here.

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

# NOTE: himalaya reads creds from /root/.config/himalaya/config.toml which is
#   rendered separately via envsubst in provision.sh — no env mirror needed here.
# NOTE: gog uses its own keyring at /root/.config/gogcli/ — no env mirror needed here.
