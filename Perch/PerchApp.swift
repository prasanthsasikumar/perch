import MenuBarExtraAccess
import MenuDoPlugin
import PerchKit
import SwiftUI

@main
struct PerchApp: App {
    @State private var registry: PluginRegistry
    @State private var migration: MigrationState
    @State private var appState = AppState()
    @AppStorage("showTitleInMenuBar") private var showTitleInMenuBar = true
    @AppStorage("titleTruncationLength") private var titleTruncationLength = 30

    init() {
        let result = LegacyImporter.runIfNeeded()
        _registry = State(initialValue: PluginRegistry(plugins: PerchApp.makePlugins()))
        let state = MigrationState()
        if result.importedTasks { state.notice = MigrationState.importedNotice }
        _migration = State(initialValue: state)
    }

    /// The one place in Perch that names a concrete plugin.
    private static func makePlugins() -> [any PerchPlugin] {
        [
            MenuDo(context: .standard(appName: "Perch", identifier: MenuDo.identifier))
        ]
    }

    var body: some Scene {
        @Bindable var appState = appState

        MenuBarExtra {
            PanelView(registry: registry, migration: migration)
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
            SettingsView(registry: registry, migration: migration)
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
