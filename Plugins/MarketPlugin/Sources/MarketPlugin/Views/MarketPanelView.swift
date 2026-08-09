import AppKit
import SwiftUI

struct MarketPanelView: View {
    let store: MarketStore
    let poller: WatchPoller
    /// Opens the sign-in window. Absent when the plugin was built with an
    /// injected source, which has no webview to show.
    let onSignIn: (() -> Void)?

    @State private var query = ""
    @State private var maxPrice = ""
    @State private var maxPriceError: String?
    @State private var expanded: Set<UUID> = []
    @Environment(\.openSettings) private var openSettings

    var body: some View {
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

            statusLine

            HStack(spacing: 6) {
                TextField("What to watch for", text: $query)
                    .textFieldStyle(.roundedBorder)
                TextField("Max $", text: $maxPrice)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 64)
                    // Otherwise a rejected entry's caption outlives the
                    // rejection — it would still be showing after the user
                    // fixed the field but before submitting again.
                    .onChange(of: maxPrice) { maxPriceError = nil }
            }
            .disabled(!store.canAddWatch)
            .onSubmit(addWatch)

            if let maxPriceError {
                Text(maxPriceError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if !store.canAddWatch {
                HStack(spacing: 4) {
                    Text("Set a location in Settings first.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Open Settings", action: showSettings)
                        .font(.caption)
                        .buttonStyle(.link)
                }
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
            Button {
                onSignIn?()
            } label: {
                Label("Sign in to Facebook", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
            .help("Opens a window where you can sign in to Facebook")
        case .backoff:
            Text(poller.lastError.map { "Retrying — \($0)" } ?? "Retrying")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .idle, .polling:
            // Round after round of every watch scraping nothing is the one
            // signal that separates "nothing matched" from "the parser stopped
            // working" — worth saying rather than showing quiet emptiness.
            if poller.isScrapingHealthy {
                EmptyView()
            } else {
                Text("Facebook may have changed — check your sign-in")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func addWatch() {
        switch parseMaxPrice(maxPrice) {
        case .invalid:
            // A non-empty field that fails to parse must never fall through
            // to "no cap" — that would create an uncapped watch with no
            // sign anything went wrong.
            maxPriceError = "Max $ must be a number, like 200."
        case .empty:
            store.addWatch(query: query, maxPrice: nil)
            query = ""
            maxPrice = ""
            maxPriceError = nil
        case .value(let value):
            store.addWatch(query: query, maxPrice: value)
            query = ""
            maxPrice = ""
            maxPriceError = nil
        }
    }

    /// A menu bar only app is not frontmost when its panel is clicked, so
    /// Settings opens behind whatever is, unless we activate first. Matches
    /// AnalyticsPanelView's `showSettings`.
    private func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
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

/// The result of reading the "Max $" field.
///
/// `Int(text)` alone turns `"$200"`, `"200.50"`, and `"1,200"` into `nil`,
/// which `addWatch` reads as "no cap" — silently creating an uncapped watch
/// from what the user typed as a price limit. This keeps "the field was
/// empty" and "the field could not be parsed" distinct, so a caller can
/// refuse the second rather than treating it like the first.
enum MaxPriceInput: Equatable {
    case empty
    case value(Int)
    case invalid
}

/// Strips currency symbols and thousands separators, so `"$200"` and
/// `"1,200"` parse the way a user typing a price expects. A single decimal
/// point survives the strip and is read as dollars-and-cents, truncated to
/// whole dollars — `"200.50"` becomes `200` rather than the digit-smash
/// `20050` that dropping the `.` outright would produce.
///
/// Rejects, rather than silently coercing:
/// - a `-` anywhere in the field. It is a sign, not a currency symbol —
///   stripped like everything else that isn't a digit or `.`, `"-5"` would
///   otherwise silently become a cap of `5`.
/// - a value that truncates to zero or less (`"0"`, `"0.4"`). A watch with
///   a cap of $0 can never match anything; that is a mistake worth
///   rejecting, not a watch worth silently creating.
/// - anything `Int` cannot hold exactly. `Int(_: Double)` *traps* on a value
///   at or beyond `Int.max` (a 19-/20-digit entry is enough), and a trap
///   here takes down every plugin in the host, not just Market — worse,
///   it isn't a clean exit, so `MarketStore`'s debounced pending save and
///   `Market.flush()` both never run. `Int(exactly:)` returns `nil` instead
///   of trapping.
func parseMaxPrice(_ raw: String) -> MaxPriceInput {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return .empty }
    guard !trimmed.contains("-") else { return .invalid }

    let cleaned = trimmed.filter { $0.isNumber || $0 == "." }
    guard !cleaned.isEmpty, let dollars = Double(cleaned) else { return .invalid }
    guard
        let value = Int(exactly: dollars.rounded(.towardZero)),
        value > 0
    else { return .invalid }
    return .value(value)
}
