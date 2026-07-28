import MenuBarExtraAccess
import SwiftUI

@main
struct PerchApp: App {
    @State private var store = TaskStore()
    @State private var appState = AppState()
    @AppStorage("showTitleInMenuBar") private var showTitleInMenuBar = true
    @AppStorage("titleTruncationLength") private var titleTruncationLength = 30

    var body: some Scene {
        @Bindable var appState = appState

        MenuBarExtra {
            TaskListView(store: store)
        } label: {
            if showTitleInMenuBar, let current = store.currentTask {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle")
                    Text(current.title.truncatedForMenuBar(to: titleTruncationLength))
                }
            } else {
                Image(systemName: "checkmark.circle")
            }
        }
        .menuBarExtraAccess(isPresented: $appState.isMenuPresented)
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}
