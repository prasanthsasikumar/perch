import PerchKit
import SwiftUI

/// The Plugins pane: every plugin with what it is for, what it can do, a
/// switch, and a way into its own settings.
///
/// It borrows the welcome window's look (tinted icon tile, one-line summary)
/// so a plugin reads the same wherever the user meets it.
struct PluginsSettingsView: View {
    @Bindable var registry: PluginRegistry
    /// Opens a plugin's own pane in the sidebar.
    let openPlugin: (String) -> Void

    var body: some View {
        Form {
            Section {
                ForEach(registry.entries) { entry in
                    PluginRow(
                        entry: entry,
                        isOn: Binding(
                            get: { registry.isEnabled(entry.id) },
                            set: { registry.setEnabled($0, for: entry.id) }
                        ),
                        openSettings: { openPlugin(entry.id) }
                    )
                }
            } header: {
                HStack(alignment: .firstTextBaseline) {
                    Text("Each plugin you turn on becomes a tab in the Perch panel.")
                    Spacer()
                    Text("\(registry.enabled.count) of \(registry.entries.count) on")
                        .monospacedDigit()
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .textCase(nil)
            } footer: {
                Text(
                    "Tags show what a plugin can do; hover one for details. "
                    + "macOS grants permissions to the whole app, not to individual plugins. "
                    + "Turning a plugin off stops it but keeps its data."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}

private struct PluginRow: View {
    let entry: PluginRegistry.Entry
    @Binding var isOn: Bool
    let openSettings: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            PluginIconTile(symbol: entry.icon, tint: PluginTint.color(for: entry.id), size: 34)
                .saturation(isOn ? 1 : 0)
                .opacity(isOn ? 1 : 0.55)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.displayName)
                    .font(.body.weight(.semibold))
                if !entry.summary.isEmpty {
                    Text(entry.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                CapabilityTags(capabilities: entry.capabilities)
            }

            Spacer(minLength: 8)

            if isOn {
                Button(action: openSettings) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help("\(entry.displayName) settings")
                .accessibilityLabel("Open \(entry.displayName) settings")
            }

            Toggle("", isOn: $isOn.animation(.easeOut(duration: 0.15)))
                .toggleStyle(.switch)
                .labelsHidden()
                .accessibilityLabel("Turn \(entry.displayName) on or off")
        }
        .padding(.vertical, 4)
    }
}

/// Small labelled tags for what a plugin does. A plugin with none says it
/// keeps everything on the Mac, which is worth saying out loud.
struct CapabilityTags: View {
    let capabilities: Set<PluginCapability>

    var body: some View {
        HStack(spacing: 6) {
            if capabilities.isEmpty {
                tag(symbol: "lock.fill", label: "Stays on your Mac", help: "Uses no network and no special permissions")
            } else {
                ForEach(PluginCapability.allCases.filter(capabilities.contains), id: \.self) { capability in
                    tag(symbol: capability.symbol, label: capability.shortLabel, help: capability.disclosure)
                }
            }
        }
    }

    private func tag(symbol: String, label: String, help: String) -> some View {
        Label(label, systemImage: symbol)
            .labelStyle(.titleAndIcon)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
            .help(help)
    }
}
