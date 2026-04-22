import type { ParsedTarget } from "./target.js"

export interface PushParams {
    pushUrl: string
    pushSecret: string
    parsed: ParsedTarget
    message: string
}

export interface PushResult {
    ok?: boolean
    post_id?: string
}

export async function pushMessage(params: PushParams): Promise<PushResult> {
    const { pushUrl, pushSecret, parsed, message } = params

    type BaseBody = { message: string; root_id?: string }
    const base: BaseBody = { message }
    if (parsed.rootId) base.root_id = parsed.rootId
    const body = parsed.kind === "direct"
        ? { ...base, user_id: parsed.id }
        : { ...base, channel_id: parsed.id }

    const res = await fetch(`${pushUrl}/push`, {
        method: "POST",
        headers: {
            Authorization: `Bearer ${pushSecret}`,
            "Content-Type": "application/json",
        },
        body: JSON.stringify(body),
    })
    if (!res.ok) {
        const text = await res.text().catch(() => "")
        throw new Error(`orchestrator push: ${res.status} ${text.slice(0, 200)}`)
    }
    return res.json().catch(() => ({}) as PushResult)
}
