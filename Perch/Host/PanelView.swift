import AppKit
import PerchKit
import SwiftUI

/// The dropdown. Chrome belongs to the host; the middle belongs to a plugin.
struct PanelView: View {
    @Bindable var registry: PluginRegistry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if registry.showsTabStrip {
                PluginTabStrip(registry: registry)
                Divider()
            }

            if let active = registry.active {
                active.plugin.panel
            } else {
                Text("No plugins enabled — turn one on in Settings")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            }

            Divider()

            PanelFooter(
                actions: registry.active?.plugin.footerActions ?? [],
                onQuit: quit
            )
        }
        .frame(width: 320)
    }

    /// Gives every enabled plugin a chance to flush before the process dies.
    private func quit() {
        NSApp.terminate(nil)
    }
}
