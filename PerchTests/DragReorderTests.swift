import XCTest
@testable import Perch

final class DragReorderTests: XCTestCase {
    /// Five uniform rows, the common case.
    private let uniform: [CGFloat] = Array(repeating: 28, count: 5)

    // MARK: - targetIndex, uniform rows

    func testNoDragKeepsIndex() {
        XCTAssertEqual(
            DragReorder.targetIndex(sourceIndex: 2, translation: 0, rowHeights: uniform),
            2
        )
    }

    func testDraggingDownOneFullRowMovesOneSlot() {
        XCTAssertEqual(
            DragReorder.targetIndex(sourceIndex: 1, translation: 28, rowHeights: uniform),
            2
        )
    }

    func testDraggingUpTwoFullRowsMovesTwoSlots() {
        XCTAssertEqual(
            DragReorder.targetIndex(sourceIndex: 3, translation: -56, rowHeights: uniform),
            1
        )
    }

    func testShortDragRoundsToNearestSlot() {
        // Less than half a row: stays put, so jitter doesn't reorder the list.
        XCTAssertEqual(
            DragReorder.targetIndex(sourceIndex: 2, translation: 10, rowHeights: uniform),
            2
        )
        // Past the halfway mark of the neighbour: advances.
        XCTAssertEqual(
            DragReorder.targetIndex(sourceIndex: 2, translation: 18, rowHeights: uniform),
            3
        )
    }

    func testDragBeyondEndsClampsToBounds() {
        XCTAssertEqual(
            DragReorder.targetIndex(sourceIndex: 4, translation: 999, rowHeights: uniform),
            4
        )
        XCTAssertEqual(
            DragReorder.targetIndex(sourceIndex: 0, translation: -999, rowHeights: uniform),
            0
        )
    }

    func testDragAcrossWholeListReachesFarEnd() {
        XCTAssertEqual(
            DragReorder.targetIndex(sourceIndex: 0, translation: 112, rowHeights: uniform),
            4
        )
        XCTAssertEqual(
            DragReorder.targetIndex(sourceIndex: 4, translation: -112, rowHeights: uniform),
            0
        )
    }

    func testDegenerateInputsDoNotCrash() {
        XCTAssertEqual(
            DragReorder.targetIndex(sourceIndex: 0, translation: 30, rowHeights: []),
            0
        )
        XCTAssertEqual(
            DragReorder.targetIndex(sourceIndex: 9, translation: 30, rowHeights: uniform),
            4
        )
        XCTAssertEqual(
            DragReorder.targetIndex(sourceIndex: 1, translation: .nan, rowHeights: uniform),
            1
        )
        XCTAssertEqual(
            DragReorder.targetIndex(sourceIndex: 1, translation: 30, rowHeights: [0, 0, 0]),
            2,
            "zero-height rows must still terminate rather than spin"
        )
    }

    // MARK: - targetIndex, variable row heights

    /// A two-line task is taller, so it takes a longer drag to cross it.
    func testCrossingATallRowNeedsALongerDrag() {
        let heights: [CGFloat] = [28, 56, 28]
        // Half of the tall neighbour is 28pt; 20pt isn't enough.
        XCTAssertEqual(
            DragReorder.targetIndex(sourceIndex: 0, translation: 20, rowHeights: heights),
            0
        )
        XCTAssertEqual(
            DragReorder.targetIndex(sourceIndex: 0, translation: 30, rowHeights: heights),
            1
        )
    }

    func testCrossingAShortRowNeedsAShorterDrag() {
        let heights: [CGFloat] = [56, 20, 56]
        // Half of the short neighbour is only 10pt.
        XCTAssertEqual(
            DragReorder.targetIndex(sourceIndex: 0, translation: 12, rowHeights: heights),
            1
        )
    }

    func testVariableHeightsAccumulateAcrossMultipleRows() {
        let heights: [CGFloat] = [28, 28, 56, 28]
        // Cross row 1 (needs 14) then row 2 (needs 28 + 28 = 56).
        XCTAssertEqual(
            DragReorder.targetIndex(sourceIndex: 0, translation: 40, rowHeights: heights),
            1
        )
        XCTAssertEqual(
            DragReorder.targetIndex(sourceIndex: 0, translation: 60, rowHeights: heights),
            2
        )
    }

    // MARK: - moveOffsets

    func testUnchangedPositionProducesNoMove() {
        XCTAssertNil(DragReorder.moveOffsets(from: 2, to: 2))
    }

    func testMovingDownAccountsForTheRowItself() throws {
        let (source, destination) = try XCTUnwrap(DragReorder.moveOffsets(from: 0, to: 2))
        XCTAssertEqual(Array(source), [0])
        XCTAssertEqual(destination, 3)
    }

    func testMovingUpUsesTargetDirectly() throws {
        let (source, destination) = try XCTUnwrap(DragReorder.moveOffsets(from: 3, to: 1))
        XCTAssertEqual(Array(source), [3])
        XCTAssertEqual(destination, 1)
    }

    /// The offsets must agree with Swift's own `move(fromOffsets:toOffset:)`,
    /// which is what `TaskStore.movePending` ultimately calls.
    func testOffsetsMatchSwiftMoveSemantics() throws {
        for source in 0..<5 {
            for target in 0..<5 where source != target {
                var items = ["A", "B", "C", "D", "E"]
                let moved = items[source]
                let (indexSet, destination) = try XCTUnwrap(
                    DragReorder.moveOffsets(from: source, to: target)
                )
                items.move(fromOffsets: indexSet, toOffset: destination)
                XCTAssertEqual(
                    items.firstIndex(of: moved), target,
                    "moving \(source)->\(target) should land at \(target), got \(items)"
                )
            }
        }
    }

    // MARK: - displacement

    func testRowsBetweenSourceAndTargetShiftUpWhenDraggingDown() {
        // Dragging 0 down to 2: rows 1 and 2 slide up, row 3 unaffected.
        let shift = { index in
            DragReorder.displacement(
                forIndex: index, sourceIndex: 0, targetIndex: 2, draggedRowHeight: 28
            )
        }
        XCTAssertEqual(shift(1), -28)
        XCTAssertEqual(shift(2), -28)
        XCTAssertEqual(shift(3), 0)
    }

    func testRowsBetweenSourceAndTargetShiftDownWhenDraggingUp() {
        // Dragging 3 up to 1: rows 1 and 2 slide down, row 0 unaffected.
        let shift = { index in
            DragReorder.displacement(
                forIndex: index, sourceIndex: 3, targetIndex: 1, draggedRowHeight: 28
            )
        }
        XCTAssertEqual(shift(0), 0)
        XCTAssertEqual(shift(1), 28)
        XCTAssertEqual(shift(2), 28)
    }

    func testNoDisplacementWhenTargetEqualsSource() {
        for index in 0..<4 {
            XCTAssertEqual(
                DragReorder.displacement(
                    forIndex: index, sourceIndex: 2, targetIndex: 2, draggedRowHeight: 28
                ),
                0
            )
        }
    }

    func testDisplacementUsesDraggedRowsOwnHeight() {
        XCTAssertEqual(
            DragReorder.displacement(
                forIndex: 1, sourceIndex: 0, targetIndex: 1, draggedRowHeight: 56
            ),
            -56
        )
    }
}
