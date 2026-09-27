import Foundation
import IOKit

@MainActor
protocol SleepStateReading {
    func isSleepDisabled() -> Bool
}

/// Reads the setting `pmset -g` prints as `SleepDisabled`. Needs no
/// privileges, which is why the app reads it rather than asking the helper.
struct IOKitSleepStateReader: SleepStateReading {
    func isSleepDisabled() -> Bool {
        let entry = IOServiceGetMatchingService(
            kIOMainPortDefault, IOServiceMatching("IOPMrootDomain")
        )
        guard entry != 0 else { return false }
        defer { IOObjectRelease(entry) }

        let property = IORegistryEntryCreateCFProperty(
            entry, "SleepDisabled" as CFString, kCFAllocatorDefault, 0
        )
        return (property?.takeRetainedValue() as? Bool) ?? false
    }
}
