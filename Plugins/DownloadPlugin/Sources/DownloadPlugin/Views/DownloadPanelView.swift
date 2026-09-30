import AppKit
import SwiftUI

/// A field to paste into, MP4 or MP3, then each link as a row and the files
/// already saved.
struct DownloadPanelView: View {
    @Bindable var store: DownloadStore
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let notice = store.loadFailureNotice {
                Text(notice).font(.caption).foregroundStyle(.orange)
            }
            if let notice = store.saveFailureNotice {
                Text(notice).font(.caption).foregroundStyle(.red)
            }

            if store.isAvailable {
                input
                if !store.jobs.isEmpty { jobs }
                if !store.recent.isEmpty { recent }
                if store.jobs.isEmpty && store.recent.isEmpty { hint }
            } else {
                SetupView(store: store)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .onAppear { fieldFocused = true }
    }

    private var input: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                TextField("Paste a link", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .focused($fieldFocused)
                    .onSubmit(submit)
                Button {
                    if let text = NSPasteboard.general.string(forType: .string) {
                        draft = text
                        submit()
                    }
                } label: {
                    Image(systemName: "doc.on.clipboard")
                }
                .buttonStyle(.borderless)
                .help("Paste from the clipboard and look it up")
            }
            HStack {
                Picker("Format", selection: $store.format) {
                    ForEach(MediaFormat.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer()
                Text("Saves to \(store.destination.lastPathComponent)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func submit() {
        if store.add(draft) > 0 || PastedLinks.extract(draft).isEmpty == false {
            draft = ""
        }
    }

    private var jobs: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(store.jobs) { job in
                JobRowView(job: job, store: store)
            }
            if store.readyCount > 1 {
                Button("Download all (\(store.readyCount))") { store.downloadAll() }
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            HStack {
                Text("Recent")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { store.clearRecent() }
                    .buttonStyle(.link)
                    .font(.caption)
            }
            ForEach(store.recent.prefix(6)) { item in
                HStack(spacing: 6) {
                    Image(systemName: item.file.pathExtension == "mp3" ? "music.note" : "film")
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Button(item.file.lastPathComponent) { store.open(item) }
                        .buttonStyle(.plain)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help("Open")
                    Spacer(minLength: 4)
                    Button {
                        store.reveal(item)
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .buttonStyle(.borderless)
                    .help("Show in Finder")
                }
                .font(.caption)
            }
        }
    }

    private var hint: some View {
        Text("YouTube, TikTok, Instagram, X, Vimeo, SoundCloud and about a thousand other sites. Paste several links at once to queue them.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Shown until yt-dlp and ffmpeg are found.
private struct SetupView: View {
    let store: DownloadStore
    private static let command = "brew install yt-dlp ffmpeg"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Needs yt-dlp and ffmpeg", systemImage: "wrench.and.screwdriver")
                .font(.headline)
            Text("Download uses the copies Homebrew installs, so `brew upgrade` keeps it working when sites change. In Terminal, run:")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text(Self.command)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(Self.command, forType: .string)
                }
                .controlSize(.small)
            }
            .padding(6)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
            Button("Check again") { store.recheckTools() }
                .controlSize(.small)
        }
    }
}
