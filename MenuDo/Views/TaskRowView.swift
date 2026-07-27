import SwiftUI

/// Backs the "commit on teardown" decision with a plain reference type
/// instead of a `@State` `Bool`. A `Bool` read inside `onDisappear`'s
/// closure would depend on whether SwiftUI's `@State` read-through sees a
/// write made during the SAME update cycle that unmounts the view — that's
/// exactly what `commit()`/`cancel()` do (they flip the flag right before
/// clearing `editingID`, which unmounts the field) — and that timing is an
/// implementation detail, not a documented guarantee. A class instance has
/// no such ambiguity: any closure holding a reference to it reads its
/// CURRENT stored property, full stop, because Swift references are never
/// value-copied or snapshotted. Held via `@State` only so one instance
/// persists across this row's re-renders; the class itself is deliberately
/// non-reactive — mutating its property never triggers a view update.
private final class TeardownIntent {
    /// Defaults to "commit" — the project owner's ruling that any teardown
    /// nobody explicitly ended (delete, panel dismissal, another row
    /// stealing `editingID`) must save the draft, not discard it.
    /// `commit()`/`cancel()` flip this to `false` before they touch
    /// `editingID`, marking "I already handled my own ending" so
    /// `onDisappear` doesn't redo it (or, for `cancel()`, wrongly do it at
    /// all). Also reset to `true` at the start of every edit session — in
    /// `beginEditing()` and in the field's own `onAppear` — so a stuck
    /// `false` from a session whose `onDisappear` never ran can't leak into
    /// the next one.
    var shouldCommitOnTeardown = true
}

struct TaskRowView: View {
    let item: TodoItem
    let store: TaskStore
    @Binding var editingID: UUID?

    @State private var hovering = false
    @State private var draftTitle = ""
    @FocusState private var fieldFocused: Bool
    @State private var teardown = TeardownIntent()

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
                    // Clicking another row's control, or the add field,
                    // steals AppKit's first responder and ends the edit the
                    // same way Return does.
                    .onChange(of: fieldFocused) { _, focused in
                        if !focused, isEditing { commit() }
                    }
                    // The field can mount two ways: `beginEditing()` just set
                    // `draftTitle`/`editingID` together (normal path — this
                    // is a same-value no-op), or this row was reconstructed
                    // while `editingID` already named it — e.g. the item
                    // moved between the pending list and the Done section,
                    // or the panel reopened mid-edit — in which case this
                    // fresh instance's `draftTitle` was never seeded.
                    // Seeding here from `item.title` makes both paths
                    // converge. The `fieldFocused = true` here is a
                    // best-effort fallback for that reconstructed case only
                    // — setting `@FocusState` from `onAppear` at first mount
                    // is known-unreliable on macOS, so it is NOT the primary
                    // focus mechanism; see `onChange(of: isEditing)` below,
                    // which is.
                    .onAppear {
                        draftTitle = item.title
                        teardown.shouldCommitOnTeardown = true
                        fieldFocused = true
                    }
                    // The field can unmount three ways: `commit()` ran
                    // (Return, or focus lost to another control) or
                    // `cancel()` ran (Esc) — both already set
                    // `teardown.shouldCommitOnTeardown = false` before
                    // clearing `editingID`, so the guard below skips them.
                    // Anything else reaching this closure is a teardown this
                    // row never asked for: it got deleted, the panel closed
                    // mid-edit, or another row's double-click stole
                    // `editingID` first. None of those call
                    // `commit`/`cancel`, so per the ruling that teardown
                    // must save (not discard), commit the draft here.
                    // `rename` no-ops harmlessly if the item was already
                    // deleted. Only clear `editingID` if it still names this
                    // row — if another row already took over, leave its
                    // edit alone.
                    //
                    // Note: this mutates `store` and the `editingID` binding
                    // from `onDisappear`, which can in principle run while
                    // the view graph is still settling the update that
                    // caused the teardown (e.g. another row's
                    // `beginEditing()` changing `editingID`, or a delete).
                    // That risks a "Modifying state during view update"
                    // runtime warning in some cases. Deferring the mutation
                    // with `DispatchQueue.main.async` would dodge the
                    // warning but would also let the panel or this row
                    // finish deallocating before the deferred block runs,
                    // which could silently drop the very commit this code
                    // exists to guarantee — a worse outcome than a
                    // debug-only console warning. The mutation is kept
                    // synchronous on purpose; see the fix report for the
                    // full tradeoff.
                    .onDisappear {
                        defer { teardown.shouldCommitOnTeardown = true }
                        guard teardown.shouldCommitOnTeardown else { return }
                        store.rename(item.id, to: draftTitle)
                        if editingID == item.id { editingID = nil }
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
        // Primary, non-racy focus path for the normal begin-editing
        // transition: this only fires once `isEditing` actually changes,
        // which happens after the field has been installed into the view
        // tree — unlike `onAppear`, which can run before the field is ready
        // to accept focus. It does NOT fire on first mount when the row
        // appears already editing (no transition to observe); that case is
        // covered by the field's own `onAppear` above instead. Both hooks
        // assigning `fieldFocused = true` is harmless — the assignment is
        // idempotent.
        .onChange(of: isEditing) { _, editing in
            if editing { fieldFocused = true }
        }
    }

    private func beginEditing() {
        guard !isEditing else { return }
        draftTitle = item.title
        teardown.shouldCommitOnTeardown = true
        editingID = item.id
    }

    private func commit() {
        teardown.shouldCommitOnTeardown = false
        store.rename(item.id, to: draftTitle)
        editingID = nil
    }

    private func cancel() {
        teardown.shouldCommitOnTeardown = false
        editingID = nil
    }
}
