import SwiftUI

@main
struct MenuDoApp: App {
    var body: some Scene {
        MenuBarExtra("MenuDo", systemImage: "checkmark.circle") {
            Text("MenuDo is running")
                .padding()
        }
        .menuBarExtraStyle(.window)
    }
}
