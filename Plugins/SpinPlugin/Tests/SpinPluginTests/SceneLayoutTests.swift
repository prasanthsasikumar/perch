@testable import SpinPlugin
import XCTest

final class SceneLayoutTests: XCTestCase {
    private func descriptor(platterX: Double, platterY: Double) -> SceneDescriptor {
        SceneDescriptor(
            id: "t", name: "T", order: 0,
            platter: .init(x: platterX, y: platterY, radius: 0.1, squash: 0.4),
            tonearm: .init(pivotX: 0.6, pivotY: 0.4, length: 0.1, restAngle: 5, playAngle: 25),
            sleeve: .init(x: 0.2, y: 0.5, size: 0.2, rotation: -3, style: .stand)
        )
    }

    private let image = CGSize(width: 3000, height: 2000)  // 3:2

    func testSixteenByTenCropsTopAndBottom() {
        let frames = SceneLayout.frames(for: descriptor(platterX: 0.5, platterY: 0.5), imageSize: image,
                                        in: CGSize(width: 1440, height: 900))
        // scale = max(1440/3000, 900/2000) = 0.48 → 1440×960, 30 pt cropped top and bottom.
        XCTAssertEqual(frames.imageRect.minX, 0, accuracy: 0.001)
        XCTAssertEqual(frames.imageRect.minY, -30, accuracy: 0.001)
        XCTAssertEqual(frames.imageRect.width, 1440, accuracy: 0.001)
        XCTAssertEqual(frames.imageRect.height, 960, accuracy: 0.001)
        XCTAssertEqual(frames.platterCenter.x, 720, accuracy: 0.001)
        XCTAssertEqual(frames.platterCenter.y, 450, accuracy: 0.001)
        XCTAssertEqual(frames.platterRadius, 144, accuracy: 0.001)
        XCTAssertEqual(frames.squash, 0.4)
    }

    func testSixteenByNine() {
        let frames = SceneLayout.frames(for: descriptor(platterX: 0.5, platterY: 0.25), imageSize: image,
                                        in: CGSize(width: 1920, height: 1080))
        // scale 0.64 → 1920×1280, offset y −100.
        XCTAssertEqual(frames.platterCenter.y, -100 + 0.25 * 1280, accuracy: 0.001)
    }

    func testUltrawideCropsHeavily() {
        let frames = SceneLayout.frames(for: descriptor(platterX: 0.25, platterY: 0.75), imageSize: image,
                                        in: CGSize(width: 3440, height: 1440))
        // scale 3440/3000 → 3440×2293.33, offset y −426.67.
        XCTAssertEqual(frames.platterCenter.x, 860, accuracy: 0.01)
        XCTAssertEqual(frames.platterCenter.y, 1293.33, accuracy: 0.01)
    }

    func testTonearmAndSleeveScale() {
        let frames = SceneLayout.frames(for: descriptor(platterX: 0.5, platterY: 0.5), imageSize: image,
                                        in: CGSize(width: 1440, height: 900))
        XCTAssertEqual(frames.tonearm?.pivot.x ?? 0, 0.6 * 1440, accuracy: 0.001)
        XCTAssertEqual(frames.tonearm?.length ?? 0, 144, accuracy: 0.001)
        XCTAssertEqual(frames.sleeveSize, 288, accuracy: 0.001)
        XCTAssertEqual(frames.sleeveCenter.y, -30 + 0.5 * 960, accuracy: 0.001)
    }
}
