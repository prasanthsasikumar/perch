import SwiftUI

struct WatchRowView: View {
    let watch: Watch
    let unseenCount: Int
    let newest: [Listing]
    let isExpanded: Bool
    let onToggle: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(watch.query)
                    .lineLimit(1)
                Spacer()
                if let maxPrice = watch.maxPrice {
                    Text("≤$\(maxPrice)")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                if unseenCount > 0 {
                    Text("\(unseenCount)")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.accentColor, in: Capsule())
                        .foregroundStyle(.white)
                }
                Button(action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete this watch")
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onToggle)

            if isExpanded {
                if newest.isEmpty {
                    Text(emptyMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(newest) { listing in
                        Link(destination: listing.url) {
                            HStack(spacing: 4) {
                                Text(listing.price)
                                Text(listing.title).lineLimit(1)
                                Spacer()
                                Text(RelativeTime.describe(listing.firstSeenAt))
                                    .foregroundStyle(.secondary)
                            }
                            .font(.caption)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if let checked = watch.lastCheckedAt {
                Text("checked \(RelativeTime.describe(checked))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    /// Never a blank space: an empty watch says since when it has been empty.
    private var emptyMessage: String {
        watch.lastCheckedAt == nil
            ? "not checked yet"
            : "nothing yet, since \(watch.createdAt.formatted(.dateTime.month().day()))"
    }
}
