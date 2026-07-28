import AppKit
import PerchKit
import SwiftUI

/// The row of controls along the bottom of the panel. The gear and the power
/// button are Perch's and always present; everything to their left is
/// contributed by whichever plugin is showing.
struct PanelFooter: View {
    let actions: [PluginAction]
    let onQuit: () -> Void

    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack {
            ForEach(actions) { action in
                Button(action.title) { action.perform() }
            }
            Spacer()
            Button {
                // A menu bar only (LSUIElement) app is not active when its
                // dropdown is clicked, so Settings would open behind the
                // frontmost app unless we activate first.
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .help("Settings")
            .accessibilityLabel("Settings")
            Button(action: onQuit) {
                Image(systemName: "power")
            }
            .help("Quit Perch")
            .accessibilityLabel("Quit Perch")
        }
        .buttonStyle(.borderless)
        .padding(12)
    }
}
