import Observation
import PerchKit
import SwiftUI

/// Paste a link, get the video or its audio in Downloads. A native take on
/// ReClip: the same yt-dlp underneath, without a local web server.
///
/// Declares `.network` because it fetches from whatever site the link points
/// at, and `.downloads` because that is where the files go. The work is done
/// by the user's own Homebrew yt-dlp and ffmpeg; see `YTDLPDownloader` for why
/// they aren't bundled.
@MainActor
@Observable
public final class Download: PerchPlugin {
    public static let identifier = "org.ahlab.perch.download"
    public static let displayName = "Download"
    public static let icon = "arrow.down.circle"
    public static let capabilities: Set<PluginCapability> = [.network, .downloads]

    public let store: DownloadStore

    public required convenience init(context: PluginContext) {
        self.init(context: context, downloader: YTDLPDownloader())
    }

    /// The testable initializer.
    public init(context: PluginContext, downloader: Downloader, destination: URL = DownloadStore.userDownloads) {
        store = DownloadStore(
            storage: context.storage,
            defaults: context.defaults,
            downloader: downloader,
            destination: destination
        )
    }

    public var panel: AnyView {
        AnyView(DownloadPanelView(store: store))
    }

    /// Progress while something is downloading, so a long one can be left to
    /// run with the panel closed; just the icon otherwise.
    public var menuBarLabel: MenuBarLabel? {
        let active = store.activeDownloads
        guard let first = active.first else { return MenuBarLabel(systemImage: Self.icon) }
        let percent: String? = if case .downloading(let progress?) = first.state {
            "\(Int(progress * 100))%"
        } else {
            nil
        }
        let text: String? = active.count > 1
            ? [String(active.count), percent].compactMap { $0 }.joined(separator: " · ")
            : percent
        return MenuBarLabel(systemImage: "arrow.down.circle.fill", text: text)
    }

    public var footerActions: [PluginAction] {
        [
            PluginAction(id: "folder", title: "Open Downloads") { [store] in
                store.openDestination()
            }
        ]
    }

    public func flush() { store.saveNow() }

    /// Switching the plugin off stops anything it is downloading.
    public func setEnabled(_ isEnabled: Bool) {
        if !isEnabled { store.cancelAll() }
    }
}
