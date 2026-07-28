# Perch — Menu Bar Plugin Framework — Design

**Date:** 2026-07-28
**Status:** Approved by user (brainstorming session)

## Goal

Turn MenuDo from a single-purpose todo app into **Perch**, a macOS menu bar host
that runs small tools as plugins. The existing todo list becomes the first
plugin. A Google Analytics plugin — showing website visits in the menu bar — is
the second, and is deliberately **out of scope for this spec**; it is what will
prove the plugin protocol is right, and it gets its own design cycle.

## Scope

In scope:

- Rename the product, repo, and bundle identifier to Perch.
- `PerchKit`: a public, versioned plugin protocol in its own Swift package.
- A host app that registers plugins, owns the menu bar item, renders the panel
  with a tab strip, and hosts a multi-pane Settings window.
- Migrate today's MenuDo code into `MenuDoPlugin` with no behaviour change.
- A one-time importer that carries existing users' tasks and preferences across
  the bundle-identifier change.
- Per-plugin capability disclosure in Settings.

Out of scope:

- The Google Analytics plugin (separate spec).
- Runtime-loadable plugin bundles. The protocol is designed so this can arrive
  later without changing the plugin-facing API, but nothing loads at runtime now.
- Keychain/credential helpers, background refresh scheduling, inter-plugin
  messaging. These get designed when a plugin actually needs them.
- A standalone MenuDo app. MenuDo ships only as a Perch plugin from now on.
- App Store distribution. Still ad-hoc signed, as today.

## Decisions taken during brainstorming

| Question | Decision |
|---|---|
| What is a plugin, technically? | A compile-time Swift package conforming to a `PerchKit` protocol. |
| Menu bar presence | One host icon; the panel switches between plugins via a segmented tab strip. |
| Menu bar label | A user-designated **primary** plugin owns it. Defaults to MenuDo. |
| Public plugin API? | Yes, that is the goal. `PerchKit` is the public contract, unstable until 1.0. |
| Privacy story | Each plugin declares capabilities; Settings discloses them per plugin. |
| Repo strategy | Rename in place, keep history, migrate user data. |
| MenuDo's future | Plugin only. No standalone build. |
| Tab label | "Tasks". Package name stays `MenuDoPlugin`. |

## Architecture

Three layers. The dependency arrow only ever points at `PerchKit`.

```
PerchKit/                   Swift package — the public plugin API. No host internals.
  PerchPlugin.swift
  PluginContext.swift
  PluginCapability.swift
  PluginStorage.swift
  MenuBarLabel.swift
  PluginAction.swift

Plugins/
  MenuDoPlugin/             depends on PerchKit
    MenuDoPlugin.swift      the entry point / manifest
    Models/TodoItem.swift
    Store/TaskStore.swift
    Views/TaskListView.swift, TaskRowView.swift, ReorderableTaskList.swift
    Support/DragReorder.swift

Perch/                      the host app — the only place naming concrete plugins
  PerchApp.swift
  Host/PluginRegistry.swift
  Host/PanelView.swift
  Host/PluginTabStrip.swift
  Host/PanelFooter.swift
  Host/MenuBarLabelResolver.swift
  Host/Migration/LegacyImporter.swift
  Settings/SettingsView.swift (General, Plugins, per-plugin panes)
  Support/LaunchAtLogin.swift, String+MenuBar.swift, AppState.swift
```

Plugins are local Swift packages referenced by path from `project.yml`, so
`xcodegen generate && open Perch.xcodeproj` remains the entire setup story.

### The plugin contract

```swift
@MainActor
public protocol PerchPlugin: AnyObject, Observable {
    static var identifier: String { get }        // "org.ahlab.perch.menudo"
    static var displayName: String { get }       // tab label
    static var icon: String { get }              // SF Symbol
    static var capabilities: Set<PluginCapability> { get }

    init(context: PluginContext)

    var panel: AnyView { get }
    var settings: AnyView { get }
    var menuBarLabel: MenuBarLabel? { get }
    var footerActions: [PluginAction] { get }
}
```

`AnyView` rather than associated types is deliberate: associated types make
`[any PerchPlugin]` painful to hold and iterate, and a menu bar panel is nowhere
near the performance envelope where the erasure cost matters.

`MenuBarLabel` is a value type (SF Symbol name + text), not a view. The host
keeps control of menu bar layout and truncation; a plugin cannot smuggle
arbitrary UI into the menu bar.

`PluginAction` is a title plus a closure, rendered by the host in the footer's
left region. MenuDo contributes "Clear completed".

### PluginContext

What the host hands each plugin at construction:

- `storage: PluginStorage` — namespaced JSON persistence at
  `Application Support/Perch/Plugins/<identifier>/<name>.json`. This is today's
  `TaskStore` persistence (debounced save, atomic write, `.bak` on decode
  failure) lifted out and made reusable.
- `defaults: PluginDefaults` — a `UserDefaults` wrapper that prefixes keys with
  the plugin identifier, so two plugins cannot collide.

### Capabilities

```swift
public enum PluginCapability: String, Sendable {
    case network
    case credentials
    case notifications
}
```

MenuDo declares an empty set. This is what lets the Plugins settings pane state
"Stays entirely on your Mac" for MenuDo and something honest and different for
Analytics later. The disclosure is generated from the declaration, not
hand-maintained prose.

Note the limit, stated plainly because the README makes a privacy claim: macOS
entitlements are per-app, not per-plugin. When a network-using plugin ships, the
whole binary gains the network entitlement. Capability disclosure describes what
each plugin *does*, not what the sandbox *enforces*.

## Host behaviour

### Menu bar

A single `MenuBarExtra`. Its label asks the primary plugin for `menuBarLabel`,
then applies the existing truncation settings. `showTitleInMenuBar` and
`titleTruncationLength` become host settings — they were never MenuDo-specific.

Resolution order: primary plugin's label → if the primary is disabled or returns
`nil`, the Perch icon alone (SF Symbol `bird`, verified against macOS 14 at
build time; fall back to a bundled asset if unavailable). MenuDo continues to
contribute `checkmark.circle`, so the bar looks unchanged for existing users.

### Panel

```
PanelView
├── PluginTabStrip      host — hidden entirely when fewer than two plugins are enabled
├── activePlugin.panel  plugin — scrolls; host clamps min/max height
└── PanelFooter         host — activePlugin.footerActions on the left, gear and quit on the right
```

Width stays 320pt. **With only MenuDo enabled the panel is structurally
identical to today's** — no tab strip, same footer. This is the acceptance
criterion for the whole migration.

### PluginRegistry

The one host object that knows concrete plugins: the built-in array, the enabled
set, the active tab, and which plugin is primary. Enabled set, active tab, and
primary selection persist in host `UserDefaults`. Reopening the panel returns the
user to the tab they left.

### Settings

A sidebar window, since one `Form` no longer suffices:

- **General** — launch at login, global hotkey, menu bar display and truncation,
  primary-plugin picker.
- **Plugins** — enable/disable each plugin, and its capability disclosure.
- **Per-plugin panes** — renders `plugin.settings` for each enabled plugin. A
  plugin with nothing to configure gets no pane. MenuDo has none today.

## Migration

### Identity changes

- Bundle identifier `org.ahlab.MenuDo` → `org.ahlab.Perch`
- Product `MenuDo.app` → `Perch.app`
- `MARKETING_VERSION` → `2.0` (new app identity)
- `PerchKit` starts at `0.1.0`, explicitly unstable. The semver promise begins at
  1.0, once the Analytics plugin has proven the protocol shape is right.
  Freezing a public API before a second implementation exists freezes the wrong
  shape.
- App icon regenerated. `scripts/make_icon.swift` currently draws MenuDo's blue
  checkmark and must be replaced with a Perch mark.
- Repo renamed to `perch`. GitHub redirects old clone URLs; history, stars, and
  releases survive.

### The sandbox obstacle

The app is sandboxed with only `com.apple.security.app-sandbox`. Changing the
bundle identifier moves the container:

```
old:  ~/Library/Containers/org.ahlab.MenuDo/Data/…/Application Support/MenuDo/tasks.json
new:  ~/Library/Containers/org.ahlab.Perch/Data/…/Application Support/Perch/Plugins/org.ahlab.perch.menudo/tasks.json
```

**A sandboxed app cannot read another app's container.** Copying the file on
first launch does not work as written.

`UserDefaults` moves with the container too, so the recorded global hotkey, the
truncation length, and the menu bar display setting also reset. The importer
must read the old preferences plist alongside `tasks.json`:

```
~/Library/Containers/org.ahlab.MenuDo/Data/Library/Preferences/org.ahlab.MenuDo.plist
```

### Two-tier importer

1. **Automatic.** Add
   `com.apple.security.temporary-exception.files.absolute-path.read-only` scoped
   to the old container path. On first launch, if the new storage is empty and
   the old files read, import tasks and the three preferences, then mark
   migration complete. The app is ad-hoc signed, so this costs nothing today, and
   the entitlement is deleted in a later release once users have moved — before
   any App Store build exists.
2. **Manual fallback.** If the entitlement does not in fact grant access — this
   must be verified empirically during implementation, not assumed; Apple has
   tightened temporary exceptions against other apps' containers over time — the
   first-run notice offers **"Import from MenuDo…"**, opening an `NSOpenPanel` at
   the old path. The user selecting the file is the consent that grants access,
   with no entitlement required.

The migration ships either way; the only open question is whether it is automatic
or one click.

The import is **non-destructive** (copies, never moves), **idempotent** (a
completion flag in host defaults), and **refuses to run when the target already
has data**.

### Stale login item

If launch-at-login was enabled, macOS has `org.ahlab.MenuDo` registered, and
Perch cannot unregister another app's login item. The first-run notice therefore
reads: *"Your tasks are here. You can move MenuDo.app to the Trash."* Once the
old app is deleted the registration lapses. The release notes must say this too,
or a user ends up running both apps.

## Testing

Tests that move unchanged:

- `TodoItemTests`, `TaskStoreLogicTests`, `DragReorderTests` → `MenuDoPlugin`
- `StringTruncationTests` → host (truncation is now a menu bar concern)
- `SmokeTests` → host

Tests that change:

- `TaskStorePersistenceTests` → `PluginStorageTests`, plus a new case proving
  two plugin identifiers cannot see each other's files.

New coverage:

- `PluginRegistry` — enabled set and active tab persist; primary plugin falls
  back sanely when disabled or absent.
- `MenuBarLabelResolver` — primary label, `nil` label, disabled primary,
  truncation applied.
- `LegacyImporter` — idempotence, non-destructive copy, refusal when the target
  has data, tested against temp directories rather than real containers.

The acceptance test, written first: **with only MenuDo enabled, the panel has no
tab strip and is structurally identical to today's.**

## Risks

| Risk | Mitigation |
|---|---|
| Temporary-exception entitlement may not grant access to another app's container | Tier-2 `NSOpenPanel` fallback always works; verify tier 1 empirically before relying on it |
| Users end up running both MenuDo and Perch | First-run notice and release notes tell them to trash the old app |
| Public API frozen in the wrong shape | `PerchKit` stays 0.x and explicitly unstable until the Analytics plugin validates it |
| The README's "no network access" claim weakens | Per-plugin capability disclosure, with the per-app entitlement limitation stated honestly rather than glossed |

## Next

The Google Analytics plugin gets its own brainstorm and spec. It brings OAuth,
the network entitlement, credential storage, and polling — none of which should
be guessed at here.
