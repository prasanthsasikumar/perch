# Keep-Awake Toggle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A footer button in Perch that turns `pmset -a disablesleep` on and off, so the Mac stays awake with the lid closed.

**Architecture:** A root LaunchDaemon bundled inside `Perch.app` and registered with `SMAppService.daemon` runs `pmset`. The sandboxed app talks to it over XPC through a one-method interface, reads the current setting itself from the IOKit registry, and shows it as a host-owned footer button.

**Tech Stack:** Swift 5.9, SwiftUI, ServiceManagement (`SMAppService`), NSXPCConnection, IOKit, XcodeGen, XCTest.

**Spec:** `docs/superpowers/specs/2026-09-27-keep-awake-toggle-design.md`

## Global Constraints

- Deployment target macOS 14.0.
- App bundle identifier `org.ahlab.Perch`; helper identifier, launchd label and mach service name are all `org.ahlab.Perch.helper`; team `3U4384584Z`.
- The helper accepts a boolean only. No caller-supplied string reaches a command line.
- Perch never stores the setting. What the button shows always comes from the system.
- Plain toggle: no timers, no battery threshold, nothing reset on quit.
- The project is generated. After adding or moving any file, run `xcodegen generate` before `xcodebuild`, or the file is silently absent.
- The to-do plugin's original name must not appear in any file this plan creates or edits.
- Host test command: `xcodebuild test -project Perch.xcodeproj -scheme Perch -destination 'platform=macOS'`.

## Review Focus

1. **Second click while the first is in flight.** Expected: ignored, one helper call. Test in Task 3 (`testToggleWhileBusyIsIgnored`).
2. **Approval granted in System Settings while Perch is running.** Expected: the "needs approval" state clears the next time the panel opens, without a click. Test in Task 3 (`testRefreshClearsNeedsApprovalOnceEnabled`).
3. **Registration fails outright** (app run from a translocated or read-only location). Expected: the error text in the tooltip, no helper call, button unchanged. Test in Task 3 (`testRegistrationFailureIsReported`).
4. **`pmset` fails and prints nothing.** Expected: a message naming the exit status rather than an empty tooltip. Test in Task 1 (`testFailureMessageFallsBackToExitStatus`).
5. **Helper reports success but the setting did not change.** Expected: the button shows the system's value. Test in Task 3 (`testStateComesFromReaderNotRequest`).

## File Structure

| File | Responsibility |
|---|---|
| `Shared/SleepHelper.swift` | Names and signing requirements both processes agree on; the XPC protocol |
| `Shared/PmsetCommand.swift` | Pure: the executable path, the arguments, the failure message |
| `PerchHelper/main.swift` | The daemon: listener, caller check, runs `pmset`, exits when idle |
| `PerchHelper/org.ahlab.Perch.helper.plist` | launchd job definition |
| `Perch/Support/SleepStateReader.swift` | Reads `SleepDisabled` from IOKit |
| `Perch/Support/SleepHelperClient.swift` | XPC client and `SMAppService` registration, each behind a protocol |
| `Perch/Support/SleepController.swift` | Observable state and the toggle logic |
| `Perch/Host/PanelFooter.swift` | The button |
| `PerchTests/Support/PmsetCommandTests.swift` | Tests for the pure command |
| `PerchTests/Support/SleepControllerTests.swift` | Tests for the controller |

`Shared/` is compiled into both the app and the helper. The tests reach it through `@testable import Perch`.

---

### Task 1: Shared contract and the pmset command

**Files:**
- Create: `Shared/SleepHelper.swift`
- Create: `Shared/PmsetCommand.swift`
- Create: `PerchTests/Support/PmsetCommandTests.swift`
- Modify: `project.yml` (add `Shared` to the Perch target's sources)

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `enum SleepHelper` with `static let machServiceName: String`, `daemonPlistName: String`, `clientRequirement: String`, `helperRequirement: String`
  - `@objc(SleepHelperProtocol) protocol SleepHelperProtocol` with `func setSleepDisabled(_ disabled: Bool, reply: @escaping (String?) -> Void)`
  - `enum PmsetCommand` with `static let executable: String`, `static func arguments(disabled: Bool) -> [String]`, `static func failureMessage(status: Int32, stderr: String) -> String`

- [ ] **Step 1: Add `Shared` to the app target**

In `project.yml`, under `targets: Perch: sources:`, add `- Shared` after `- Perch`:

```yaml
    sources:
      - Perch
      - Shared
      - path: Perch/Resources
        buildPhase: resources
```

- [ ] **Step 2: Write the failing tests**

Create `PerchTests/Support/PmsetCommandTests.swift`:

```swift
@testable import Perch
import XCTest

final class PmsetCommandTests: XCTestCase {
    func testExecutableIsTheSystemPmset() {
        XCTAssertEqual(PmsetCommand.executable, "/usr/bin/pmset")
    }

    func testArgumentsToDisableSleep() {
        XCTAssertEqual(PmsetCommand.arguments(disabled: true), ["-a", "disablesleep", "1"])
    }

    func testArgumentsToRestoreSleep() {
        XCTAssertEqual(PmsetCommand.arguments(disabled: false), ["-a", "disablesleep", "0"])
    }

    func testFailureMessageUsesStderr() {
        XCTAssertEqual(
            PmsetCommand.failureMessage(status: 1, stderr: "pmset: must be root\n"),
            "pmset: must be root"
        )
    }

    func testFailureMessageFallsBackToExitStatus() {
        XCTAssertEqual(
            PmsetCommand.failureMessage(status: 71, stderr: "  \n"),
            "pmset exited with status 71"
        )
    }

    func testRequirementsNameTheTeamAndEachSide() {
        XCTAssertTrue(SleepHelper.clientRequirement.contains("identifier \"org.ahlab.Perch\""))
        XCTAssertTrue(SleepHelper.helperRequirement.contains("identifier \"org.ahlab.Perch.helper\""))
        for requirement in [SleepHelper.clientRequirement, SleepHelper.helperRequirement] {
            XCTAssertTrue(requirement.contains("anchor apple generic"))
            XCTAssertTrue(requirement.contains("certificate leaf[subject.OU] = \"3U4384584Z\""))
        }
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `xcodegen generate && xcodebuild test -project Perch.xcodeproj -scheme Perch -destination 'platform=macOS' -only-testing:PerchTests/PmsetCommandTests 2>&1 | tail -20`
Expected: build FAILS with "cannot find 'PmsetCommand' in scope".

- [ ] **Step 4: Write the shared contract**

Create `Shared/SleepHelper.swift`:

```swift
import Foundation

/// Everything the app and its root helper have to agree on. Compiled into
/// both, so neither can drift from the other.
enum SleepHelper {
    /// Also the launchd label.
    static let machServiceName = "org.ahlab.Perch.helper"
    /// The file in `Contents/Library/LaunchDaemons`.
    static let daemonPlistName = "org.ahlab.Perch.helper.plist"

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
```

Create `Shared/PmsetCommand.swift`:

```swift
import Foundation

/// What the helper runs. Pure, so it can be tested without being root.
enum PmsetCommand {
    static let executable = "/usr/bin/pmset"

    static func arguments(disabled: Bool) -> [String] {
        ["-a", "disablesleep", disabled ? "1" : "0"]
    }

    /// `pmset` can fail without saying why; an empty tooltip helps nobody.
    static func failureMessage(status: Int32, stderr: String) -> String {
        let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "pmset exited with status \(status)" : trimmed
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `xcodegen generate && xcodebuild test -project Perch.xcodeproj -scheme Perch -destination 'platform=macOS' -only-testing:PerchTests/PmsetCommandTests 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`, 6 tests.

- [ ] **Step 6: Commit**

```bash
git add Shared PerchTests/Support/PmsetCommandTests.swift project.yml
git commit -m "feat: the contract between Perch and its sleep helper"
```

---

### Task 2: The helper daemon, embedded and signed

**Files:**
- Create: `PerchHelper/main.swift`
- Create: `PerchHelper/org.ahlab.Perch.helper.plist`
- Modify: `project.yml` (new target; embed it and its plist in Perch)
- Modify: `Perch/Perch.entitlements`

**Interfaces:**
- Consumes: `SleepHelper`, `SleepHelperProtocol`, `PmsetCommand` from Task 1.
- Produces: a built app containing `Contents/MacOS/PerchHelper` and `Contents/Library/LaunchDaemons/org.ahlab.Perch.helper.plist`. No Swift API; later tasks reach the helper only through `SleepHelper.machServiceName`.

- [ ] **Step 1: Write the launchd plist**

Create `PerchHelper/org.ahlab.Perch.helper.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>org.ahlab.Perch.helper</string>
	<key>BundleProgram</key>
	<string>Contents/MacOS/PerchHelper</string>
	<key>MachServices</key>
	<dict>
		<key>org.ahlab.Perch.helper</key>
		<true/>
	</dict>
	<key>AssociatedBundleIdentifiers</key>
	<array>
		<string>org.ahlab.Perch</string>
	</array>
</dict>
</plist>
```

There is deliberately no `RunAtLoad` and no `KeepAlive`: launchd starts the helper when Perch connects.

- [ ] **Step 2: Write the helper**

Create `PerchHelper/main.swift`:

```swift
import Foundation

/// Perch's root helper. Started by launchd when Perch connects, does one
/// thing, and exits once nobody has asked for anything in a while.

/// Exits the process after a quiet spell, so nothing root stays resident.
final class IdleExit {
    private let delay: TimeInterval = 10
    private var pending: DispatchWorkItem?

    func touch() {
        pending?.cancel()
        let item = DispatchWorkItem { exit(EXIT_SUCCESS) }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }
}

final class HelperService: NSObject, SleepHelperProtocol {
    private let onRequest: () -> Void

    init(onRequest: @escaping () -> Void) {
        self.onRequest = onRequest
    }

    func setSleepDisabled(_ disabled: Bool, reply: @escaping (String?) -> Void) {
        DispatchQueue.main.async(execute: onRequest)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: PmsetCommand.executable)
        process.arguments = PmsetCommand.arguments(disabled: disabled)
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            reply("Could not run pmset: \(error.localizedDescription)")
            return
        }
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            reply(PmsetCommand.failureMessage(
                status: process.terminationStatus,
                stderr: String(decoding: errorData, as: UTF8.self)
            ))
            return
        }
        reply(nil)
    }
}

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    let idle = IdleExit()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: SleepHelperProtocol.self)
        connection.exportedObject = HelperService(onRequest: { [idle] in idle.touch() })
        connection.resume()
        DispatchQueue.main.async { [idle] in idle.touch() }
        return true
    }
}

let delegate = ListenerDelegate()
let listener = NSXPCListener(machServiceName: SleepHelper.machServiceName)
// The system refuses any caller that is not Perch, signed by our team,
// before `shouldAcceptNewConnection` is ever asked.
listener.setConnectionCodeSigningRequirement(SleepHelper.clientRequirement)
listener.delegate = delegate
listener.resume()
delegate.idle.touch()
dispatchMain()
```

- [ ] **Step 3: Add the target and embed it**

In `project.yml`, add to the Perch target's `sources`, after `- Shared`:

```yaml
      - path: PerchHelper/org.ahlab.Perch.helper.plist
        buildPhase:
          copyFiles:
            destination: wrapper
            subpath: Contents/Library/LaunchDaemons
```

Add to the Perch target's `dependencies`, as the first entry:

```yaml
      - target: PerchHelper
        embed: true
        codeSign: false
        copy:
          destination: executables
```

`codeSign: false` because the helper target signs its own product with its own identifier; re-signing on copy is not needed.

Add a new target under `targets:`, between `Perch` and `PerchTests`:

```yaml
  # The root helper behind the keep-awake toggle. Registered with
  # SMAppService.daemon and run by launchd, never launched directly.
  PerchHelper:
    type: tool
    platform: macOS
    sources:
      - path: PerchHelper
        excludes:
          - "*.plist"
      - Shared
    settings:
      base:
        PRODUCT_NAME: PerchHelper
        PRODUCT_BUNDLE_IDENTIFIER: org.ahlab.Perch.helper
        SKIP_INSTALL: YES
      configs:
        Debug:
          CODE_SIGN_STYLE: Manual
          CODE_SIGN_IDENTITY: "Apple Development: Prasanth Sasikumar (5AD8QG2238)"
          DEVELOPMENT_TEAM: 3U4384584Z
          PROVISIONING_PROFILE_SPECIFIER: ""
        # Same rules as the app: notarization rejects get-task-allow and a
        # signature without a secure timestamp.
        Release:
          CODE_SIGN_STYLE: Manual
          CODE_SIGN_IDENTITY: "Developer ID Application: FLOWXR PTE. LTD. (3U4384584Z)"
          DEVELOPMENT_TEAM: 3U4384584Z
          ENABLE_HARDENED_RUNTIME: YES
          CODE_SIGN_INJECT_BASE_ENTITLEMENTS: NO
          OTHER_CODE_SIGN_FLAGS: "--timestamp"
```

- [ ] **Step 4: Let the sandboxed app reach the helper**

Replace the `<dict>` in `Perch/Perch.entitlements` with:

```xml
<dict>
	<key>com.apple.security.app-sandbox</key>
	<true/>
	<key>com.apple.security.network.client</key>
	<true/>
	<key>com.apple.security.files.user-selected.read-only</key>
	<true/>
	<key>com.apple.security.temporary-exception.mach-lookup.global-name</key>
	<array>
		<string>org.ahlab.Perch.helper</string>
	</array>
</dict>
```

- [ ] **Step 5: Build and verify the bundle**

Run:

```bash
xcodegen generate
xcodebuild build -project Perch.xcodeproj -scheme Perch -configuration Debug -derivedDataPath build 2>&1 | tail -5
APP=build/Build/Products/Debug/Perch.app
ls "$APP/Contents/MacOS" "$APP/Contents/Library/LaunchDaemons"
plutil -lint "$APP/Contents/Library/LaunchDaemons/org.ahlab.Perch.helper.plist"
codesign -dv "$APP/Contents/MacOS/PerchHelper" 2>&1 | grep -E "Identifier|TeamIdentifier"
codesign --verify --deep --strict "$APP" && echo "signature ok"
codesign -d --entitlements - "$APP" 2>/dev/null | grep -A3 mach-lookup
```

Expected:
- `** BUILD SUCCEEDED **`
- `Perch` and `PerchHelper` listed; `org.ahlab.Perch.helper.plist` listed and `OK`
- `Identifier=org.ahlab.Perch.helper` and `TeamIdentifier=3U4384584Z`
- `signature ok`
- the mach-lookup key followed by `org.ahlab.Perch.helper`

If the helper's identifier prints as `PerchHelper`, add `OTHER_CODE_SIGN_FLAGS: "--identifier org.ahlab.Perch.helper"` to the helper's Debug config and `"--timestamp --identifier org.ahlab.Perch.helper"` to its Release config, then rebuild.

- [ ] **Step 6: Run the full host suite to confirm nothing regressed**

Run: `xcodebuild test -project Perch.xcodeproj -scheme Perch -destination 'platform=macOS' 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add PerchHelper project.yml Perch/Perch.entitlements
git commit -m "feat: a root helper that sets disablesleep"
```

---

### Task 3: State reader, helper client and controller

**Files:**
- Create: `Perch/Support/SleepStateReader.swift`
- Create: `Perch/Support/SleepHelperClient.swift`
- Create: `Perch/Support/SleepController.swift`
- Create: `PerchTests/Support/SleepControllerTests.swift`

**Interfaces:**
- Consumes: `SleepHelper`, `SleepHelperProtocol` from Task 1.
- Produces:
  - `@MainActor protocol SleepStateReading { func isSleepDisabled() -> Bool }`, implemented by `IOKitSleepStateReader`
  - `@MainActor protocol SleepHelperClient { func setSleepDisabled(_ disabled: Bool) async throws }`, implemented by `XPCSleepHelperClient`
  - `enum HelperRegistrationState { case notRegistered, enabled, requiresApproval }`
  - `@MainActor protocol HelperRegistering { var state: HelperRegistrationState { get }; func register() throws; func openApprovalSettings() }`, implemented by `DaemonRegistration`
  - `struct SleepHelperError: LocalizedError` with `init(_ message: String)`
  - `@MainActor @Observable final class SleepController` with `enum Status: Equatable { case ready, needsApproval, failed(String) }`, `private(set) var isSleepDisabled: Bool`, `private(set) var status: Status`, `private(set) var isBusy: Bool`, `var tooltip: String`, `func refresh()`, `func toggle() async`, `init(reader:helper:registration:)`, and `convenience init()` using the real implementations

- [ ] **Step 1: Write the failing tests**

Create `PerchTests/Support/SleepControllerTests.swift`:

```swift
@testable import Perch
import XCTest

@MainActor
private final class FakeReader: SleepStateReading {
    var value = false
    func isSleepDisabled() -> Bool { value }
}

@MainActor
private final class FakeHelper: SleepHelperClient {
    var calls: [Bool] = []
    var error: Error?
    /// What a successful call does to the system. `nil` leaves it untouched.
    var onSuccess: ((Bool) -> Void)?
    /// Held open until the test resumes it, to keep a call in flight.
    var gate: CheckedContinuation<Void, Never>?
    var holdsCalls = false

    func setSleepDisabled(_ disabled: Bool) async throws {
        calls.append(disabled)
        if holdsCalls {
            await withCheckedContinuation { gate = $0 }
        }
        if let error { throw error }
        onSuccess?(disabled)
    }
}

@MainActor
private final class FakeRegistration: HelperRegistering {
    var state: HelperRegistrationState = .enabled
    var stateAfterRegister: HelperRegistrationState = .enabled
    var registerError: Error?
    var registerCalls = 0
    var openedSettings = 0

    func register() throws {
        registerCalls += 1
        state = stateAfterRegister
        if let registerError { throw registerError }
    }

    func openApprovalSettings() { openedSettings += 1 }
}

@MainActor
final class SleepControllerTests: XCTestCase {
    private var reader: FakeReader!
    private var helper: FakeHelper!
    private var registration: FakeRegistration!

    override func setUp() async throws {
        reader = FakeReader()
        helper = FakeHelper()
        registration = FakeRegistration()
        helper.onSuccess = { [reader] in reader?.value = $0 }
    }

    private func makeController() -> SleepController {
        SleepController(reader: reader, helper: helper, registration: registration)
    }

    func testStartsFromTheSystemState() {
        reader.value = true
        XCTAssertTrue(makeController().isSleepDisabled)
    }

    func testToggleOnThenOff() async {
        let controller = makeController()

        await controller.toggle()
        XCTAssertEqual(helper.calls, [true])
        XCTAssertTrue(controller.isSleepDisabled)
        XCTAssertEqual(controller.status, .ready)

        await controller.toggle()
        XCTAssertEqual(helper.calls, [true, false])
        XCTAssertFalse(controller.isSleepDisabled)
    }

    func testStateComesFromReaderNotRequest() async {
        helper.onSuccess = nil
        let controller = makeController()

        await controller.toggle()

        XCTAssertEqual(helper.calls, [true])
        XCTAssertFalse(controller.isSleepDisabled)
    }

    func testHelperFailureIsReportedAndStateUnchanged() async {
        helper.error = SleepHelperError("pmset: must be root")
        let controller = makeController()

        await controller.toggle()

        XCTAssertFalse(controller.isSleepDisabled)
        XCTAssertEqual(controller.status, .failed("pmset: must be root"))
        XCTAssertEqual(controller.tooltip, "pmset: must be root")
    }

    func testFailureClearsOnNextSuccess() async {
        helper.error = SleepHelperError("interrupted")
        let controller = makeController()
        await controller.toggle()

        helper.error = nil
        await controller.toggle()

        XCTAssertEqual(controller.status, .ready)
        XCTAssertTrue(controller.isSleepDisabled)
    }

    func testFirstToggleRegistersTheHelper() async {
        registration.state = .notRegistered
        let controller = makeController()

        await controller.toggle()

        XCTAssertEqual(registration.registerCalls, 1)
        XCTAssertEqual(helper.calls, [true])
    }

    func testNeedsApprovalAfterRegistering() async {
        registration.state = .notRegistered
        registration.stateAfterRegister = .requiresApproval
        let controller = makeController()

        await controller.toggle()

        XCTAssertEqual(controller.status, .needsApproval)
        XCTAssertEqual(registration.openedSettings, 1)
        XCTAssertTrue(helper.calls.isEmpty)
        XCTAssertEqual(controller.tooltip, "Allow Perch in System Settings → Login Items")
    }

    /// `SMAppService.register()` throws when approval is pending; that is the
    /// approval case, not a failure.
    func testRegisterThrowingWhileApprovalPendingIsNeedsApproval() async {
        registration.state = .notRegistered
        registration.stateAfterRegister = .requiresApproval
        registration.registerError = SleepHelperError("Operation not permitted")
        let controller = makeController()

        await controller.toggle()

        XCTAssertEqual(controller.status, .needsApproval)
        XCTAssertTrue(helper.calls.isEmpty)
    }

    func testAlreadyAwaitingApprovalDoesNotRegisterAgain() async {
        registration.state = .requiresApproval
        let controller = makeController()

        await controller.toggle()

        XCTAssertEqual(registration.registerCalls, 0)
        XCTAssertEqual(registration.openedSettings, 1)
        XCTAssertEqual(controller.status, .needsApproval)
    }

    func testRegistrationFailureIsReported() async {
        registration.state = .notRegistered
        registration.stateAfterRegister = .notRegistered
        registration.registerError = SleepHelperError("The helper could not be found")
        let controller = makeController()

        await controller.toggle()

        XCTAssertEqual(controller.status, .failed("The helper could not be found"))
        XCTAssertTrue(helper.calls.isEmpty)
        XCTAssertEqual(registration.openedSettings, 0)
    }

    func testRefreshPicksUpAChangeMadeOutsidePerch() {
        let controller = makeController()
        reader.value = true

        controller.refresh()

        XCTAssertTrue(controller.isSleepDisabled)
    }

    func testRefreshClearsNeedsApprovalOnceEnabled() async {
        registration.state = .requiresApproval
        let controller = makeController()
        await controller.toggle()
        XCTAssertEqual(controller.status, .needsApproval)

        registration.state = .enabled
        controller.refresh()

        XCTAssertEqual(controller.status, .ready)
    }

    func testToggleWhileBusyIsIgnored() async {
        helper.holdsCalls = true
        let controller = makeController()

        let first = Task { await controller.toggle() }
        while helper.gate == nil { await Task.yield() }
        XCTAssertTrue(controller.isBusy)

        await controller.toggle()
        XCTAssertEqual(helper.calls, [true])

        helper.gate?.resume()
        await first.value
        XCTAssertFalse(controller.isBusy)
        XCTAssertTrue(controller.isSleepDisabled)
    }

    func testTooltipsForOnAndOff() async {
        let controller = makeController()
        XCTAssertEqual(controller.tooltip, "Keep awake with lid closed")

        await controller.toggle()
        XCTAssertEqual(controller.tooltip, "Staying awake with lid closed")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodegen generate && xcodebuild test -project Perch.xcodeproj -scheme Perch -destination 'platform=macOS' -only-testing:PerchTests/SleepControllerTests 2>&1 | tail -20`
Expected: build FAILS with "cannot find type 'SleepStateReading' in scope".

- [ ] **Step 3: Write the state reader**

Create `Perch/Support/SleepStateReader.swift`:

```swift
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
```

- [ ] **Step 4: Write the helper client and registration**

Create `Perch/Support/SleepHelperClient.swift`:

```swift
import Foundation
import ServiceManagement

struct SleepHelperError: LocalizedError, Equatable {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

@MainActor
protocol SleepHelperClient {
    func setSleepDisabled(_ disabled: Bool) async throws
}

/// One connection per call. The helper exits when idle, so a connection kept
/// around would only ever be found invalidated.
struct XPCSleepHelperClient: SleepHelperClient {
    func setSleepDisabled(_ disabled: Bool) async throws {
        let connection = NSXPCConnection(
            machServiceName: SleepHelper.machServiceName, options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(with: SleepHelperProtocol.self)
        // Refuse to talk to anything that is not our own helper.
        connection.setCodeSigningRequirement(SleepHelper.helperRequirement)
        connection.resume()
        defer { connection.invalidate() }

        // Exactly one of the error handler and the reply is ever called.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                continuation.resume(throwing: SleepHelperError(error.localizedDescription))
            }
            guard let helper = proxy as? SleepHelperProtocol else {
                continuation.resume(throwing: SleepHelperError("The helper did not respond"))
                return
            }
            helper.setSleepDisabled(disabled) { message in
                if let message {
                    continuation.resume(throwing: SleepHelperError(message))
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

enum HelperRegistrationState: Equatable {
    case notRegistered
    case enabled
    case requiresApproval
}

@MainActor
protocol HelperRegistering {
    var state: HelperRegistrationState { get }
    func register() throws
    func openApprovalSettings()
}

struct DaemonRegistration: HelperRegistering {
    private var service: SMAppService {
        .daemon(plistName: SleepHelper.daemonPlistName)
    }

    var state: HelperRegistrationState {
        switch service.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notRegistered, .notFound: .notRegistered
        @unknown default: .notRegistered
        }
    }

    func register() throws {
        try service.register()
    }

    func openApprovalSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
```

- [ ] **Step 5: Write the controller**

Create `Perch/Support/SleepController.swift`:

```swift
import Foundation
import Observation

/// The keep-awake toggle: `pmset -a disablesleep`, without the Terminal.
///
/// Holds no setting of its own. `isSleepDisabled` is whatever the system
/// last reported, so the button stays truthful when the setting is changed
/// from Terminal, and a helper that claims success cannot make it lie.
@MainActor
@Observable
final class SleepController {
    enum Status: Equatable {
        case ready
        case needsApproval
        case failed(String)
    }

    private(set) var isSleepDisabled: Bool
    private(set) var status: Status = .ready
    private(set) var isBusy = false

    private let reader: SleepStateReading
    private let helper: SleepHelperClient
    private let registration: HelperRegistering

    init(reader: SleepStateReading, helper: SleepHelperClient, registration: HelperRegistering) {
        self.reader = reader
        self.helper = helper
        self.registration = registration
        isSleepDisabled = reader.isSleepDisabled()
    }

    convenience init() {
        self.init(
            reader: IOKitSleepStateReader(),
            helper: XPCSleepHelperClient(),
            registration: DaemonRegistration()
        )
    }

    var tooltip: String {
        switch status {
        case .needsApproval:
            "Allow Perch in System Settings → Login Items"
        case .failed(let message):
            message
        case .ready:
            isSleepDisabled ? "Staying awake with lid closed" : "Keep awake with lid closed"
        }
    }

    /// Called at launch and whenever the panel opens.
    func refresh() {
        isSleepDisabled = reader.isSleepDisabled()
        // The user may have approved the helper since we last looked.
        if status == .needsApproval, registration.state == .enabled {
            status = .ready
        }
    }

    func toggle() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        guard ensureHelperIsUsable() else { return }

        do {
            try await helper.setSleepDisabled(!isSleepDisabled)
            status = .ready
        } catch {
            status = .failed(error.localizedDescription)
        }
        isSleepDisabled = reader.isSleepDisabled()
    }

    /// Registers the helper on first use. Returns `false`, with `status`
    /// explaining why, when the helper cannot be called yet.
    private func ensureHelperIsUsable() -> Bool {
        switch registration.state {
        case .enabled:
            return true
        case .requiresApproval:
            askForApproval()
            return false
        case .notRegistered:
            do {
                try registration.register()
            } catch {
                // `register()` throws while approval is pending; only a
                // throw that leaves us anywhere else is a real failure.
                guard registration.state == .requiresApproval else {
                    status = .failed(error.localizedDescription)
                    return false
                }
            }
            if registration.state == .enabled { return true }
            if registration.state == .requiresApproval {
                askForApproval()
            } else {
                status = .failed("The helper could not be registered")
            }
            return false
        }
    }

    private func askForApproval() {
        status = .needsApproval
        registration.openApprovalSettings()
    }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `xcodegen generate && xcodebuild test -project Perch.xcodeproj -scheme Perch -destination 'platform=macOS' -only-testing:PerchTests/SleepControllerTests 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`, 14 tests.

- [ ] **Step 7: Commit**

```bash
git add Perch/Support/SleepStateReader.swift Perch/Support/SleepHelperClient.swift Perch/Support/SleepController.swift PerchTests/Support/SleepControllerTests.swift
git commit -m "feat: SleepController, the state behind the keep-awake toggle"
```

---

### Task 4: The footer button

**Files:**
- Modify: `Perch/Host/PanelFooter.swift`
- Modify: `Perch/Host/PanelView.swift`
- Modify: `Perch/PerchApp.swift`

**Interfaces:**
- Consumes: `SleepController` from Task 3 (`isSleepDisabled`, `isBusy`, `tooltip`, `refresh()`, `toggle() async`, `init()`).
- Produces: `PanelFooter(actions:sleep:onQuit:)` and `PanelView(registry:sleep:)`.

- [ ] **Step 1: Add the button to the footer**

In `Perch/Host/PanelFooter.swift`, replace the doc comment and the stored properties:

```swift
/// The row of controls along the bottom of the panel. The keep-awake toggle,
/// the gear and the power button are Perch's and always present; everything
/// to their left is contributed by whichever plugin is showing.
struct PanelFooter: View {
    let actions: [PluginAction]
    let sleep: SleepController
    let onQuit: () -> Void
```

Insert between `Spacer()` and the gear button:

```swift
            Button {
                Task { await sleep.toggle() }
            } label: {
                Image(systemName: sleep.isSleepDisabled ? "cup.and.saucer.fill" : "cup.and.saucer")
                    .foregroundStyle(
                        sleep.isSleepDisabled ? AnyShapeStyle(.tint) : AnyShapeStyle(.foreground)
                    )
            }
            .disabled(sleep.isBusy)
            .help(sleep.tooltip)
            .accessibilityLabel("Keep awake with lid closed")
            .accessibilityValue(sleep.isSleepDisabled ? "On" : "Off")
```

- [ ] **Step 2: Pass the controller through the panel and refresh on open**

In `Perch/Host/PanelView.swift`, add the property under `registry`:

```swift
    @Bindable var registry: PluginRegistry
    let sleep: SleepController
```

Replace the `PanelFooter(` call:

```swift
            PanelFooter(
                actions: registry.active?.plugin.footerActions ?? [],
                sleep: sleep,
                onQuit: quit
            )
```

Replace `.frame(width: 320)` with:

```swift
        .frame(width: 320)
        // The setting can be changed from Terminal while the panel is
        // closed; re-read it every time the panel is shown.
        .onAppear { sleep.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            sleep.refresh()
        }
```

- [ ] **Step 3: Create the controller in the app**

In `Perch/PerchApp.swift`, add under `@State private var appState = AppState()`:

```swift
    @State private var sleep = SleepController()
```

Replace `PanelView(registry: registry)` with:

```swift
            PanelView(registry: registry, sleep: sleep)
```

- [ ] **Step 4: Build and run the full suite**

Run: `xcodegen generate && xcodebuild test -project Perch.xcodeproj -scheme Perch -destination 'platform=macOS' 2>&1 | tail -5`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Perch/Host/PanelFooter.swift Perch/Host/PanelView.swift Perch/PerchApp.swift
git commit -m "feat: keep-awake toggle in the panel footer"
```

---

### Task 5: Prove it on a real build

This task retires the spec's two risks. Nothing here can run under XCTest: it needs root, launchd and a human approval.

**Files:**
- Modify only if a fallback below is triggered.

**Interfaces:**
- Consumes: the built app from Tasks 2 and 4.
- Produces: a verified working toggle.

- [ ] **Step 1: Build and launch**

```bash
pkill -x Perch; true
xcodebuild build -project Perch.xcodeproj -scheme Perch -configuration Debug -derivedDataPath build 2>&1 | tail -3
open build/Build/Products/Debug/Perch.app
```

- [ ] **Step 2: First click asks for approval**

Open the panel and click the cup. Expected: System Settings opens at Login Items, Perch is listed under "Allow in the Background", and the cup's tooltip reads "Allow Perch in System Settings → Login Items". Turn Perch on there.

- [ ] **Step 3: Toggle on**

Reopen the panel and click the cup. Then run: `pmset -g | grep SleepDisabled`
Expected: `SleepDisabled 1`, and the cup is filled.

- [ ] **Step 4: Toggle off**

Click again. Run: `pmset -g | grep SleepDisabled`
Expected: `SleepDisabled 0`, and the cup is an outline.

- [ ] **Step 5: A change from Terminal is picked up**

With the panel closed, run `sudo pmset -a disablesleep 1`, then open the panel.
Expected: the cup is filled. Click it to restore normal sleep.

- [ ] **Step 6: The helper does not stay resident**

Wait 15 seconds after the last click. Run: `pgrep -x PerchHelper || echo "not running"`
Expected: `not running`.

- [ ] **Step 7: A stranger is refused**

Create `/tmp/claude-501/stranger.swift`:

```swift
import Foundation

@objc(SleepHelperProtocol) protocol SleepHelperProtocol {
    func setSleepDisabled(_ disabled: Bool, reply: @escaping (String?) -> Void)
}

let connection = NSXPCConnection(machServiceName: "org.ahlab.Perch.helper", options: .privileged)
connection.remoteObjectInterface = NSXPCInterface(with: SleepHelperProtocol.self)
connection.resume()
let proxy = connection.remoteObjectProxyWithErrorHandler { error in
    print("refused: \(error.localizedDescription)")
    exit(0)
} as! SleepHelperProtocol
proxy.setSleepDisabled(true) { message in
    print("ACCEPTED, reply: \(message ?? "nil")")
    exit(1)
}
dispatchMain()
```

Run: `swiftc /tmp/claude-501/stranger.swift -o /tmp/claude-501/stranger && /tmp/claude-501/stranger; pmset -g | grep SleepDisabled`
Expected: a line starting `refused:` and `SleepDisabled 0`.

- [ ] **Step 8: Lid close**

Turn the toggle on, start `ping -i 5 1.1.1.1 | while read l; do echo "$(date +%T) $l"; done > /tmp/claude-501/lid.log &`, unplug external displays, close the lid for 60 seconds, open it. Run: `kill %1; tail -15 /tmp/claude-501/lid.log`
Expected: timestamps every 5 seconds with no gap. Turn the toggle off afterwards.

**Fallbacks, only if a step above fails:**

- **Step 3 fails with a connection error and Console shows a sandbox `mach-lookup` denial for `org.ahlab.Perch.helper`:** the entitlement exception is not enough. Rename the mach service to `3U4384584Z.org.ahlab.Perch.helper` in `Shared/SleepHelper.swift` (`machServiceName` only) and in the plist's `MachServices` key, and replace the mach-lookup entitlement with:

  ```xml
  <key>com.apple.security.application-groups</key>
  <array>
  	<string>3U4384584Z.org.ahlab.Perch</string>
  </array>
  ```

  Rebuild and repeat from Step 1.

- **The cup never fills although `pmset -g` reports `SleepDisabled 1`:** the sandbox is blocking the IOKit read. Add `func getSleepDisabled(reply: @escaping (Bool) -> Void)` to `SleepHelperProtocol`, implement it in `HelperService` by moving the body of `IOKitSleepStateReader.isSleepDisabled()` into `Shared/`, and have `SleepController.refresh()` keep its last value when the helper is not yet approved.

- [ ] **Step 9: Commit any fallback change**

```bash
git add -A
git commit -m "fix: reach the sleep helper from inside the sandbox"
```

Skip this step if no fallback was needed.

---

### Task 6: Document it

**Files:**
- Modify: `README.md`
- Modify: `docs/superpowers/specs/2026-09-27-keep-awake-toggle-design.md`

**Interfaces:**
- Consumes: the verified behaviour from Task 5.
- Produces: nothing code depends on.

- [ ] **Step 1: Add a README section**

In `README.md`, immediately before the `## Building from source` heading, add:

```markdown
## Keep awake

The cup in the panel's footer keeps your Mac awake when the lid is closed. It
is the same setting as `sudo pmset -a disablesleep 1`, without the Terminal.

- **One approval, once.** The setting needs root, so Perch ships a small
  helper. The first click opens System Settings → Login Items; allow Perch
  there and every click after that is instant.
- **It stays on until you turn it off**, including after you quit Perch or
  restart. A Mac that stays awake in a bag runs hot and drains its battery,
  so turn it off when you are done.
- **The cup tells the truth.** Perch reads the setting from the system each
  time the panel opens, so it is right even if you changed it from Terminal.

The helper does one thing, accepts requests only from Perch, and exits a few
seconds after each use.
```

In the `### Layout` block, add these two lines after the `Plugins/ServerPlugin/` line:

```
PerchHelper/             The root helper behind the keep-awake toggle
Shared/                  What the app and the helper both compile
```

- [ ] **Step 2: Mark the spec implemented**

In `docs/superpowers/specs/2026-09-27-keep-awake-toggle-design.md`, change `**Status:** approved` to `**Status:** approved, implemented`.

- [ ] **Step 3: Commit**

```bash
git add README.md docs/superpowers/specs/2026-09-27-keep-awake-toggle-design.md
git commit -m "docs: the keep-awake toggle"
```

---

## After this plan

Two things follow, neither part of this plan:

1. **Release.** Bump the version in `project.yml`, then the usual Release build, notarize, staple and GitHub release. Extra check for this release: `codesign -dv --verbose=4 Perch.app/Contents/MacOS/PerchHelper` shows the Developer ID authority, `flags=0x10000(runtime)` and a `Timestamp=` line.
2. **Renaming the to-do plugin to Tasks**, with a migration of its stored data. It gets its own plan.
