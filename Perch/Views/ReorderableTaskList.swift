import MenuDoPlugin
import SwiftUI

/// Collects the measured height of every row, keyed by task id.
private struct RowHeightsKey: PreferenceKey {
    static let defaultValue: [UUID: CGFloat] = [:]

    static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
        value.merge(nextValue()) { _, latest in latest }
    }
}

/// The pending tasks, reorderable by dragging a row.
///
/// This deliberately avoids `List` + `.onMove`. Inside a `.window`-style
/// `MenuBarExtra` the row lifts but AppKit never delivers the drop, so
/// `.onMove` is never called (see `DragReorder`). A plain `DragGesture` isn't
/// routed through AppKit's dragging machinery, so it works in the panel.
struct ReorderableTaskList: View {
    let store: TaskStore
    @Binding var editingID: UUID?

    @State private var draggingID: UUID?
    @State private var dragTranslation: CGFloat = 0
    @State private var measuredHeights: [UUID: CGFloat] = [:]

    /// Used only until a row has reported its real height.
    private static let estimatedRowHeight: CGFloat = 28

    private var items: [TodoItem] { store.pending }

    private var rowHeights: [CGFloat] {
        items.map { measuredHeights[$0.id] ?? Self.estimatedRowHeight }
    }

    private var sourceIndex: Int? {
        draggingID.flatMap { id in items.firstIndex { $0.id == id } }
    }

    private var targetIndex: Int? {
        sourceIndex.map {
            DragReorder.targetIndex(
                sourceIndex: $0, translation: dragTranslation, rowHeights: rowHeights
            )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                TaskRowView(item: item, store: store, editingID: $editingID)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: RowHeightsKey.self,
                                value: [item.id: proxy.size.height]
                            )
                        }
                    }
                    .background(rowBackground(for: item.id))
                    .offset(y: verticalOffset(index: index, id: item.id))
                    .zIndex(item.id == draggingID ? 1 : 0)
                    // While a row is editing, dragging inside its text field
                    // must select text, not start a reorder. `.subviews` keeps
                    // the gesture off this view while leaving the text field's
                    // own gestures intact.
                    .gesture(
                        dragGesture(for: item.id),
                        including: editingID == item.id ? .subviews : .all
                    )
            }
        }
        .onPreferenceChange(RowHeightsKey.self) { heights in
            measuredHeights = heights
        }
        // Scoped to targetIndex so the gap animates while the dragged row
        // itself keeps tracking the cursor without lag.
        .animation(.snappy(duration: 0.18), value: targetIndex)
    }

    @ViewBuilder
    private func rowBackground(for id: UUID) -> some View {
        if id == draggingID {
            RoundedRectangle(cornerRadius: 6)
                .fill(.selection.opacity(0.35))
        }
    }

    private func verticalOffset(index: Int, id: UUID) -> CGFloat {
        guard let sourceIndex, let targetIndex else { return 0 }
        if id == draggingID { return dragTranslation }
        let heights = rowHeights
        guard heights.indices.contains(sourceIndex) else { return 0 }
        return DragReorder.displacement(
            forIndex: index,
            sourceIndex: sourceIndex,
            targetIndex: targetIndex,
            draggedRowHeight: heights[sourceIndex]
        )
    }

    private func dragGesture(for id: UUID) -> some Gesture {
        // A minimum distance keeps taps on the checkbox and trash buttons from
        // being swallowed by the drag.
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if draggingID == nil { draggingID = id }
                dragTranslation = value.translation.height
            }
            .onEnded { _ in
                defer {
                    draggingID = nil
                    dragTranslation = 0
                }
                guard
                    let sourceIndex, let targetIndex,
                    let (offsets, destination) = DragReorder.moveOffsets(
                        from: sourceIndex, to: targetIndex
                    )
                else { return }
                store.movePending(fromOffsets: offsets, toOffset: destination)
            }
    }
}
