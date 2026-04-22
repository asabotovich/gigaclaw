// POST to the orchestrator's /push endpoint. Body shape matches what main.ts
// handlePush() expects: exactly one of {channel_id} or {user_id}, plus optional
// root_id, plus message.

export async function pushMessage({ pushUrl, pushSecret, parsed, message }) {
    const base = { message }
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
    return res.json().catch(() => ({}))
}
