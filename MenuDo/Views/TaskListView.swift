import SwiftUI

struct TaskListView: View {
    @Bindable var store: TaskStore
    @State private var newTitle = ""
    @State private var showDone = false
    @FocusState private var addFieldFocused: Bool

    var body: some View {
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
                List {
                    ForEach(store.pending) { item in
                        TaskRowView(item: item, store: store)
                    }
                    .onMove { source, destination in
                        store.movePending(fromOffsets: source, toOffset: destination)
                    }

                    if !store.done.isEmpty {
                        DisclosureGroup("Done (\(store.done.count))", isExpanded: $showDone) {
                            ForEach(store.done) { item in
                                TaskRowView(item: item, store: store)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .frame(minHeight: 120, maxHeight: 360)
            }

            Divider()

            HStack {
                if !store.done.isEmpty {
                    Button("Clear completed") { store.clearCompleted() }
                }
                Spacer()
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .help("Quit MenuDo")
            }
            .buttonStyle(.borderless)
            .padding(12)
        }
        .frame(width: 320)
        .onAppear { addFieldFocused = true }
    }
}
