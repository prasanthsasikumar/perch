import AppKit
import SwiftUI

/// One property. Collapsed it is the week's headline; expanded it is
/// everything the summary script prints.
struct PropertyCardView: View {
    let property: AnalyticsProperty
    let stats: PropertyStats?
    let failure: AnalyticsError?
    let clientEmail: String?
    let isExpanded: Bool
    let isStale: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if let failure {
                FailureNote(failure: failure, clientEmail: clientEmail)
            }

            if let stats {
                weekHeadline(stats)
                if isExpanded {
                    Divider()
                    thirtyDays(stats)
                    if !stats.daily.isEmpty {
                        Divider()
                        dailyBreakdown(stats)
                    }
                }
            } else if failure == nil {
                Text("No data yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 10)
        // Stale numbers are still worth showing; dimming says so without
        // taking them away.
        .opacity(isStale ? 0.55 : 1)
    }

    private var header: some View {
        Button(action: onToggle) {
            HStack(spacing: 6) {
                Text(property.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func weekHeadline(_ stats: PropertyStats) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                Text("This week")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                SparklineView(points: stats.daily)
                    .frame(width: 92)
            }
            MetricRow(
                label: "Users",
                value: Formatting.compact(stats.currentWeek.activeUsers),
                change: stats.usersChange
            )
            MetricRow(
                label: "Sessions",
                value: Formatting.compact(stats.currentWeek.sessions),
                change: stats.sessionsChange
            )
        }
    }

    private func thirtyDays(_ stats: PropertyStats) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Last 30 days")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 14) {
                Stat(value: Formatting.compact(stats.last30Days.activeUsers), label: "users")
                Stat(value: Formatting.compact(stats.last30Days.sessions), label: "sessions")
                Stat(value: Formatting.compact(stats.last30Days.screenPageViews), label: "views")
            }
            HStack(spacing: 14) {
                Stat(value: Formatting.rate(stats.last30Days.bounceRate), label: "bounce")
                Stat(value: Formatting.duration(stats.last30Days.averageSessionDuration), label: "avg. session")
            }
        }
    }

    private func dailyBreakdown(_ stats: PropertyStats) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Daily")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(stats.daily) { point in
                HStack {
                    Text(Self.dayLabel(point.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(Formatting.compact(point.activeUsers))
                        .font(.caption.monospacedDigit())
                    Text(Formatting.compact(point.sessions))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
            }
        }
    }

    /// `20260728` is not a date anyone reads. `Mon 28 Jul` is.
    static func dayLabel(_ gaDate: String) -> String {
        guard let date = gaDateParser.date(from: gaDate) else { return gaDate }
        return dayFormatter.string(from: date)
    }

    private static let gaDateParser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return formatter
    }()
}

// MARK: - Pieces

private struct MetricRow: View {
    let label: String
    let value: String
    let change: PercentChange

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.callout)
            Spacer()
            Text(value)
                .font(.callout.monospacedDigit().weight(.medium))
            HStack(spacing: 2) {
                if let isUp = change.isUp {
                    Image(systemName: isUp ? "arrow.up" : "arrow.down")
                        .font(.system(size: 8, weight: .bold))
                }
                Text(change.text)
                    .font(.caption.monospacedDigit())
            }
            .foregroundStyle(tint)
            .frame(width: 62, alignment: .trailing)
        }
    }

    private var tint: Color {
        switch change.isUp {
        case true: .green
        case false: .red
        default: .secondary
        }
    }
}

private struct Stat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.callout.monospacedDigit().weight(.medium))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

/// A failure the user can act on, with the service-account address right there
/// rather than described in the abstract.
private struct FailureNote: View {
    let failure: AnalyticsError
    let clientEmail: String?

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.caption)
            Text(failure.message(clientEmail: clientEmail))
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            if case .permissionDenied = failure, let clientEmail {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(clientEmail, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Copy the service account address")
            }
        }
        .foregroundStyle(.orange)
    }
}
