import SwiftUI

struct SettingsView: View {
    @Bindable var registry: PluginRegistry

    private enum Pane: Hashable {
        case general
        case plugins
        case plugin(String)
    }

    @State private var selection: Pane = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("General", systemImage: "gearshape").tag(Pane.general)
                Label("Plugins", systemImage: "puzzlepiece.extension").tag(Pane.plugins)
                ForEach(registry.enabled) { entry in
                    Label(entry.displayName, systemImage: entry.icon).tag(Pane.plugin(entry.id))
                }
            }
            .navigationSplitViewColumnWidth(180)
        } detail: {
            switch selection {
            case .general:
                GeneralSettingsView(registry: registry)
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
