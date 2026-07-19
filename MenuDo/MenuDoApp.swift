import SwiftUI

@main
struct MenuDoApp: App {
    @State private var store = TaskStore()
    @AppStorage("showTitleInMenuBar") private var showTitleInMenuBar = true
    @AppStorage("titleTruncationLength") private var titleTruncationLength = 30

    var body: some Scene {
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
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}
