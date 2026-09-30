@testable import DownloadPlugin
import XCTest

final class YTDLPTests: XCTestCase {
    private let request = DownloadRequest(
        url: URL(string: "https://youtu.be/abc")!,
        format: .video,
        maxHeight: nil,
        destination: URL(fileURLWithPath: "/Users/me/Downloads")
    )
    private let ffmpeg = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
    private let temporary = URL(fileURLWithPath: "/tmp/job")

    func testLocateFindsBothToolsInTheFirstDirectoryThatHasEach() {
        let present = ["/usr/local/bin/yt-dlp", "/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]
        let tools = YTDLP.locate(isExecutable: present.contains)
        XCTAssertEqual(tools?.ytdlp.path, "/usr/local/bin/yt-dlp")
        XCTAssertEqual(tools?.ffmpeg.path, "/opt/homebrew/bin/ffmpeg")
    }

    func testLocateNeedsFfmpegToo() {
        XCTAssertNil(YTDLP.locate(isExecutable: { $0 == "/opt/homebrew/bin/yt-dlp" }))
    }

    func testVideoAtBestQuality() {
        let arguments = YTDLP.downloadArguments(for: request, ffmpeg: ffmpeg, temporary: temporary)
        XCTAssertEqual(value(after: "-f", in: arguments), "bv*+ba/b")
        XCTAssertEqual(value(after: "--merge-output-format", in: arguments), "mp4")
        XCTAssertEqual(arguments.last, "https://youtu.be/abc")
        XCTAssertTrue(arguments.contains("--ignore-config"))
        XCTAssertTrue(arguments.contains("/Users/me/Downloads"))
        XCTAssertTrue(arguments.contains("temp:/tmp/job"))
        XCTAssertEqual(value(after: "--ffmpeg-location", in: arguments), "/opt/homebrew/bin/ffmpeg")
    }

    func testVideoCappedAtAHeight() {
        var capped = request
        capped.maxHeight = 720
        let arguments = YTDLP.downloadArguments(for: capped, ffmpeg: ffmpeg, temporary: temporary)
        XCTAssertEqual(value(after: "-f", in: arguments), "bv*[height<=720]+ba/b[height<=720]/b")
    }

    func testAudioExtractsMP3AndIgnoresHeight() {
        var audio = request
        audio.format = .audio
        audio.maxHeight = 720
        let arguments = YTDLP.downloadArguments(for: audio, ffmpeg: ffmpeg, temporary: temporary)
        XCTAssertTrue(arguments.contains("-x"))
        XCTAssertEqual(value(after: "--audio-format", in: arguments), "mp3")
        XCTAssertFalse(arguments.contains("-f"))
    }

    func testProgressUsesTotalThenEstimate() {
        XCTAssertEqual(YTDLP.parse(line: "PERCH-PROGRESS 50 200 NA"), .progress(0.25))
        XCTAssertEqual(YTDLP.parse(line: "PERCH-PROGRESS 50 NA 100.0\n"), .progress(0.5))
        XCTAssertEqual(YTDLP.parse(line: "PERCH-PROGRESS 50 NA NA"), .progress(nil))
        XCTAssertEqual(YTDLP.parse(line: "PERCH-PROGRESS 300 200 NA"), .progress(1))
        XCTAssertEqual(YTDLP.parse(line: "/Users/me/Downloads/a.mp4"), .other("/Users/me/Downloads/a.mp4"))
    }

    func testFilePathIsTheLastNonProgressLine() {
        let stdout = "PERCH-PROGRESS 1 2 NA\n/Users/me/Downloads/Me at the zoo.mp4\nPERCH-PROGRESS 2 2 NA\n"
        XCTAssertEqual(YTDLP.filePath(fromStdout: stdout), "/Users/me/Downloads/Me at the zoo.mp4")
        XCTAssertNil(YTDLP.filePath(fromStdout: "PERCH-PROGRESS 1 2 NA\n"))
    }

    func testErrorMessageDropsPrefixAndExtractorTag() {
        let stderr = "WARNING: something\nERROR: [youtube] abc123: Video unavailable\n"
        XCTAssertEqual(YTDLP.errorMessage(fromStderr: stderr), "Video unavailable")
        XCTAssertEqual(
            YTDLP.errorMessage(fromStderr: "ERROR: Unsupported URL: https://x.test/"),
            "Unsupported URL: https://x.test/"
        )
        XCTAssertEqual(YTDLP.errorMessage(fromStderr: ""), "yt-dlp stopped without saying why.")
    }

    private func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }
}
