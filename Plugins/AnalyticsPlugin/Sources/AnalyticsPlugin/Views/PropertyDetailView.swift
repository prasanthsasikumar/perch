import AppKit
import SwiftUI

/// The week behind one card, split by source, place, device and page — enough
/// to tell the people from the crawlers.
struct PropertyDetailView: View {
    let property: AnalyticsProperty
    let store: AnalyticsStore

    private enum Phase {
        case loading
        case loaded(PropertyBreakdown)
        case failed(AnalyticsError)
    }

    @State private var phase: Phase = .loading

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                switch phase {
                case .loading:
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.top, 40)
                case .failed(let error):
                    failure(error)
                case .loaded(let breakdown):
                    summary(breakdown.totals)
                    ForEach(breakdown.sections) { section in
                        SectionTable(section: section)
                    }
                }
            }
            .padding(20)
        }
        .frame(minWidth: 520, idealWidth: 600, minHeight: 400, idealHeight: 720)
        .task { await load() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(property.title)
                    .font(.title2.weight(.semibold))
                Text("Last 7 days")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await load() }
            } label: {
                Label("Reload", systemImage: "arrow.clockwise")
            }
            .disabled(isLoading)
        }
    }

    private func summary(_ totals: PropertyStats.Totals) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 24) {
                Figure(value: Formatting.compact(totals.activeUsers), label: "users")
                Figure(value: Formatting.compact(totals.sessions), label: "sessions")
                Figure(value: Formatting.compact(totals.engagedSessions), label: "engaged")
                Figure(value: Formatting.rate(totals.engagementRate), label: "engagement")
                Figure(value: Formatting.duration(totals.averageEngagementTime), label: "avg. time")
                Figure(value: Formatting.decimal(totals.pagesPerSession), label: "pages / session")
            }
            if totals.looksLikeBots {
                BotNote()
            }
            Text("Engaged means the visit lasted over 10 seconds, saw a second page, or converted. Rows where nobody engaged are dimmed; they are usually crawlers.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func failure(_ error: AnalyticsError) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(error.message(clientEmail: store.clientEmail), systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            Button("Retry") { Task { await load() } }
        }
    }

    private var isLoading: Bool {
        if case .loading = phase { return true }
        return false
    }

    private func load() async {
        phase = .loading
        do {
            phase = .loaded(try await store.breakdown(for: property.id))
        } catch is CancellationError {
            // The window closed mid-fetch; nothing is left to show it to.
        } catch let error as AnalyticsError {
            phase = .failed(error)
        } catch {
            phase = .failed(.malformedResponse)
        }
    }
}

// MARK: - Pieces

private struct SectionTable: View {
    let section: PropertyBreakdown.Section

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(section.dimension.title)
                .font(.headline)
            if section.rows.isEmpty {
                Text("No data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 4) {
                    GridRow {
                        Text("").gridColumnAlignment(.leading)
                        Text("Users")
                        Text("Sessions")
                        Text("Engaged")
                        Text("Avg. time")
                        Text("Pages")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Divider()
                    ForEach(section.rows) { row in
                        GridRow {
                            Text(row.value)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .help(row.value)
                            Text(Formatting.compact(row.totals.activeUsers))
                            Text(Formatting.compact(row.totals.sessions))
                            Text(Formatting.rate(row.totals.engagementRate))
                            Text(Formatting.duration(row.totals.averageEngagementTime))
                            Text(Formatting.decimal(row.totals.pagesPerSession))
                        }
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(row.totals.hasNoEngagement ? .secondary : .primary)
                        .opacity(row.totals.hasNoEngagement ? 0.6 : 1)
                    }
                }
            }
        }
    }
}

private struct Figure: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.title3.monospacedDigit().weight(.medium))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Shared by the card and the window so the two never disagree on wording.
struct BotNote: View {
    var body: some View {
        Label("Mostly bots", systemImage: "exclamationmark.triangle.fill")
            .font(.caption.weight(.medium))
            .foregroundStyle(.orange)
            .help("Under 20% of sessions were engaged. Most of this traffic loads one page and leaves in 0 seconds.")
    }
}

// MARK: - Window

/// One window per property, reused if it is already open.
@MainActor
enum PropertyDetailWindows {
    private static var windows: [String: NSWindow] = [:]

    static func show(_ property: AnalyticsProperty, store: AnalyticsStore) {
        let window = windows[property.id] ?? makeWindow(for: property, store: store)
        windows[property.id] = window
        window.title = "\(property.title) — Analytics"
        // A menu bar app is never frontmost when its dropdown is clicked.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private static func makeWindow(for property: AnalyticsProperty, store: AnalyticsStore) -> NSWindow {
        let window = NSWindow(
            contentViewController: NSHostingController(
                rootView: PropertyDetailView(property: property, store: store)
            )
        )
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        // ARC owns it via `windows`; closing drops it from there, so the next
        // open builds a fresh window that fetches fresh numbers.
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 600, height: 720))
        window.center()
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { _ in
            MainActor.assumeIsolated { windows[property.id] = nil }
        }
        return window
    }
}
