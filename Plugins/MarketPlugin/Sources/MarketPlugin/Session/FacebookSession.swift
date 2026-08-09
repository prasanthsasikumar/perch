import Foundation
import WebKit

/// The search URL for a watch, or `nil` when there is no city to search in.
///
/// Pure, so the URL shape is pinned by tests rather than discovered in
/// production.
public func marketplaceSearchURL(
    query: String, maxPrice: Int?, location: String, radiusKm: Int
) -> URL? {
    let city = location.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !city.isEmpty else { return nil }

    var components = URLComponents()
    components.scheme = "https"
    components.host = "www.facebook.com"
    components.path = "/marketplace/\(city)/search"
    var items = [
        URLQueryItem(name: "query", value: query),
        URLQueryItem(name: "radius", value: String(radiusKm)),
    ]
    if let maxPrice { items.append(URLQueryItem(name: "maxPrice", value: String(maxPrice))) }
    components.queryItems = items
    return components.url
}

/// Owns the one `WKWebView` everything Facebook-shaped goes through.
///
/// On `WKWebsiteDataStore.default()`, so the sign-in cookie survives quitting
/// Perch. The superseded Python sidecar signed in once per *run* and could not
/// do better without forking its upstream; this is the single biggest reason
/// the rewrite was worth it.
///
/// One webview also makes the poller's serial guarantee structural rather than
/// a matter of discipline.
@MainActor
public final class FacebookSession: NSObject {
    /// A `WKWebView` load can hang with no delegate callback ever arriving.
    /// Without a deadline that wedges the poller permanently.
    private let navigationTimeout: TimeInterval

    public let webView: WKWebView

    /// Parked offscreen while polling: a webview outside a window may not lay
    /// out or run scripts reliably, and we need it live without showing it.
    private let hiddenWindow: NSWindow
    private var pendingLoad: CheckedContinuation<Void, Error>?

    public init(navigationTimeout: TimeInterval = 30) {
        self.navigationTimeout = navigationTimeout

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 1280, height: 900), configuration: configuration
        )

        hiddenWindow = NSWindow(
            contentRect: NSRect(x: -10_000, y: -10_000, width: 1280, height: 900),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        hiddenWindow.title = "Market"
        hiddenWindow.contentView = webView
        hiddenWindow.orderBack(nil)

        super.init()
        webView.navigationDelegate = self
    }

    /// Loads a results page and returns whatever `extract.js` finds on it.
    ///
    /// Throws `SearchError.signedOut` when the page is a login wall, and
    /// `SearchError.failed` when navigation fails or times out.
    public func loadResults(url: URL) async throws -> [ScrapedListing] {
        try await navigate(to: url)

        let script = try extractScriptSource()
        let raw = try await evaluate(script)
        let listings = try decodeExtractedListings(raw)

        let signals = LoginSignals(
            urlPath: webView.url?.path ?? "",
            hasPasswordField: await evaluateBool(
                "document.querySelector('input[type=\"password\"]') !== null"
            ),
            hasLoginForm: await evaluateBool(
                "document.querySelector('form[action*=\"login\"]') !== null"
            ),
            listingCount: listings.count
        )
        if isLoginWall(signals) { throw SearchError.signedOut }

        return listings
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
                let timedOut = SearchError.failed("navigation timed out")
                self.finishLoad(throwing: timedOut)
                // Thrown as well as handed to the continuation: whichever task
                // `next()` happens to see first, a timed-out navigation has to
                // come back as an error. Returning normally here would let a
                // hung page fall through to extraction and be counted as a
                // watch that simply matched nothing.
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

    private func evaluate(_ script: String) async throws -> String {
        do {
            let result = try await webView.evaluateJavaScript(script)
            guard let string = result as? String else {
                throw SearchError.failed("the page returned no listings payload")
            }
            return string
        } catch let error as SearchError {
            throw error
        } catch {
            throw SearchError.failed("could not read the page")
        }
    }

    private func evaluateBool(_ script: String) async -> Bool {
        (try? await webView.evaluateJavaScript(script)) as? Bool ?? false
    }
}

extension FacebookSession: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finishLoad(throwing: nil)
    }

    public func webView(
        _ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error
    ) {
        finishLoad(throwing: SearchError.failed(error.localizedDescription))
    }

    public func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        finishLoad(throwing: SearchError.failed(error.localizedDescription))
    }
}
