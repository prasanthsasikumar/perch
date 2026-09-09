@testable import ServerPlugin
import XCTest

final class TrendGeometryTests: XCTestCase {
    func testEmptyInputDrawsNothing() {
        XCTAssertTrue(TrendGeometry.normalise([]).isEmpty)
    }

    func testASinglePointSitsAtTheStart() {
        let points = TrendGeometry.normalise([50])
        XCTAssertEqual(points.count, 1)
        XCTAssertEqual(points[0].x, 0)
        XCTAssertEqual(points[0].y, 0.5, accuracy: 0.0001)
    }

    func testPointsSpanTheFullWidth() {
        let points = TrendGeometry.normalise([0, 50, 100])
        XCTAssertEqual(points.map(\.x), [0, 0.5, 1])
    }

    /// y is flipped for drawing: a busy sample belongs at the top.
    func testHighValuesAreDrawnHigh() {
        let points = TrendGeometry.normalise([100, 0])
        XCTAssertEqual(points[0].y, 0, accuracy: 0.0001)
        XCTAssertEqual(points[1].y, 1, accuracy: 0.0001)
    }

    func testValuesAreClampedToTheCeiling() {
        let points = TrendGeometry.normalise([-20, 180])
        XCTAssertEqual(points[0].y, 1, accuracy: 0.0001)
        XCTAssertEqual(points[1].y, 0, accuracy: 0.0001)
    }

    func testNonFiniteValuesDoNotProduceNaNCoordinates() {
        for point in TrendGeometry.normalise([.nan, .infinity, 50]) {
            XCTAssertFalse(point.x.isNaN); XCTAssertFalse(point.y.isNaN)
        }
    }

    /// The regression this type exists for: a full ring buffer used to collapse
    /// each bar below a pixel and the sparkline disappeared. A line keeps every
    /// sample addressable no matter how many there are.
    func testAFullRingBufferStillProducesAPointPerSample() {
        let values = (0..<ServerStore.trendCapacity).map { Double($0 % 100) }
        let points = TrendGeometry.normalise(values)
        XCTAssertEqual(points.count, ServerStore.trendCapacity)
        XCTAssertEqual(points.first?.x, 0)
        XCTAssertEqual(points.last?.x, 1)
    }
}
