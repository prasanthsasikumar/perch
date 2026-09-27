import AppKit
import PerchKit
import SwiftUI

/// The row of controls along the bottom of the panel. The keep-awake toggle,
/// the gear and the power button are Perch's and always present; everything
/// to their left is contributed by whichever plugin is showing.
struct PanelFooter: View {
    let actions: [PluginAction]
    let sleep: SleepController
    let onQuit: () -> Void

    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack {
            ForEach(actions) { action in
                Button(action.title) { action.perform() }
            }
            Spacer()
            Button {
                Task { await sleep.toggle() }
            } label: {
                Image(systemName: sleep.isSleepDisabled ? "cup.and.saucer.fill" : "cup.and.saucer")
                    .foregroundStyle(
                        sleep.isSleepDisabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.foreground)
                    )
            }
            .disabled(sleep.isBusy)
            .help(sleep.tooltip)
            .accessibilityLabel("Keep awake with lid closed")
            .accessibilityValue(sleep.isSleepDisabled ? "On" : "Off")
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
