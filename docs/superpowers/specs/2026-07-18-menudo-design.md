# MenuDo — macOS Menu Bar Todo App — Design

**Date:** 2026-07-18
**Status:** Approved by user (brainstorming session)

## Goal

A macOS menu bar todo app in the style of TodoBar: the user's current task is
visible in the menu bar at all times; clicking it opens a dropdown to manage a
single flat task list. Distributed via the Mac App Store.

## Scope (v1)

- Menu bar dropdown: add, complete, delete, and reorder tasks.
- The first incomplete task's title is shown in the menu bar (the "current
  task"); completing it promotes the next task.
- Completed tasks collapse into a "Done" section with a "Clear completed"
  button. Nothing is deleted implicitly.
- Settings window: menu bar display style (icon + title, or icon only), title
  truncation length (default 30 characters), launch-at-login toggle, global
  hotkey recorder.
- Global hotkey opens the dropdown with the quick-add field focused. No
  default shortcut ships; it is unset until the user records one in Settings.
- Launch at login via `SMAppService`.

Out of scope for v1: due dates, notifications, Apple Reminders sync, multiple
lists, iCloud sync, menu bar countdown timers.

## Approach

SwiftUI `MenuBarExtra` (`.window` style) in a single app target. No AppKit
status-item code, no extensions, no network. Minimum deployment target:
macOS 14 (Sonoma). App Sandbox enabled (App Store requirement) — trivially
satisfied since the app only touches its own container.

Alternatives considered and rejected:
- **AppKit `NSStatusItem` + `NSPopover`:** more control, much more
  boilerplate; can migrate later without changing the SwiftUI view layer if a
  `MenuBarExtra` limitation is hit.
- **Electron/Tauri:** heavy, non-native, poor App Store fit.

## Structure

```
MenuDo.app (single target)
├── MenuDoApp.swift          — @main; MenuBarExtra (label = current task) + Settings scene
├── Models/
│   └── Task.swift           — struct Task: id (UUID), title, isDone, sortOrder, createdAt (Codable)
├── Store/
│   └── TaskStore.swift      — @Observable single source of truth; CRUD + reorder; JSON persistence
├── Views/
│   ├── TaskListView.swift   — dropdown: quick-add field, task rows, Done section, footer
│   ├── TaskRowView.swift    — checkbox, title, drag-to-reorder, delete on hover
│   └── SettingsView.swift   — display style, truncation, launch-at-login, hotkey recorder
└── Support/
    ├── LaunchAtLogin.swift  — SMAppService wrapper; reflects real status
    └── KeyboardShortcuts    — SPM dependency (sindresorhus/KeyboardShortcuts), sandbox-safe hotkey
```

`TaskStore` is the only stateful object. Views bind to it directly. Settings
live in `UserDefaults` via `@AppStorage`.

## Data flow

View action → `TaskStore` method → in-memory `[Task]` mutation → SwiftUI
re-render (menu bar label included) → debounced (~0.5 s) save to
`Application Support/MenuDo/tasks.json` (inside the sandbox container). Load
once at launch. "Current task" = first task with `isDone == false` ordered by
`sortOrder`.

## Error handling

- **Corrupt/unreadable `tasks.json` at launch:** copy it to `tasks.json.bak`,
  start with an empty list, show a one-line notice in the dropdown
  ("Couldn't read saved tasks — backup kept"). Never crash; never silently
  discard data.
- **Save failure (disk full, permissions):** in-memory state stays
  authoritative; retry the save on the next mutation.
- **Launch-at-login / hotkey registration failure:** settings toggles read
  actual state (`SMAppService.status`) rather than assuming success.

## Testing

- **Unit tests (XCTest) for `TaskStore`:** add/complete/delete/reorder,
  sort-order integrity after reorder, JSON round-trip, corrupt-file recovery
  (backup created, empty list loaded), current-task selection logic. The store
  takes an injectable storage URL so tests run against a temp directory.
- **Manual smoke checklist:** menu bar label updates and truncation, icon-only
  mode, hotkey open + focus, launch-at-login round-trip, light/dark mode,
  quit/relaunch persistence.

## App Store phase (final)

- Entitlements: App Sandbox on; no additional entitlements needed.
- App Store Connect: bundle ID, app record, screenshots, description.
- Privacy label: "Data Not Collected" (no network, no analytics).
- Requires the user's Apple Developer Program account for signing and upload.
- The name "MenuDo" is a working title; confirm availability/rename before
  submission (rename is a find-replace + target rename).
