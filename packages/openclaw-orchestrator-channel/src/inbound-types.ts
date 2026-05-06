/**
 * Wire shape from the orchestrator's /channel/orchestrator/poll endpoint.
 *
 * Orchestrator owns the canonical session-key and target string (computed
 * from MM channel-type + post.root_id) and sends both pre-baked. We do not
 * recompute them here — the plugin trusts them as the routing intent.
 */

export type InboundChatType = "direct" | "channel" | "group"

export interface InboundAttachment {
    mimeType: string
    fileName: string
    contentBase64: string
}

export type InboundSkipReason = "too_large" | "fetch_failed" | "post_cap"

export interface InboundSkippedAttachment {
    name: string
    mimeType: string
    size?: number
    reason: InboundSkipReason
}

export interface InboundMessage {
    id: string
    text: string
    senderId: string
    senderName: string
    timestamp: number
    replyToId: string | null
    conversation: { id: string; title: string | null }
}

export interface InboundEvent {
    kind: "inbound-message"
    sessionKey: string
    agentId: string
    target: string
    chatType: InboundChatType
    threadId: string | null
    message: InboundMessage
    attachments: InboundAttachment[]
    skipped: InboundSkippedAttachment[]
}

export interface PollResponse {
    cursor: number
    events: InboundEvent[]
}
