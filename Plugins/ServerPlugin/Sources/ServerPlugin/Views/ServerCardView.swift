import AppKit
import SwiftUI

/// One machine: what is wrong with it first, then the numbers, then the
/// detail one disclosure down.
struct ServerCardView: View {
    let server: ServerTarget
    let snapshot: HostSnapshot?
    let failure: String?
    let alerts: [HostAlert]
    let trend: [TrendPoint]
    let onDelete: () -> Void

    @State private var showsDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            header

            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let snapshot {
                // Stale numbers are dimmed rather than hidden: after a dropped
                // connection, the last known state is still the most useful
                // thing on screen.
                meters(snapshot)
                    .opacity(failure == nil ? 1 : 0.5)

                if !alerts.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(alerts) { alert in
                            Label(alert.message, systemImage: alert.level == .critical
                                  ? "exclamationmark.octagon.fill" : "exclamationmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(alert.level == .critical ? .red : .orange)
                        }
                    }
                }

                DisclosureGroup(isExpanded: $showsDetail) {
                    detail(snapshot)
                } label: {
                    Text("Detail")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .disclosureGroupStyle(.automatic)
            } else if failure == nil {
                Text("Not checked yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(server.name)
                    .font(.subheadline.weight(.semibold))
                if let snapshot {
                    // The core count lives on the Load meter instead, where it
                    // is the number that makes the reading mean anything. Here
                    // it only made the line wrap.
                    Text("\(snapshot.host) · up \(Format.uptime(snapshot.uptime))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text(server.displayHost)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if !trend.isEmpty {
                TrendView(points: trend)
                    .frame(width: 66)
            }
            Menu {
                Button("Open Dashboard") {
                    NSWorkspace.shared.open(EndpointURL.dashboardURL(for: server.endpoint))
                }
                Divider()
                Button("Remove", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 18)
        }
    }

    @ViewBuilder
    private func meters(_ snapshot: HostSnapshot) -> some View {
        VStack(spacing: 6) {
            MeterView(
                title: "CPU",
                value: snapshot.cpuBusy.map(Format.percent) ?? "—",
                fraction: (snapshot.cpuBusy ?? 0) / 100,
                warning: 0.7,
                critical: 0.9,
                caption: cpuCaption(snapshot)
            )
            MeterView(
                title: "Load",
                value: Format.load(snapshot.load1),
                fraction: snapshot.loadFraction,
                warning: HostAlerts.loadWarning,
                critical: HostAlerts.loadCritical,
                caption: "\(snapshot.ncpu) core\(snapshot.ncpu == 1 ? "" : "s") · 5m \(Format.load(snapshot.load5)) · 15m \(Format.load(snapshot.load15))"
            )
            MeterView(
                title: "Memory",
                value: "\(Format.bytes(snapshot.memUsed)) / \(Format.bytes(snapshot.memTotal))",
                fraction: snapshot.memoryFraction,
                caption: "\(Format.bytes(snapshot.memAvail)) available"
            )
            if snapshot.swapTotal > 0 {
                MeterView(
                    title: "Swap",
                    value: "\(Format.bytes(snapshot.swapUsed)) / \(Format.bytes(snapshot.swapTotal))",
                    fraction: snapshot.swapFraction,
                    warning: 0.25,
                    critical: 0.6,
                    caption: snapshot.isSwapping
                        ? "in \(Format.rate(snapshot.swapIn ?? 0)) · out \(Format.rate(snapshot.swapOut ?? 0))"
                        : "not paging"
                )
            }
            MeterView(
                title: "Disk",
                value: Format.percent(snapshot.diskFraction * 100),
                fraction: snapshot.diskFraction,
                warning: HostAlerts.diskWarning,
                critical: HostAlerts.diskCritical,
                caption: "\(Format.bytes(snapshot.fsTotal - snapshot.fsUsed)) free of \(Format.bytes(snapshot.fsTotal))"
            )
            networkRow(snapshot)
        }
    }

    private func cpuCaption(_ snapshot: HostSnapshot) -> String? {
        guard snapshot.cpuBusy != nil else { return "waiting for a second sample" }
        var parts: [String] = []
        if let user = snapshot.cpuUser { parts.append("user \(Format.percent(user))") }
        if let system = snapshot.cpuSys { parts.append("sys \(Format.percent(system))") }
        if let wait = snapshot.cpuIowait, wait >= 1 { parts.append("io \(Format.percent(wait))") }
        if let steal = snapshot.cpuSteal, steal >= 1 { parts.append("steal \(Format.percent(steal))") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func networkRow(_ snapshot: HostSnapshot) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Network")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text("↓ \(Format.rate(snapshot.netRxBps ?? 0))  ↑ \(Format.rate(snapshot.netTxBps ?? 0))")
                .font(.caption.monospacedDigit())
        }
    }

    @ViewBuilder
    private func detail(_ snapshot: HostSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let traffic = snapshot.traffic {
                section("Traffic") {
                    row("Today", "↓ \(Format.bytes(traffic.today.rx))  ↑ \(Format.bytes(traffic.today.tx))")
                    row("This month", "↓ \(Format.bytes(traffic.month.rx))  ↑ \(Format.bytes(traffic.month.tx))")
                    if let since = traffic.since {
                        Text("Counted since \(since), when the agent started.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !snapshot.containers.isEmpty {
                section("Containers") {
                    // Only the busiest few: a card in a menu bar panel is not
                    // the place to list fifteen containers that are all idle.
                    ForEach(snapshot.containers.prefix(5)) { container in
                        row(container.name, "\(Format.percent(container.cpu)) · \(Format.bytes(container.mem))")
                    }
                }
            }

            if !snapshot.topCpu.isEmpty {
                section("Top processes") {
                    ForEach(snapshot.topCpu.prefix(5)) { process in
                        row(process.name, "\(Format.percent(process.cpu)) · \(Format.bytes(process.rss))")
                    }
                }
            }

            if !snapshot.health.isEmpty {
                section("Services") {
                    ForEach(snapshot.health) { check in
                        row(
                            check.name,
                            check.ok ? "\(check.code.map(String.init) ?? "ok") · \(check.ms ?? 0) ms"
                                     : (check.error ?? "down")
                        )
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Text(value)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}
