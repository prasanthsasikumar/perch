import SwiftUI

/// One link: what it is, how tall to download it, and where it's up to.
struct JobRowView: View {
    let job: DownloadJob
    let store: DownloadStore

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            thumbnail
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .top, spacing: 4) {
                    Text(job.title)
                        .font(.caption.weight(.medium))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        store.remove(job.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Remove")
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                status
            }
        }
    }

    private var subtitle: String? {
        guard let info = job.info else { return job.url.host() }
        let parts = [info.uploader, info.duration.map(Self.formatDuration)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var thumbnail: some View {
        AsyncImage(url: job.info?.thumbnail) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            Rectangle().fill(.quaternary)
                .overlay {
                    if job.state == .fetching { ProgressView().controlSize(.mini) }
                }
        }
        .frame(width: 64, height: 36)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    @ViewBuilder
    private var status: some View {
        switch job.state {
        case .fetching:
            Text("Looking up…")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .ready:
            HStack(spacing: 6) {
                if store.format == .video, let heights = job.info?.heights, !heights.isEmpty {
                    Picker("Quality", selection: Binding(
                        get: { job.maxHeight },
                        set: { store.setMaxHeight($0, for: job.id) }
                    )) {
                        Text("Best").tag(Int?.none)
                        ForEach(heights, id: \.self) { Text("\($0)p").tag(Int?.some($0)) }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .fixedSize()
                }
                Spacer()
                Button("Download \(store.format.label)") { store.download(job.id) }
                    .controlSize(.small)
                    .keyboardShortcut(.defaultAction)
            }
        case .downloading(let progress):
            HStack(spacing: 6) {
                if let progress, progress < 1 {
                    ProgressView(value: progress)
                        .controlSize(.small)
                    Text("\(Int(progress * 100))%")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView().controlSize(.mini)
                    Text(progress == nil ? "Starting…" : "Finishing…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                Button("Cancel") { store.cancel(job.id) }
                    .buttonStyle(.link)
                    .font(.caption2)
            }
        case .failed(let message):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                Spacer(minLength: 4)
                Button("Retry") { store.retry(job.id) }
                    .buttonStyle(.link)
                    .font(.caption2)
            }
        }
    }

    static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let (h, m, s) = (total / 3600, total / 60 % 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
