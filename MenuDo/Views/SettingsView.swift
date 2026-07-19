import SwiftUI

struct SettingsView: View {
    @AppStorage("showTitleInMenuBar") private var showTitleInMenuBar = true
    @AppStorage("titleTruncationLength") private var titleTruncationLength = 30
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchAtLoginError: String?

    var body: some View {
        Form {
            Section("Menu bar") {
                Toggle("Show current task in menu bar", isOn: $showTitleInMenuBar)
                Stepper(
                    "Title length: \(titleTruncationLength) characters",
                    value: $titleTruncationLength,
                    in: 10...60,
                    step: 5
                )
                .disabled(!showTitleInMenuBar)
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        // Re-fired by the resync below; actual state already matches.
                        guard newValue != LaunchAtLogin.isEnabled else { return }
                        do {
                            try LaunchAtLogin.set(newValue)
                            launchAtLoginError = nil
                        } catch {
                            launchAtLoginError = error.localizedDescription
                        }
                        let actual = LaunchAtLogin.isEnabled
                        if actual != newValue {
                            if newValue && LaunchAtLogin.status == .requiresApproval {
                                launchAtLoginError = "Approval needed: enable MenuDo in System Settings → General → Login Items."
                            }
                            launchAtLogin = actual
                        }
                    }
                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .fixedSize()
    }
}
