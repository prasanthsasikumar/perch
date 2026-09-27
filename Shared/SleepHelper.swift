import Foundation

/// Everything the app and its root helper have to agree on. Compiled into
/// both, so neither can drift from the other.
enum SleepHelper {
    /// Also the launchd label.
    static let machServiceName = "org.ahlab.Perch.helper"
    /// The file in the companion's `Contents/Library/LaunchDaemons`.
    static let daemonPlistName = "org.ahlab.Perch.helper.plist"
    /// The app that registers the helper, relative to Perch's bundle.
    static let companionPath = "Contents/Helpers/PerchKeepAwake.app"

    private static let team = "anchor apple generic and certificate leaf[subject.OU] = \"3U4384584Z\""

    /// Who the helper will take orders from. Pinned to the team rather than
    /// one certificate, so the Development-signed Debug build and the
    /// Developer ID Release build both pass.
    static let clientRequirement = "identifier \"org.ahlab.Perch\" and \(team)"
    /// Who the app will send orders to.
    static let helperRequirement = "identifier \"org.ahlab.Perch.helper\" and \(team)"
}

/// The whole of the helper's surface. It runs as root, so it takes a boolean
/// and nothing else: no string from the caller ever reaches a command line.
///
/// The explicit Objective-C name keeps it the same protocol in both modules.
@objc(SleepHelperProtocol)
protocol SleepHelperProtocol {
    /// `reply` carries `nil` on success and a message on failure.
    func setSleepDisabled(_ disabled: Bool, reply: @escaping (String?) -> Void)
}
