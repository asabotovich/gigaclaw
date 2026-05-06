/**
 * Gateway adapter for the orchestrator channel.
 *
 * `startAccount` opens a long-poll loop against the orchestrator's
 * GET /channel/orchestrator/poll. Each batch of inbound events is dispatched
 * through the SDK via handleOrchestratorInbound; the resulting agent reply
 * chunks travel back to the orchestrator via outbound.sendText (POST /push).
 *
 * Cursor is persisted to <stateDir>/orchestrator-channel-cursor.json so a
 * container restart resumes from the next event instead of replaying the
 * whole queue. First contact passes no cursor, which the orchestrator treats
 * as snapshot mode and returns its current position with no events — we
 * persist that and start polling from there.
 */

import { mkdirSync, readFileSync, writeFileSync } from "node:fs"
import { dirname } from "node:path"
import type { ChannelGatewayContext } from "openclaw/plugin-sdk/channel-contract"
import type { PluginRuntime } from "openclaw/plugin-sdk/runtime-store"
import type { ResolvedAccount } from "./channel.js"
import { CHANNEL_ID, handleOrchestratorInbound } from "./inbound.js"
import type { PollResponse } from "./inbound-types.js"

const POLL_TIMEOUT_MS = 20_000
const RETRY_BACKOFF_MS = 5_000
const STATE_DIR = "/root/.openclaw"
const CURSOR_FILE = `${STATE_DIR}/orchestrator-channel-cursor.json`

type ChannelRuntime = PluginRuntime["channel"]

function readPersistedCursor(accountId: string): number | null {
    try {
        const raw = readFileSync(CURSOR_FILE, "utf8")
        const parsed = JSON.parse(raw) as Record<string, number>
        const value = parsed[accountId]
        return typeof value === "number" && Number.isInteger(value) && value >= 0 ? value : null
    } catch {
        return null
    }
}

function persistCursor(accountId: string, cursor: number): void {
    let parsed: Record<string, number> = {}
    try {
        parsed = JSON.parse(readFileSync(CURSOR_FILE, "utf8")) as Record<string, number>
    } catch {
        // first write — start clean
    }
    parsed[accountId] = cursor
    try {
        mkdirSync(dirname(CURSOR_FILE), { recursive: true })
    } catch {
        // dir exists
    }
    writeFileSync(CURSOR_FILE, JSON.stringify(parsed), { mode: 0o600 })
}

async function pollOnce(params: {
    pushUrl: string
    pushSecret: string
    accountId: string
    cursor: number | null
    signal: AbortSignal
}): Promise<PollResponse> {
    const url = new URL(`${params.pushUrl}/channel/orchestrator/poll`)
    url.searchParams.set("accountId", params.accountId)
    if (params.cursor !== null) url.searchParams.set("cursor", String(params.cursor))
    url.searchParams.set("timeoutMs", String(POLL_TIMEOUT_MS))
    const res = await fetch(url, {
        method: "GET",
        headers: { Authorization: `Bearer ${params.pushSecret}` },
        signal: params.signal,
    })
    if (!res.ok) throw new Error(`poll: ${res.status} ${(await res.text().catch(() => "")).slice(0, 200)}`)
    return (await res.json()) as PollResponse
}

function pickAccountId(ctx: ChannelGatewayContext<ResolvedAccount>): string {
    return ctx.accountId || ctx.account.accountId || "default"
}

export async function startOrchestratorGatewayAccount(
    ctx: ChannelGatewayContext<ResolvedAccount>,
): Promise<void> {
    if (!ctx.channelRuntime) {
        ctx.log?.warn?.("orchestrator-channel: ctx.channelRuntime missing — aborting gateway loop")
        return
    }
    const channelRuntime = ctx.channelRuntime as unknown as ChannelRuntime
    const accountId = pickAccountId(ctx)
    const account = ctx.account
    const pushUrl = account.pushUrl.replace(/\/+$/, "")

    ctx.setStatus({ accountId, running: true, configured: true, enabled: true })
    let cursor = readPersistedCursor(accountId)

    try {
        while (!ctx.abortSignal.aborted) {
            let result: PollResponse
            try {
                result = await pollOnce({
                    pushUrl,
                    pushSecret: account.pushSecret,
                    accountId,
                    cursor,
                    signal: ctx.abortSignal,
                })
            } catch (err) {
                if (ctx.abortSignal.aborted) break
                ctx.log?.warn?.(`orchestrator-channel: poll failed (${String(err)}); retrying in ${RETRY_BACKOFF_MS}ms`)
                await sleep(RETRY_BACKOFF_MS, ctx.abortSignal)
                continue
            }

            for (const event of result.events) {
                if (event.kind !== "inbound-message") continue
                try {
                    await handleOrchestratorInbound({
                        cfg: ctx.cfg,
                        account,
                        channelRuntime,
                        event,
                    })
                } catch (err) {
                    ctx.log?.error?.(`orchestrator-channel: inbound dispatch failed: ${String(err)}`)
                }
            }
            cursor = result.cursor
            persistCursor(accountId, cursor)
        }
    } finally {
        ctx.setStatus({ accountId, running: false, configured: true, enabled: true })
    }
}

function sleep(ms: number, signal: AbortSignal): Promise<void> {
    return new Promise((resolve) => {
        const timer = setTimeout(resolve, ms)
        signal.addEventListener("abort", () => {
            clearTimeout(timer)
            resolve()
        }, { once: true })
    })
}

export const orchestratorGatewayAdapter = {
    startAccount: startOrchestratorGatewayAccount,
} as const

void CHANNEL_ID // re-export sanity
