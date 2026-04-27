// Custom OpenRouter media-understanding provider — bypass for the broken
// built-in openrouter image path in openclaw 2026.4.x (issue #8096:
// `image` tool ignores maxTokens, "Image model returned no text" even when
// the model itself works fine when called directly).
//
// We register this under id="openrouter-direct" (the built-in is "openrouter",
// duplicate ids would be rejected by the loader). patches.jq points
// `agents.defaults.imageModel.primary` to "openrouter-direct/<model>", so
// openclaw routes describeImage calls to us instead of the broken pipeline.
//
// Inside, we just hit OpenRouter's standard /chat/completions with the
// system+user-image format that I verified returns full image descriptions
// for qwen3-vl-* — same exact request that openclaw should be sending but
// somehow isn't.

import type {
    ImageDescriptionRequest,
    ImageDescriptionResult,
    ImagesDescriptionRequest,
    ImagesDescriptionResult,
    MediaUnderstandingProvider,
} from "openclaw/plugin-sdk/media-understanding"
import type { OpenClawConfig } from "openclaw/plugin-sdk/core"

const DEFAULT_BASE_URL = "https://openrouter.ai/api/v1"
const DEFAULT_MAX_TOKENS = 4096

interface OpenRouterChatMessage {
    role: "system" | "user" | "assistant"
    content: string | Array<
        | { type: "text"; text: string }
        | { type: "image_url"; image_url: { url: string } }
    >
}

interface OpenRouterChoice {
    message?: { content?: string | null; reasoning?: string | null }
    finish_reason?: string
}

function resolveOpenRouterAuth(cfg: OpenClawConfig): { apiKey: string; baseUrl: string } {
    const providers = (cfg as { models?: { providers?: Record<string, unknown> } }).models?.providers ?? {}
    // We register patches.jq to clone openrouter → openrouter-direct, but tolerate
    // either key in case the user maps things differently.
    const direct = (providers["openrouter-direct"] ?? {}) as { apiKey?: string; baseUrl?: string }
    const fallback = (providers["openrouter"] ?? {}) as { apiKey?: string; baseUrl?: string }
    const apiKey = (direct.apiKey ?? fallback.apiKey ?? "").trim()
    if (!apiKey) {
        throw new Error("openrouter-direct: no apiKey on models.providers.openrouter-direct or .openrouter")
    }
    const baseUrl = (direct.baseUrl ?? fallback.baseUrl ?? DEFAULT_BASE_URL).replace(/\/+$/, "")
    return { apiKey, baseUrl }
}

function buildDataUrl(buffer: Buffer, mime: string | undefined): string {
    return `data:${(mime || "image/jpeg").toLowerCase()};base64,${buffer.toString("base64")}`
}

function extractText(choice: OpenRouterChoice | undefined): string {
    const content = choice?.message?.content
    if (typeof content === "string" && content.trim()) return content.trim()
    return ""
}

async function callChatCompletions(params: {
    apiKey: string
    baseUrl: string
    model: string
    messages: OpenRouterChatMessage[]
    maxTokens: number
    timeoutMs: number
}): Promise<{ text: string; finishReason?: string }> {
    const controller = new AbortController()
    const timer = setTimeout(() => controller.abort(), params.timeoutMs)
    try {
        const res = await fetch(`${params.baseUrl}/chat/completions`, {
            method: "POST",
            headers: {
                Authorization: `Bearer ${params.apiKey}`,
                "Content-Type": "application/json",
            },
            body: JSON.stringify({
                model: params.model,
                max_tokens: params.maxTokens,
                messages: params.messages,
            }),
            signal: controller.signal,
        })
        if (!res.ok) {
            const body = await res.text().catch(() => "")
            throw new Error(`openrouter ${res.status}: ${body.slice(0, 300)}`)
        }
        const json = (await res.json()) as { choices?: OpenRouterChoice[]; error?: { message?: string } }
        if (json.error) throw new Error(`openrouter error: ${json.error.message ?? "unknown"}`)
        const choice = json.choices?.[0]
        return { text: extractText(choice), finishReason: choice?.finish_reason }
    } finally {
        clearTimeout(timer)
    }
}

async function describeImage(req: ImageDescriptionRequest): Promise<ImageDescriptionResult> {
    const { apiKey, baseUrl } = resolveOpenRouterAuth(req.cfg)
    const dataUrl = buildDataUrl(req.buffer, req.mime)
    const prompt = req.prompt?.trim() || "Describe the image."
    const messages: OpenRouterChatMessage[] = [
        { role: "system", content: prompt },
        { role: "user", content: [{ type: "image_url", image_url: { url: dataUrl } }] },
    ]
    const { text } = await callChatCompletions({
        apiKey,
        baseUrl,
        model: req.model,
        messages,
        maxTokens: req.maxTokens ?? DEFAULT_MAX_TOKENS,
        timeoutMs: req.timeoutMs,
    })
    if (!text) {
        throw new Error(`openrouter-direct: empty content from ${req.provider}/${req.model}`)
    }
    return { text, model: req.model }
}

async function describeImages(req: ImagesDescriptionRequest): Promise<ImagesDescriptionResult> {
    const { apiKey, baseUrl } = resolveOpenRouterAuth(req.cfg)
    const prompt = req.prompt?.trim() || "Describe the image."
    const userParts: OpenRouterChatMessage["content"] = req.images.map((img: { buffer: Buffer; mime?: string }) => ({
        type: "image_url" as const,
        image_url: { url: buildDataUrl(img.buffer, img.mime) },
    }))
    const messages: OpenRouterChatMessage[] = [
        { role: "system", content: prompt },
        { role: "user", content: userParts },
    ]
    const { text } = await callChatCompletions({
        apiKey,
        baseUrl,
        model: req.model,
        messages,
        maxTokens: req.maxTokens ?? DEFAULT_MAX_TOKENS,
        timeoutMs: req.timeoutMs,
    })
    if (!text) {
        throw new Error(`openrouter-direct: empty content from ${req.provider}/${req.model}`)
    }
    return { text, model: req.model }
}

export const openrouterDirectMediaUnderstandingProvider: MediaUnderstandingProvider = {
    id: "openrouter-direct",
    capabilities: ["image"],
    defaultModels: { image: "auto" },
    describeImage,
    describeImages,
}
