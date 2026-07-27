# Inline Task Editing — Design

**Date:** 2026-07-25
**Status:** Approved by user (brainstorming session)

## Goal

Let the user correct a task's title in place. Today a typo means deleting the
task and retyping it, which also loses its position in the list.

## Scope

- Double-clicking a task row turns its title into an editable text field.
- An "Edit" entry in the row's existing right-click menu, and a matching
  accessibility action.
- Both pending and done tasks are editable.

Out of scope: editing anything other than the title, multi-line titles,
undo/redo.

## Interaction

While a row is editing, the title `Text` is replaced by a `TextField` bound to
a local draft string, focused on appear. The checkbox and trash button are
hidden so the field spans the row.

| Action | Result |
|---|---|
| Enter | Commit the draft, leave edit mode |
| Esc | Discard the draft, leave edit mode |
| Focus lost (another row, the add field) | Commit, same as Enter |
| The row's view is torn down (panel dismissed, another row takes over the edit, Done section collapsed) | Commit, same as Enter |
| Committing an empty or whitespace-only draft | `rename` no-ops, so the original title stands and the row leaves edit mode |

Esc is therefore the only way to throw a draft away; every other ending
saves it. An earlier revision of this spec called discarding on panel
dismissal acceptable — that was overridden during implementation, because
losing what you typed by clicking away is worse than saving it.

Because teardown commits by default, the flag that suppresses the commit on
the Esc path cannot live in `@State`: `cancel()` writes it in the same update
cycle that unmounts the field, and a stale read would turn every Esc into a
save. It is held in a small reference type instead, so the write and the read
always reach the same storage.

Clearing the text is deliberately not a way to delete a task: an accidental
Cmd+A followed by Enter would otherwise destroy the item silently. Deleting
stays explicit, via the trash button or the context menu.

## Where the editing state lives

`TaskListView` owns `@State private var editingID: UUID?` and passes it as a
binding to `ReorderableTaskList` and to the done-section `TaskRowView`s.

Keeping this state local to `TaskRowView` would be simpler, but
`ReorderableTaskList` attaches a `DragGesture(minimumDistance: 4)` to each
pending row. If that gesture stayed active during editing, click-dragging to
select text inside the field would start a reorder instead. The parent must
therefore know which row is editing so it can omit the drag gesture for that
row. Hoisting the state also guarantees only one row edits at a time.

`TaskRowView` keeps a local `@State draftTitle` — the in-progress text is
nobody else's business, and discarding it on Esc should not touch shared state.

## Changes

**`Store/TaskStore.swift`** — new method:

```swift
func rename(_ id: UUID, to title: String)
```

Trims whitespace and newlines, returns early on an empty result or an unknown
id, otherwise assigns `title` and calls `scheduleSave()`. This mirrors the
existing trim-and-guard in `add(_:)`.

**`Views/TaskRowView.swift`** — takes `@Binding var editingID: UUID?`. Renders
the `TextField` branch when `editingID == item.id`, otherwise today's row.
Adds `.onTapGesture(count: 2)`, an `Edit` context-menu item, and
`.accessibilityAction(named: "Edit")`.

**`Views/ReorderableTaskList.swift`** — takes the same binding, forwards it to
each row, and skips `.gesture(dragGesture(for:))` for the editing row.

**`Views/TaskListView.swift`** — owns `editingID` and passes it down.

## Testing

`rename` is pure store logic and is covered by unit tests:

- `MenuDoTests/TaskStoreLogicTests.swift` — renames the matching item and
  leaves others alone; trims surrounding whitespace; no-ops on an empty or
  whitespace-only title; no-ops on an unknown id; does not change `isDone`,
  `sortOrder`, or `createdAt`.
- `MenuDoTests/TaskStorePersistenceTests.swift` — a renamed title survives a
  save/load round trip.

The view interaction is not unit-testable here, so double-click, Esc, commit
on focus loss, and drag-still-works-when-not-editing are verified by building
and running the app.

## Risk

Esc may be swallowed by the `MenuBarExtra` panel, which closes on Esc. The
deployment target is macOS 14, so `.onKeyPress(.escape)` is available as a
fallback if `.onExitCommand` does not fire or the panel closes instead of
cancelling the edit. Which one is used gets settled by running the app.

**Settled:** `.onKeyPress(.escape)` returning `.handled` wins the key ahead of
the panel. Verified by hand — Esc reverts the title and leaves the panel open.
