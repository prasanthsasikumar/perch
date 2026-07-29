import AppKit
import Foundation
import Observation
import PerchKit

@MainActor
@Observable
public final class TaskStore {
    public private(set) var items: [TodoItem] = []
    public private(set) var loadFailureNotice: String?

    private let storage: PluginStorage
    private let filename: String
    @ObservationIgnored private var pendingSave: Task<Void, Never>?

    public init(storage: PluginStorage, filename: String = "tasks.json") {
        self.storage = storage
        self.filename = filename
        load()
        // Belt and braces. The host now calls `MenuDo.flush()` on both quit
        // paths, so this is redundant inside Perch — but it costs nothing and
        // a debounced write is the one thing worth losing sleep over.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveNow() }
        }
    }

    // MARK: - Derived state

    public var pending: [TodoItem] {
        items.filter { !$0.isDone }.sorted { $0.sortOrder < $1.sortOrder }
    }

    public var done: [TodoItem] {
        items.filter(\.isDone).sorted { $0.sortOrder < $1.sortOrder }
    }

    public var currentTask: TodoItem? { pending.first }

    // MARK: - Mutations

    public func add(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let nextOrder = (items.map(\.sortOrder).max() ?? -1) + 1
        items.append(TodoItem(title: trimmed, sortOrder: nextOrder))
        scheduleSave()
    }

    public func toggle(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isDone.toggle()
        scheduleSave()
    }

    public func delete(_ id: UUID) {
        items.removeAll { $0.id == id }
        scheduleSave()
    }

    public func rename(_ id: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].title = trimmed
        scheduleSave()
    }

    public func movePending(fromOffsets source: IndexSet, toOffset destination: Int) {
        var reordered = pending
        reordered.move(fromOffsets: source, toOffset: destination)
        var order = 0
        var renumbered: [TodoItem] = []
        for var item in reordered {
            item.sortOrder = order
            order += 1
            renumbered.append(item)
        }
        for var item in done {
            item.sortOrder = order
            order += 1
            renumbered.append(item)
        }
        items = renumbered
        scheduleSave()
    }

    public func clearCompleted() {
        items.removeAll { $0.isDone }
        scheduleSave()
    }

    // MARK: - Persistence

    public func saveNow() {
        pendingSave?.cancel()
        // In-memory state stays authoritative; the next mutation retries via scheduleSave().
        try? storage.save(items, named: filename)
    }

    /// Throws away in-memory state and re-reads the file.
    ///
    /// Only for when something outside this store has replaced the file — the
    /// legacy MenuDo import does exactly that, copying tasks in underneath a
    /// store that already loaded an empty list. Without this, the very next
    /// save writes that empty list back over the import.
    ///
    /// Any debounced save is cancelled first: the state it was going to write
    /// is precisely the state being discarded.
    public func reload() {
        pendingSave?.cancel()
        load()
    }

    private func load() {
        do {
            items = try storage.load([TodoItem].self, named: filename) ?? []
            loadFailureNotice = nil
        } catch {
            items = []
            loadFailureNotice = "Couldn't read saved tasks — backup kept"
        }
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }
}
