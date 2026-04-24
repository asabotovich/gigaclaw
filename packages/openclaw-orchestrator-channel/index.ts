// Entry file loaded by openclaw plugin loader via the
// `openclaw.extensions: ["./dist/index.js"]` hint in package.json.
//
// openclaw's loader (dist/loader-*.js → resolvePluginModuleExport):
//   - default export can be a function → treated as `register` directly
//   - default export can be an object with a .register or .activate
//     function → object is the plugin "definition", function is invoked
//     with the plugin-runtime api to register channels/tools/etc.
//
// We used to export the channel-plugin object itself as default. That
// exposed no .register / .activate — loader logged
// "plugin export missing register/activate" and dropped us; outbound
// dispatch later failed with "Unsupported channel: orchestrator"
// because the registry never saw our adapter.

import { orchestratorPlugin } from "./src/channel.js"

interface PluginApi {
    registerChannel: (plugin: unknown) => void
}

export default {
    id: "orchestrator",
    name: "GigaClaw Orchestrator",
    description: "Outbound bridge to the gigaclaw-orchestrator /push endpoint.",
    kind: "channel" as const,
    register(api: PluginApi): void {
        api.registerChannel(orchestratorPlugin)
    },
}

export { orchestratorPlugin }
