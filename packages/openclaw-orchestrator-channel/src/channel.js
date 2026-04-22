import {
    createChatChannelPlugin,
    createChannelPluginBase,
} from "openclaw/plugin-sdk/channel-core"
import { parseTarget } from "./target.js"
import { pushMessage } from "./push.js"

function resolveAccount(cfg, accountId) {
    const section = cfg?.channels?.orchestrator ?? {}
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

function inspectAccount(cfg) {
    const section = cfg?.channels?.orchestrator ?? {}
    const pushUrl = typeof section.pushUrl === "string" ? section.pushUrl : ""
    const pushSecret = typeof section.pushSecret === "string" ? section.pushSecret : ""
    const configured = Boolean(pushUrl && pushSecret)
    return {
        enabled: configured && section.enabled !== false,
        configured,
        tokenStatus: pushSecret ? "available" : "missing",
    }
}

export const orchestratorPlugin = createChatChannelPlugin({
    base: createChannelPluginBase({
        id: "orchestrator",
        setup: {
            resolveAccount,
            inspectAccount,
        },
    }),
    // We always want replies to root posts to stay in the same thread
    // (matches what the orchestrator's /push relay does when root_id is set).
    threading: { topLevelReplyToMode: "reply" },
    outbound: {
        attachedResults: {
            async sendText(params) {
                const parsed = parseTarget(params.to)
                const result = await pushMessage({
                    pushUrl: params.account.pushUrl,
                    pushSecret: params.account.pushSecret,
                    parsed,
                    message: params.text,
                })
                return { messageId: typeof result?.post_id === "string" ? result.post_id : "" }
            },
        },
    },
})
