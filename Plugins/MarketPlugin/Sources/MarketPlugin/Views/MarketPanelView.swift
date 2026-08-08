import SwiftUI

struct MarketPanelView: View {
    @Bindable var store: MarketStore
    let poller: WatchPoller

    @State private var query = ""
    @State private var maxPrice = ""
    @State private var expanded: Set<UUID> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let notice = store.loadFailureNotice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            statusLine

            HStack(spacing: 6) {
                TextField("What to watch for", text: $query)
                    .textFieldStyle(.roundedBorder)
                TextField("Max $", text: $maxPrice)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 64)
            }
            .disabled(!store.canAddWatch)
            .onSubmit(addWatch)

            if !store.canAddWatch {
                Text("Set a location in Settings first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if store.watches.isEmpty {
                Text("Nothing watched yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            } else {
                ForEach(store.watches) { watch in
                    Divider()
                    WatchRowView(
                        watch: watch,
                        unseenCount: store.unseenCount(for: watch.id),
                        newest: store.newest(for: watch.id, limit: 3),
                        isExpanded: expanded.contains(watch.id),
                        onToggle: { toggle(watch) },
                        onDelete: { store.deleteWatch(id: watch.id) }
                    )
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// The panel never presents itself as watching when it is not.
    @ViewBuilder
    private var statusLine: some View {
        switch poller.state {
        case .signedOut:
            Label("Sign in to Facebook", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
        case .backoff:
            Text(poller.lastError.map { "Retrying — \($0)" } ?? "Retrying")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .idle, .polling:
            EmptyView()
        }
    }

    private func addWatch() {
        store.addWatch(query: query, maxPrice: Int(maxPrice))
        query = ""
        maxPrice = ""
    }

    /// Expanding a watch is how you look at it, so that is when it stops
    /// counting as unseen.
    private func toggle(_ watch: Watch) {
        if expanded.contains(watch.id) {
            expanded.remove(watch.id)
        } else {
            expanded.insert(watch.id)
            store.markSeen(watchID: watch.id)
        }
    }
}
