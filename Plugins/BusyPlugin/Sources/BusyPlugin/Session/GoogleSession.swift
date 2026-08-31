import Foundation
import PerchKit
import WebKit

/// What one page load produced: the script's payload, and where the load
/// actually ended up, so the caller can tell a consent redirect from a
/// results page.
public struct LoadedPage {
    public let payload: String
    public let finalURL: URL?
}

/// Owns the one `WKWebView` everything Google-shaped goes through.
///
/// One webview keeps the store's serial refresh structural: two fetches
/// cannot overlap because there is nothing for the second one to run in.
/// There is no sign-in and no session to keep — Google renders popular times
/// for anyone — so this is `FacebookSession` with the sign-in half removed.
///
/// Parked in an offscreen window while working: a webview outside a window
/// may not lay out or run scripts reliably, and we need it live without
/// showing it.
@MainActor
public final class GoogleSession: NSObject {
    /// A `WKWebView` load can hang with no delegate callback ever arriving.
    /// Without a deadline that wedges the refresh loop permanently.
    private let navigationTimeout: TimeInterval
    /// Google fills the knowledge panel in after the page's own load event,
    /// so the widget is often not there the instant `didFinish` fires.
    private let settleDelay: TimeInterval

    public let webView: WKWebView
    private let hiddenWindow: NSWindow
    private var pendingLoad: CheckedContinuation<Void, Error>?

    public init(navigationTimeout: TimeInterval = 30, settleDelay: TimeInterval = 2) {
        self.navigationTimeout = navigationTimeout
        self.settleDelay = settleDelay

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 1280, height: 900), configuration: configuration
        )

        hiddenWindow = ParkedWindow(
            contentRect: NSRect(x: -10_000, y: -10_000, width: 1280, height: 900),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        hiddenWindow.title = "Busy"
        hiddenWindow.contentView = webView
        hiddenWindow.orderBack(nil)

        // WKWebView's own user agent lacks the `Version/… Safari/…` tokens
        // that Google uses to recognise a full browser; without them it
        // serves a reduced results page with no knowledge panel, and so no
        // busyness widget — verified on 2026-08-31 with both agents against
        // the same query. This is Safari's string for the same WebKit.
        webView.customUserAgent = Self.desktopSafariUserAgent

        super.init()
        webView.navigationDelegate = self
    }

    static let desktopSafariUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
        + "(KHTML, like Gecko) Version/17.5 Safari/605.1.15"

    /// Loads a page, waits for Google to fill it in, and runs the extractor.
    public func load(url: URL) async throws -> LoadedPage {
        try await navigate(to: url)
        try? await Task.sleep(for: .seconds(settleDelay))

        let script = try extractScriptSource()
        let result: Any?
        do {
            result = try await webView.evaluateJavaScript(script)
        } catch {
            throw BusyError.failed("could not read the page")
        }
        guard let payload = result as? String else {
            throw BusyError.failed("the page returned no busyness payload")
        }
        return LoadedPage(payload: payload, finalURL: webView.url)
    }

    // MARK: - Navigation

    private func navigate(to url: URL) async throws {
        webView.stopLoading()
        return try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                try await withCheckedThrowingContinuation { continuation in
                    self.pendingLoad = continuation
                    self.webView.load(URLRequest(url: url))
                }
            }
            group.addTask { @MainActor in
                try await Task.sleep(for: .seconds(self.navigationTimeout))
                let timedOut = BusyError.failed("navigation timed out")
                self.finishLoad(throwing: timedOut)
                // Thrown as well as handed to the continuation: whichever task
                // `next()` sees first, a timed-out navigation has to come back
                // as an error rather than fall through to extraction.
                throw timedOut
            }
            defer { group.cancelAll() }
            try await group.next()
        }
    }

    private func finishLoad(throwing error: Error?) {
        guard let continuation = pendingLoad else { return }
        pendingLoad = nil
        if let error {
            webView.stopLoading()
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }
}

extension GoogleSession: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finishLoad(throwing: nil)
    }

    public func webView(
        _ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error
    ) {
        finishLoad(throwing: BusyError.failed(error.localizedDescription))
    }

    public func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        finishLoad(throwing: BusyError.failed(error.localizedDescription))
    }
}
