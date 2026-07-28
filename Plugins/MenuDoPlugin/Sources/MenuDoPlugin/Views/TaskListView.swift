import SwiftUI

public struct TaskListView: View {
    @Bindable var store: TaskStore
    @State private var newTitle = ""
    @State private var showDone = false
    @State private var editingID: UUID?
    @FocusState private var addFieldFocused: Bool

    public init(store: TaskStore) {
        self.store = store
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let notice = store.loadFailureNotice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            }

            TextField("Add a task…", text: $newTitle)
                .textFieldStyle(.roundedBorder)
                .focused($addFieldFocused)
                .onSubmit {
                    store.add(newTitle)
                    newTitle = ""
                }
                .padding(12)

            Divider()

            if store.pending.isEmpty && store.done.isEmpty {
                Text("No tasks — enjoy your day ✨")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ReorderableTaskList(store: store, editingID: $editingID)

                        if !store.done.isEmpty {
                            DisclosureGroup("Done (\(store.done.count))", isExpanded: $showDone) {
                                VStack(spacing: 0) {
                                    ForEach(store.done) { item in
                                        TaskRowView(item: item, store: store, editingID: $editingID)
                                            .padding(.vertical, 6)
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                        }
                    }
                }
                .frame(minHeight: 120, maxHeight: 360)
            }
        }
        .onAppear { addFieldFocused = true }
    }
}
