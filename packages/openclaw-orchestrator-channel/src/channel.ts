import { createChatChannelPlugin } from "openclaw/plugin-sdk/channel-core"
import type { OpenClawConfig } from "openclaw/plugin-sdk/channel-core"
import { emptyChannelConfigSchema } from "openclaw/plugin-sdk/core"
import type { ChannelOutboundSessionRoute } from "openclaw/plugin-sdk/core"
import { orchestratorGatewayAdapter } from "./gateway.js"
import { parseTarget } from "./target.js"
import { pushMessage } from "./push.js"

export interface ResolvedAccount {
    /** Stable identifier used by the orchestrator's poll endpoint to look up
     *  this container's inbound queue. Pinned to channels.orchestrator.accountId
     *  in the config (provision sets it to the container owner's MM username). */
    accountId: string | null
    pushUrl: string
    pushSecret: string
}

interface OrchestratorChannelConfig {
    enabled?: boolean
    pushUrl?: string
    pushSecret?: string
    accountId?: string
}

function readSection(cfg: OpenClawConfig): OrchestratorChannelConfig {
    const channels = (cfg as { channels?: Record<string, unknown> }).channels
    const section = (channels?.orchestrator ?? {}) as OrchestratorChannelConfig
    return section
}

function resolveAccount(cfg: OpenClawConfig, _accountId?: string | null): ResolvedAccount {
    const section = readSection(cfg)
    const pushUrl = typeof section.pushUrl === "string" ? section.pushUrl.replace(/\/+$/, "") : ""
    const pushSecret = typeof section.pushSecret === "string" ? section.pushSecret : ""
    const accountId = typeof section.accountId === "string" && section.accountId ? section.accountId : null
    if (!pushUrl || !pushSecret || !accountId) {
        throw new Error(
            "orchestrator channel: channels.orchestrator.pushUrl, pushSecret and accountId are required",
        )
    }
    return { accountId, pushUrl, pushSecret }
}

function inspectAccount(cfg: OpenClawConfig) {
    const section = readSection(cfg)
    const configured = Boolean(section.pushUrl && section.pushSecret)
    return {
        enabled: configured && section.enabled !== false,
        configured,
        tokenStatus: section.pushSecret ? ("available" as const) : ("missing" as const),
    }
}

const TARGET_HINT =
    "mattermost:direct:<user_id> for DM, mattermost:channel:<channel_id> for a channel, " +
    "mattermost:group:<channel_id> for a private group; append :thread:<root_post_id> for thread reply. " +
    "The container's owner id is available as $ADMIN_USER_ID."

const TARGET_PREFIX_RE = /^(agent:[^:]+:)?mattermost:/

export const orchestratorPlugin = createChatChannelPlugin<ResolvedAccount>({
    base: {
        id: "orchestrator",
        meta: {
            id: "orchestrator",
            label: "GigaClaw Orchestrator",
            selectionLabel: "GigaClaw Orchestrator",
            docsPath: "docs/channel.md",
            blurb: [
                "Outbound channel to Mattermost via the gigaclaw-orchestrator /push endpoint.",
                "Target shape (session-key-like, required):",
                "  DM to user:            mattermost:direct:<user_id>",
                "  Channel (O|P):         mattermost:channel:<channel_id>",
                "  Private group:         mattermost:group:<channel_id>",
                "  Thread reply (any):    append :thread:<root_post_id>",
                "An optional agent:<id>: prefix is stripped; bare mattermost:<user_id> is accepted as DM for back-compat.",
                "For DMs to the owner use $ADMIN_USER_ID (the container's env has it): mattermost:direct:$ADMIN_USER_ID.",
                "Shortcuts like @username or user:<id> are NOT resolved — use the mattermost: prefix with a 26-char MM id.",
            ].join("\n"),
        },
        capabilities: {
            chatTypes: ["direct", "channel", "group", "thread"],
        },
        reload: { configPrefixes: ["channels.orchestrator"] },
        gateway: orchestratorGatewayAdapter,
        // Control UI looks up configSchema to build a settings form. Without
        // one it renders "Unsupported type: . Use Raw mode." in the Channels
        // panel. Our three fields (enabled / pushUrl / pushSecret) are driven
        // by the orchestrator via patches.jq on provision — there's nothing
        // useful to edit here by hand, so we declare an empty schema to
        // suppress the error.
        configSchema: emptyChannelConfigSchema(),
        config: {
            listAccountIds: (cfg: OpenClawConfig) => {
                const section = readSection(cfg)
                return section.accountId ? [section.accountId] : []
            },
            defaultAccountId: (cfg: OpenClawConfig) => {
                const section = readSection(cfg)
                return section.accountId ?? ""
            },
            resolveAccount,
            inspectAccount,
        },
        setup: {
            applyAccountConfig: ({ cfg }) => cfg,
        },
        // Without this hook OpenClaw's message-action-runner treats any
        // target it doesn't find in its directory cache as "Unknown target"
        // and never calls our sendText. The resolver tells core: "yes, this
        // mattermost:... string is something I own — hand it to sendText as-is".
        messaging: {
            normalizeTarget: (raw: string) => {
                const trimmed = raw?.trim()
                return trimmed ? trimmed : undefined
            },
            targetResolver: {
                hint: TARGET_HINT,
                looksLikeId: (raw: string) => {
                    const trimmed = raw?.trim() ?? ""
                    return TARGET_PREFIX_RE.test(trimmed)
                },
                resolveTarget: async ({ input }) => {
                    try {
                        const parsed = parseTarget(input)
                        const kind = parsed.kind === "direct" ? "user" : parsed.kind
                        return {
                            to: input.trim(),
                            kind,
                            display: input.trim(),
                            source: "normalized",
                        }
                    } catch {
                        return null
                    }
                },
            },
            // Without this hook OpenClaw builds outbound session keys like
            // `agent:main:orchestrator:direct:mattermost:direct:<id>` — prefixing
            // our target with the channel name. That puts the BOOT welcome DM
            // and every cron into separate jsonl files from the inbound session
            // (which uses `agent:main:mattermost:direct:<id>`). From the user's
            // point of view it's one DM with the bot, so we pin the outbound
            // session to the same key the orchestrator sets on inbound.
            //
            // DMs flatten the thread suffix (MM threads in a DM are visual
            // grouping). Groups and channels keep `:thread:<root>` when present.
            resolveOutboundSessionRoute: ({ target, agentId }) => {
                const id = agentId || "main"
                let parsed
                try {
                    parsed = parseTarget(target)
                } catch {
                    return null
                }
                if (parsed.kind === "direct") {
                    const key = `agent:${id}:mattermost:direct:${parsed.id}`
                    return {
                        sessionKey: key,
                        baseSessionKey: key,
                        peer: { kind: "direct", id: parsed.id },
                        chatType: "direct",
                        from: "orchestrator",
                        to: target.trim(),
                    }
                }
                const kindPrefix = parsed.kind === "group" ? "group" : "channel"
                const base = `agent:${id}:mattermost:${kindPrefix}:${parsed.id}`
                const key = parsed.rootId ? `${base}:thread:${parsed.rootId}` : base
                const route: ChannelOutboundSessionRoute = {
                    sessionKey: key,
                    baseSessionKey: base,
                    peer: { kind: parsed.kind, id: parsed.id },
                    chatType: parsed.kind,
                    from: "orchestrator",
                    to: target.trim(),
                }
                if (parsed.rootId) route.threadId = parsed.rootId
                return route
            },
        },
    },
    outbound: {
        base: {
            deliveryMode: "direct",
        },
        attachedResults: {
            channel: "orchestrator",
            sendText: async ({ cfg, to, text, accountId }) => {
                const parsed = parseTarget(to)
                const account = resolveAccount(cfg, accountId ?? null)
                const result = await pushMessage({
                    pushUrl: account.pushUrl,
                    pushSecret: account.pushSecret,
                    parsed,
                    message: text,
                })
                return { messageId: typeof result.post_id === "string" ? result.post_id : "" }
            },
        },
    },
})
