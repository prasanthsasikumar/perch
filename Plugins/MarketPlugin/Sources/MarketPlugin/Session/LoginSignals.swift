import Foundation

/// What the page looked like after a search navigation.
///
/// Gathered by `FacebookSession` from the live webview; judged here, so the
/// judgement is testable without a browser.
public struct LoginSignals: Equatable, Sendable {
    public let urlPath: String
    public let hasPasswordField: Bool
    public let hasLoginForm: Bool
    public let listingCount: Int

    public init(urlPath: String, hasPasswordField: Bool, hasLoginForm: Bool, listingCount: Int) {
        self.urlPath = urlPath
        self.hasPasswordField = hasPasswordField
        self.hasLoginForm = hasLoginForm
        self.listingCount = listingCount
    }
}

/// Whether the page we landed on is a login wall.
///
/// Detection is positive: it looks for evidence of a login screen, and never
/// infers one from an empty result set. That inference is exactly what broke
/// the superseded Python implementation — upstream returned an empty list for
/// both "no matches" and "session dead", so the sign-in state could never fire
/// and a dead session looked like a quiet search forever.
public func isLoginWall(_ signals: LoginSignals) -> Bool {
    // Anything rendered means we are through. Facebook leaves login markup in
    // the DOM of some signed-in pages, so listings outrank those markers.
    guard signals.listingCount == 0 else { return false }
    if signals.urlPath.contains("/login") { return true }
    return signals.hasPasswordField || signals.hasLoginForm
}
