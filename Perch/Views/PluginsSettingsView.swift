import SwiftUI

struct PluginsSettingsView: View {
    @Bindable var registry: PluginRegistry

    var body: some View {
        Form {
            Section {
                ForEach(registry.entries) { entry in
                    Toggle(isOn: Binding(
                        get: { registry.isEnabled(entry.id) },
                        set: { registry.setEnabled($0, for: entry.id) }
                    )) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: entry.icon)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.displayName)
                                ForEach(entry.capabilities.disclosureLines, id: \.self) { line in
                                    Text(line)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            } footer: {
                Text(
                    "Capabilities describe what a plugin does. macOS grants permissions "
                    + "to the whole app, not to individual plugins."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
