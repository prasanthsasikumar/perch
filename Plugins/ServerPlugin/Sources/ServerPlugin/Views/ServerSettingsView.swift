import SwiftUI

struct ServerSettingsView: View {
    let store: ServerStore

    @State private var refreshIntervalSeconds = ServerSettings.defaults.refreshIntervalSeconds

    var body: some View {
        Form {
            Section {
                Stepper(
                    "Check every \(refreshIntervalSeconds) seconds",
                    value: $refreshIntervalSeconds,
                    in: ServerSettings.minimumRefreshSeconds...600,
                    step: 15
                )
                .onChange(of: refreshIntervalSeconds) { apply() }
                Text(
                    "Fifteen seconds is the floor. The agent samples every ten seconds "
                        + "regardless, so asking more often only costs both ends bandwidth."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Text("How often")
            }

            Section {
                Text(
                    "Each server runs the vpsstat agent, which reads the machine's own "
                        + "/proc and container cgroups and serves them as JSON. Perch polls "
                        + "that endpoint and shows the result. Add servers from the panel."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                Text(
                    "Passwords for servers behind basic auth are kept in your login "
                        + "Keychain, not in Perch's settings file."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Text("How it works")
            }

            Section {
                Text(
                    "Perch keeps its own short history, so the sparkline covers only what "
                        + "it has watched. The agent's own dashboard has the full 24 hours "
                        + "and 30 days; open it from a server's ••• menu."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Text("History")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            refreshIntervalSeconds = store.settings.refreshIntervalSeconds
        }
    }

    private func apply() {
        store.updateSettings(ServerSettings(refreshIntervalSeconds: refreshIntervalSeconds))
    }
}
