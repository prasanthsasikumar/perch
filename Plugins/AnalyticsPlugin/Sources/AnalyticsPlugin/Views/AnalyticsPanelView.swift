import AppKit
import SwiftUI

/// The plugin's half of the dropdown: a card per property, and one line
/// saying how old the numbers are.
struct AnalyticsPanelView: View {
    @Bindable var store: AnalyticsStore

    /// How old the cache may be before opening the panel refetches. Short
    /// enough that a deliberate reopen feels live, long enough that clicking
    /// twice does not hit the API twice.
    private static let openRefreshAge: TimeInterval = 60

    @State private var expanded: Set<String> = []
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Group {
            if !store.isConfigured {
                ConnectPrompt(openSettings: showSettings)
            } else if store.properties.isEmpty {
                EmptyPrompt(openSettings: showSettings)
            } else {
                content
            }
        }
        .task {
            expanded = Set([store.primaryPropertyID].compactMap { $0 })
            await store.refreshIfStale(maxAge: Self.openRefreshAge)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let failure = store.credentialFailure {
                CredentialBanner(failure: failure, openSettings: showSettings)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(store.properties.enumerated()), id: \.element.id) { index, property in
                        if index > 0 { Divider() }
                        PropertyCardView(
                            property: property,
                            stats: store.stats[property.id],
                            failure: store.failures[property.id],
                            clientEmail: store.clientEmail,
                            isExpanded: expanded.contains(property.id),
                            isStale: store.failures[property.id] != nil && store.stats[property.id] != nil,
                            onToggle: { toggle(property.id) }
                        )
                    }
                }
                .padding(.horizontal, 12)
            }
            // Two cards fit; beyond that it scrolls rather than growing the
            // dropdown past the point of being a dropdown.
            .frame(maxHeight: 380)

            Divider()
            footer
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if store.isRefreshing {
                ProgressView()
                    .controlSize(.mini)
                Text("Refreshing…")
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
        guard let lastRefreshed = store.lastRefreshed else { return "Not fetched yet" }
        let age = Self.relative.localizedString(for: lastRefreshed, relativeTo: Date())
        return store.failures.isEmpty ? "Updated \(age)" : "Couldn't refresh — showing data from \(age)"
    }

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    private func toggle(_ id: String) {
        if expanded.contains(id) {
            expanded.remove(id)
        } else {
            expanded.insert(id)
        }
    }

    /// A menu bar only app is not frontmost when its panel is clicked, so
    /// Settings opens behind whatever is, unless we activate first.
    private func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
    }
}

// MARK: - Empty states

private struct ConnectPrompt: View {
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Connect Google Analytics")
                .font(.subheadline.weight(.medium))
            Text("Import a service-account key to see your properties here.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open Settings", action: openSettings)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }
}

private struct EmptyPrompt: View {
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text("No properties yet")
                .font(.subheadline.weight(.medium))
            Text("Find the ones this account can see in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open Settings", action: openSettings)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }
}

/// A credential problem breaks every property at once, so it says so once at
/// the top instead of repeating itself on every card.
private struct CredentialBanner: View {
    let failure: AnalyticsError
    let openSettings: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(failure.message(clientEmail: nil))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button("Fix", action: openSettings)
                .controlSize(.mini)
        }
        .font(.caption)
        .foregroundStyle(.orange)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.1))
    }
}
