import SwiftUI

struct WatchRowView: View {
    let watch: Watch
    let unseenCount: Int
    let listings: [Listing]
    let isExpanded: Bool
    let onToggle: () -> Void
    let onDelete: () -> Void

    /// How many listings an expanded watch shows before it asks. Enough to
    /// see what turned up today; few enough that three watches fit on
    /// screen. "Show all" lifts it for that watch until the panel closes.
    static let collapsedLimit = 5

    @State private var hovering = false
    @State private var showingAll = false

    private var shown: [Listing] {
        showingAll ? listings : Array(listings.prefix(Self.collapsedLimit))
    }

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
                // Hover-gated like `TaskRowView`'s trash button, rather than
                // a control that is always sitting there to be misclicked —
                // this one deletes up to 200 listings along with the watch.
                if hovering {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Delete this watch")
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onToggle)
            .onHover { hovering = $0 }
            .contextMenu {
                Button("Delete", role: .destructive, action: onDelete)
            }
            .accessibilityAction(named: "Delete", onDelete)

            if isExpanded {
                if listings.isEmpty {
                    Text(emptyMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(shown) { listing in
                        Link(destination: listing.url) {
                            HStack(spacing: 4) {
                                Text(listing.price)
                                Text(Self.displayTitle(listing)).lineLimit(1)
                                Spacer()
                                Text(RelativeTime.describe(listing.firstSeenAt))
                                    .foregroundStyle(.secondary)
                            }
                            .font(.caption)
                        }
                        .buttonStyle(.plain)
                    }
                    if listings.count > Self.collapsedLimit {
                        Button(showingAll ? "Show fewer" : "Show all \(listings.count)") {
                            showingAll.toggle()
                        }
                        .font(.caption)
                        .buttonStyle(.link)
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

    /// Facebook lets a listing go out with no title. Its location is the
    /// next most useful thing, but it must read as a stand-in, not a title.
    static func displayTitle(_ listing: Listing) -> String {
        if !listing.title.isEmpty { return listing.title }
        return listing.location.isEmpty ? "Untitled listing" : "Untitled listing in \(listing.location)"
    }

    /// Never a blank space: an empty watch says since when it has been empty.
    private var emptyMessage: String {
        watch.lastCheckedAt == nil
            ? "not checked yet"
            : "nothing yet, since \(watch.createdAt.formatted(.dateTime.month().day()))"
    }
}
