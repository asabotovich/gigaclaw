import { createChatChannelPlugin } from "openclaw/plugin-sdk/channel-core"
import type { OpenClawConfig } from "openclaw/plugin-sdk/channel-core"
import { parseTarget } from "./target.js"
import { pushMessage } from "./push.js"

export interface ResolvedAccount {
    accountId: string | null
    pushUrl: string
    pushSecret: string
}

interface OrchestratorChannelConfig {
    enabled?: boolean
    pushUrl?: string
    pushSecret?: string
}

function readSection(cfg: OpenClawConfig): OrchestratorChannelConfig {
    const channels = (cfg as { channels?: Record<string, unknown> }).channels
    const section = (channels?.orchestrator ?? {}) as OrchestratorChannelConfig
    return section
}

function resolveAccount(cfg: OpenClawConfig, accountId?: string | null): ResolvedAccount {
    const section = readSection(cfg)
    const pushUrl = typeof section.pushUrl === "string" ? section.pushUrl.replace(/\/+$/, "") : ""
    const pushSecret = typeof section.pushSecret === "string" ? section.pushSecret : ""
    if (!pushUrl || !pushSecret) {
        throw new Error(
            "orchestrator channel: channels.orchestrator.pushUrl and channels.orchestrator.pushSecret are required",
        )
    }
    return {
        accountId: accountId ?? null,
        pushUrl,
        pushSecret,
    }
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
        config: {
            listAccountIds: () => [],
            resolveAccount,
            inspectAccount,
        },
        setup: {
            applyAccountConfig: ({ cfg }) => cfg,
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
