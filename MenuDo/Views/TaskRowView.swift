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
