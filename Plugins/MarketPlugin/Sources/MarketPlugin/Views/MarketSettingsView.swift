import SwiftUI

struct MarketSettingsView: View {
    @Bindable var store: MarketStore

    @State private var location = ""
    @State private var radiusKm = 50
    @State private var pollIntervalMinutes = 15
    @State private var notificationsEnabled = true

    var body: some View {
        Form {
            Section {
                TextField("City", text: $location)
                    .onSubmit(apply)
                Text(
                    "Facebook scopes searches to a city. Use the slug from a "
                        + "Marketplace URL — the part after /marketplace/, like “auckland”."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Stepper("Radius: \(radiusKm) km", value: $radiusKm, in: 1...500, step: 10)
                    .onChange(of: radiusKm) { apply() }
            } header: {
                Text("Where to search")
            }

            Section {
                Stepper(
                    "Check every \(pollIntervalMinutes) minutes",
                    value: $pollIntervalMinutes,
                    in: 10...240,
                    step: 5
                )
                .onChange(of: pollIntervalMinutes) { apply() }
                Text("Ten minutes is the floor. Checking harder gets the session blocked.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Notify me about new listings", isOn: $notificationsEnabled)
                    .onChange(of: notificationsEnabled) { apply() }
            } header: {
                Text("How often")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            location = store.settings.location ?? ""
            radiusKm = store.settings.radiusKm
            pollIntervalMinutes = store.settings.pollIntervalMinutes
            notificationsEnabled = store.settings.notificationsEnabled
        }
    }

    private func apply() {
        let trimmed = location.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        store.updateSettings(
            MarketSettings(
                location: trimmed.isEmpty ? nil : trimmed,
                radiusKm: radiusKm,
                pollIntervalMinutes: pollIntervalMinutes,
                notificationsEnabled: notificationsEnabled
            )
        )
    }
}
