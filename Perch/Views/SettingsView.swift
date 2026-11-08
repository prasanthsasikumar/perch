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
        // A plain sidebar beside the content, not a NavigationSplitView: the
        // split view expects a toolbar this Settings window doesn't have, and
        // without one its inset sidebar slides under the window buttons. A
        // collapsible sidebar has no use in a settings window anyway.
        HStack(spacing: 0) {
            List(selection: $selection) {
                SidebarRow(title: "General", symbol: "gearshape.fill", tint: .gray).tag(Pane.general)
                // Each plugin's own settings sit under "Plugins", so it reads
                // as one place: pick Plugins to turn them on and off, open a
                // plugin beneath it to configure that one.
                DisclosureGroup(isExpanded: $pluginsExpanded) {
                    ForEach(registry.enabled) { entry in
                        SidebarRow(
                            title: entry.displayName,
                            symbol: entry.icon,
                            tint: PluginTint.color(for: entry.id)
                        )
                        .tag(Pane.plugin(entry.id))
                    }
                } label: {
                    SidebarRow(title: "Plugins", symbol: "puzzlepiece.extension.fill", tint: .gray).tag(Pane.plugins)
                }
            }
            .listStyle(.sidebar)
            .frame(width: 200)

            Divider()

            Group {
                switch selection {
                case .general:
                    GeneralSettingsView(registry: registry, welcome: welcome)
                case .plugins:
                    PluginsSettingsView(registry: registry) { id in
                        selection = .plugin(id)
                    }
                case .plugin(let id):
                    if let entry = registry.enabled.first(where: { $0.id == id }) {
                        entry.plugin.settings
                    } else if let entry = registry.entries.first(where: { $0.id == id }) {
                        // The plugin was switched off while its pane was showing.
                        ContentUnavailableView {
                            Label("\(entry.displayName) is off", systemImage: entry.icon)
                        } description: {
                            Text("Turn it on to change its settings. Its data was kept.")
                        } actions: {
                            Button("Turn On") { registry.setEnabled(true, for: id) }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 720, height: 540)
    }
}

/// A sidebar entry with a small tinted tile, the way System Settings draws
/// its own, so a plugin wears the same colour here as in the Plugins list and
/// the welcome window.
private struct SidebarRow: View {
    let title: String
    let symbol: String
    let tint: Color

    var body: some View {
        Label {
            Text(title)
        } icon: {
            PluginIconTile(symbol: symbol, tint: tint, size: 20)
                .shadow(radius: 0)
        }
    }
}
