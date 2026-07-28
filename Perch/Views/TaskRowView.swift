import MenuDoPlugin
import SwiftUI

/// Backs the "commit on teardown" decision with a plain reference type
/// instead of a `@State` `Bool`, so a closure captured by `onDisappear`
/// always reads the CURRENT flag value instead of depending on `@State`'s
/// undocumented same-cycle read-through timing. Held via `@State` only so
/// one instance persists across re-renders; the class itself is
/// non-reactive — mutating its property never triggers a view update.
///
/// Rule: never reassign `teardown` after `@State` installs it — a fresh
/// `TeardownIntent()` would split future writes and reads across two
/// objects and reintroduce the bug this class exists to prevent.
private final class TeardownIntent {
    /// Defaults to "commit": any teardown nobody explicitly ended (delete,
    /// panel dismissal, another row stealing `editingID`) must save the
    /// draft, not discard it. `commit()`/`cancel()` flip this to `false`
    /// first so `onDisappear` doesn't redo (or wrongly do) their work.
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
                    // Seeds draftTitle/flag for both mount paths: the normal
                    // begin-editing transition (same-value no-op) and a row
                    // reconstructed while editingID already named it (e.g.
                    // moved to Done, panel reopened mid-edit), where
                    // draftTitle was never set. fieldFocused here is a
                    // fallback only — onAppear focus is unreliable on
                    // macOS; onChange(of: isEditing) below is primary.
                    .onAppear {
                        draftTitle = item.title
                        teardown.shouldCommitOnTeardown = true
                        fieldFocused = true
                    }
                    // commit()/cancel() (Return/Esc/focus loss) already set
                    // the flag false before clearing editingID, so the guard
                    // skips them here. Any other teardown — delete, panel
                    // close, another row stealing editingID — never called
                    // them, so per the "teardown commits" rule the draft is
                    // saved here. `rename` no-ops if the item was already
                    // deleted; editingID is only cleared if it still names
                    // this row, so a takeover isn't clobbered.
                    //
                    // Kept synchronous on purpose: this can run while the
                    // view graph is still settling the update that caused
                    // it, risking a "Modifying state during view update"
                    // warning. Deferring with `DispatchQueue.main.async`
                    // would dodge that warning but could let the row
                    // deallocate first and silently drop the commit — worse
                    // than a debug-only warning.
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
        // Primary focus path for the normal begin-editing transition —
        // fires once `isEditing` flips, after the field is installed
        // (`onAppear` can fire too early). Doesn't fire on first mount when
        // already editing; `onAppear` above covers that case instead.
        // Both assigning `fieldFocused = true` is harmless (idempotent).
        .onChange(of: isEditing) { _, editing in
            if editing { fieldFocused = true }
        }
    }

    private func beginEditing() {
        guard !isEditing else { return }
        // draftTitle/shouldCommitOnTeardown aren't set here: the guard above
        // guarantees the field is about to newly mount, and its own
        // `onAppear` (above) always seeds both before anything reads them.
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
