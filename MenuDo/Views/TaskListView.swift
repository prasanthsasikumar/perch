import SwiftUI

struct TaskListView: View {
    @Bindable var store: TaskStore
    @State private var newTitle = ""
    @State private var showDone = false
    @State private var editingID: UUID?
    @FocusState private var addFieldFocused: Bool
    @Environment(\.openSettings) private var openSettings

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

            Divider()

            HStack {
                if !store.done.isEmpty {
                    Button("Clear completed") { store.clearCompleted() }
                }
                Spacer()
                Button {
                    // A menu bar only (LSUIElement) app is not active when its
                    // dropdown is clicked, so Settings would open behind the
                    // frontmost app unless we activate first.
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
                .accessibilityLabel("Settings")
                Button {
                    store.saveNow()
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .help("Quit MenuDo")
                .accessibilityLabel("Quit MenuDo")
            }
            .buttonStyle(.borderless)
            .padding(12)
        }
        .frame(width: 320)
        .onAppear { addFieldFocused = true }
    }
}
