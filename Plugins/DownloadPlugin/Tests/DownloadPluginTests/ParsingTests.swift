@testable import DownloadPlugin
import XCTest

final class MediaInfoTests: XCTestCase {
    func testKeepsOneHeightPerResolutionTallestFirstAndSkipsAudioOnly() throws {
        // One object per line, as `-j` prints them.
        let json = #"{"title":"Me at the zoo","thumbnail":"https://i.ytimg.com/vi/x/hq.jpg","duration":19,"uploader":"jawed","#
            + #""formats":[{"height":240,"vcodec":"avc1"},{"height":144,"vcodec":"vp9"},{"height":240,"vcodec":"vp9"},"#
            + #"{"vcodec":"none"},{"height":null,"vcodec":"avc1"}]}"#
            + "\n" + #"{"title":"second object, ignored"}"#
        let info = try MediaInfo.parse(Data(json.utf8))
        XCTAssertEqual(info.title, "Me at the zoo")
        XCTAssertEqual(info.thumbnail?.absoluteString, "https://i.ytimg.com/vi/x/hq.jpg")
        XCTAssertEqual(info.duration, 19)
        XCTAssertEqual(info.uploader, "jawed")
        XCTAssertEqual(info.heights, [240, 144])
    }

    func testMissingFieldsFallBack() throws {
        let info = try MediaInfo.parse(Data(#"{"title":""}"#.utf8))
        XCTAssertEqual(info, MediaInfo(title: "Untitled"))
    }

    func testEmptyOutputThrows() {
        XCTAssertThrowsError(try MediaInfo.parse(Data("\n".utf8)))
    }
}

final class PastedLinksTests: XCTestCase {
    func testSplitsOnWhitespaceAndCommasAndDedupes() {
        let urls = PastedLinks.extract("""
        https://youtu.be/a  https://vimeo.com/1,
        https://youtu.be/a
        """)
        XCTAssertEqual(urls.map(\.absoluteString), ["https://youtu.be/a", "https://vimeo.com/1"])
    }

    func testAddsAMissingScheme() {
        XCTAssertEqual(PastedLinks.extract("youtube.com/watch?v=x").map(\.absoluteString),
                       ["https://youtube.com/watch?v=x"])
    }

    func testIgnoresWordsAndOtherSchemes() {
        XCTAssertEqual(PastedLinks.extract("hello there ftp://x.com/a file:///tmp/a"), [])
    }
}
