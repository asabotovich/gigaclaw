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
            docsPath: "",
            blurb: "Relays outbound messages through the gigaclaw-orchestrator /push endpoint.",
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
