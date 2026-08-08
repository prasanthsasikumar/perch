# Plugin Enable Lifecycle — Design and Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Make disabling a plugin in Settings actually stop it working, rather than only hiding its tab.

**Tech Stack:** Swift 5.9, macOS 14, SwiftUI, Observation, XCTest, XcodeGen.

## Why

`PerchApp.makePlugins()` constructs every plugin unconditionally at launch, and
`PluginRegistry`'s enabled set only filters what the UI draws. A plugin that
starts background work in its initializer therefore keeps doing that work after
the user switches it off.

This is live today, not hypothetical. `Analytics.init` calls
`startRefreshing()`, so a disabled Analytics still authenticates to Google and
fetches GA4 numbers every half hour. `Market` has the same shape, and once its
Plan 2 lands it will load Facebook pages every fifteen minutes while switched
off. A toggle that does not do what it says is worse on the plugin that reaches
the network.

`PluginRegistry` already solves the sibling problem correctly: `flushAll()`
calls `flush()` on every plugin, with a comment explaining that disabling hides
a plugin rather than destroying it. This adds the missing half — a way to tell
a plugin to stop.

## Design

One optional method on `PerchPlugin`, mirroring `flush()`:

```swift
func setEnabled(_ isEnabled: Bool)
```

with an empty default, so no existing plugin breaks and a plugin with no
background work implements nothing.

`PluginRegistry` calls it in two places: once per plugin during `init` with its
stored state, and from `enabledIDs.didSet` for the plugins whose state actually
changed. Nothing else in the host changes.

Then:

- **Market** stops calling `poller.run()` in `init` and starts the poller from
  `setEnabled(true)`, stopping it on `false`. Not auto-starting is the point:
  `tick()` runs immediately on the first pass, so a disabled plugin that
  started in `init` would fire one real search at every launch before the
  registry could tell it to stop.
- **Analytics** cancels and restarts its refresh task the same way.
- **Tasks** needs nothing — the default no-op covers it.

### Decisions taken

These were left to my judgment; recording them so they are not mistaken for
accidents.

- **The hook is `setEnabled(_:)`, not separate `enable()`/`disable()` calls.**
  One method with a Bool matches `flush()`'s shape and makes the startup call —
  where a plugin needs to be told its state regardless of which state that is —
  natural rather than a special case.
- **The registry calls it during `init`, not lazily on first access.** A plugin
  must learn it is disabled before it can start anything, and `init` is the
  only moment guaranteed to precede that.
- **Only changed plugins are notified on toggle.** Re-notifying every plugin on
  every toggle would make `setEnabled` implementations need idempotence for no
  benefit. They should be idempotent anyway; they are not required to be.
- **`flushAll()` keeps flushing disabled plugins.** Its existing comment gives
  the reason — a disabled plugin still holds state the user typed — and that
  reasoning is unaffected by this change.
- **This modifies `PerchKit`,** which prior plans forbade. It is an additive
  protocol requirement with a default implementation, so nothing breaks.
  PerchKit documents itself as 0.x and unstable and predicts that a third
  plugin will force a change; this is that.

## Global Constraints

- macOS 14, `swift-tools-version: 5.9`. Swift 6.0-only APIs do not compile.
- Tests are XCTest. Host and PerchKit tests go in `PerchTests/`, which is
  healthy (164 tests, 3.5s). Market's own tests stay in its package target.
- No new dependencies.
- `Perch.xcodeproj` is gitignored; only `project.yml` is tracked.
- Run host tests with:
  `xcodebuild test -project Perch.xcodeproj -scheme Perch -destination 'platform=macOS' 2>&1 | tail -20`
  **In the foreground.** It takes about a minute.
- Run Market's package tests with:
  `swift test --package-path Plugins/MarketPlugin`

---

### Task 1: The hook and the host wiring

**Files:**
- Modify: `PerchKit/Sources/PerchKit/PerchPlugin.swift`
- Modify: `Perch/Host/PluginRegistry.swift`
- Test: `PerchTests/Host/PluginEnableTests.swift`

**Interfaces:**
- Produces: `PerchPlugin.setEnabled(_ isEnabled: Bool)` with an empty default
  implementation in the existing `public extension PerchPlugin` block.
  `PluginRegistry` calls it during `init` for every plugin and from
  `enabledIDs.didSet` for changed plugins only.

- [ ] **Step 1: Write the failing test**

`PerchTests/Host/PluginEnableTests.swift`:

```swift
import PerchKit
@testable import Perch
import SwiftUI
import XCTest

/// A plugin that records every enable/disable it is told about.
@MainActor
@Observable
private final class RecordingPlugin: PerchPlugin {
    static let identifier = "org.ahlab.perch.recording"
    static let displayName = "Recording"
    static let icon = "circle"
    static let capabilities: Set<PluginCapability> = []

    var calls: [Bool] = []

    required init(context: PluginContext) {}

    var panel: AnyView { AnyView(EmptyView()) }

    func setEnabled(_ isEnabled: Bool) { calls.append(isEnabled) }
}

/// A second one, so we can prove only the changed plugin is notified.
@MainActor
@Observable
private final class OtherRecordingPlugin: PerchPlugin {
    static let identifier = "org.ahlab.perch.recording.other"
    static let displayName = "Other"
    static let icon = "square"
    static let capabilities: Set<PluginCapability> = []

    var calls: [Bool] = []

    required init(context: PluginContext) {}

    var panel: AnyView { AnyView(EmptyView()) }

    func setEnabled(_ isEnabled: Bool) { calls.append(isEnabled) }
}

@MainActor
final class PluginEnableTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "PluginEnableTests-\(UUID().uuidString)")!
    }

    private func context(_ identifier: String) -> PluginContext {
        PluginContext(
            storage: PluginStorage(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("PluginEnableTests-\(UUID().uuidString)")
            ),
            defaults: PluginDefaults(suite: makeDefaults(), prefix: identifier)
        )
    }

    func testAPluginIsToldItIsEnabledAtStartup() {
        let plugin = RecordingPlugin(context: context(RecordingPlugin.identifier))

        _ = PluginRegistry(plugins: [plugin], defaults: makeDefaults())

        XCTAssertEqual(plugin.calls, [true])
    }

    func testAPluginStoredAsDisabledIsToldSoAtStartup() {
        let defaults = makeDefaults()
        let plugin = RecordingPlugin(context: context(RecordingPlugin.identifier))
        let other = OtherRecordingPlugin(context: context(OtherRecordingPlugin.identifier))
        // Both known to this install, only `other` switched on.
        defaults.set([RecordingPlugin.identifier, OtherRecordingPlugin.identifier],
                     forKey: "seenPluginIDs")
        defaults.set([OtherRecordingPlugin.identifier], forKey: "enabledPluginIDs")

        _ = PluginRegistry(plugins: [plugin, other], defaults: defaults)

        XCTAssertEqual(plugin.calls, [false])
        XCTAssertEqual(other.calls, [true])
    }

    func testDisablingNotifiesThePlugin() {
        let plugin = RecordingPlugin(context: context(RecordingPlugin.identifier))
        let other = OtherRecordingPlugin(context: context(OtherRecordingPlugin.identifier))
        let registry = PluginRegistry(plugins: [plugin, other], defaults: makeDefaults())
        plugin.calls.removeAll()
        other.calls.removeAll()

        registry.setEnabled(false, for: RecordingPlugin.identifier)

        XCTAssertEqual(plugin.calls, [false])
    }

    func testOnlyTheChangedPluginIsNotified() {
        let plugin = RecordingPlugin(context: context(RecordingPlugin.identifier))
        let other = OtherRecordingPlugin(context: context(OtherRecordingPlugin.identifier))
        let registry = PluginRegistry(plugins: [plugin, other], defaults: makeDefaults())
        plugin.calls.removeAll()
        other.calls.removeAll()

        registry.setEnabled(false, for: RecordingPlugin.identifier)

        XCTAssertTrue(other.calls.isEmpty)
    }

    func testReEnablingNotifiesThePlugin() {
        let plugin = RecordingPlugin(context: context(RecordingPlugin.identifier))
        let other = OtherRecordingPlugin(context: context(OtherRecordingPlugin.identifier))
        let registry = PluginRegistry(plugins: [plugin, other], defaults: makeDefaults())
        registry.setEnabled(false, for: RecordingPlugin.identifier)
        plugin.calls.removeAll()

        registry.setEnabled(true, for: RecordingPlugin.identifier)

        XCTAssertEqual(plugin.calls, [true])
    }

    func testSettingTheSameStateTwiceDoesNotRenotify() {
        let plugin = RecordingPlugin(context: context(RecordingPlugin.identifier))
        let other = OtherRecordingPlugin(context: context(OtherRecordingPlugin.identifier))
        let registry = PluginRegistry(plugins: [plugin, other], defaults: makeDefaults())
        registry.setEnabled(false, for: RecordingPlugin.identifier)
        plugin.calls.removeAll()

        registry.setEnabled(false, for: RecordingPlugin.identifier)

        XCTAssertTrue(plugin.calls.isEmpty)
    }

    func testAPluginThatDoesNotImplementTheHookStillWorks() {
        // The default implementation must make this a no-op, not a crash.
        let plugin = SilentPlugin(context: context(SilentPlugin.identifier))
        let registry = PluginRegistry(plugins: [plugin], defaults: makeDefaults())

        registry.setEnabled(false, for: SilentPlugin.identifier)

        XCTAssertFalse(registry.isEnabled(SilentPlugin.identifier))
    }
}

/// Implements none of the optional protocol members.
@MainActor
@Observable
private final class SilentPlugin: PerchPlugin {
    static let identifier = "org.ahlab.perch.silent"
    static let displayName = "Silent"
    static let icon = "circle"
    static let capabilities: Set<PluginCapability> = []

    required init(context: PluginContext) {}

    var panel: AnyView { AnyView(EmptyView()) }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `xcodebuild test -project Perch.xcodeproj -scheme Perch -destination 'platform=macOS' -only-testing:PerchTests/PluginEnableTests 2>&1 | tail -20`
Expected: FAIL — `value of type 'RecordingPlugin' has no member 'setEnabled'` or a protocol-conformance error, because the requirement does not exist yet.

- [ ] **Step 3: Add the protocol requirement**

In `PerchKit/Sources/PerchKit/PerchPlugin.swift`, add to the protocol body, after `flush()`:

```swift
    /// Told when the user enables or disables this plugin, and once at startup
    /// with its stored state.
    ///
    /// A plugin that does background work — a timer, a refresh loop, a poller —
    /// must stop it when this is `false`. Disabling hides a plugin's tab, but
    /// hiding is not stopping: without this, a switched-off plugin keeps
    /// talking to the network on a user who thought they had turned it off.
    ///
    /// Stored state is left alone. Disabling is not deleting, and re-enabling
    /// should pick up where the plugin left off.
    ///
    /// Default: no-op. A plugin that only does work while its panel is on
    /// screen needs nothing here.
    func setEnabled(_ isEnabled: Bool)
```

and to the existing `public extension PerchPlugin` block, beside `func flush() {}`:

```swift
    func setEnabled(_ isEnabled: Bool) {}
```

- [ ] **Step 4: Wire the registry**

In `Perch/Host/PluginRegistry.swift`, change the `enabledIDs` property to notify on change:

```swift
    private var enabledIDs: Set<String> {
        didSet {
            persistEnabledIDs()
            notifyEnabledChanges(from: oldValue)
            reconcileSelections()
        }
    }
```

Add this method beside `flushAll()`:

```swift
    /// Tells each plugin whose state actually changed, and no others.
    ///
    /// Only the changed ones: re-notifying everything on every toggle would
    /// require every `setEnabled` implementation to be idempotent for no gain.
    private func notifyEnabledChanges(from oldValue: Set<String>) {
        for entry in entries where enabledIDs.contains(entry.id) != oldValue.contains(entry.id) {
            entry.plugin.setEnabled(enabledIDs.contains(entry.id))
        }
    }

    /// Every plugin learns its stored state once, at startup, before it has a
    /// chance to start any background work of its own.
    private func notifyInitialEnabledState() {
        for entry in entries { entry.plugin.setEnabled(enabledIDs.contains(entry.id)) }
    }
```

At the end of `init`, after the existing `persistEnabledIDs()` and
`reconcileSelections()` calls, add:

```swift
        notifyInitialEnabledState()
```

Note the `didSet` does not fire for the assignments in `init`'s own body, which
is exactly why the explicit startup call is needed — the same reason
`persistEnabledIDs()` is already called there.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `xcodebuild test -project Perch.xcodeproj -scheme Perch -destination 'platform=macOS' -only-testing:PerchTests/PluginEnableTests 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`, 7 tests

- [ ] **Step 6: Run the whole host suite**

Run: `xcodebuild test -project Perch.xcodeproj -scheme Perch -destination 'platform=macOS' 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`, 171 tests (164 existing plus 7 new), no regressions in the existing `PluginRegistryTests` or `PluginFlushTests`.

- [ ] **Step 7: Commit**

```bash
git add PerchKit Perch/Host/PluginRegistry.swift PerchTests/Host/PluginEnableTests.swift
git commit -m "feat: tell plugins when they are enabled or disabled"
```

---

### Task 2: Market and Analytics stop working when disabled

**Files:**
- Modify: `Plugins/MarketPlugin/Sources/MarketPlugin/Market.swift`
- Modify: `Plugins/AnalyticsPlugin/Sources/AnalyticsPlugin/Analytics.swift`
- Test: `Plugins/MarketPlugin/Tests/MarketPluginTests/MarketPluginTests.swift` (add to)
- Test: `PerchTests/Plugins/Analytics/AnalyticsPluginTests.swift` (add to)

**Interfaces:**
- Consumes: `PerchPlugin.setEnabled(_:)` from Task 1.
- Produces: `Market.setEnabled(_:)` starting/stopping `poller`; `Analytics.setEnabled(_:)` starting/cancelling `refreshTask`. `Market.init` no longer starts the poller.

- [ ] **Step 1: Write the failing Market test**

Add to `Plugins/MarketPlugin/Tests/MarketPluginTests/MarketPluginTests.swift`:

```swift
    func testThePollerDoesNotRunUntilTheHostEnablesIt() {
        // A disabled plugin that started polling in init would fire one real
        // search at every launch before the registry could stop it.
        let plugin = makePlugin()

        XCTAssertFalse(plugin.poller.isRunning)
    }

    func testEnablingStartsThePoller() {
        let plugin = makePlugin()

        plugin.setEnabled(true)

        XCTAssertTrue(plugin.poller.isRunning)
    }

    func testDisablingStopsThePoller() {
        let plugin = makePlugin()
        plugin.setEnabled(true)

        plugin.setEnabled(false)

        XCTAssertFalse(plugin.poller.isRunning)
    }

    func testEnablingTwiceDoesNotLeaveTwoLoopsRunning() {
        let plugin = makePlugin()

        plugin.setEnabled(true)
        plugin.setEnabled(true)
        plugin.setEnabled(false)

        XCTAssertFalse(plugin.poller.isRunning)
    }
```

`isRunning` does not exist yet — add it to `WatchPoller` as
`public var isRunning: Bool { loop != nil }`. `run()` already cancels any
previous loop before starting a new one, so the double-enable case is covered
by making `stop()` nil the reference, which it already does.

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --package-path Plugins/MarketPlugin --filter MarketPluginTests`
Expected: FAIL — `value of type 'WatchPoller' has no member 'isRunning'`

- [ ] **Step 3: Implement Market**

In `Plugins/MarketPlugin/Sources/MarketPlugin/Poller/WatchPoller.swift`, add
beside `run()`:

```swift
    /// Whether the background loop is live. The host's enable/disable hook is
    /// the only thing that should change this.
    public var isRunning: Bool { loop != nil }
```

In `Market.swift`, remove `poller.run()` from `init`, and add:

```swift
    /// The host calls this at startup with the stored state, and again on
    /// every toggle. Polling Facebook is precisely the kind of work a user
    /// expects to stop when they switch a plugin off.
    public func setEnabled(_ isEnabled: Bool) {
        if isEnabled {
            poller.run()
        } else {
            poller.stop()
        }
    }
```

Leave `flush()` as it is — a disabled plugin still holds watches the user
created, and the registry still flushes it on quit.

- [ ] **Step 4: Run the Market tests**

Run: `swift test --package-path Plugins/MarketPlugin`
Expected: 91 tests, 0 failures (87 existing plus 4 new)

- [ ] **Step 5: Write the failing Analytics test**

Add to `PerchTests/Plugins/Analytics/AnalyticsPluginTests.swift`, following the
construction pattern already used in that file:

```swift
    func testTheRefreshLoopDoesNotRunUntilTheHostEnablesIt() {
        let plugin = makePlugin()

        XCTAssertFalse(plugin.isRefreshing)
    }

    func testEnablingStartsTheRefreshLoop() {
        let plugin = makePlugin()

        plugin.setEnabled(true)

        XCTAssertTrue(plugin.isRefreshing)
    }

    func testDisablingStopsTheRefreshLoop() {
        let plugin = makePlugin()
        plugin.setEnabled(true)

        plugin.setEnabled(false)

        XCTAssertFalse(plugin.isRefreshing)
    }
```

If `AnalyticsPluginTests` has no `makePlugin()` helper, add one matching how the
file already constructs an `Analytics` with a stub API and an in-memory
credential store — do not introduce a new construction pattern.

- [ ] **Step 6: Run it to verify it fails**

Run: `xcodebuild test -project Perch.xcodeproj -scheme Perch -destination 'platform=macOS' -only-testing:PerchTests/AnalyticsPluginTests 2>&1 | tail -20`
Expected: FAIL — `value of type 'Analytics' has no member 'isRefreshing'`

- [ ] **Step 7: Implement Analytics**

In `Plugins/AnalyticsPlugin/Sources/AnalyticsPlugin/Analytics.swift`, remove
`startRefreshing()` from `init`, and add:

```swift
    /// Whether the background refresh loop is live.
    public var isRefreshing: Bool { refreshTask != nil }

    /// The host calls this at startup with the stored state, and again on every
    /// toggle. Until this existed, a switched-off Analytics went on
    /// authenticating to Google and fetching GA4 numbers every half hour.
    public func setEnabled(_ isEnabled: Bool) {
        if isEnabled {
            startRefreshing()
        } else {
            stopRefreshing()
        }
    }

    private func stopRefreshing() {
        refreshTask?.cancel()
        refreshTask = nil
    }
```

`startRefreshing()` must cancel any existing task before starting a new one, so
a double enable cannot leave two loops running. If it does not already, add
`refreshTask?.cancel()` as its first line.

- [ ] **Step 8: Run the whole host suite**

Run: `xcodebuild test -project Perch.xcodeproj -scheme Perch -destination 'platform=macOS' 2>&1 | tail -20`
Expected: `** TEST SUCCEEDED **`, 174 tests, no regressions.

- [ ] **Step 9: Hand the app check to the user — do not automate it**

**Do not script the UI.** No accessibility scripting, no `cliclick`, no
coordinate clicks. This runs on a real working desktop with the user's own
windows open; a missed click has already landed on unrelated content once.
Building and launching the app to confirm it starts is fine. Clicking through
it is not your job.

Report this as a check for the user to run themselves:

1. Settings → Plugins. Switch **Analytics** off.
2. Confirm its tab disappears from the panel.
3. Switch it back on and confirm the tab returns and the plugin still works.
4. Do the same for **Market**.

This only checks that the toggle still behaves correctly and nothing crashes
on the transition — the loop behaviour itself is covered by the tests above.

- [ ] **Step 10: Commit**

```bash
git add Plugins/MarketPlugin Plugins/AnalyticsPlugin PerchTests
git commit -m "feat: Market and Analytics stop working when disabled"
```

---

## What this does not do

- It does not stop a plugin being *constructed* at launch. Construction is
  cheap — reading a JSON file — and gating it would mean the Settings list
  could not show a disabled plugin's name and capabilities. Only work stops.
- It does not unload or free a disabled plugin. Disabling is not deleting;
  re-enabling picks up the same state.
- It does not touch `flushAll()`, which still flushes every plugin on quit for
  the reason its existing comment gives.
