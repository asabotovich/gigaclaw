// Entry file loaded by openclaw plugin loader via the
// `openclaw.extensions: ["./dist/index.js"]` hint in package.json.
//
// Historically we wrapped the plugin with `defineChannelPluginEntry` from
// `openclaw/plugin-sdk/channel-core`, but that subpath isn't in the
// `openclaw` package's exports map — the import silently fails at runtime,
// the plugin never registers, and openclaw never dispatches outbound
// through our sendText (cron replies, subagent announces, BOOT DMs all
// go nowhere). Inbound replies to DMs happen to work because the
// orchestrator HTTP server posts to MM directly, bypassing openclaw's
// channel dispatcher entirely.
//
// Export the ChannelPlugin object directly — the loader's own manifest
// reader merges it with `openclaw.plugin.json` metadata.

import { orchestratorPlugin } from "./src/channel.js"

export { orchestratorPlugin }
export const plugin = orchestratorPlugin
export default orchestratorPlugin
