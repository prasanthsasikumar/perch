@testable import SpinPlugin
import XCTest

final class SceneCatalogTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ id: String, order: Int, background: Bool = true, json: String? = nil) throws {
        let dir = root.appendingPathComponent(id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let body = json ?? """
        {"id":"\(id)","name":"\(id)","order":\(order),
         "platter":{"x":0.5,"y":0.5,"radius":0.1,"squash":0.4},
         "sleeve":{"x":0.2,"y":0.5,"size":0.2,"rotation":0,"style":"flat"}}
        """
        try body.write(to: dir.appendingPathComponent("scene.json"), atomically: true, encoding: .utf8)
        if background { try Data([0]).write(to: dir.appendingPathComponent("background.jpg")) }
    }

    func testLoadsScenesInOrder() throws {
        try write("b", order: 2)
        try write("a", order: 1)
        XCTAssertEqual(SceneCatalog.load(from: root).map(\.id), ["a", "b"])
    }

    func testSkipsSceneWithoutBackground() throws {
        try write("a", order: 1, background: false)
        XCTAssertTrue(SceneCatalog.load(from: root).isEmpty)
    }

    func testSkipsUnreadableJSON() throws {
        try write("a", order: 1, json: "{")
        XCTAssertTrue(SceneCatalog.load(from: root).isEmpty)
    }

    func testTonearmIsOptional() throws {
        try write("a", order: 1)
        XCTAssertNil(SceneCatalog.load(from: root).first?.descriptor.tonearm)
    }
}
