/**
 * Dispatch one InboundEvent through the OpenClaw SDK.
 *
 * `channelRuntime` is the documented seam for external channel plugins
 * (ChannelGatewayContext.channelRuntime, since Plugin SDK 2026.2.19) and
 * exposes the same `runtime.channel.*` methods bundled plugins access via
 * direct imports (qa-channel uses `getQaChannelRuntime()` for this).
 *
 * Orchestrator pre-bakes sessionKey and target — we trust them as the route.
 * ctxPayload mirrors the bundled qa-channel layout so SDK helpers find every
 * field they need for command-detection, mentions, threading, history.
 *
 * deliver is the outbound seam: SDK calls it for each agent reply chunk
 * (silent payloads are filtered inside the SDK and never reach us). We POST
 * each chunk to the orchestrator's /push endpoint, which relays to MM as
 * the bot.
 */

import { dispatchInboundReplyWithBase } from "openclaw/plugin-sdk/inbound-reply-dispatch"
import type { OpenClawConfig } from "openclaw/plugin-sdk/channel-core"
import type { PluginRuntime } from "openclaw/plugin-sdk/runtime-store"
import { buildAgentMediaPayload } from "openclaw/plugin-sdk/agent-media-payload"
import type { ResolvedAccount } from "./channel.js"
import { pushMessage } from "./push.js"
import { parseTarget } from "./target.js"
import type { InboundAttachment, InboundEvent } from "./inbound-types.js"

export const CHANNEL_ID = "orchestrator"
const CHANNEL_LABEL = "GigaClaw Orchestrator"

type ChannelRuntime = PluginRuntime["channel"]

async function resolveInboundMediaPayload(
    runtime: ChannelRuntime,
    attachments: InboundAttachment[],
): Promise<Record<string, unknown>> {
    if (attachments.length === 0) return {}
    const mediaList: Array<{ path: string; contentType: string }> = []
    for (const a of attachments) {
        if (!a.mimeType || !a.contentBase64) continue
        const saved = await runtime.media.saveMediaBuffer(
            Buffer.from(a.contentBase64, "base64"),
            a.mimeType,
            "inbound",
            undefined,
            a.fileName,
        )
        mediaList.push({ path: saved.path, contentType: saved.contentType ?? a.mimeType })
    }
    return mediaList.length > 0 ? buildAgentMediaPayload(mediaList) : {}
}

export async function handleOrchestratorInbound(params: {
    cfg: OpenClawConfig
    account: ResolvedAccount
    channelRuntime: ChannelRuntime
    event: InboundEvent
}): Promise<void> {
    const { cfg, account, channelRuntime: runtime, event } = params
    const route = { agentId: event.agentId, sessionKey: event.sessionKey }
    // From is a target-string identifying the sender — SDK calls .trim() on
    // it during command-detection, so it must be a string, not a peer object.
    // Mirror qa-channel: build a DM-target from the sender's id.
    const fromTarget = `mattermost:direct:${event.message.senderId}`

    const sessionStore = (cfg as { session?: { store?: string } }).session?.store
    const storePath = runtime.session.resolveStorePath(sessionStore, { agentId: route.agentId })
    const previousTimestamp = runtime.session.readSessionUpdatedAt({
        storePath,
        sessionKey: route.sessionKey,
    })
    const body = runtime.reply.formatAgentEnvelope({
        channel: CHANNEL_LABEL,
        from: event.message.senderName || event.message.senderId,
        timestamp: event.message.timestamp,
        previousTimestamp,
        envelope: runtime.reply.resolveEnvelopeFormatOptions(cfg),
        body: event.message.text,
    })
    const mediaPayload = await resolveInboundMediaPayload(runtime, event.attachments)

    const ctxPayload = runtime.reply.finalizeInboundContext({
        Body: body,
        BodyForAgent: event.message.text,
        RawBody: event.message.text,
        CommandBody: event.message.text,
        From: fromTarget,
        To: event.target,
        SessionKey: route.sessionKey,
        AccountId: account.accountId ?? undefined,
        ChatType: event.chatType === "direct" ? "direct" : "group",
        ConversationLabel: event.message.conversation.title || event.message.conversation.id,
        GroupSubject:
            event.chatType !== "direct"
                ? event.message.conversation.title || event.message.conversation.id
                : undefined,
        GroupChannel: event.chatType !== "direct" ? event.message.conversation.id : undefined,
        NativeChannelId: event.message.conversation.id,
        MessageThreadId: event.threadId ?? undefined,
        ThreadParentId: event.threadId ? event.message.conversation.id : undefined,
        SenderName: event.message.senderName,
        SenderId: event.message.senderId,
        Provider: CHANNEL_ID,
        Surface: CHANNEL_ID,
        MessageSid: event.message.id,
        MessageSidFull: event.message.id,
        ReplyToId: event.message.replyToId ?? undefined,
        Timestamp: event.message.timestamp,
        OriginatingChannel: CHANNEL_ID,
        OriginatingTo: event.target,
        CommandAuthorized: true,
        ...mediaPayload,
    })

    await dispatchInboundReplyWithBase({
        cfg,
        channel: CHANNEL_ID,
        accountId: account.accountId ?? undefined,
        route,
        storePath,
        ctxPayload,
        core: { channel: runtime } as never,
        deliver: async (payload) => {
            const text =
                payload && typeof payload === "object" && "text" in payload
                    ? ((payload as { text?: string }).text ?? "")
                    : ""
            if (!text.trim()) return
            const parsed = parseTarget(event.target)
            await pushMessage({
                pushUrl: account.pushUrl,
                pushSecret: account.pushSecret,
                parsed,
                message: text,
            })
        },
        onRecordError: (err) => {
            throw err instanceof Error ? err : new Error(`orchestrator-channel session record failed: ${String(err)}`)
        },
        onDispatchError: (err) => {
            throw err instanceof Error ? err : new Error(`orchestrator-channel dispatch failed: ${String(err)}`)
        },
    })
}
