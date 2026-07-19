import SwiftUI

struct TaskRowView: View {
    let item: TodoItem
    let store: TaskStore
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
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
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Delete", role: .destructive) { store.delete(item.id) }
        }
        .accessibilityAction(named: "Delete") { store.delete(item.id) }
    }
}
