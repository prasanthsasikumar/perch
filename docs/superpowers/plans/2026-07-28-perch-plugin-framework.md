# Perch Plugin Framework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn MenuDo into Perch, a macOS menu bar host that runs small tools as compile-time plugins, with today's todo list as the first plugin and no change to how it behaves.

**Architecture:** Three layers. `PerchKit` is a local Swift package holding the public plugin protocol and its support types — it knows nothing about the host. `Plugins/MenuDoPlugin` is a local Swift package depending only on `PerchKit`. `Perch` is the app target: it is the only place that names concrete plugins, and it owns the menu bar item, the panel chrome (tab strip + footer), the Settings window, and the one-time import of data from the old MenuDo bundle identifier.

**Tech Stack:** Swift 5.9+, SwiftUI (`MenuBarExtra`, `.window` style), XcodeGen, XCTest, `SMAppService`, plus the two existing SPM dependencies (KeyboardShortcuts, MenuBarExtraAccess).

**Reference spec:** `docs/superpowers/specs/2026-07-28-perch-plugin-framework-design.md`

## Global Constraints

- Deployment target: macOS 14.0. Every package declares `platforms: [.macOS(.v14)]`.
- Swift tools version for all packages: `5.9`.
- No new third-party dependencies. KeyboardShortcuts and MenuBarExtraAccess are the only external packages.
- Bundle identifier: `org.ahlab.Perch`. Product and module name: `Perch`.
- `MARKETING_VERSION: "2.0"`, `CURRENT_PROJECT_VERSION: "2"`.
- `PerchKit` version is `0.1.0` and explicitly unstable. Do not document it as a stable API.
- Copyright string stays `© 2026 Prasanth Sasikumar`.
- Plugin identifiers are reverse-DNS: MenuDo's is `org.ahlab.perch.menudo`.
- Test symbols in packages are reached with plain `import`, not `@testable` — anything a test touches in `PerchKit` or `MenuDoPlugin` must be `public`. Only the app module is imported with `@testable`.
- Standard build/test command:
  `xcodebuild test -project Perch.xcodeproj -scheme Perch -destination 'platform=macOS' 2>&1 | tail -30`
- Regenerate the Xcode project after any `project.yml` change: `xcodegen generate`
- Commit after every task. Never leave the build red between tasks.

---

### Task 1: Rename the app to Perch

Purely mechanical. Nothing about the todo list changes; only names, identifiers, and paths. This goes first so every later task is written in its final names.

**Files:**
- Modify: `project.yml` (full rewrite)
- Rename: `MenuDo/` → `Perch/`
- Rename: `MenuDo/MenuDoApp.swift` → `Perch/PerchApp.swift`
- Rename: `MenuDo/MenuDo.entitlements` → `Perch/Perch.entitlements`
- Rename: `MenuDoTests/` → `PerchTests/`
- Modify: `Perch/Info.plist`, `Perch/Support/AppState.swift`, `Perch/Views/SettingsView.swift`, `Perch/Views/TaskListView.swift`
- Modify: `.gitignore`

- [ ] **Step 1: Move the directories with git**

```bash
cd /Users/prasanthsasikumar/Documents/GitHub/menudo
git mv MenuDo Perch
git mv Perch/MenuDoApp.swift Perch/PerchApp.swift
git mv Perch/MenuDo.entitlements Perch/Perch.entitlements
git mv MenuDoTests PerchTests
rm -rf MenuDo.xcodeproj
```

- [ ] **Step 2: Rewrite `project.yml`**

```yaml
name: Perch
options:
  createIntermediateGroups: true
  deploymentTarget:
    macOS: "14.0"
packages:
  KeyboardShortcuts:
    url: https://github.com/sindresorhus/KeyboardShortcuts
    from: 2.0.0
  MenuBarExtraAccess:
    url: https://github.com/orchetect/MenuBarExtraAccess
    from: 1.0.0
targets:
  Perch:
    type: application
    platform: macOS
    sources:
      - Perch
      - path: Perch/Resources
        buildPhase: resources
    dependencies:
      - package: KeyboardShortcuts
      - package: MenuBarExtraAccess
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: org.ahlab.Perch
        CODE_SIGN_ENTITLEMENTS: Perch/Perch.entitlements
        CODE_SIGN_IDENTITY: "-"
        ENABLE_HARDENED_RUNTIME: YES
        MARKETING_VERSION: "2.0"
        CURRENT_PROJECT_VERSION: "2"
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
    info:
      path: Perch/Info.plist
      properties:
        LSUIElement: true
        CFBundleDisplayName: Perch
        LSApplicationCategoryType: public.app-category.productivity
        ITSAppUsesNonExemptEncryption: false
        NSHumanReadableCopyright: "© 2026 Prasanth Sasikumar"
    scheme:
      testTargets: [PerchTests]
  PerchTests:
    type: bundle.unit-test
    platform: macOS
    sources: [PerchTests]
    settings:
      base:
        GENERATE_INFOPLIST_FILE: YES
    dependencies:
      - target: Perch
```

- [ ] **Step 3: Update `Perch/Info.plist`**

Change two keys only:

```xml
	<key>CFBundleDisplayName</key>
	<string>Perch</string>
	<key>CFBundleShortVersionString</key>
	<string>2.0</string>
```

and `CFBundleVersion` to `2`.

- [ ] **Step 4: Rename the app struct**

In `Perch/PerchApp.swift`, rename `MenuDoApp` to `PerchApp`:

```swift
@main
struct PerchApp: App {
```

Leave the body alone for now — it still renders `TaskListView(store: store)`.

- [ ] **Step 5: Rename the keyboard shortcut**

In `Perch/Support/AppState.swift`:

```swift
extension KeyboardShortcuts.Name {
    /// No default shortcut — unset until the user records one in Settings.
    static let openPerch = Self("openPerch")
}

@MainActor
@Observable
final class AppState {
    var isMenuPresented = false

    init() {
        KeyboardShortcuts.onKeyUp(for: .openPerch) { [weak self] in
            self?.isMenuPresented.toggle()
        }
    }
}
```

In `Perch/Views/SettingsView.swift` change the recorder and the approval message:

```swift
                                launchAtLoginError = "Approval needed: enable Perch in System Settings → General → Login Items."
```

```swift
                KeyboardShortcuts.Recorder("Open Perch:", name: .openPerch)
```

- [ ] **Step 6: Update the quit button copy**

In `Perch/Views/TaskListView.swift`, the two quit-button strings:

```swift
                .help("Quit Perch")
                .accessibilityLabel("Quit Perch")
```

- [ ] **Step 7: Update the storage directory name**

In `Perch/Store/TaskStore.swift`, `defaultFileURL` still says `"MenuDo"`. Change to `"Perch"`:

```swift
    nonisolated static var defaultFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Perch", isDirectory: true)
            .appendingPathComponent("tasks.json")
    }
```

- [ ] **Step 8: Update test imports**

In every file under `PerchTests/`, replace `@testable import MenuDo` with `@testable import Perch`. Files affected: `DragReorderTests.swift`, `StringTruncationTests.swift`, `TaskStoreLogicTests.swift`, `TaskStorePersistenceTests.swift`, `TodoItemTests.swift`.

Also delete `PerchTests/SmokeTests.swift` entirely — its single test asserts `XCTAssertTrue(true)`, which proved the harness ran back when there was nothing else to run. With 46 real tests it earns nothing:

```bash
git rm PerchTests/SmokeTests.swift
```

Also update the temp-directory prefixes in `TaskStoreLogicTests.swift` and `TaskStorePersistenceTests.swift`:

```swift
            .appendingPathComponent("PerchTests-\(UUID().uuidString)", isDirectory: true)
```

- [ ] **Step 9: Update `.gitignore`**

```
.DS_Store
build/
Perch.xcodeproj/
xcuserdata/
```

- [ ] **Step 10: Generate and run the full suite**

```bash
xcodegen generate
xcodebuild test -project Perch.xcodeproj -scheme Perch -destination 'platform=macOS' 2>&1 | tail -30
```

Expected: build succeeds, every existing test passes. Nothing about behaviour changed.

Record the test count this run reports — later tasks refer to "the existing tests" and this is the baseline. (The README's claim of 22 is stale; the real figure is higher, and Task 14 does not repeat it.)

- [ ] **Step 11: Commit**

```bash
git add -A
git commit -m "refactor: rename MenuDo to Perch"
```

---

### Task 2: PerchKit package with PluginStorage

**Files:**
- Create: `PerchKit/Package.swift`
- Create: `PerchKit/Sources/PerchKit/PluginStorage.swift`
- Create: `PerchTests/PerchKit/PluginStorageTests.swift`
- Modify: `project.yml`

**Interfaces:**
- Produces: `PluginStorage(directory: URL)`, `storage.url(named: String) -> URL`, `storage.load<T: Decodable>(_:named:) throws -> T?`, `storage.save<T: Encodable>(_:named:) throws`, and `PluginStorageError.unreadable`.

- [ ] **Step 1: Create the package manifest**

`PerchKit/Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PerchKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PerchKit", targets: ["PerchKit"])
    ],
    targets: [
        .target(name: "PerchKit")
    ]
)
```

- [ ] **Step 2: Wire the package into the Xcode project**

In `project.yml`, add a `packages` entry and depend on it from both targets:

```yaml
packages:
  KeyboardShortcuts:
    url: https://github.com/sindresorhus/KeyboardShortcuts
    from: 2.0.0
  MenuBarExtraAccess:
    url: https://github.com/orchetect/MenuBarExtraAccess
    from: 1.0.0
  PerchKit:
    path: PerchKit
```

Under `targets.Perch.dependencies` add:

```yaml
      - package: PerchKit
        product: PerchKit
```

Under `targets.PerchTests.dependencies` add the same entry.

- [ ] **Step 3: Write the failing tests**

`PerchTests/PerchKit/PluginStorageTests.swift`:

```swift
import PerchKit
import XCTest

private struct Note: Codable, Equatable {
    var text: String
}

final class PluginStorageTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PerchTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    func testLoadingAMissingFileReturnsNil() throws {
        let storage = PluginStorage(directory: directory)
        XCTAssertNil(try storage.load(Note.self, named: "note.json"))
    }

    func testSaveCreatesTheDirectoryAndRoundTrips() throws {
        let storage = PluginStorage(directory: directory)
        try storage.save(Note(text: "hello"), named: "note.json")
        XCTAssertEqual(try storage.load(Note.self, named: "note.json"), Note(text: "hello"))
    }

    func testUnreadableFileIsBackedUpAndThrows() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("note.json")
        try Data("not json".utf8).write(to: fileURL)

        let storage = PluginStorage(directory: directory)
        XCTAssertThrowsError(try storage.load(Note.self, named: "note.json")) { error in
            XCTAssertEqual(error as? PluginStorageError, .unreadable)
        }
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: fileURL.appendingPathExtension("bak").path)
        )
    }

    func testBackupIsReplacedOnASecondFailure() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("note.json")
        let storage = PluginStorage(directory: directory)

        try Data("first".utf8).write(to: fileURL)
        XCTAssertThrowsError(try storage.load(Note.self, named: "note.json"))
        try Data("second".utf8).write(to: fileURL)
        XCTAssertThrowsError(try storage.load(Note.self, named: "note.json"))

        let backup = try Data(contentsOf: fileURL.appendingPathExtension("bak"))
        XCTAssertEqual(String(decoding: backup, as: UTF8.self), "second")
    }

    func testTwoPluginDirectoriesDoNotSeeEachOther() throws {
        let a = PluginStorage(directory: directory.appendingPathComponent("org.ahlab.perch.a"))
        let b = PluginStorage(directory: directory.appendingPathComponent("org.ahlab.perch.b"))
        try a.save(Note(text: "a"), named: "note.json")
        XCTAssertNil(try b.load(Note.self, named: "note.json"))
        XCTAssertEqual(try a.load(Note.self, named: "note.json"), Note(text: "a"))
    }
}
```

- [ ] **Step 4: Run the tests to verify they fail**

```bash
xcodegen generate
xcodebuild test -project Perch.xcodeproj -scheme Perch -destination 'platform=macOS' -only-testing:PerchTests/PluginStorageTests 2>&1 | tail -30
```

Expected: FAIL — `cannot find 'PluginStorage' in scope`.

- [ ] **Step 5: Implement PluginStorage**

`PerchKit/Sources/PerchKit/PluginStorage.swift`:

```swift
import Foundation

public enum PluginStorageError: Error, Equatable {
    /// The file existed but could not be decoded. A `.bak` copy was kept beside it.
    case unreadable
}

/// A plugin's private corner of disk. Every plugin gets its own directory, so
/// two plugins can never collide on a filename.
///
/// Reads and writes are synchronous and small by design — a plugin's state is
/// expected to be a modest JSON document. Callers that mutate often should
/// debounce their own writes rather than expecting this type to.
public final class PluginStorage {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func url(named name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    /// Returns `nil` when the file does not exist, which is the normal
    /// first-launch case rather than an error.
    ///
    /// A file that exists but cannot be decoded is copied to `<name>.bak`
    /// before throwing, so a decoding bug never silently destroys user data.
    public func load<T: Decodable>(_ type: T.Type, named name: String) throws -> T? {
        let fileURL = url(named: name)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        do {
            return try JSONDecoder().decode(T.self, from: Data(contentsOf: fileURL))
        } catch {
            let backupURL = fileURL.appendingPathExtension("bak")
            try? FileManager.default.removeItem(at: backupURL)
            try? FileManager.default.copyItem(at: fileURL, to: backupURL)
            throw PluginStorageError.unreadable
        }
    }

    public func save<T: Encodable>(_ value: T, named name: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url(named: name), options: .atomic)
    }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

```bash
xcodebuild test -project Perch.xcodeproj -scheme Perch -destination 'platform=macOS' -only-testing:PerchTests/PluginStorageTests 2>&1 | tail -30
```

Expected: PASS, 5 tests.

- [ ] **Step 7: Commit**

```bash
git add PerchKit project.yml PerchTests/PerchKit
git commit -m "feat: add PerchKit with namespaced plugin storage"
```

---

### Task 3: PerchKit value types

**Files:**
- Create: `PerchKit/Sources/PerchKit/MenuBarLabel.swift`
- Create: `PerchKit/Sources/PerchKit/PluginCapability.swift`
- Create: `PerchKit/Sources/PerchKit/PluginAction.swift`
- Create: `PerchKit/Sources/PerchKit/PluginDefaults.swift`
- Create: `PerchTests/PerchKit/PluginCapabilityTests.swift`
- Create: `PerchTests/PerchKit/PluginDefaultsTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `MenuBarLabel(systemImage:text:)` with `systemImage: String` and `text: String?`; `PluginCapability` (`.network`, `.credentials`, `.notifications`) and `Set<PluginCapability>.disclosureLines -> [String]`; `PluginAction(id:title:perform:)`; `PluginDefaults(suite:prefix:)` with `bool(_:default:)`, `set(_:for:)` overloads for `Bool`/`Int`/`String?`, `integer(_:default:)`, `string(_:)`.

- [ ] **Step 1: Create MenuBarLabel**

`PerchKit/Sources/PerchKit/MenuBarLabel.swift`:

```swift
import Foundation

/// What a plugin wants shown in the menu bar.
///
/// Deliberately a value type rather than a `View`: the host owns menu bar
/// layout and truncation, so a plugin cannot smuggle arbitrary UI up there.
public struct MenuBarLabel: Equatable, Sendable {
    /// SF Symbol name.
    public let systemImage: String
    /// Accompanying text, or `nil` for icon only.
    public let text: String?

    public init(systemImage: String, text: String? = nil) {
        self.systemImage = systemImage
        self.text = text
    }
}
```

- [ ] **Step 2: Create PluginAction**

`PerchKit/Sources/PerchKit/PluginAction.swift`:

```swift
import Foundation

/// A button a plugin contributes to the panel footer.
public struct PluginAction: Identifiable {
    public let id: String
    public let title: String
    public let perform: @MainActor () -> Void

    public init(id: String, title: String, perform: @escaping @MainActor () -> Void) {
        self.id = id
        self.title = title
        self.perform = perform
    }
}
```

- [ ] **Step 3: Write the failing capability test**

`PerchTests/PerchKit/PluginCapabilityTests.swift`:

```swift
import PerchKit
import XCTest

final class PluginCapabilityTests: XCTestCase {
    func testEmptySetDisclosesLocalOnly() {
        let capabilities: Set<PluginCapability> = []
        XCTAssertEqual(capabilities.disclosureLines, ["Stays entirely on your Mac"])
    }

    func testEachCapabilityHasItsOwnLine() {
        XCTAssertEqual(Set([PluginCapability.network]).disclosureLines, ["Connects to the internet"])
        XCTAssertEqual(
            Set([PluginCapability.credentials]).disclosureLines,
            ["Stores an account credential"]
        )
        XCTAssertEqual(
            Set([PluginCapability.notifications]).disclosureLines,
            ["Sends notifications"]
        )
    }

    func testMultipleCapabilitiesAreOrderedDeterministically() {
        let capabilities: Set<PluginCapability> = [.notifications, .network, .credentials]
        XCTAssertEqual(
            capabilities.disclosureLines,
            ["Stores an account credential", "Connects to the internet", "Sends notifications"]
        )
    }
}
```

- [ ] **Step 4: Run it to verify it fails**

```bash
xcodegen generate
xcodebuild test -project Perch.xcodeproj -scheme Perch -destination 'platform=macOS' -only-testing:PerchTests/PluginCapabilityTests 2>&1 | tail -20
```

Expected: FAIL — `cannot find type 'PluginCapability' in scope`.

- [ ] **Step 5: Implement PluginCapability**

`PerchKit/Sources/PerchKit/PluginCapability.swift`. Note the case order: `disclosureLines` sorts by `allCases` order, so the declaration order below is what produces the expected credentials → network → notifications sequence in the test.

```swift
import Foundation

/// What a plugin does that a user would want disclosed before enabling it.
///
/// This describes behaviour, not enforcement. macOS entitlements are per-app,
/// not per-plugin, so once any plugin declares `.network` the whole binary
/// carries the network entitlement. Perch's Settings pane says what each
/// plugin does; it cannot sandbox one plugin away from another's permissions.
public enum PluginCapability: String, CaseIterable, Sendable {
    case credentials
    case network
    case notifications

    public var disclosure: String {
        switch self {
        case .credentials: "Stores an account credential"
        case .network: "Connects to the internet"
        case .notifications: "Sends notifications"
        }
    }
}

public extension Set where Element == PluginCapability {
    /// Human-readable disclosure lines, in a stable order. A plugin that
    /// declares nothing gets an explicit reassurance rather than blank space.
    var disclosureLines: [String] {
        guard !isEmpty else { return ["Stays entirely on your Mac"] }
        return PluginCapability.allCases.filter(contains).map(\.disclosure)
    }
}
```

- [ ] **Step 6: Run it to verify it passes**

```bash
xcodebuild test -project Perch.xcodeproj -scheme Perch -destination 'platform=macOS' -only-testing:PerchTests/PluginCapabilityTests 2>&1 | tail -20
```

Expected: PASS, 3 tests.

- [ ] **Step 7: Write the failing defaults test**

`PerchTests/PerchKit/PluginDefaultsTests.swift`:

```swift
import PerchKit
import XCTest

final class PluginDefaultsTests: XCTestCase {
    private var suite: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "PerchTests-\(UUID().uuidString)"
        suite = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testMissingKeysReturnTheProvidedDefault() {
        let defaults = PluginDefaults(suite: suite, prefix: "org.ahlab.perch.a")
        XCTAssertTrue(defaults.bool("enabled", default: true))
        XCTAssertEqual(defaults.integer("count", default: 7), 7)
        XCTAssertNil(defaults.string("token"))
    }

    func testValuesRoundTrip() {
        let defaults = PluginDefaults(suite: suite, prefix: "org.ahlab.perch.a")
        defaults.set(false, for: "enabled")
        defaults.set(3, for: "count")
        defaults.set("abc", for: "token")
        XCTAssertFalse(defaults.bool("enabled", default: true))
        XCTAssertEqual(defaults.integer("count", default: 7), 3)
        XCTAssertEqual(defaults.string("token"), "abc")
    }

    func testTwoPrefixesDoNotCollideOnTheSameKey() {
        let a = PluginDefaults(suite: suite, prefix: "org.ahlab.perch.a")
        let b = PluginDefaults(suite: suite, prefix: "org.ahlab.perch.b")
        a.set(1, for: "count")
        b.set(2, for: "count")
        XCTAssertEqual(a.integer("count", default: 0), 1)
        XCTAssertEqual(b.integer("count", default: 0), 2)
    }

    func testSettingAStringToNilClearsIt() {
        let defaults = PluginDefaults(suite: suite, prefix: "org.ahlab.perch.a")
        defaults.set("abc", for: "token")
        defaults.set(nil, for: "token")
        XCTAssertNil(defaults.string("token"))
    }
}
```

- [ ] **Step 8: Run it to verify it fails**

```bash
xcodegen generate
xcodebuild test -project Perch.xcodeproj -scheme Perch -destination 'platform=macOS' -only-testing:PerchTests/PluginDefaultsTests 2>&1 | tail -20
```

Expected: FAIL — `cannot find 'PluginDefaults' in scope`.

- [ ] **Step 9: Implement PluginDefaults**

`PerchKit/Sources/PerchKit/PluginDefaults.swift`:

```swift
import Foundation

/// A plugin's slice of `UserDefaults`. Every key is prefixed with the plugin
/// identifier, so two plugins asking for `"interval"` get two different values.
public final class PluginDefaults {
    private let suite: UserDefaults
    private let prefix: String

    public init(suite: UserDefaults = .standard, prefix: String) {
        self.suite = suite
        self.prefix = prefix
    }

    private func key(_ name: String) -> String { "\(prefix).\(name)" }

    public func bool(_ name: String, default fallback: Bool) -> Bool {
        suite.object(forKey: key(name)) as? Bool ?? fallback
    }

    public func integer(_ name: String, default fallback: Int) -> Int {
        suite.object(forKey: key(name)) as? Int ?? fallback
    }

    public func string(_ name: String) -> String? {
        suite.string(forKey: key(name))
    }

    public func set(_ value: Bool, for name: String) {
        suite.set(value, forKey: key(name))
    }

    public func set(_ value: Int, for name: String) {
        suite.set(value, forKey: key(name))
    }

    public func set(_ value: String?, for name: String) {
        if let value {
            suite.set(value, forKey: key(name))
        } else {
            suite.removeObject(forKey: key(name))
        }
    }
}
```

- [ ] **Step 10: Run the whole suite**

```bash
xcodebuild test -project Perch.xcodeproj -scheme Perch -destination 'platform=macOS' 2>&1 | tail -30
```

Expected: PASS — the existing tests plus 12 new ones (5 storage, 3 capability, 4 defaults).

- [ ] **Step 11: Commit**

```bash
git add PerchKit PerchTests/PerchKit
git commit -m "feat: add PerchKit value types for labels, capabilities, actions, defaults"
```

---

### Task 4: The PerchPlugin protocol and PluginContext

**Files:**
- Create: `PerchKit/Sources/PerchKit/PluginContext.swift`
- Create: `PerchKit/Sources/PerchKit/PerchPlugin.swift`
- Create: `PerchTests/PerchKit/PerchPluginTests.swift`

**Interfaces:**
- Consumes: `PluginStorage`, `PluginDefaults`, `MenuBarLabel`, `PluginAction`, `PluginCapability` from Tasks 2–3.
- Produces: the `PerchPlugin` protocol with statics `identifier`, `displayName`, `icon`, `capabilities`; `init(context: PluginContext)`; instance members `panel: AnyView`, `settings: AnyView`, `menuBarLabel: MenuBarLabel?`, `footerActions: [PluginAction]`. Also `PluginContext(storage:defaults:)` and `PluginContext.standard(appName:identifier:)`.

- [ ] **Step 1: Implement PluginContext**

`PerchKit/Sources/PerchKit/PluginContext.swift`:

```swift
import Foundation

/// Everything the host hands a plugin at construction. A plugin should reach
/// for the world only through this — that is what keeps plugins testable and
/// keeps the host free to change where things live on disk.
public struct PluginContext {
    public let storage: PluginStorage
    public let defaults: PluginDefaults

    public init(storage: PluginStorage, defaults: PluginDefaults) {
        self.storage = storage
        self.defaults = defaults
    }

    /// The standard on-disk layout:
    /// `Application Support/<appName>/Plugins/<identifier>/`
    public static func standard(appName: String, identifier: String) -> PluginContext {
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(appName, isDirectory: true)
            .appendingPathComponent("Plugins", isDirectory: true)
            .appendingPathComponent(identifier, isDirectory: true)
        return PluginContext(
            storage: PluginStorage(directory: directory),
            defaults: PluginDefaults(prefix: identifier)
        )
    }
}
```

- [ ] **Step 2: Write the failing conformance test**

This test exists to prove the protocol is actually usable through an existential — that `[any PerchPlugin]` can be held and its members read. If that breaks, every host type breaks with it.

`PerchTests/PerchKit/PerchPluginTests.swift`:

```swift
import Observation
import PerchKit
import SwiftUI
import XCTest

@MainActor
@Observable
private final class StubPlugin: PerchPlugin {
    static let identifier = "org.ahlab.perch.stub"
    static let displayName = "Stub"
    static let icon = "circle"
    static let capabilities: Set<PluginCapability> = [.network]

    var count = 0

    required init(context: PluginContext) {}

    var panel: AnyView { AnyView(Text("stub")) }
    var menuBarLabel: MenuBarLabel? { MenuBarLabel(systemImage: "circle", text: "\(count)") }
}

@MainActor
@Observable
private final class BarePlugin: PerchPlugin {
    static let identifier = "org.ahlab.perch.bare"
    static let displayName = "Bare"
    static let icon = "square"
    static let capabilities: Set<PluginCapability> = []

    required init(context: PluginContext) {}

    var panel: AnyView { AnyView(EmptyView()) }
}

@MainActor
final class PerchPluginTests: XCTestCase {
    private func makeContext(_ identifier: String) -> PluginContext {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PerchTests-\(UUID().uuidString)", isDirectory: true)
        return PluginContext(
            storage: PluginStorage(directory: directory),
            defaults: PluginDefaults(suite: UserDefaults(suiteName: identifier)!, prefix: identifier)
        )
    }

    func testStaticMetadataIsReadableThroughAnExistential() {
        let plugins: [any PerchPlugin] = [
            StubPlugin(context: makeContext("stub")),
            BarePlugin(context: makeContext("bare")),
        ]
        XCTAssertEqual(plugins.map(\.identifier), ["org.ahlab.perch.stub", "org.ahlab.perch.bare"])
        XCTAssertEqual(plugins.map(\.displayName), ["Stub", "Bare"])
        XCTAssertEqual(plugins.map(\.icon), ["circle", "square"])
        XCTAssertEqual(plugins[0].capabilities, [.network])
        XCTAssertEqual(plugins[1].capabilities, [])
    }

    func testDefaultsAreSuppliedForOptionalRequirements() {
        let plugin: any PerchPlugin = BarePlugin(context: makeContext("bare"))
        XCTAssertNil(plugin.menuBarLabel)
        XCTAssertTrue(plugin.footerActions.isEmpty)
    }

    func testMenuBarLabelReflectsPluginState() {
        let plugin = StubPlugin(context: makeContext("stub"))
        XCTAssertEqual(plugin.menuBarLabel?.text, "0")
        plugin.count = 5
        XCTAssertEqual(plugin.menuBarLabel?.text, "5")
    }

    func testStandardContextNamespacesByIdentifier() {
        let context = PluginContext.standard(appName: "Perch", identifier: "org.ahlab.perch.stub")
        XCTAssertTrue(
            context.storage.directory.path.hasSuffix("Perch/Plugins/org.ahlab.perch.stub")
        )
    }
}
```

- [ ] **Step 3: Run it to verify it fails**

```bash
xcodegen generate
xcodebuild test -project Perch.xcodeproj -scheme Perch -destination 'platform=macOS' -only-testing:PerchTests/PerchPluginTests 2>&1 | tail -20
```

Expected: FAIL — `cannot find type 'PerchPlugin' in scope`.

- [ ] **Step 4: Implement the protocol**

`PerchKit/Sources/PerchKit/PerchPlugin.swift`:

```swift
import Observation
import SwiftUI

/// A tool that lives inside Perch.
///
/// `AnyView` rather than associated types is deliberate. Associated types make
/// `[any PerchPlugin]` painful to hold and iterate, and a menu bar panel is
/// nowhere near the performance envelope where erasure costs anything.
///
/// `Observable` is required rather than merely encouraged: the host reads
/// `menuBarLabel` and `footerActions` during view evaluation, so a plugin whose
/// state changes must be observable for the menu bar to update.
///
/// This API is 0.x and unstable. It will change once a second plugin exists to
/// prove the shape is right.
@MainActor
public protocol PerchPlugin: AnyObject, Observable {
    /// Reverse-DNS, e.g. `"org.ahlab.perch.menudo"`. Also names this plugin's
    /// storage directory and its `UserDefaults` prefix, so it must be stable
    /// across releases — changing it orphans the user's data.
    static var identifier: String { get }
    /// Shown on the panel's tab and in Settings.
    static var displayName: String { get }
    /// SF Symbol name.
    static var icon: String { get }
    /// Disclosed to the user in Settings before they enable the plugin.
    static var capabilities: Set<PluginCapability> { get }

    init(context: PluginContext)

    /// Everything between the tab strip and the footer.
    var panel: AnyView { get }
    /// This plugin's pane in the Settings window. Default: nothing.
    var settings: AnyView { get }
    /// What to show in the menu bar when this plugin is primary. Default: nothing.
    var menuBarLabel: MenuBarLabel? { get }
    /// Buttons contributed to the left of the panel footer. Default: none.
    var footerActions: [PluginAction] { get }
}

public extension PerchPlugin {
    var settings: AnyView { AnyView(EmptyView()) }
    var menuBarLabel: MenuBarLabel? { nil }
    var footerActions: [PluginAction] { [] }

    // Instance mirrors of the statics, so the host can read metadata off an
    // `any PerchPlugin` without opening the existential.
    var identifier: String { Self.identifier }
    var displayName: String { Self.displayName }
    var icon: String { Self.icon }
    var capabilities: Set<PluginCapability> { Self.capabilities }
}
```

**If the compiler rejects `Observable` in the inheritance clause** (a redundant-conformance error against the `@Observable` macro), remove `Observable` from the protocol's inheritance list, leaving `AnyObject` only, and move the requirement into the doc comment as a rule plugin authors must follow. Everything else in this plan is unaffected.

- [ ] **Step 5: Run it to verify it passes**

```bash
xcodebuild test -project Perch.xcodeproj -scheme Perch -destination 'platform=macOS' -only-testing:PerchTests/PerchPluginTests 2>&1 | tail -20
```

Expected: PASS, 4 tests.

- [ ] **Step 6: Commit**

```bash
git add PerchKit PerchTests/PerchKit
git commit -m "feat: add the PerchPlugin protocol and plugin context"
```

---

### Task 5: Move the todo model and logic into MenuDoPlugin

**Files:**
- Create: `Plugins/MenuDoPlugin/Package.swift`
- Create: `Plugins/MenuDoPlugin/Sources/MenuDoPlugin/Models/TodoItem.swift` (moved)
- Create: `Plugins/MenuDoPlugin/Sources/MenuDoPlugin/Store/TaskStore.swift` (moved, rewired)
- Create: `Plugins/MenuDoPlugin/Sources/MenuDoPlugin/Support/DragReorder.swift` (moved)
- Delete: `Perch/Models/`, `Perch/Store/`, `Perch/Support/DragReorder.swift`
- Modify: `Perch/PerchApp.swift`, `Perch/Views/TaskListView.swift`, `Perch/Views/TaskRowView.swift`, `Perch/Views/ReorderableTaskList.swift` (add imports)
- Modify: `PerchTests/TodoItemTests.swift`, `PerchTests/DragReorderTests.swift`, `PerchTests/TaskStoreLogicTests.swift`, `PerchTests/TaskStorePersistenceTests.swift`
- Modify: `project.yml`

**Interfaces:**
- Consumes: `PluginStorage`, `PluginContext.standard(appName:identifier:)` from Tasks 2 and 4.
- Produces: public `TodoItem`, public `TaskStore(storage:filename:)`, public `DragReorder`. `TaskStore.defaultFileURL` is gone — storage now comes from the context.

- [ ] **Step 1: Create the package manifest**

`Plugins/MenuDoPlugin/Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MenuDoPlugin",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MenuDoPlugin", targets: ["MenuDoPlugin"])
    ],
    dependencies: [
        .package(path: "../../PerchKit")
    ],
    targets: [
        .target(name: "MenuDoPlugin", dependencies: ["PerchKit"])
    ]
)
```

- [ ] **Step 2: Wire it into the Xcode project**

In `project.yml` add to `packages`:

```yaml
  MenuDoPlugin:
    path: Plugins/MenuDoPlugin
```

and to both `targets.Perch.dependencies` and `targets.PerchTests.dependencies`:

```yaml
      - package: MenuDoPlugin
        product: MenuDoPlugin
```

- [ ] **Step 3: Move the three files**

```bash
mkdir -p Plugins/MenuDoPlugin/Sources/MenuDoPlugin/{Models,Store,Support}
git mv Perch/Models/TodoItem.swift Plugins/MenuDoPlugin/Sources/MenuDoPlugin/Models/TodoItem.swift
git mv Perch/Store/TaskStore.swift Plugins/MenuDoPlugin/Sources/MenuDoPlugin/Store/TaskStore.swift
git mv Perch/Support/DragReorder.swift Plugins/MenuDoPlugin/Sources/MenuDoPlugin/Support/DragReorder.swift
rmdir Perch/Models Perch/Store
```

- [ ] **Step 4: Make TodoItem public**

Replace the whole of `Plugins/MenuDoPlugin/Sources/MenuDoPlugin/Models/TodoItem.swift`:

```swift
import Foundation

public struct TodoItem: Identifiable, Codable, Equatable {
    public let id: UUID
    public var title: String
    public var isDone: Bool
    public var sortOrder: Int
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        isDone: Bool = false,
        sortOrder: Int,
        createdAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.isDone = isDone
        self.sortOrder = sortOrder
        self.createdAt = createdAt
    }
}
```

- [ ] **Step 5: Make DragReorder public**

In `Plugins/MenuDoPlugin/Sources/MenuDoPlugin/Support/DragReorder.swift`, change the enum and its three methods to `public`. Keep every doc comment exactly as it is.

```swift
public enum DragReorder {
```
```swift
    public static func targetIndex(
```
```swift
    public static func moveOffsets(from sourceIndex: Int, to targetIndex: Int) -> (IndexSet, Int)? {
```
```swift
    public static func displacement(
```

- [ ] **Step 6: Rewire TaskStore onto PluginStorage and make it public**

Replace the top of `Plugins/MenuDoPlugin/Sources/MenuDoPlugin/Store/TaskStore.swift` down to the end of `init`, and the whole `// MARK: - Persistence` section. Every mutation method and derived property gains `public`; their bodies are unchanged.

```swift
import AppKit
import Foundation
import Observation
import PerchKit

@MainActor
@Observable
public final class TaskStore {
    public private(set) var items: [TodoItem] = []
    public private(set) var loadFailureNotice: String?

    private let storage: PluginStorage
    private let filename: String
    @ObservationIgnored private var pendingSave: Task<Void, Never>?

    public init(storage: PluginStorage, filename: String = "tasks.json") {
        self.storage = storage
        self.filename = filename
        load()
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveNow() }
        }
    }
```

Derived state and mutations become public — signatures only, bodies untouched:

```swift
    public var pending: [TodoItem] {
    public var done: [TodoItem] {
    public var currentTask: TodoItem? { pending.first }
    public func add(_ title: String) {
    public func toggle(_ id: UUID) {
    public func delete(_ id: UUID) {
    public func rename(_ id: UUID, to title: String) {
    public func movePending(fromOffsets source: IndexSet, toOffset destination: Int) {
    public func clearCompleted() {
```

Persistence section, replacing `saveNow()` and `load()` entirely:

```swift
    // MARK: - Persistence

    public func saveNow() {
        pendingSave?.cancel()
        // In-memory state stays authoritative; the next mutation retries via scheduleSave().
        try? storage.save(items, named: filename)
    }

    private func load() {
        do {
            items = try storage.load([TodoItem].self, named: filename) ?? []
        } catch {
            items = []
            loadFailureNotice = "Couldn't read saved tasks — backup kept"
        }
    }
```

`scheduleSave()` stays exactly as it is, still `private`.

- [ ] **Step 7: Update the app and views to import the package**

Add `import MenuDoPlugin` to the top of each of: `Perch/PerchApp.swift`, `Perch/Views/TaskListView.swift`, `Perch/Views/TaskRowView.swift`, `Perch/Views/ReorderableTaskList.swift`.

In `Perch/PerchApp.swift`, `TaskStore()` no longer compiles. Replace the store property:

```swift
    @State private var store = TaskStore(
        storage: PluginContext.standard(
            appName: "Perch", identifier: "org.ahlab.perch.menudo"
        ).storage
    )
```

and add `import PerchKit` to that file.

- [ ] **Step 8: Update the moved tests**

In `PerchTests/TodoItemTests.swift` and `PerchTests/DragReorderTests.swift`, replace `@testable import Perch` with:

```swift
import MenuDoPlugin
```

In `PerchTests/TaskStoreLogicTests.swift`, replace the import and `setUp`:

```swift
import MenuDoPlugin
import PerchKit
import XCTest

@MainActor
final class TaskStoreLogicTests: XCTestCase {
    private var store: TaskStore!

    override func setUp() {
        super.setUp()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PerchTests-\(UUID().uuidString)", isDirectory: true)
        store = TaskStore(storage: PluginStorage(directory: directory))
    }
```

`TaskStoreLogicTests` also reads `store.items` in three tests; `items` is public, so no further change.

In `PerchTests/TaskStorePersistenceTests.swift`, replace the import and `setUp`, and change every `TaskStore(fileURL: fileURL)` to `TaskStore(storage: storage)`:

```swift
import MenuDoPlugin
import PerchKit
import XCTest

@MainActor
final class TaskStorePersistenceTests: XCTestCase {
    private var directory: URL!
    private var storage: PluginStorage!
    private var fileURL: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PerchTests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        storage = PluginStorage(directory: directory)
        fileURL = directory.appendingPathComponent("tasks.json")
    }
```

- [ ] **Step 9: Run the full suite**

```bash
xcodegen generate
xcodebuild test -project Perch.xcodeproj -scheme Perch -destination 'platform=macOS' 2>&1 | tail -30
```

Expected: PASS — no change in count from Task 4; these tests moved rather than multiplied. The app behaves identically; only the file's location on disk moved.

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "refactor: move the todo model and store into the MenuDoPlugin package"
```

---

### Task 6: Move the todo views into MenuDoPlugin

**Files:**
- Create: `Plugins/MenuDoPlugin/Sources/MenuDoPlugin/Views/TaskListView.swift` (moved)
- Create: `Plugins/MenuDoPlugin/Sources/MenuDoPlugin/Views/TaskRowView.swift` (moved)
- Create: `Plugins/MenuDoPlugin/Sources/MenuDoPlugin/Views/ReorderableTaskList.swift` (moved)
- Modify: `Perch/PerchApp.swift`

**Interfaces:**
- Produces: public `TaskListView(store:)`. `TaskRowView` and `ReorderableTaskList` stay internal to the package.

Note the footer is deliberately **left in place** in this task — it moves to the host in Task 10, once there is a host footer to move it to. Keeping one behaviour change per task keeps the build green throughout.

- [ ] **Step 1: Move the three view files**

```bash
mkdir -p Plugins/MenuDoPlugin/Sources/MenuDoPlugin/Views
git mv Perch/Views/TaskListView.swift Plugins/MenuDoPlugin/Sources/MenuDoPlugin/Views/TaskListView.swift
git mv Perch/Views/TaskRowView.swift Plugins/MenuDoPlugin/Sources/MenuDoPlugin/Views/TaskRowView.swift
git mv Perch/Views/ReorderableTaskList.swift Plugins/MenuDoPlugin/Sources/MenuDoPlugin/Views/ReorderableTaskList.swift
```

- [ ] **Step 2: Drop the now-redundant imports**

All three files were given `import MenuDoPlugin` in Task 5; inside the package that is a self-import. Remove that line from each of the three moved files.

- [ ] **Step 3: Make TaskListView public**

In `Plugins/MenuDoPlugin/Sources/MenuDoPlugin/Views/TaskListView.swift`:

```swift
public struct TaskListView: View {
    @Bindable var store: TaskStore
```

and add a public initialiser, since a memberwise init on a public struct is internal by default:

```swift
    public init(store: TaskStore) {
        self.store = store
    }
```

Place it directly above `public var body: some View {`, and make `body` public:

```swift
    public var body: some View {
```

- [ ] **Step 4: Build and run the full suite**

```bash
xcodegen generate
xcodebuild test -project Perch.xcodeproj -scheme Perch -destination 'platform=macOS' 2>&1 | tail -30
```

Expected: PASS — same count as Task 5. `Perch/Views/` now contains only `SettingsView.swift`.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor: move the todo views into the MenuDoPlugin package"
```

---

### Task 7: The MenuDo plugin conformance

**Files:**
- Create: `Plugins/MenuDoPlugin/Sources/MenuDoPlugin/MenuDo.swift`
- Create: `PerchTests/Plugins/MenuDoTests.swift`

**Interfaces:**
- Consumes: `PerchPlugin`, `PluginContext`, `MenuBarLabel`, `PluginAction` from Tasks 3–4; `TaskStore`, `TaskListView` from Tasks 5–6.
- Produces: `MenuDo` — a `PerchPlugin` with `identifier == "org.ahlab.perch.menudo"`, `displayName == "Tasks"`, `icon == "checkmark.circle"`, empty `capabilities`, and a public `store: TaskStore`.

The type is named `MenuDo` rather than `MenuDoPlugin` because the module is already called `MenuDoPlugin` and a type of the same name shadows it awkwardly at call sites.

- [ ] **Step 1: Write the failing test**

`PerchTests/Plugins/MenuDoTests.swift`:

```swift
import MenuDoPlugin
import PerchKit
import XCTest

@MainActor
final class MenuDoTests: XCTestCase {
    private func makePlugin() -> MenuDo {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PerchTests-\(UUID().uuidString)", isDirectory: true)
        return MenuDo(
            context: PluginContext(
                storage: PluginStorage(directory: directory),
                defaults: PluginDefaults(
                    suite: UserDefaults(suiteName: "PerchTests-\(UUID().uuidString)")!,
                    prefix: "org.ahlab.perch.menudo"
                )
            )
        )
    }

    func testMetadata() {
        XCTAssertEqual(MenuDo.identifier, "org.ahlab.perch.menudo")
        XCTAssertEqual(MenuDo.displayName, "Tasks")
        XCTAssertEqual(MenuDo.icon, "checkmark.circle")
        XCTAssertTrue(MenuDo.capabilities.isEmpty)
    }

    func testMenuBarLabelIsIconOnlyWithNoTasks() {
        let plugin = makePlugin()
        XCTAssertEqual(plugin.menuBarLabel?.systemImage, "checkmark.circle")
        XCTAssertNil(plugin.menuBarLabel?.text)
    }

    func testMenuBarLabelShowsTheCurrentTask() {
        let plugin = makePlugin()
        plugin.store.add("Write the spec")
        plugin.store.add("Ship it")
        XCTAssertEqual(plugin.menuBarLabel?.text, "Write the spec")
    }

    func testMenuBarLabelAdvancesWhenTheCurrentTaskIsCompleted() {
        let plugin = makePlugin()
        plugin.store.add("First")
        plugin.store.add("Second")
        plugin.store.toggle(plugin.store.currentTask!.id)
        XCTAssertEqual(plugin.menuBarLabel?.text, "Second")
    }

    func testNoFooterActionUntilSomethingIsDone() {
        let plugin = makePlugin()
        plugin.store.add("A")
        XCTAssertTrue(plugin.footerActions.isEmpty)
    }

    func testClearCompletedActionAppearsAndWorks() {
        let plugin = makePlugin()
        plugin.store.add("A")
        plugin.store.toggle(plugin.store.pending[0].id)

        XCTAssertEqual(plugin.footerActions.map(\.title), ["Clear completed"])
        plugin.footerActions[0].perform()
        XCTAssertTrue(plugin.store.done.isEmpty)
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
xcodegen generate
xcodebuild test -project Perch.xcodeproj -scheme Perch -destination 'platform=macOS' -only-testing:PerchTests/MenuDoTests 2>&1 | tail -20
```

Expected: FAIL — `cannot find 'MenuDo' in scope`.

- [ ] **Step 3: Implement the plugin**

`Plugins/MenuDoPlugin/Sources/MenuDoPlugin/MenuDo.swift`:

```swift
import Observation
import PerchKit
import SwiftUI

/// The todo list Perch grew out of: your current task in the menu bar, and a
/// flat list one click away.
///
/// Declares no capabilities. Nothing it stores ever leaves the Mac.
@MainActor
@Observable
public final class MenuDo: PerchPlugin {
    public static let identifier = "org.ahlab.perch.menudo"
    public static let displayName = "Tasks"
    public static let icon = "checkmark.circle"
    public static let capabilities: Set<PluginCapability> = []

    public let store: TaskStore

    public required init(context: PluginContext) {
        store = TaskStore(storage: context.storage)
    }

    public var panel: AnyView {
        AnyView(TaskListView(store: store))
    }

    /// Always contributes its icon, so the menu bar item keeps a stable
    /// appearance even with an empty list; the text is the current task.
    public var menuBarLabel: MenuBarLabel? {
        MenuBarLabel(systemImage: Self.icon, text: store.currentTask?.title)
    }

    public var footerActions: [PluginAction] {
        guard !store.done.isEmpty else { return [] }
        return [
            PluginAction(id: "clearCompleted", title: "Clear completed") { [store] in
                store.clearCompleted()
            }
        ]
    }
}
```

- [ ] **Step 4: Run it to verify it passes**

```bash
xcodebuild test -project Perch.xcodeproj -scheme Perch -destination 'platform=macOS' -only-testing:PerchTests/MenuDoTests 2>&1 | tail -20
```

Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: conform MenuDo to PerchPlugin"
```

---

### Task 8: PluginRegistry

**Files:**
- Create: `Perch/Host/PluginRegistry.swift`
- Create: `PerchTests/Host/PluginRegistryTests.swift`

**Interfaces:**
- Consumes: `PerchPlugin`, `PluginCapability` from Tasks 3–4.
- Produces: `PluginRegistry(plugins:defaults:)` with `entries: [Entry]`, `enabled: [Entry]`, `active: Entry?`, `primary: Entry?`, `activeID: String?`, `primaryID: String?`, `showsTabStrip: Bool`, `isEnabled(_:) -> Bool`, `setEnabled(_:for:)`. `Entry` has `id`, `plugin`, `displayName`, `icon`, `capabilities`.

Defaults keys: `"enabledPluginIDs"` (`[String]`), `"activePluginID"` (`String`), `"primaryPluginID"` (`String`).

- [ ] **Step 1: Write the failing tests**

`PerchTests/Host/PluginRegistryTests.swift`:

```swift
import Observation
import PerchKit
@testable import Perch
import SwiftUI
import XCTest

@MainActor
@Observable
private final class AlphaPlugin: PerchPlugin {
    static let identifier = "alpha"
    static let displayName = "Alpha"
    static let icon = "a.circle"
    static let capabilities: Set<PluginCapability> = []
    required init(context: PluginContext) {}
    var panel: AnyView { AnyView(EmptyView()) }
}

@MainActor
@Observable
private final class BetaPlugin: PerchPlugin {
    static let identifier = "beta"
    static let displayName = "Beta"
    static let icon = "b.circle"
    static let capabilities: Set<PluginCapability> = [.network]
    required init(context: PluginContext) {}
    var panel: AnyView { AnyView(EmptyView()) }
}

@MainActor
final class PluginRegistryTests: XCTestCase {
    private var suite: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "PerchTests-\(UUID().uuidString)"
        suite = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    /// A throwaway context — these stubs never touch storage, and tests have no
    /// business writing into the real Application Support directory.
    private func makePlugins() -> [any PerchPlugin] {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PerchTests-\(UUID().uuidString)", isDirectory: true)
        let context = PluginContext(
            storage: PluginStorage(directory: directory),
            defaults: PluginDefaults(suite: suite, prefix: "stub")
        )
        return [AlphaPlugin(context: context), BetaPlugin(context: context)]
    }

    private func makeRegistry() -> PluginRegistry {
        PluginRegistry(plugins: makePlugins(), defaults: suite)
    }

    func testEverythingIsEnabledByDefault() {
        let registry = makeRegistry()
        XCTAssertEqual(registry.enabled.map(\.id), ["alpha", "beta"])
    }

    func testFirstEnabledIsActiveAndPrimaryByDefault() {
        let registry = makeRegistry()
        XCTAssertEqual(registry.active?.id, "alpha")
        XCTAssertEqual(registry.primary?.id, "alpha")
    }

    func testEntryCarriesMetadataFromThePlugin() {
        let registry = makeRegistry()
        XCTAssertEqual(registry.entries.map(\.displayName), ["Alpha", "Beta"])
        XCTAssertEqual(registry.entries.map(\.icon), ["a.circle", "b.circle"])
        XCTAssertEqual(registry.entries[1].capabilities, [.network])
    }

    func testDisablingAPluginRemovesItFromEnabled() {
        let registry = makeRegistry()
        registry.setEnabled(false, for: "beta")
        XCTAssertEqual(registry.enabled.map(\.id), ["alpha"])
        XCTAssertFalse(registry.isEnabled("beta"))
    }

    func testDisablingTheActivePluginMovesActiveToTheFirstRemaining() {
        let registry = makeRegistry()
        registry.activeID = "beta"
        registry.setEnabled(false, for: "beta")
        XCTAssertEqual(registry.active?.id, "alpha")
    }

    func testDisablingThePrimaryPluginMovesPrimaryToTheFirstRemaining() {
        let registry = makeRegistry()
        registry.primaryID = "beta"
        registry.setEnabled(false, for: "beta")
        XCTAssertEqual(registry.primary?.id, "alpha")
    }

    func testDisablingEverythingLeavesNoActiveOrPrimary() {
        let registry = makeRegistry()
        registry.setEnabled(false, for: "alpha")
        registry.setEnabled(false, for: "beta")
        XCTAssertNil(registry.active)
        XCTAssertNil(registry.primary)
    }

    func testSelectionsPersistAcrossInstances() {
        let registry = makeRegistry()
        registry.setEnabled(false, for: "alpha")
        registry.primaryID = "beta"
        registry.activeID = "beta"

        let reloaded = makeRegistry()
        XCTAssertEqual(reloaded.enabled.map(\.id), ["beta"])
        XCTAssertEqual(reloaded.primary?.id, "beta")
        XCTAssertEqual(reloaded.active?.id, "beta")
    }

    func testAPersistedIDForAPluginThatNoLongerExistsIsIgnored() {
        suite.set(["alpha", "gamma"], forKey: "enabledPluginIDs")
        suite.set("gamma", forKey: "activePluginID")
        suite.set("gamma", forKey: "primaryPluginID")

        let registry = makeRegistry()
        XCTAssertEqual(registry.enabled.map(\.id), ["alpha"])
        XCTAssertEqual(registry.active?.id, "alpha")
        XCTAssertEqual(registry.primary?.id, "alpha")
    }

    func testTabStripIsHiddenUntilASecondPluginIsEnabled() {
        let registry = makeRegistry()
        XCTAssertTrue(registry.showsTabStrip)
        registry.setEnabled(false, for: "beta")
        XCTAssertFalse(registry.showsTabStrip)
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

```bash
xcodegen generate
xcodebuild test -project Perch.xcodeproj -scheme Perch -destination 'platform=macOS' -only-testing:PerchTests/PluginRegistryTests 2>&1 | tail -20
```

Expected: FAIL — `cannot find 'PluginRegistry' in scope`.

- [ ] **Step 3: Implement the registry**

`Perch/Host/PluginRegistry.swift`:

```swift
import Foundation
import Observation
import PerchKit

/// The one host type that knows which plugins exist.
///
/// Everything else in the host works off `Entry`, so adding a plugin means
/// touching exactly one array in `PerchApp` and nothing else.
@MainActor
@Observable
final class PluginRegistry {
    /// A plugin plus the metadata the host needs to draw it. Metadata is
    /// copied at construction so list rendering never reaches into the plugin.
    struct Entry: Identifiable {
        let id: String
        let plugin: any PerchPlugin
        let displayName: String
        let icon: String
        let capabilities: Set<PluginCapability>
    }

    private enum Key {
        static let enabled = "enabledPluginIDs"
        static let active = "activePluginID"
        static let primary = "primaryPluginID"
    }

    let entries: [Entry]
    private let defaults: UserDefaults

    private var enabledIDs: Set<String> {
        didSet {
            defaults.set(Array(enabledIDs), forKey: Key.enabled)
            reconcileSelections()
        }
    }

    var activeID: String? {
        didSet { defaults.set(activeID, forKey: Key.active) }
    }

    var primaryID: String? {
        didSet { defaults.set(primaryID, forKey: Key.primary) }
    }

    init(plugins: [any PerchPlugin], defaults: UserDefaults = .standard) {
        self.defaults = defaults
        entries = plugins.map { plugin in
            Entry(
                id: plugin.identifier,
                plugin: plugin,
                displayName: plugin.displayName,
                icon: plugin.icon,
                capabilities: plugin.capabilities
            )
        }

        let known = Set(entries.map(\.id))
        // A plugin removed from a build leaves its id behind in defaults;
        // filtering against `known` keeps those ghosts out of the UI.
        if let stored = defaults.array(forKey: Key.enabled) as? [String] {
            enabledIDs = Set(stored).intersection(known)
        } else {
            enabledIDs = known
        }
        activeID = defaults.string(forKey: Key.active).flatMap { known.contains($0) ? $0 : nil }
        primaryID = defaults.string(forKey: Key.primary).flatMap { known.contains($0) ? $0 : nil }
        reconcileSelections()
    }

    // MARK: - Derived state

    var enabled: [Entry] {
        entries.filter { enabledIDs.contains($0.id) }
    }

    var active: Entry? {
        enabled.first { $0.id == activeID } ?? enabled.first
    }

    var primary: Entry? {
        enabled.first { $0.id == primaryID } ?? enabled.first
    }

    /// With a single plugin the panel should look exactly like that plugin's
    /// own window — no chrome advertising a framework the user didn't ask for.
    var showsTabStrip: Bool { enabled.count > 1 }

    // MARK: - Mutation

    func isEnabled(_ id: String) -> Bool { enabledIDs.contains(id) }

    func setEnabled(_ isEnabled: Bool, for id: String) {
        guard entries.contains(where: { $0.id == id }) else { return }
        if isEnabled {
            enabledIDs.insert(id)
        } else {
            enabledIDs.remove(id)
        }
    }

    /// Keeps the stored selections pointing at something real, so a disabled
    /// plugin never leaves the panel blank or the menu bar stuck on stale text.
    private func reconcileSelections() {
        let fallback = enabled.first?.id
        if activeID == nil || !enabledIDs.contains(activeID!) { activeID = fallback }
        if primaryID == nil || !enabledIDs.contains(primaryID!) { primaryID = fallback }
    }
}
```

- [ ] **Step 4: Run them to verify they pass**

```bash
xcodebuild test -project Perch.xcodeproj -scheme Perch -destination 'platform=macOS' -only-testing:PerchTests/PluginRegistryTests 2>&1 | tail -20
```

Expected: PASS, 10 tests.

- [ ] **Step 5: Commit**

```bash
git add Perch/Host PerchTests/Host
git commit -m "feat: add the host plugin registry"
```

---

### Task 9: MenuBarLabelResolver

**Files:**
- Create: `Perch/Host/MenuBarLabelResolver.swift`
- Move: `Perch/Support/String+MenuBar.swift` stays where it is (host-owned already)
- Create: `PerchTests/Host/MenuBarLabelResolverTests.swift`

**Interfaces:**
- Consumes: `MenuBarLabel` from Task 3; `String.truncatedForMenuBar(to:)` which already exists in the host.
- Produces: `MenuBarLabelResolver.resolve(primary:showTitle:truncationLength:) -> MenuBarLabel?`, where `nil` means "no plugin contributed, draw Perch's own icon".

- [ ] **Step 1: Write the failing tests**

`PerchTests/Host/MenuBarLabelResolverTests.swift`:

```swift
import PerchKit
@testable import Perch
import XCTest

final class MenuBarLabelResolverTests: XCTestCase {
    func testNoContributedLabelResolvesToNil() {
        XCTAssertNil(
            MenuBarLabelResolver.resolve(primary: nil, showTitle: true, truncationLength: 30)
        )
    }

    func testTitleIsDroppedWhenTheUserAsksForIconOnly() {
        let resolved = MenuBarLabelResolver.resolve(
            primary: MenuBarLabel(systemImage: "checkmark.circle", text: "Buy milk"),
            showTitle: false,
            truncationLength: 30
        )
        XCTAssertEqual(resolved?.systemImage, "checkmark.circle")
        XCTAssertNil(resolved?.text)
    }

    func testShortTitlePassesThrough() {
        let resolved = MenuBarLabelResolver.resolve(
            primary: MenuBarLabel(systemImage: "checkmark.circle", text: "Buy milk"),
            showTitle: true,
            truncationLength: 30
        )
        XCTAssertEqual(resolved?.text, "Buy milk")
    }

    func testLongTitleIsTruncated() {
        let resolved = MenuBarLabelResolver.resolve(
            primary: MenuBarLabel(systemImage: "checkmark.circle", text: "abcdefghij"),
            showTitle: true,
            truncationLength: 5
        )
        XCTAssertEqual(resolved?.text, "abcde…")
    }

    func testAPluginWithNoTextKeepsItsIcon() {
        let resolved = MenuBarLabelResolver.resolve(
            primary: MenuBarLabel(systemImage: "checkmark.circle", text: nil),
            showTitle: true,
            truncationLength: 30
        )
        XCTAssertEqual(resolved?.systemImage, "checkmark.circle")
        XCTAssertNil(resolved?.text)
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

```bash
xcodegen generate
xcodebuild test -project Perch.xcodeproj -scheme Perch -destination 'platform=macOS' -only-testing:PerchTests/MenuBarLabelResolverTests 2>&1 | tail -20
```

Expected: FAIL — `cannot find 'MenuBarLabelResolver' in scope`.

- [ ] **Step 3: Implement the resolver**

`Perch/Host/MenuBarLabelResolver.swift`:

```swift
import PerchKit

/// Turns the primary plugin's contribution into what actually gets drawn,
/// applying the user's menu bar preferences.
///
/// Kept separate from the view so the rules are testable: a plugin's label is
/// the most visible thing Perch does, and it is the easiest to get subtly wrong.
enum MenuBarLabelResolver {
    /// - Returns: the label to draw, or `nil` when no plugin contributed one —
    ///   in which case the caller falls back to Perch's own icon.
    static func resolve(
        primary: MenuBarLabel?,
        showTitle: Bool,
        truncationLength: Int
    ) -> MenuBarLabel? {
        guard let primary else { return nil }
        guard showTitle, let text = primary.text else {
            return MenuBarLabel(systemImage: primary.systemImage, text: nil)
        }
        return MenuBarLabel(
            systemImage: primary.systemImage,
            text: text.truncatedForMenuBar(to: truncationLength)
        )
    }
}
```

- [ ] **Step 4: Run them to verify they pass**

```bash
xcodebuild test -project Perch.xcodeproj -scheme Perch -destination 'platform=macOS' -only-testing:PerchTests/MenuBarLabelResolverTests 2>&1 | tail -20
```

Expected: PASS, 5 tests.

- [ ] **Step 5: Commit**

```bash
git add Perch/Host PerchTests/Host
git commit -m "feat: resolve the menu bar label from the primary plugin"
```

---

### Task 10: The host panel

This is where the app stops being a todo app that happens to have packages, and starts being a host.

**Files:**
- Create: `Perch/Host/PanelView.swift`
- Create: `Perch/Host/PluginTabStrip.swift`
- Create: `Perch/Host/PanelFooter.swift`
- Modify: `Perch/PerchApp.swift`
- Modify: `Plugins/MenuDoPlugin/Sources/MenuDoPlugin/Views/TaskListView.swift` (remove the footer and the fixed width)

**Interfaces:**
- Consumes: `PluginRegistry`, `MenuBarLabelResolver`, `MenuDo`, `PluginContext.standard(appName:identifier:)`.
- Produces: `PanelView(registry:)`.

- [ ] **Step 1: Strip the footer out of TaskListView**

In `Plugins/MenuDoPlugin/Sources/MenuDoPlugin/Views/TaskListView.swift`, delete the trailing `Divider()`, the whole `HStack { … }` footer block with its `.buttonStyle(.borderless)` and `.padding(12)` modifiers, and the `.frame(width: 320)` on the outer `VStack`. The host owns all three now.

After the edit the view ends like this:

```swift
                }
                .frame(minHeight: 120, maxHeight: 360)
            }
        }
        .onAppear { addFieldFocused = true }
    }
}
```

Also remove the now-unused `@Environment(\.openSettings) private var openSettings` line and the `import AppKit` if the compiler flags it as unused (the file imports SwiftUI only; `NSApp` was the sole AppKit user and it lived in the deleted footer).

- [ ] **Step 2: Build the tab strip**

`Perch/Host/PluginTabStrip.swift`:

```swift
import SwiftUI

/// Switches between enabled plugins. Never shown for a single plugin — see
/// `PluginRegistry.showsTabStrip`.
struct PluginTabStrip: View {
    @Bindable var registry: PluginRegistry

    var body: some View {
        Picker("", selection: Binding(
            get: { registry.active?.id ?? "" },
            set: { registry.activeID = $0 }
        )) {
            ForEach(registry.enabled) { entry in
                Text(entry.displayName).tag(entry.id)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }
}
```

- [ ] **Step 3: Build the footer**

`Perch/Host/PanelFooter.swift`:

```swift
import AppKit
import PerchKit
import SwiftUI

/// The row of controls along the bottom of the panel. The gear and the power
/// button are Perch's and always present; everything to their left is
/// contributed by whichever plugin is showing.
struct PanelFooter: View {
    let actions: [PluginAction]
    let onQuit: () -> Void

    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack {
            ForEach(actions) { action in
                Button(action.title) { action.perform() }
            }
            Spacer()
            Button {
                // A menu bar only (LSUIElement) app is not active when its
                // dropdown is clicked, so Settings would open behind the
                // frontmost app unless we activate first.
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .help("Settings")
            .accessibilityLabel("Settings")
            Button(action: onQuit) {
                Image(systemName: "power")
            }
            .help("Quit Perch")
            .accessibilityLabel("Quit Perch")
        }
        .buttonStyle(.borderless)
        .padding(12)
    }
}
```

- [ ] **Step 4: Assemble the panel**

`Perch/Host/PanelView.swift`:

```swift
import PerchKit
import SwiftUI

/// The dropdown. Chrome belongs to the host; the middle belongs to a plugin.
struct PanelView: View {
    @Bindable var registry: PluginRegistry

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if registry.showsTabStrip {
                PluginTabStrip(registry: registry)
                Divider()
            }

            if let active = registry.active {
                active.plugin.panel
            } else {
                Text("No plugins enabled — turn one on in Settings")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            }

            Divider()

            PanelFooter(
                actions: registry.active?.plugin.footerActions ?? [],
                onQuit: quit
            )
        }
        .frame(width: 320)
    }

    /// Gives every enabled plugin a chance to flush before the process dies.
    private func quit() {
        NSApp.terminate(nil)
    }
}
```

Note `TaskStore` already flushes on `NSApplication.willTerminateNotification`, so `NSApp.terminate` is sufficient and no plugin-facing "save now" hook is needed. Do not add one.

- [ ] **Step 5: Rewire PerchApp**

Replace `Perch/PerchApp.swift` entirely:

```swift
import MenuBarExtraAccess
import MenuDoPlugin
import PerchKit
import SwiftUI

@main
struct PerchApp: App {
    @State private var registry = PluginRegistry(plugins: PerchApp.makePlugins())
    @State private var appState = AppState()
    @AppStorage("showTitleInMenuBar") private var showTitleInMenuBar = true
    @AppStorage("titleTruncationLength") private var titleTruncationLength = 30

    /// The one place in Perch that names a concrete plugin.
    private static func makePlugins() -> [any PerchPlugin] {
        [
            MenuDo(context: .standard(appName: "Perch", identifier: MenuDo.identifier))
        ]
    }

    var body: some Scene {
        @Bindable var appState = appState

        MenuBarExtra {
            PanelView(registry: registry)
        } label: {
            menuBarContent(
                MenuBarLabelResolver.resolve(
                    primary: registry.primary?.plugin.menuBarLabel,
                    showTitle: showTitleInMenuBar,
                    truncationLength: titleTruncationLength
                )
            )
        }
        .menuBarExtraAccess(isPresented: $appState.isMenuPresented)
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(registry: registry)
        }
    }

    /// `nil` means no enabled plugin contributed a label, so Perch shows its
    /// own mark rather than an empty menu bar item.
    @ViewBuilder
    private func menuBarContent(_ label: MenuBarLabel?) -> some View {
        if let label {
            if let text = label.text {
                HStack(spacing: 4) {
                    Image(systemName: label.systemImage)
                    Text(text)
                }
            } else {
                Image(systemName: label.systemImage)
            }
        } else {
            Image(systemName: "bird")
        }
    }
}
```

`SettingsView` does not take a `registry` argument yet — that arrives in Task 11. For this task, add the parameter to `SettingsView` as an unused stored property so the app compiles:

```swift
struct SettingsView: View {
    let registry: PluginRegistry
```

- [ ] **Step 6: Build and run the full suite**

```bash
xcodegen generate
xcodebuild test -project Perch.xcodeproj -scheme Perch -destination 'platform=macOS' 2>&1 | tail -30
```

Expected: PASS — Task 6's count plus the 16 added in Tasks 7–9.

- [ ] **Step 7: Verify the panel by hand**

```bash
xcodebuild -project Perch.xcodeproj -scheme Perch -configuration Debug -derivedDataPath build build 2>&1 | tail -5
open build/Build/Products/Debug/Perch.app
```

Confirm, with only MenuDo registered:
- No tab strip is visible.
- The panel is 320pt wide with the add field, list, Done section, and a footer holding "Clear completed" (once something is done), the gear, and the power button.
- The menu bar shows the current task title, truncating at 30 characters.
- `bird` renders if you temporarily comment out the plugin in `makePlugins()` — check this, then restore.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: render the panel from the plugin registry"
```

---

### Task 11: Settings with capability disclosure

**Files:**
- Rewrite: `Perch/Views/SettingsView.swift`
- Create: `Perch/Views/GeneralSettingsView.swift`
- Create: `Perch/Views/PluginsSettingsView.swift`

**Interfaces:**
- Consumes: `PluginRegistry`, `Set<PluginCapability>.disclosureLines`, `LaunchAtLogin`, `KeyboardShortcuts.Name.openPerch`.
- Produces: `SettingsView(registry:)`.

- [ ] **Step 1: Move the existing form into GeneralSettingsView**

`Perch/Views/GeneralSettingsView.swift` — this is today's `SettingsView` body with the primary-plugin picker added:

```swift
import KeyboardShortcuts
import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var registry: PluginRegistry

    @AppStorage("showTitleInMenuBar") private var showTitleInMenuBar = true
    @AppStorage("titleTruncationLength") private var titleTruncationLength = 30
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchAtLoginError: String?

    var body: some View {
        Form {
            Section("Menu bar") {
                Picker("Show in menu bar", selection: Binding(
                    get: { registry.primary?.id ?? "" },
                    set: { registry.primaryID = $0 }
                )) {
                    ForEach(registry.enabled) { entry in
                        Text(entry.displayName).tag(entry.id)
                    }
                }
                .disabled(registry.enabled.isEmpty)
                Toggle("Show title in menu bar", isOn: $showTitleInMenuBar)
                Stepper(
                    "Title length: \(titleTruncationLength) characters",
                    value: $titleTruncationLength,
                    in: 10...60,
                    step: 5
                )
                .disabled(!showTitleInMenuBar)
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        // Re-fired by the resync below; actual state already matches.
                        guard newValue != LaunchAtLogin.isEnabled else { return }
                        do {
                            try LaunchAtLogin.set(newValue)
                            launchAtLoginError = nil
                        } catch {
                            launchAtLoginError = error.localizedDescription
                        }
                        let actual = LaunchAtLogin.isEnabled
                        if actual != newValue {
                            if newValue && LaunchAtLogin.status == .requiresApproval {
                                launchAtLoginError = "Approval needed: enable Perch in System Settings → General → Login Items."
                            }
                            launchAtLogin = actual
                        }
                    }
                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                KeyboardShortcuts.Recorder("Open Perch:", name: .openPerch)
            }
        }
        .formStyle(.grouped)
    }
}
```

- [ ] **Step 2: Build the Plugins pane**

`Perch/Views/PluginsSettingsView.swift`:

```swift
import SwiftUI

struct PluginsSettingsView: View {
    @Bindable var registry: PluginRegistry

    var body: some View {
        Form {
            Section {
                ForEach(registry.entries) { entry in
                    Toggle(isOn: Binding(
                        get: { registry.isEnabled(entry.id) },
                        set: { registry.setEnabled($0, for: entry.id) }
                    )) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: entry.icon)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.displayName)
                                ForEach(entry.capabilities.disclosureLines, id: \.self) { line in
                                    Text(line)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            } footer: {
                Text(
                    "Capabilities describe what a plugin does. macOS grants permissions "
                    + "to the whole app, not to individual plugins."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
```

That footer is not decoration — it is the honest half of the privacy story, and the spec requires it. Do not drop it.

- [ ] **Step 3: Build the sidebar shell**

Replace `Perch/Views/SettingsView.swift` entirely:

```swift
import SwiftUI

struct SettingsView: View {
    @Bindable var registry: PluginRegistry

    private enum Pane: Hashable {
        case general
        case plugins
        case plugin(String)
    }

    @State private var selection: Pane = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Label("General", systemImage: "gearshape").tag(Pane.general)
                Label("Plugins", systemImage: "puzzlepiece.extension").tag(Pane.plugins)
                ForEach(registry.enabled) { entry in
                    Label(entry.displayName, systemImage: entry.icon).tag(Pane.plugin(entry.id))
                }
            }
            .navigationSplitViewColumnWidth(180)
        } detail: {
            switch selection {
            case .general:
                GeneralSettingsView(registry: registry)
            case .plugins:
                PluginsSettingsView(registry: registry)
            case .plugin(let id):
                if let entry = registry.enabled.first(where: { $0.id == id }) {
                    entry.plugin.settings
                } else {
                    // The plugin was disabled while its pane was showing.
                    Text("This plugin is disabled")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 640, height: 420)
    }
}
```

- [ ] **Step 4: Build and run the full suite**

```bash
xcodegen generate
xcodebuild test -project Perch.xcodeproj -scheme Perch -destination 'platform=macOS' 2>&1 | tail -30
```

Expected: PASS — unchanged from Task 10; this task adds views, not tests.

- [ ] **Step 5: Verify Settings by hand**

```bash
xcodebuild -project Perch.xcodeproj -scheme Perch -configuration Debug -derivedDataPath build build 2>&1 | tail -5
open build/Build/Products/Debug/Perch.app
```

Open Settings from the panel's gear and confirm:
- Sidebar lists General, Plugins, and Tasks.
- Plugins shows Tasks with "Stays entirely on your Mac" beneath it, and the footer sentence about per-app permissions.
- Disabling Tasks empties the panel and shows "No plugins enabled"; the menu bar falls back to the `bird` icon. Re-enable it.
- Launch at login and the hotkey recorder still work.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add a sidebar Settings window with per-plugin capability disclosure"
```

---

### Task 12: Automatic import from the old MenuDo container

**Files:**
- Create: `Perch/Host/Migration/LegacyImporter.swift`
- Modify: `Perch/Perch.entitlements`
- Modify: `Perch/PerchApp.swift`
- Create: `PerchTests/Host/LegacyImporterTests.swift`

**Interfaces:**
- Produces: `LegacyImporter.run(tasksSource:tasksDestination:preferencesSource:defaults:) -> LegacyImporter.Result` with `Result(importedTasks: Bool, importedPreferences: Bool)`; `LegacyImporter.runIfNeeded() -> Result`; `LegacyImporter.legacyTasksURL`; `LegacyImporter.legacyPreferencesURL`.

Two things here are easy to get wrong and are the reason this task has its own tests:

1. In a sandboxed app `NSHomeDirectory()` returns the **container**, not the real home. Building the legacy path needs `getpwuid(getuid())`.
2. `UserDefaults` moved with the container too, so the hotkey, truncation length, and display toggle reset — not just the tasks. The importer carries all four.

- [ ] **Step 1: Write the failing tests**

`PerchTests/Host/LegacyImporterTests.swift`:

```swift
@testable import Perch
import XCTest

final class LegacyImporterTests: XCTestCase {
    private var root: URL!
    private var suite: UserDefaults!
    private var suiteName: String!

    private var tasksSource: URL { root.appendingPathComponent("old/tasks.json") }
    private var tasksDestination: URL { root.appendingPathComponent("new/tasks.json") }
    private var preferencesSource: URL { root.appendingPathComponent("old/prefs.plist") }

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PerchTests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(
            at: root.appendingPathComponent("old"), withIntermediateDirectories: true
        )
        suiteName = "PerchTests-\(UUID().uuidString)"
        suite = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func writeLegacyTasks(_ contents: String = #"[{"title":"Old task"}]"#) {
        try! Data(contents.utf8).write(to: tasksSource)
    }

    private func writeLegacyPreferences(_ dictionary: [String: Any]) {
        try! NSDictionary(dictionary: dictionary).write(to: preferencesSource)
    }

    private func run() -> LegacyImporter.Result {
        LegacyImporter.run(
            tasksSource: tasksSource,
            tasksDestination: tasksDestination,
            preferencesSource: preferencesSource,
            defaults: suite
        )
    }

    func testNothingToImportIsNotAnError() {
        let result = run()
        XCTAssertFalse(result.importedTasks)
        XCTAssertFalse(result.importedPreferences)
    }

    func testTasksAreCopiedNotMoved() {
        writeLegacyTasks()
        let result = run()
        XCTAssertTrue(result.importedTasks)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tasksSource.path))
        XCTAssertEqual(
            try? String(contentsOf: tasksDestination, encoding: .utf8),
            #"[{"title":"Old task"}]"#
        )
    }

    func testImportRunsOnlyOnce() {
        writeLegacyTasks()
        XCTAssertTrue(run().importedTasks)

        try! FileManager.default.removeItem(at: tasksDestination)
        XCTAssertFalse(run().importedTasks)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tasksDestination.path))
    }

    func testExistingDataIsNeverOverwritten() {
        writeLegacyTasks()
        try! FileManager.default.createDirectory(
            at: tasksDestination.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try! Data(#"[{"title":"New task"}]"#.utf8).write(to: tasksDestination)

        XCTAssertFalse(run().importedTasks)
        XCTAssertEqual(
            try? String(contentsOf: tasksDestination, encoding: .utf8),
            #"[{"title":"New task"}]"#
        )
    }

    func testPreferencesAreCarriedAcross() {
        writeLegacyPreferences([
            "showTitleInMenuBar": false,
            "titleTruncationLength": 45,
            "KeyboardShortcuts_openMenuDo": "{\"carbonKeyCode\":1}",
        ])
        let result = run()
        XCTAssertTrue(result.importedPreferences)
        XCTAssertEqual(suite.object(forKey: "showTitleInMenuBar") as? Bool, false)
        XCTAssertEqual(suite.object(forKey: "titleTruncationLength") as? Int, 45)
        XCTAssertEqual(
            suite.string(forKey: "KeyboardShortcuts_openPerch"),
            "{\"carbonKeyCode\":1}"
        )
    }

    func testAbsentPreferenceKeysAreLeftAlone() {
        writeLegacyPreferences(["titleTruncationLength": 45])
        XCTAssertTrue(run().importedPreferences)
        XCTAssertNil(suite.object(forKey: "showTitleInMenuBar"))
        XCTAssertNil(suite.object(forKey: "KeyboardShortcuts_openPerch"))
    }

    func testPreferencesAlreadySetLocallyWin() {
        suite.set(20, forKey: "titleTruncationLength")
        writeLegacyPreferences(["titleTruncationLength": 45])
        _ = run()
        XCTAssertEqual(suite.object(forKey: "titleTruncationLength") as? Int, 20)
    }

    func testLegacyPathsPointAtTheOldContainer() {
        XCTAssertTrue(
            LegacyImporter.legacyTasksURL.path.hasSuffix(
                "Library/Containers/org.ahlab.MenuDo/Data/Library/Application Support/MenuDo/tasks.json"
            )
        )
        XCTAssertTrue(
            LegacyImporter.legacyPreferencesURL.path.hasSuffix(
                "Library/Containers/org.ahlab.MenuDo/Data/Library/Preferences/org.ahlab.MenuDo.plist"
            )
        )
        // Sandboxed, NSHomeDirectory() is the container — the importer must not use it.
        XCTAssertFalse(LegacyImporter.legacyTasksURL.path.contains("org.ahlab.Perch"))
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

```bash
xcodegen generate
xcodebuild test -project Perch.xcodeproj -scheme Perch -destination 'platform=macOS' -only-testing:PerchTests/LegacyImporterTests 2>&1 | tail -20
```

Expected: FAIL — `cannot find 'LegacyImporter' in scope`.

- [ ] **Step 3: Implement the importer**

`Perch/Host/Migration/LegacyImporter.swift`:

```swift
import Foundation
import PerchKit

/// Carries a MenuDo 1.x user's data across the bundle identifier change.
///
/// Renaming the app moved the sandbox container, which took both the task file
/// and every `UserDefaults` value with it. This runs once, copies both, and
/// then never touches the old container again.
enum LegacyImporter {
    struct Result: Equatable {
        var importedTasks = false
        var importedPreferences = false
    }

    private static let hasRunKey = "legacyImportCompleted"

    /// The real home directory. `NSHomeDirectory()` is the sandbox container,
    /// so it cannot be used to find another app's container.
    private static var realHomeDirectory: URL {
        guard let entry = getpwuid(getuid()) else { return URL(fileURLWithPath: NSHomeDirectory()) }
        return URL(fileURLWithPath: String(cString: entry.pointee.pw_dir))
    }

    private static var legacyContainer: URL {
        realHomeDirectory
            .appendingPathComponent("Library/Containers/org.ahlab.MenuDo/Data", isDirectory: true)
    }

    static var legacyTasksURL: URL {
        legacyContainer
            .appendingPathComponent("Library/Application Support/MenuDo/tasks.json")
    }

    static var legacyPreferencesURL: URL {
        legacyContainer
            .appendingPathComponent("Library/Preferences/org.ahlab.MenuDo.plist")
    }

    /// Preference keys to carry over, old key to new key. The hotkey key is
    /// renamed because the shortcut itself was renamed to `openPerch`.
    private static let preferenceKeys = [
        "showTitleInMenuBar": "showTitleInMenuBar",
        "titleTruncationLength": "titleTruncationLength",
        "KeyboardShortcuts_openMenuDo": "KeyboardShortcuts_openPerch",
    ]

    @discardableResult
    static func runIfNeeded() -> Result {
        run(
            tasksSource: legacyTasksURL,
            tasksDestination: PluginContext
                .standard(appName: "Perch", identifier: "org.ahlab.perch.menudo")
                .storage
                .url(named: "tasks.json"),
            preferencesSource: legacyPreferencesURL,
            defaults: .standard
        )
    }

    static func run(
        tasksSource: URL,
        tasksDestination: URL,
        preferencesSource: URL,
        defaults: UserDefaults
    ) -> Result {
        guard !defaults.bool(forKey: hasRunKey) else { return Result() }
        defer { defaults.set(true, forKey: hasRunKey) }

        var result = Result()
        result.importedTasks = importTasks(from: tasksSource, to: tasksDestination)
        result.importedPreferences = importPreferences(from: preferencesSource, into: defaults)
        return result
    }

    /// Copies rather than moves, and refuses to touch a destination that
    /// already holds data — losing tasks to a migration would be unforgivable.
    static func importTasks(from source: URL, to destination: URL) -> Bool {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: source.path) else { return false }
        guard !fileManager.fileExists(atPath: destination.path) else { return false }
        do {
            try fileManager.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try fileManager.copyItem(at: source, to: destination)
            return true
        } catch {
            return false
        }
    }

    private static func importPreferences(from source: URL, into defaults: UserDefaults) -> Bool {
        guard let plist = NSDictionary(contentsOf: source) as? [String: Any] else { return false }
        for (oldKey, newKey) in preferenceKeys {
            guard let value = plist[oldKey] else { continue }
            // Anything the user already set in Perch wins over the old value.
            guard defaults.object(forKey: newKey) == nil else { continue }
            defaults.set(value, forKey: newKey)
        }
        return true
    }
}
```

- [ ] **Step 4: Run them to verify they pass**

```bash
xcodebuild test -project Perch.xcodeproj -scheme Perch -destination 'platform=macOS' -only-testing:PerchTests/LegacyImporterTests 2>&1 | tail -20
```

Expected: PASS, 8 tests.

- [ ] **Step 5: Add the read-only entitlement**

`Perch/Perch.entitlements`. The **home-relative** key is the right one — an absolute-path exception cannot name the user's home directory, and `/Users/` would grant far more than needed.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<true/>
	<!-- One-time migration from MenuDo 1.x. Remove once users have moved. -->
	<key>com.apple.security.temporary-exception.files.home-relative-path.read-only</key>
	<array>
		<string>/Library/Containers/org.ahlab.MenuDo/</string>
	</array>
</dict>
</plist>
```

- [ ] **Step 6: Call the importer before any plugin reads storage**

In `Perch/PerchApp.swift`, add an `init` above `body`. It must run before `makePlugins()` constructs `MenuDo`, because `TaskStore` loads in its own initialiser.

```swift
    @State private var registry: PluginRegistry

    init() {
        LegacyImporter.runIfNeeded()
        _registry = State(initialValue: PluginRegistry(plugins: PerchApp.makePlugins()))
    }
```

Delete the old inline initialiser on the `registry` property.

- [ ] **Step 7: Verify the automatic path against a real container**

This is the step that determines whether tier 1 actually works. Do not skip it, and do not assume the answer.

```bash
# Fabricate a MenuDo 1.x container.
mkdir -p ~/Library/Containers/org.ahlab.MenuDo/Data/Library/Application\ Support/MenuDo
echo '[{"id":"11111111-1111-1111-1111-111111111111","title":"Imported task","isDone":false,"sortOrder":0,"createdAt":770000000}]' \
  > ~/Library/Containers/org.ahlab.MenuDo/Data/Library/Application\ Support/MenuDo/tasks.json

# Clear any previous Perch state so the import is allowed to run.
defaults delete org.ahlab.Perch 2>/dev/null
rm -rf ~/Library/Containers/org.ahlab.Perch

xcodebuild -project Perch.xcodeproj -scheme Perch -configuration Debug -derivedDataPath build build 2>&1 | tail -5
open build/Build/Products/Debug/Perch.app
```

Expected: "Imported task" appears in the panel and in the menu bar.

**Record the outcome in the commit message.** If the task does not appear, the entitlement did not grant access — that is exactly the risk the spec named, Task 13's manual fallback becomes the only path, and Step 5's entitlement should be reverted rather than shipped for nothing.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: import tasks and preferences from the MenuDo 1.x container"
```

---

### Task 13: Manual import fallback and the first-run notice

**Files:**
- Create: `Perch/Host/Migration/MigrationState.swift`
- Modify: `Perch/Host/PanelView.swift`
- Modify: `Perch/Views/GeneralSettingsView.swift`
- Modify: `Perch/PerchApp.swift`

**Interfaces:**
- Consumes: `LegacyImporter.importTasks(from:to:)`, `LegacyImporter.legacyTasksURL`.
- Produces: `MigrationState` — an `@Observable` class with `notice: String?` and `func dismiss()`.

- [ ] **Step 1: Add the observable notice**

`Perch/Host/Migration/MigrationState.swift`:

```swift
import Observation

/// A one-off message shown at the top of the panel after a migration.
///
/// Deliberately not persisted: it is worth saying once, and a notice that
/// survives a relaunch becomes clutter.
@MainActor
@Observable
final class MigrationState {
    var notice: String?

    static let importedNotice =
        "Imported your tasks from MenuDo. You can move MenuDo.app to the Trash."

    func dismiss() { notice = nil }
}
```

- [ ] **Step 2: Show it in the panel**

In `Perch/Host/PanelView.swift`, add the state and render it above the tab strip:

```swift
struct PanelView: View {
    @Bindable var registry: PluginRegistry
    @Bindable var migration: MigrationState
```

and at the top of the outer `VStack`:

```swift
            if let notice = migration.notice {
                HStack(alignment: .top, spacing: 8) {
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        migration.dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Dismiss")
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                Divider()
            }
```

- [ ] **Step 3: Wire it up in PerchApp**

In `Perch/PerchApp.swift`:

```swift
    @State private var registry: PluginRegistry
    @State private var migration = MigrationState()

    init() {
        let result = LegacyImporter.runIfNeeded()
        _registry = State(initialValue: PluginRegistry(plugins: PerchApp.makePlugins()))
        let state = MigrationState()
        if result.importedTasks { state.notice = MigrationState.importedNotice }
        _migration = State(initialValue: state)
    }
```

and pass it through:

```swift
            PanelView(registry: registry, migration: migration)
```

`SettingsView` also needs it for the import button, so extend that call too:

```swift
            SettingsView(registry: registry, migration: migration)
```

Add the parameter to `SettingsView` and forward it to `GeneralSettingsView`:

```swift
struct SettingsView: View {
    @Bindable var registry: PluginRegistry
    @Bindable var migration: MigrationState
```
```swift
            case .general:
                GeneralSettingsView(registry: registry, migration: migration)
```

- [ ] **Step 4: Add the manual import button**

In `Perch/Views/GeneralSettingsView.swift`, add the property and a new section at the end of the `Form`:

```swift
    @Bindable var migration: MigrationState
```

```swift
            Section("Migration") {
                Button("Import from MenuDo…") { importFromMenuDo() }
                Text(
                    "Only needed if your tasks didn't carry over from MenuDo 1.x. "
                    + "Choose the old tasks.json when prompted."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
```

and the handler, below `body`:

```swift
    /// The fallback for when the sandbox refuses the automatic import. The
    /// user picking the file is itself the consent that grants read access, so
    /// this path works with no entitlement at all.
    private func importFromMenuDo() {
        let panel = NSOpenPanel()
        panel.title = "Import from MenuDo"
        panel.prompt = "Import"
        panel.allowedContentTypes = [.json]
        panel.directoryURL = LegacyImporter.legacyTasksURL.deletingLastPathComponent()
        panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let source = panel.url else { return }

        let destination = PluginContext
            .standard(appName: "Perch", identifier: "org.ahlab.perch.menudo")
            .storage
            .url(named: "tasks.json")
        if LegacyImporter.importTasks(from: source, to: destination) {
            migration.notice = "Imported. Relaunch Perch to see your tasks."
        } else {
            migration.notice = "Nothing imported — Perch already has tasks saved."
        }
    }
```

Add `import AppKit`, `import PerchKit`, and `import UniformTypeIdentifiers` to the top of the file.

The "relaunch" wording is honest rather than lazy: `TaskStore` loads once in its initialiser, and adding a reload hook to `PerchPlugin` for a one-time migration would be the wrong thing to put in a public protocol.

- [ ] **Step 5: Build and run the full suite**

```bash
xcodegen generate
xcodebuild test -project Perch.xcodeproj -scheme Perch -destination 'platform=macOS' 2>&1 | tail -30
```

Expected: PASS — Task 11's count plus the 8 importer tests from Task 12.

- [ ] **Step 6: Verify by hand**

```bash
defaults delete org.ahlab.Perch 2>/dev/null
rm -rf ~/Library/Containers/org.ahlab.Perch
xcodebuild -project Perch.xcodeproj -scheme Perch -configuration Debug -derivedDataPath build build 2>&1 | tail -5
open build/Build/Products/Debug/Perch.app
```

With the fabricated MenuDo container from Task 12 still in place, confirm the notice appears at the top of the panel and dismisses. Then open Settings → General → Import from MenuDo… and confirm the open panel appears at the old container path.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: add the manual MenuDo import fallback and first-run notice"
```

---

### Task 14: Icon and documentation

**Files:**
- Rewrite: `scripts/make_icon.swift`
- Modify: `Perch/Resources/Assets.xcassets/AppIcon.appiconset/` (regenerated PNG)
- Rewrite: `README.md`

- [ ] **Step 1: Rewrite the icon generator**

`scripts/make_icon.swift`. Rendering the SF Symbol is also how the `bird` availability requirement gets verified: if the symbol is missing on this macOS version, the script fails loudly instead of the app silently showing a blank menu bar item.

```swift
// Generates AppIcon.png (1024×1024): a white bird on a teal rounded rect.
// Run: swift scripts/make_icon.swift
import AppKit

let symbolName = "bird.fill"
guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else {
    FileHandle.standardError.write(
        Data("error: SF Symbol '\(symbolName)' is unavailable on this macOS version\n".utf8)
    )
    exit(1)
}

let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()

NSColor(calibratedRed: 0.11, green: 0.51, blue: 0.51, alpha: 1).setFill()
NSBezierPath(
    roundedRect: NSRect(origin: .zero, size: size),
    xRadius: 184,
    yRadius: 184
).fill()

let configuration = NSImage.SymbolConfiguration(pointSize: 560, weight: .medium)
    .applying(.init(paletteColors: [.white]))
let glyph = symbol.withSymbolConfiguration(configuration) ?? symbol
let glyphSize = glyph.size
glyph.draw(
    in: NSRect(
        x: (size.width - glyphSize.width) / 2,
        y: (size.height - glyphSize.height) / 2,
        width: glyphSize.width,
        height: glyphSize.height
    )
)

image.unlockFocus()

let tiff = image.tiffRepresentation!
let png = NSBitmapImageRep(data: tiff)!.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: "AppIcon.png"))
print("Wrote AppIcon.png")
```

- [ ] **Step 2: Generate and install the icon**

```bash
swift scripts/make_icon.swift
mv AppIcon.png Perch/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
```

Confirm `Contents.json` in that appiconset references `AppIcon.png`; if the existing entry uses a different filename, rename the generated file to match rather than editing the catalog.

- [ ] **Step 3: Verify the icon builds in**

```bash
xcodegen generate
xcodebuild -project Perch.xcodeproj -scheme Perch -configuration Debug -derivedDataPath build build 2>&1 | tail -5
open build/Build/Products/Debug/Perch.app
```

Expected: build succeeds; the app icon appears in the Settings window's title bar and in the About box.

- [ ] **Step 4: Rewrite the README**

Replace `README.md` with the following. Every factual claim here must match what actually shipped — in particular, do not promise a network-free app now that the framework anticipates network plugins.

```markdown
# Perch

Small tools that live in your macOS menu bar.

Perch is a host. The tools themselves are plugins: today there's **Tasks**, the
todo list Perch grew out of, which keeps your current task visible in the menu
bar. More can be added without disturbing what's already there.

## Download

Grab the latest `Perch.zip` from the [Releases page](../../releases/latest),
unzip it, and drag `Perch.app` into your Applications folder.

Requires macOS 14 (Sonoma) or later. Apple Silicon and Intel are both supported.

### First launch

This build is signed ad hoc rather than with a paid Apple Developer certificate,
so macOS Gatekeeper will block it the first time. To open it:

1. Right click (or Control click) `Perch.app` and choose **Open**.
2. Click **Open** again in the dialog that appears.

You only need to do this once. If macOS still refuses, run this in Terminal and
try again:

```bash
xattr -dr com.apple.quarantine /Applications/Perch.app
```

## Upgrading from MenuDo

Perch is MenuDo 1.x renamed and rebuilt as a plugin host. Your tasks and
settings are carried across automatically the first time you launch it.

macOS gives each app its own sandbox, so if the automatic import doesn't find
your old data, open **Settings → General → Import from MenuDo…** and choose the
old `tasks.json`. It lives at:

```
~/Library/Containers/org.ahlab.MenuDo/Data/Library/Application Support/MenuDo/tasks.json
```

Once your tasks are in Perch, **move `MenuDo.app` to the Trash**. Perch can't
unregister MenuDo's launch-at-login entry, so until the old app is deleted both
will start when you log in.

## Plugins

### Tasks

- **Current task in the menu bar.** The first unfinished task is always visible.
  Complete it and the next one takes its place.
- **Quick add.** Open the panel, type, press Return.
- **Edit in place.** Double-click a task to fix its title. Return saves, Escape
  cancels.
- **Reorder by dragging.** Whatever you drag to the top becomes your current task.
- **Done section.** Completed tasks collapse out of the way instead of
  disappearing. Clear them when you want.

Tasks declares no capabilities: everything it stores stays on your Mac.

## Settings

Click the gear icon in the panel.

| Pane | What's in it |
|---|---|
| General | Which plugin owns the menu bar, title display and length, launch at login, global hotkey, MenuDo import |
| Plugins | Enable or disable each plugin, and see what each one can access |
| Tasks | Per-plugin settings, when a plugin has any |

## Your data

Each plugin gets its own directory inside Perch's sandbox container, on your Mac
only:

```
~/Library/Containers/org.ahlab.Perch/Data/Library/Application Support/Perch/Plugins/<plugin-id>/
```

Tasks stores a plain JSON file there and nothing else. If that file is ever
unreadable, Perch keeps a `.bak` copy beside it and tells you, rather than
silently starting empty.

A note on how far that guarantee goes: macOS grants permissions to an app, not
to individual plugins. Perch's Settings window discloses what each plugin does,
but a permission any plugin needs is one the whole app carries. Every plugin
that ships today declares nothing and touches the network never.

## Building from source

Perch is a SwiftUI app built around `MenuBarExtra`. The Xcode project is
generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen), so only
`project.yml` is tracked in git.

```bash
brew install xcodegen
git clone https://github.com/prasanthsasikumar/perch.git
cd perch
xcodegen generate
open Perch.xcodeproj
```

Run the tests with:

```bash
xcodebuild test -project Perch.xcodeproj -scheme Perch -destination 'platform=macOS'
```

### Layout

```
PerchKit/                The public plugin API. Knows nothing about the host.
Plugins/MenuDoPlugin/    The Tasks plugin: model, store, views
Perch/
  Host/                  Registry, panel chrome, menu bar label, MenuDo import
  Views/                 Settings window
  Support/               Launch at login, hotkey state, title truncation
PerchTests/              Unit tests for the kit, the plugin, and the host
```

Dependencies are
[KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) for the
sandbox-safe global hotkey and
[MenuBarExtraAccess](https://github.com/orchetect/MenuBarExtraAccess) for opening
the panel programmatically.

## Writing a plugin

`PerchKit` is the contract. A plugin is a Swift package depending on it, with one
type conforming to `PerchPlugin`, added to the array in `PerchApp.makePlugins()`.

The API is **0.x and unstable** — it will change once a second plugin proves the
shape is right. Plugins are compiled in rather than loaded at runtime.

## License

MIT. See [LICENSE](LICENSE).
```

- [ ] **Step 5: Verify the README's claims against reality**

Run the suite, then check the README's Layout section against the actual tree and fix any path that drifted:

```bash
xcodebuild test -project Perch.xcodeproj -scheme Perch -destination 'platform=macOS' 2>&1 | tail -30
find PerchKit Plugins Perch PerchTests -type d -not -path '*/.*'
```

Expected: PASS, unchanged from Task 13.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "docs: rewrite the README for Perch and regenerate the app icon"
```

- [ ] **Step 7: Rename the GitHub repository**

The last step, and the only one that isn't a file change. On GitHub: **Settings → General → Repository name** → `perch`. GitHub redirects the old clone URL, so existing clones keep working, and stars, issues, and releases carry over.

Then update the local remote and confirm:

```bash
git remote set-url origin https://github.com/prasanthsasikumar/perch.git
git remote -v
git push
```

---

## Notes for the implementer

- **The acceptance criterion for the whole plan** is that a MenuDo 1.x user upgrading to Perch sees no difference: same menu bar text, same 320pt panel with no tab strip, same tasks. If any task breaks that, the task is wrong, not the criterion.
- **Task 12 Step 7 is a real experiment, not a formality.** The spec explicitly flags that the temporary-exception entitlement may not grant access to another app's container. Report what actually happened.
- Do not add hooks, extension points, or capabilities to `PerchKit` beyond what this plan's tasks specify. The Google Analytics plugin gets its own spec, and guessing its needs now is how the protocol ends up the wrong shape. (`PluginDefaults` and `PluginCapability` have no consumer in MenuDo and are still in scope — the approved spec calls for both, one to prevent key collisions and one to drive the Settings disclosure. That ruling is made; do not re-litigate it, and do not extend it to anything else.)
