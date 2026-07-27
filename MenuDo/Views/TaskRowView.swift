import SwiftUI

struct TaskRowView: View {
    let item: TodoItem
    let store: TaskStore
    @Binding var editingID: UUID?

    @State private var hovering = false
    @State private var draftTitle = ""
    @FocusState private var fieldFocused: Bool

    // Set synchronously inside `commit()`/`cancel()`, before either touches
    // `editingID`. Read (and cleared) by `onDisappear` below to tell an
    // explicit end of the edit apart from the field being torn down out from
    // under it — see the state-machine note on `onDisappear`.
    @State private var didEndExplicitly = false

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
                    // fresh instance's `draftTitle` was never seeded and it
                    // isn't focused. Seeding here from `item.title` and
                    // grabbing focus makes both paths converge.
                    .onAppear {
                        draftTitle = item.title
                        fieldFocused = true
                    }
                    // The field can unmount three ways: `commit()` ran
                    // (Return, or focus lost to another control) or
                    // `cancel()` ran (Esc) — both already did their job and
                    // set `didEndExplicitly` before clearing `editingID`, so
                    // the guard below skips them. Anything else reaching
                    // this closure is a teardown this row never asked for:
                    // the row got deleted, the panel closed mid-edit, or
                    // another row's double-click stole `editingID` first.
                    // None of those call `commit`/`cancel`, so per the
                    // ruling that teardown must save (not discard), commit
                    // the draft here. `rename` no-ops harmlessly if the item
                    // was already deleted. Only clear `editingID` if it
                    // still names this row — if another row already took
                    // over, leave its edit alone.
                    .onDisappear {
                        defer { didEndExplicitly = false }
                        guard !didEndExplicitly else { return }
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
    }

    private func beginEditing() {
        guard !isEditing else { return }
        draftTitle = item.title
        editingID = item.id
    }

    private func commit() {
        didEndExplicitly = true
        store.rename(item.id, to: draftTitle)
        editingID = nil
    }

    private func cancel() {
        didEndExplicitly = true
        editingID = nil
    }
}
