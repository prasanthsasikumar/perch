import SwiftUI

/// Switches between enabled plugins. Never shown for a single plugin — see
/// `PluginRegistry.showsTabStrip`.
struct PluginTabStrip: View {
    @Bindable var registry: PluginRegistry

    var body: some View {
        Picker("", selection: Binding(
            get: { registry.active?.id ?? "" },
            set: { registry.activeID = $0 }
        )) {
            ForEach(registry.enabled) { entry in
                Group {
                    if registry.tabStripUsesIcons {
                        Image(systemName: entry.icon)
                            .accessibilityLabel(entry.displayName)
                    } else {
                        Text(entry.displayName)
                    }
                }
                .help(entry.displayName)
                .tag(entry.id)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }
}
