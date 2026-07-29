import AnalyticsPlugin
import AppKit
import MenuBarExtraAccess
import MenuDoPlugin
import PerchKit
import SwiftUI

extension PluginContext {
    /// Every plugin context in Perch is built here, so "where does plugin X
    /// keep its data" has exactly one answer.
    static func perch(_ identifier: String) -> PluginContext {
        .standard(appName: "Perch", identifier: identifier)
    }
}

@main
struct PerchApp: App {
    @State private var registry: PluginRegistry
    @State private var appState = AppState()
    @AppStorage("showTitleInMenuBar") private var showTitleInMenuBar = true
    @AppStorage("titleTruncationLength") private var titleTruncationLength = 30

    init() {
        let registry = PluginRegistry(plugins: PerchApp.makePlugins())
        _registry = State(initialValue: registry)
        PerchApp.flushPluginsOnTermination(registry)
    }

    /// The one place in Perch that decides which plugins exist.
    private static func makePlugins() -> [any PerchPlugin] {
        [
            MenuDo(context: .perch(MenuDo.identifier)),
            Analytics(context: .perch(Analytics.identifier)),
        ]
    }

    /// The panel's Quit button flushes explicitly, but the app can also die via
    /// ⌘Q or a logout, and `PerchPlugin.flush()` promises to be called either
    /// way. Registered once, for the lifetime of the process.
    private static func flushPluginsOnTermination(_ registry: PluginRegistry) {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { registry.flushAll() }
        }
    }

    var body: some Scene {
        @Bindable var appState = appState

        MenuBarExtra {
            PanelView(registry: registry)
        } label: {
            menuBarContent(
                MenuBarLabelResolver.resolve(
                    primary: registry.primary?.plugin.menuBarLabel,
                    showTitle: showTitleInMenuBar,
                    truncationLength: titleTruncationLength
                )
            )
        }
        .menuBarExtraAccess(isPresented: $appState.isMenuPresented)
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(registry: registry)
        }
    }

    /// `nil` means no enabled plugin contributed a label, so Perch shows its
    /// own mark rather than an empty menu bar item.
    @ViewBuilder
    private func menuBarContent(_ label: MenuBarLabel?) -> some View {
        if let label {
            if let text = label.text {
                HStack(spacing: 4) {
                    Image(systemName: label.systemImage)
                    Text(text)
                }
            } else {
                Image(systemName: label.systemImage)
            }
        } else {
            Image(systemName: "bird")
        }
    }
}
