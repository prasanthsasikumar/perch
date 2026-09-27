import AppKit
import PerchKit
import SwiftUI

/// The dropdown. Chrome belongs to the host; the middle belongs to a plugin.
struct PanelView: View {
    @Bindable var registry: PluginRegistry
    let sleep: SleepController

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
                sleep: sleep,
                onQuit: quit
            )
        }
        .frame(width: 320)
        // The setting can be changed from Terminal while the panel is
        // closed; re-read it every time the panel is shown.
        .onAppear { sleep.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            sleep.refresh()
        }
    }

    /// Gives every enabled plugin a chance to flush before the process dies.
    ///
    /// The host has to make this call itself. Leaving it to plugins to notice
    /// `NSApplication.willTerminateNotification` on their own means the first
    /// plugin author who doesn't think of it loses their users' unsaved work.
    private func quit() {
        registry.flushAll()
        NSApp.terminate(nil)
    }
}
