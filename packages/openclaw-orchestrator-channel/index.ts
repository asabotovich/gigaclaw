import { defineChannelPluginEntry } from "openclaw/plugin-sdk/channel-core"
import { orchestratorPlugin } from "./src/channel.js"

export default defineChannelPluginEntry({
    id: "orchestrator",
    name: "GigaClaw Orchestrator",
    description: "Outbound bridge to the gigaclaw-orchestrator /push endpoint.",
    plugin: orchestratorPlugin,
})
