# Inline Task Editing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user rename a task in place by double-clicking it, instead of deleting and retyping.

**Architecture:** A new `TaskStore.rename(_:to:)` mutation carries the model change. The UI state — which row is currently being edited — is hoisted to `TaskListView` as an `editingID: UUID?` and threaded down through `ReorderableTaskList` to `TaskRowView`, because `ReorderableTaskList` must suppress its drag gesture on the editing row so text selection works.

**Tech Stack:** Swift 5 / SwiftUI, macOS 14+, XcodeGen, XCTest.

**Spec:** `docs/superpowers/specs/2026-07-25-inline-task-editing-design.md`

## Global Constraints

- Working directory for all commands: `/Users/prasanthsasikumar/Documents/GitHub/menudo`.
- Minimum deployment target: **macOS 14.0**. `.onKeyPress` and `@Observable` are available; anything newer is not.
- The model type is named **`TodoItem`** (not `Task` — that collides with Swift Concurrency's `Task`).
- No new source *files* are created by this plan, so `xcodegen generate` is **not** needed. Only existing files are modified.
- Tests: `xcodebuild test -project MenuDo.xcodeproj -scheme MenuDo -destination 'platform=macOS'`
- `TaskStore` is `@MainActor`; all tests touching it are on `@MainActor` classes.
- Follow the existing test style: `XCTest`, `@testable import MenuDo`, a per-test temp `fileURL` built in `setUp`.

---

### Task 1: `TaskStore.rename(_:to:)`

**Files:**
- Modify: `MenuDo/Store/TaskStore.swift` (add a method in the `// MARK: - Mutations` section, after `delete(_:)` at line 58-61)
- Test: `MenuDoTests/TaskStoreLogicTests.swift` (append tests before the closing brace)
- Test: `MenuDoTests/TaskStorePersistenceTests.swift` (append one test before the closing brace)

**Interfaces:**
- Consumes: existing `TaskStore.add(_:)`, `toggle(_:)`, `items`, `pending`, `done`, `scheduleSave()`, `saveNow()`.
- Produces: `func rename(_ id: UUID, to title: String)` on `TaskStore`. Trims whitespace and newlines from `title`; no-ops when the trimmed title is empty or when no item has `id`; otherwise assigns the trimmed title and schedules a save. Task 2's views call this.

- [ ] **Step 1: Write the failing tests**

Append to `MenuDoTests/TaskStoreLogicTests.swift`, immediately before the final closing brace:

```swift
    func testRenameUpdatesMatchingTaskOnly() {
        store.add("A")
        store.add("B")
        store.rename(store.pending[0].id, to: "A renamed")
        XCTAssertEqual(store.pending.map(\.title), ["A renamed", "B"])
    }

    func testRenameTrimsWhitespace() {
        store.add("A")
        store.rename(store.pending[0].id, to: "  Buy oat milk  ")
        XCTAssertEqual(store.pending[0].title, "Buy oat milk")
    }

    func testRenameIgnoresEmptyAndWhitespaceTitles() {
        store.add("A")
        let id = store.pending[0].id
        store.rename(id, to: "")
        store.rename(id, to: "   ")
        XCTAssertEqual(store.pending[0].title, "A")
    }

    func testRenameIgnoresUnknownID() {
        store.add("A")
        store.rename(UUID(), to: "Nope")
        XCTAssertEqual(store.items.map(\.title), ["A"])
    }

    func testRenamePreservesIdentityAndPosition() {
        store.add("A")
        store.add("B")
        store.toggle(store.pending[1].id)
        let original = store.done[0]
        store.rename(original.id, to: "B renamed")
        let renamed = store.done[0]
        XCTAssertEqual(renamed.id, original.id)
        XCTAssertEqual(renamed.isDone, original.isDone)
        XCTAssertEqual(renamed.sortOrder, original.sortOrder)
        XCTAssertEqual(renamed.createdAt, original.createdAt)
        XCTAssertEqual(renamed.title, "B renamed")
    }
```

Append to `MenuDoTests/TaskStorePersistenceTests.swift`, immediately before the final closing brace:

```swift
    func testRenameSurvivesSaveAndReload() {
        let store = TaskStore(fileURL: fileURL)
        store.add("A")
        store.rename(store.pending[0].id, to: "A renamed")
        store.saveNow()

        let reloaded = TaskStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.pending.map(\.title), ["A renamed"])
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
xcodebuild test -project MenuDo.xcodeproj -scheme MenuDo -destination 'platform=macOS' -quiet 2>&1 | tail -20
```

Expected: compile failure — `value of type 'TaskStore' has no member 'rename'`.

- [ ] **Step 3: Implement `rename`**

In `MenuDo/Store/TaskStore.swift`, add directly after the `delete(_:)` method:

```swift
    func rename(_ id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].title = trimmed
        scheduleSave()
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
xcodebuild test -project MenuDo.xcodeproj -scheme MenuDo -destination 'platform=macOS' -quiet 2>&1 | tail -20
```

Expected: all tests pass (40 existing + 6 new = 46).

- [ ] **Step 5: Commit**

```bash
git add MenuDo/Store/TaskStore.swift MenuDoTests/TaskStoreLogicTests.swift MenuDoTests/TaskStorePersistenceTests.swift
git commit -m "feat: add TaskStore.rename for editing task titles"
```

---

### Task 2: Inline editing in the task row

Everything in this task has to land together — `TaskRowView` gains a required
`@Binding`, so its two call sites must change in the same commit or nothing
compiles.

**Files:**
- Modify: `MenuDo/Views/TaskRowView.swift` (whole file rewritten)
- Modify: `MenuDo/Views/ReorderableTaskList.swift` (add the binding property, pass it to the row, make the drag gesture conditional)
- Modify: `MenuDo/Views/TaskListView.swift` (own `editingID`, pass it to both row call sites)

**Interfaces:**
- Consumes: `TaskStore.rename(_:to:)` from Task 1; existing `store.toggle(_:)`, `store.delete(_:)`, `store.pending`, `store.done`.
- Produces: `TaskRowView(item:store:editingID:)` and `ReorderableTaskList(store:editingID:)`, where `editingID` is a `Binding<UUID?>` naming the row currently being edited (`nil` = none).

- [ ] **Step 1: Rewrite `TaskRowView`**

Replace the entire contents of `MenuDo/Views/TaskRowView.swift` with:

```swift
import SwiftUI

struct TaskRowView: View {
    let item: TodoItem
    let store: TaskStore
    @Binding var editingID: UUID?

    @State private var hovering = false
    @State private var draftTitle = ""
    @FocusState private var fieldFocused: Bool

    private var isEditing: Bool { editingID == item.id }

    var body: some View {
        HStack(spacing: 8) {
            if isEditing {
                TextField("", text: $draftTitle)
                    .textFieldStyle(.roundedBorder)
                    .focused($fieldFocused)
                    .onSubmit(commit)
                    // Esc: the MenuBarExtra panel also closes on Esc, so the
                    // key press is consumed here to cancel the edit instead.
                    .onKeyPress(.escape) {
                        cancel()
                        return .handled
                    }
                    // Clicking another row, or the add field, ends the edit.
                    .onChange(of: fieldFocused) { _, focused in
                        if !focused, isEditing { commit() }
                    }
            } else {
                Button {
                    store.toggle(item.id)
                } label: {
                    Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(item.isDone ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                }
                .buttonStyle(.borderless)

                Text(item.title)
                    .strikethrough(item.isDone)
                    .foregroundStyle(item.isDone ? .secondary : .primary)
                    .lineLimit(2)

                Spacer()

                if hovering {
                    Button {
                        store.delete(item.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { beginEditing() }
        .contextMenu {
            Button("Edit") { beginEditing() }
            Button("Delete", role: .destructive) { store.delete(item.id) }
        }
        .accessibilityAction(named: "Edit") { beginEditing() }
        .accessibilityAction(named: "Delete") { store.delete(item.id) }
        .onChange(of: isEditing) { _, editing in
            if editing { fieldFocused = true }
        }
    }

    private func beginEditing() {
        guard !isEditing else { return }
        draftTitle = item.title
        editingID = item.id
    }

    private func commit() {
        store.rename(item.id, to: draftTitle)
        editingID = nil
    }

    private func cancel() {
        editingID = nil
    }
}
```

- [ ] **Step 2: Thread the binding through `ReorderableTaskList`**

In `MenuDo/Views/ReorderableTaskList.swift`, change the stored properties at
the top of the struct from:

```swift
struct ReorderableTaskList: View {
    let store: TaskStore

    @State private var draggingID: UUID?
```

to:

```swift
struct ReorderableTaskList: View {
    let store: TaskStore
    @Binding var editingID: UUID?

    @State private var draggingID: UUID?
```

Then in `body`, change the row construction and the gesture modifier from:

```swift
                TaskRowView(item: item, store: store)
```

to:

```swift
                TaskRowView(item: item, store: store, editingID: $editingID)
```

and from:

```swift
                    .gesture(dragGesture(for: item.id))
```

to:

```swift
                    // While a row is editing, dragging inside its text field
                    // must select text, not start a reorder. `.subviews` keeps
                    // the gesture off this view while leaving the text field's
                    // own gestures intact.
                    .gesture(
                        dragGesture(for: item.id),
                        including: editingID == item.id ? .subviews : .all
                    )
```

`gesture(_:including:)` takes a `GestureMask` and is available on macOS 14;
`gesture(_:isEnabled:)` is macOS 15+, so do not use it here.

- [ ] **Step 3: Own `editingID` in `TaskListView`**

In `MenuDo/Views/TaskListView.swift`, add a state property alongside the
existing ones near the top of the struct:

```swift
    @State private var editingID: UUID?
```

Change the pending list call site from:

```swift
                        ReorderableTaskList(store: store)
```

to:

```swift
                        ReorderableTaskList(store: store, editingID: $editingID)
```

Change the done-section row call site from:

```swift
                                        TaskRowView(item: item, store: store)
```

to:

```swift
                                        TaskRowView(item: item, store: store, editingID: $editingID)
```

- [ ] **Step 4: Build and run the test suite**

```bash
xcodebuild test -project MenuDo.xcodeproj -scheme MenuDo -destination 'platform=macOS' -quiet 2>&1 | tail -20
```

Expected: builds clean, all 46 tests still pass.

If the compiler rejects the `including:` mask expression (SwiftUI's gesture
modifiers can be fussy about ternaries in generic position), hoist it into a
computed property on the struct and pass that instead:

```swift
    private func dragMask(for id: UUID) -> GestureMask {
        editingID == id ? .subviews : .all
    }
```

```swift
                    .gesture(dragGesture(for: item.id), including: dragMask(for: item.id))
```

- [ ] **Step 5: Verify by hand in the running app**

```bash
xcodebuild -project MenuDo.xcodeproj -scheme MenuDo -configuration Debug -derivedDataPath build build -quiet 2>&1 | tail -3
open build/Build/Products/Debug/MenuDo.app
```

Click the menu bar item and check each of these:

1. Add two tasks. Double-click the first — it becomes a focused text field with
   the current title selected/editable, and the checkbox and trash disappear.
2. Type a new title, press Return — the row shows the new title.
3. Double-click, change the text, press Esc — the row reverts to the old title
   and the panel stays open.
4. Double-click, select all, delete, press Return — the old title stands.
5. Double-click a row, then click a different row — the first commits and closes.
6. Double-click a row, click-drag across the text — text selects; the row does
   not lift or reorder.
7. Without editing, drag a row up and down — reordering still works.
8. Right-click a row — "Edit" is present above "Delete" and starts an edit.
9. Expand the Done section, double-click a completed task — it edits the same
   way.

Fix anything that fails before moving on.

- [ ] **Step 6: Commit**

```bash
git add MenuDo/Views/TaskRowView.swift MenuDo/Views/ReorderableTaskList.swift MenuDo/Views/TaskListView.swift
git commit -m "feat: edit a task title by double-clicking the row"
```

---

### Task 3: Document the feature

**Files:**
- Modify: `README.md` (the `## Features` list, lines 28-36)

**Interfaces:**
- Consumes: the behaviour shipped in Task 2.
- Produces: nothing other tasks depend on.

- [ ] **Step 1: Add a Features bullet**

In `README.md`, insert this line directly after the **Quick add** bullet and
before the **Reorder by dragging** bullet:

```markdown
- **Edit in place.** Double-click a task to fix its title. Return saves, Escape cancels.
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: mention double-click to edit a task"
```
