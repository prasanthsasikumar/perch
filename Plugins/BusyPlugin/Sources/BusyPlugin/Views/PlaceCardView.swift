import SwiftUI

/// One place: its name, how busy it is right now, and today's shape.
struct PlaceCardView: View {
    let place: Place
    let result: Busyness?
    let failure: String?
    let onDelete: () -> Void

    @State private var hovering = false

    private var reading: BusyReading? { result?.reading }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(reading?.name ?? place.query)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                // Hover-gated like Market's trash button, rather than a
                // control that is always sitting there to be misclicked.
                if hovering {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove this place")
                }
            }
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .contextMenu {
                Button("Remove", role: .destructive, action: onDelete)
            }
            .accessibilityAction(named: "Remove", onDelete)

            if let reading {
                HStack(spacing: 6) {
                    Circle()
                        .fill(reading.level.color)
                        .frame(width: 8, height: 8)
                    Text(reading.summary)
                        .font(.caption)
                        .lineLimit(2)
                }

                if !reading.hours.isEmpty {
                    HistogramView(
                        hours: reading.hours,
                        currentHour: reading.currentHour,
                        livePercent: reading.livePercent,
                        level: reading.level,
                        ceiling: reading.chartCeiling
                    )
                }
            }

            if let failure {
                Text(failure)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let result {
                Text("checked \(RelativeTime.describe(result.fetchedAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("not checked yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        // Stale numbers are still worth showing; dimming says so without
        // taking them away.
        .opacity(failure != nil && result != nil ? 0.55 : 1)
    }
}
