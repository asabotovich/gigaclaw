import { defineChannelPluginEntry } from "openclaw/plugin-sdk/channel-core"
import { orchestratorPlugin } from "./src/channel.js"
import { openrouterDirectMediaUnderstandingProvider } from "./src/image-provider.js"

export default defineChannelPluginEntry({
    id: "orchestrator",
    name: "GigaClaw Orchestrator",
    description: "Outbound bridge to the gigaclaw-orchestrator /push endpoint.",
    plugin: orchestratorPlugin,
    // Workaround for openclaw issue #8096: built-in openrouter image path
    // returns "Image model returned no text" even when the model itself works.
    // Register a parallel provider under id="openrouter-direct" that hits
    // /chat/completions directly with a known-good payload. patches.jq points
    // imageModel.primary at openrouter-direct/<model> so it routes here.
    registerFull(api) {
        api.registerMediaUnderstandingProvider(openrouterDirectMediaUnderstandingProvider)
    },
})
