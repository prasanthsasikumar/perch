import AppKit
import SwiftUI

/// The plugin's half of the dropdown: a field to add a place, a card per
/// place, and one line saying how old the numbers are.
struct BusyPanelView: View {
    @Bindable var store: BusyStore

    /// How old the numbers may be before opening the panel refetches. Live
    /// busyness moves every few minutes; a deliberate reopen should feel
    /// live without clicking twice hitting Google twice.
    private static let openRefreshAge: TimeInterval = 180

    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                if let notice = store.loadFailureNotice {
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if let notice = store.saveFailureNotice {
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                TextField("A place as you'd search it, or a Planet Fitness club link", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addPlace)

                if store.places.isEmpty {
                    Text("Nothing watched yet. Try “lion gym kesavadasapuram”.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                } else {
                    ForEach(store.places) { place in
                        Divider()
                        PlaceCardView(
                            place: place,
                            result: store.results[place.id],
                            failure: store.failures[place.id],
                            onDelete: { store.deletePlace(id: place.id) }
                        )
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()
            footer
        }
        .task {
            guard !store.places.isEmpty else { return }
            await store.refreshIfStale(maxAge: Self.openRefreshAge)
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if store.isRefreshing {
                ProgressView()
                    .controlSize(.mini)
                Text("Checking…")
            } else {
                Text(freshness)
            }
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var freshness: String {
        guard let lastRefreshed = store.lastRefreshed else { return "Not checked yet" }
        return "Updated \(RelativeTime.describe(lastRefreshed))"
    }

    private func addPlace() {
        guard store.addPlace(query: query) != nil else { return }
        query = ""
        Task { await store.refresh() }
    }
}
