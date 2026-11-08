import SwiftUI

struct SettingsView: View {
    @Bindable var registry: PluginRegistry
    let welcome: WelcomeCoordinator

    private enum Pane: Hashable {
        case general
        case plugins
        case plugin(String)
    }

    @State private var selection: Pane = .general
    @State private var pluginsExpanded = true

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("General", systemImage: "gearshape").tag(Pane.general)
                // Each plugin's own settings sit under "Plugins", so it reads
                // as one place: pick Plugins to turn them on and off, open a
                // plugin beneath it to configure that one.
                DisclosureGroup(isExpanded: $pluginsExpanded) {
                    ForEach(registry.enabled) { entry in
                        Label(entry.displayName, systemImage: entry.icon).tag(Pane.plugin(entry.id))
                    }
                } label: {
                    Label("Plugins", systemImage: "puzzlepiece.extension").tag(Pane.plugins)
                }
            }
            .navigationSplitViewColumnWidth(180)
        } detail: {
            switch selection {
            case .general:
                GeneralSettingsView(registry: registry, welcome: welcome)
            case .plugins:
                PluginsSettingsView(registry: registry)
            case .plugin(let id):
                if let entry = registry.enabled.first(where: { $0.id == id }) {
                    entry.plugin.settings
                } else {
                    // The plugin was disabled while its pane was showing.
                    Text("This plugin is disabled")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 640, height: 420)
    }
}
