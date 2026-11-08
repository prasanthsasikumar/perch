import ScrollKit
import SwiftUI

/// Scroll's pane in Perch's Settings: the panel's switches, the permission,
/// and why there is a second app.
struct ScrollSettingsView: View {
    @Bindable var store: ScrollStore

    var body: some View {
        Form {
            if store.isScrollReverserRunning {
                Section { ScrollReverserWarning() }
            }

            Section {
                Toggle("Reverse scrolling", isOn: $store.settings.isOn)
                Toggle("Mouse wheel", isOn: $store.settings.reverseMouse)
                    .disabled(!store.settings.isOn)
                Toggle("Trackpad and Magic Mouse", isOn: $store.settings.reverseTrackpad)
                    .disabled(!store.settings.isOn)
            } header: {
                Text("Devices")
            } footer: {
                Text("Anything that scrolls with phases, as a trackpad does, counts as a trackpad. That includes a Magic Mouse. Everything else counts as a mouse.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Up and down", isOn: $store.settings.reverseVertical)
                Toggle("Left and right", isOn: $store.settings.reverseHorizontal)
            } header: {
                Text("Directions")
            } footer: {
                Text("Shift with a scroll wheel scrolls left and right, so it follows the second switch.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .disabled(!store.settings.isOn)

            Section {
                LabeledContent("Accessibility") {
                    if store.isTrusted {
                        Text("Granted").foregroundStyle(.green)
                    } else if store.companion == .running {
                        Button("Allow…") { store.requestAccessibility() }
                    } else {
                        Text("Unknown while PerchScroll isn't running").foregroundStyle(.secondary)
                    }
                }
                Button("Run setup again") { store.replaySetup() }
            } header: {
                Text("Permission")
            } footer: {
                Text("Scroll's work happens in PerchScroll, inside Perch.app. Perch is sandboxed, and the sandbox won't let an app change other apps' input, so PerchScroll is not. It has no window, runs only while this plugin is on and set up, and quits with Perch. Accessibility is granted to it, not to Perch.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Text("The approach follows [Scroll Reverser](https://pilotmoon.com/scrollreverser/) by Nick Moore, Apache License 2.0.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { store.refreshConflicts() }
    }
}
