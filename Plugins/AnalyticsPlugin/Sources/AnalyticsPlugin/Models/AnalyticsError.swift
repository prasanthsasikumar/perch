import Foundation

/// Every way this plugin can fail, in the terms the panel has to explain them.
///
/// Deliberately narrow: the panel renders one of these per property, so a case
/// only earns its place if the user would do something different about it.
public enum AnalyticsError: Error, Equatable, Sendable {
    /// No service-account key has been imported yet.
    case notConfigured
    /// The key was rejected. Usually a revoked or malformed key, or a clock
    /// far enough out that the assertion is already expired.
    case authenticationFailed(String)
    /// The credential is fine but this property is not shared with it.
    case permissionDenied
    /// The credential is fine and the property may well be shared, but the API
    /// itself has never been switched on for the key's Cloud project. Google
    /// reports this as a 403 too, and telling the user to fix their GA sharing
    /// would send them somewhere that cannot help.
    case apiNotEnabled(String)
    /// The key file was not a Google service-account JSON.
    case malformedKey(String)
    /// The private key parsed but could not be turned into a signing key.
    case unusableKey
    /// The device could not reach Google at all.
    case offline
    /// Anything else Google said, kept verbatim rather than flattened, because
    /// a message we did not anticipate is more useful than "something failed".
    case api(status: Int, message: String)
    case malformedResponse

    /// One sentence, addressed to the user, saying what to do next.
    public func message(clientEmail: String?) -> String {
        switch self {
        case .notConfigured:
            "Connect a Google service account in Settings."
        case .authenticationFailed(let detail):
            "Sign-in failed — re-import your key in Settings. (\(detail))"
        case .permissionDenied:
            if let clientEmail {
                "No access. Add \(clientEmail) as a viewer in GA4 Admin › Property Access."
            } else {
                "No access. Add the service account as a viewer in GA4 Admin › Property Access."
            }
        case .apiNotEnabled(let detail):
            detail
        case .malformedKey(let detail):
            "That file isn't a Google service-account key. (\(detail))"
        case .unusableKey:
            "The private key in that file couldn't be read."
        case .offline:
            "Couldn't reach Google Analytics."
        case .api(let status, let message):
            "Google Analytics returned \(status). \(message)"
        case .malformedResponse:
            "Google Analytics sent a response Perch couldn't read."
        }
    }

    /// Whether re-importing the key is the fix. Drives the "Open Settings"
    /// affordance rather than leaving the user to guess.
    public var isCredentialProblem: Bool {
        switch self {
        case .notConfigured, .authenticationFailed, .malformedKey, .unusableKey: true
        case .permissionDenied, .apiNotEnabled, .offline, .api, .malformedResponse: false
        }
    }
}
