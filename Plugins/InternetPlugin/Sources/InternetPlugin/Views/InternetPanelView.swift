import SwiftUI

/// The verdict first, then the three numbers behind it, then each target and
/// the speed test.
struct InternetPanelView: View {
    let store: InternetStore

    /// Opening the panel is someone asking "is it working right now?", so a
    /// check more than this old is redone.
    private static let openRefreshAge: TimeInterval = 15

    var body: some View {
        // Re-evaluated every few seconds so "just now" and the verdict's
        // time window move on while the panel sits open.
        TimelineView(.periodic(from: .now, by: 5)) { _ in
            content(store.report)
        }
        .task { await store.checkIfStale(maxAge: Self.openRefreshAge) }
    }

    private func content(_ report: HealthReport) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                if let notice = store.loadFailureNotice {
                    Text(notice).font(.caption).foregroundStyle(.orange)
                }
                if let notice = store.saveFailureNotice {
                    Text(notice).font(.caption).foregroundStyle(.red)
                }

                header(report)
                stats(report)

                if store.checks.count > 1 {
                    VStack(alignment: .leading, spacing: 3) {
                        LatencyTrendView(checks: store.checks)
                        Text("Latency over the last \(trendSpan)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()
                targets
                Divider()
                speed
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()
            footer
        }
    }

    private func header(_ report: HealthReport) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: report.verdict.symbol)
                .font(.title2)
                .foregroundStyle(report.verdict.color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(report.verdict.title)
                    .font(.headline)
                Text(report.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let connection {
                    Text(connection)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var connection: String? {
        guard let path = store.path, let interface = path.interface else { return nil }
        var parts = [interface.rawValue]
        if path.isExpensive { parts.append("metered") }
        if path.isConstrained { parts.append("Low Data Mode") }
        return parts.joined(separator: " · ")
    }

    private func stats(_ report: HealthReport) -> some View {
        HStack(spacing: 0) {
            stat("Latency", report.latency.map(Format.milliseconds),
                 warn: (report.latency ?? 0) > HealthReport.fairLatency)
            stat("Jitter", report.jitter.map(Format.milliseconds),
                 warn: (report.jitter ?? 0) > HealthReport.fairJitter)
            stat("Loss", report.loss.map(Format.percent),
                 warn: (report.loss ?? 0) >= HealthReport.fairLoss)
        }
    }

    private func stat(_ title: String, _ value: String?, warn: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value ?? "—")
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(warn ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var trendSpan: String {
        guard let first = store.checks.first?.at, let last = store.checks.last?.at else { return "" }
        let minutes = Int((last.timeIntervalSince(first) / 60).rounded())
        return minutes >= 60 ? "hour" : minutes <= 1 ? "minute" : "\(minutes) minutes"
    }

    private var targets: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(store.targets) { target in
                let outcome = store.latestOutcomes[target.id]
                HStack(spacing: 6) {
                    Circle()
                        .fill(color(outcome))
                        .frame(width: 6, height: 6)
                    Text(target.name)
                    Spacer()
                    Text(describe(outcome))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
    }

    private func color(_ outcome: ProbeOutcome?) -> Color {
        switch outcome {
        case nil: .secondary
        case .ok: .green
        case .intercepted, .dnsFailed: .orange
        case .failed: .red
        }
    }

    private func describe(_ outcome: ProbeOutcome?) -> String {
        switch outcome {
        case nil: "—"
        case .ok(let ms): Format.milliseconds(ms)
        case .intercepted: "intercepted"
        case .dnsFailed: "no DNS"
        case .failed: "no answer"
        }
    }

    private var speed: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                if let speed = store.speed {
                    Text("Download \(Format.speed(speed.megabitsPerSecond))")
                        .font(.caption.weight(.medium))
                    Text("Tested \(RelativeTime.describe(speed.at))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No speed test yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let failure = store.speedFailure {
                    Text(failure)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            if store.isTestingSpeed {
                ProgressView().controlSize(.mini)
                Text("Testing…").font(.caption).foregroundStyle(.secondary)
            } else {
                Button("Test speed") { Task { await store.testSpeed() } }
                    .buttonStyle(.link)
                    .font(.caption)
                    .help(store.path?.isExpensive == true
                          ? "This network is metered. A speed test downloads 25 MB."
                          : "Downloads 25 MB from Cloudflare.")
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if store.isChecking {
                ProgressView().controlSize(.mini)
                Text("Checking…")
            } else if let last = store.lastChecked {
                Text("Checked \(RelativeTime.describe(last)) · every 30 seconds")
            } else {
                Text("Not checked yet")
            }
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
