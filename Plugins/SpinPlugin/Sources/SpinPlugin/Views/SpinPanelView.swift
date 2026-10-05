import SwiftUI

struct SpinPanelView: View {
    @Bindable var model: SpinModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            nowPlaying
            Toggle("Show scene on desktop", isOn: $model.showsScene)
                .toggleStyle(.switch)
            if !model.showsScene {
                Text("Turn this on and the desktop becomes a turntable while Spotify or Music plays. macOS will ask once to let Perch read each player.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if model.artworkStatus == .notPermitted {
                HStack {
                    Text("Perch isn't allowed to read album art.").font(.caption)
                    Spacer()
                    Button("Open Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
                    }
                    .controlSize(.small)
                }
            }
            scenePicker
        }
        .padding(14)
    }

    private var nowPlaying: some View {
        HStack(spacing: 10) {
            Group {
                if let artwork = model.artwork {
                    Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "record.circle").font(.title2).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity).background(.quaternary)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                if let event = model.nowPlaying, let track = event.track {
                    Text(track.title).font(.headline).lineLimit(1)
                    Text("\(track.artist) · \(event.player.displayName)\(event.state == .playing ? "" : " · \(event.state.rawValue.capitalized)")")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    Text("Nothing playing").font(.headline)
                    Text("Play something in Spotify or Music").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var scenePicker: some View {
        HStack(spacing: 10) {
            ForEach(model.scenes) { scene in
                Button {
                    model.selectedSceneID = scene.id
                } label: {
                    VStack(spacing: 4) {
                        AsyncImage(url: scene.thumbnailURL) { image in
                            image.resizable().aspectRatio(16 / 9, contentMode: .fill)
                        } placeholder: {
                            Color.secondary.opacity(0.2)
                        }
                        .frame(width: 120, height: 68)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .stroke(model.selectedScene?.id == scene.id ? Color.accentColor : .clear, lineWidth: 2))
                        Text(scene.descriptor.name).font(.caption)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}
