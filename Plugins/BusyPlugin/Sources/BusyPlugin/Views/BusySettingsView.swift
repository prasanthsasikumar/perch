import SwiftUI

struct BusySettingsView: View {
    let store: BusyStore

    @State private var refreshIntervalMinutes = BusySettings.defaults.refreshIntervalMinutes

    var body: some View {
        Form {
            Section {
                Stepper(
                    "Check every \(refreshIntervalMinutes) minutes",
                    value: $refreshIntervalMinutes,
                    in: BusySettings.minimumRefreshMinutes...60,
                    step: 5
                )
                .onChange(of: refreshIntervalMinutes) { apply() }
                Text(
                    "Five minutes is the floor. Google's live figure only moves every "
                        + "few minutes anyway, and checking harder gets Perch blocked."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Text("How often")
            }

            Section {
                Text(
                    "Perch loads the Google search page for each place in a hidden "
                        + "browser and reads the Popular times box — the same live "
                        + "busyness you'd see on Google. Add places from the panel, "
                        + "worded the way Maps names them."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Text("How it works")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            refreshIntervalMinutes = store.settings.refreshIntervalMinutes
        }
    }

    private func apply() {
        store.updateSettings(BusySettings(refreshIntervalMinutes: refreshIntervalMinutes))
    }
}
