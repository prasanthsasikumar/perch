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

            // A VStack, not a Group: a Group around a plugin's EmptyView has
            // nothing to give the frame to, so the pane collapsed and the
            // sidebar slid to the middle of the window.
            VStack(spacing: 0) {
                switch selection {
                case .general:
                    GeneralSettingsView(registry: registry, welcome: welcome)
                case .plugins:
                    PluginsSettingsView(registry: registry) { id in
                        selection = .plugin(id)
                    }
                case .plugin(let id):
                    if let entry = registry.enabled.first(where: { $0.id == id }) {
                        PluginPane(entry: entry, registry: registry)
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

/// One plugin's page: who it is and a switch, then whatever settings it has.
/// The header makes every page look like part of the same app, and a plugin
/// with nothing to set still gets a page that says so rather than a blank one.
private struct PluginPane: View {
    let entry: PluginRegistry.Entry
    @Bindable var registry: PluginRegistry

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                PluginIconTile(symbol: entry.icon, tint: PluginTint.color(for: entry.id), size: 44)
                VStack(alignment: .leading, spacing: 5) {
                    Text(entry.displayName)
                        .font(.title2.weight(.semibold))
                    if !entry.summary.isEmpty {
                        Text(entry.summary)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    CapabilityTags(capabilities: entry.capabilities)
                }
                Spacer(minLength: 8)
                Toggle("", isOn: Binding(
                    get: { registry.isEnabled(entry.id) },
                    set: { registry.setEnabled($0, for: entry.id) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .accessibilityLabel("Turn \(entry.displayName) on or off")
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, entry.plugin.hasSettings ? 4 : 18)

            if entry.plugin.hasSettings {
                entry.plugin.settings
            } else {
                Divider().padding(.horizontal, 20)
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Nothing else to set")
                        .font(.headline)
                    Text("\(entry.displayName) works as soon as it's on. Open the Perch panel to use it.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
