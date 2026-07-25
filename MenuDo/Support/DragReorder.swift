import CoreGraphics
import Foundation

/// Index math for gesture-driven list reordering.
///
/// SwiftUI's `List` + `.onMove` cannot be used inside a `.window`-style
/// `MenuBarExtra`: the row lifts, but AppKit never delivers the drop to the
/// panel, so `.onMove` is never called. Reordering is therefore driven by a
/// plain `DragGesture`, which needs this arithmetic to turn a vertical
/// translation into a destination index.
///
/// Rows are not assumed to be the same height — titles wrap to two lines — so
/// every calculation works off measured per-row heights.
enum DragReorder {
    /// The index a row dragged `translation` points vertically would land on.
    ///
    /// A row is only displaced once the drag passes the halfway mark of the
    /// neighbour it is crossing, which keeps small jitters from reordering the
    /// list. The result is clamped to the bounds of the list.
    static func targetIndex(
        sourceIndex: Int,
        translation: CGFloat,
        rowHeights: [CGFloat]
    ) -> Int {
        let count = rowHeights.count
        guard count > 0 else { return 0 }
        guard sourceIndex >= 0, sourceIndex < count, translation.isFinite else {
            return min(max(sourceIndex, 0), max(count - 1, 0))
        }

        var index = sourceIndex
        var crossed: CGFloat = 0

        if translation > 0 {
            var neighbour = sourceIndex + 1
            while neighbour < count, translation >= crossed + rowHeights[neighbour] / 2 {
                index = neighbour
                crossed += rowHeights[neighbour]
                neighbour += 1
            }
        } else if translation < 0 {
            var neighbour = sourceIndex - 1
            while neighbour >= 0, translation <= -(crossed + rowHeights[neighbour] / 2) {
                index = neighbour
                crossed += rowHeights[neighbour]
                neighbour -= 1
            }
        }

        return index
    }

    /// Translates a source/target index pair into `move(fromOffsets:toOffset:)`
    /// arguments, or `nil` when the row hasn't changed position.
    ///
    /// `toOffset` is interpreted against the array *before* removal, so moving
    /// downward needs one extra slot to account for the row itself.
    static func moveOffsets(from sourceIndex: Int, to targetIndex: Int) -> (IndexSet, Int)? {
        guard sourceIndex != targetIndex else { return nil }
        let destination = targetIndex > sourceIndex ? targetIndex + 1 : targetIndex
        return (IndexSet(integer: sourceIndex), destination)
    }

    /// Vertical offset to apply to a row that is *not* being dragged, so the
    /// list visibly opens a gap where the dragged row will land. Rows between
    /// the source and the target slide by the dragged row's own height.
    static func displacement(
        forIndex index: Int,
        sourceIndex: Int,
        targetIndex: Int,
        draggedRowHeight: CGFloat
    ) -> CGFloat {
        if targetIndex > sourceIndex, index > sourceIndex, index <= targetIndex {
            return -draggedRowHeight
        }
        if targetIndex < sourceIndex, index >= targetIndex, index < sourceIndex {
            return draggedRowHeight
        }
        return 0
    }
}
