// Target format for `--channel orchestrator --to <TARGET>` mirrors OpenClaw's
// native Mattermost session-key shape — so agents can take a key from
// session_status output and paste it straight into --to.
//
// Accepted shapes (all equivalent once normalized):
//
//   mattermost:direct:<user_id>                            → DM
//   mattermost:<user_id>                                   → DM (legacy, 26-char id inferred)
//   mattermost:group:<channel_id>                          → private group (G)
//   mattermost:channel:<channel_id>                        → open/private channel (O|P)
//   ... any of the above + ":thread:<root_id>"             → thread suffix
//
// An optional "agent:<agentId>:" prefix is stripped, so full session keys
// like "agent:main:mattermost:direct:<id>" also work. Inside the container
// the canonical form to use is `mattermost:direct:$ADMIN_USER_ID` for DMs
// to the container's owner.

export type ParsedTargetKind = "direct" | "group" | "channel"

export interface ParsedTarget {
    kind: ParsedTargetKind
    id: string
    rootId?: string
}

const MATTERMOST_PREFIX = "mattermost:"
const THREAD_MARKER = ":thread:"
const AGENT_PREFIX_RE = /^agent:[^:]+:/

export function parseTarget(raw: string): ParsedTarget {
    if (typeof raw !== "string" || !raw.trim()) {
        throw new Error("orchestrator channel: empty target")
    }
    let body = raw.trim()

    const agentMatch = AGENT_PREFIX_RE.exec(body)
    if (agentMatch) body = body.slice(agentMatch[0].length)

    if (!body.startsWith(MATTERMOST_PREFIX)) {
        throw new Error(
            `orchestrator channel: target must start with "mattermost:" (after optional "agent:<id>:" prefix); got ${JSON.stringify(raw)}`,
        )
    }
    body = body.slice(MATTERMOST_PREFIX.length)

    let rootId: string | undefined
    const threadIdx = body.lastIndexOf(THREAD_MARKER)
    if (threadIdx !== -1) {
        rootId = body.slice(threadIdx + THREAD_MARKER.length)
        body = body.slice(0, threadIdx)
        if (!rootId) throw new Error(`orchestrator channel: empty thread id in ${JSON.stringify(raw)}`)
    }

    let kind: ParsedTargetKind
    let id: string
    if (body.startsWith("direct:")) {
        kind = "direct"
        id = body.slice("direct:".length)
    } else if (body.startsWith("group:")) {
        kind = "group"
        id = body.slice("group:".length)
    } else if (body.startsWith("channel:")) {
        kind = "channel"
        id = body.slice("channel:".length)
    } else {
        // Back-compat: bare body is a user id for DM.
        kind = "direct"
        id = body
    }
    if (!id) throw new Error(`orchestrator channel: empty id in ${JSON.stringify(raw)}`)

    return rootId !== undefined ? { kind, id, rootId } : { kind, id }
}
