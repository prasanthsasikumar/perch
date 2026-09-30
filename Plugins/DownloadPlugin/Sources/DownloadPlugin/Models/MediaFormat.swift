import Foundation

/// What to save: the video, or just its sound.
public enum MediaFormat: String, CaseIterable, Codable, Sendable {
    case video
    case audio

    public var label: String {
        switch self {
        case .video: "MP4"
        case .audio: "MP3"
        }
    }

    public var fileExtension: String {
        switch self {
        case .video: "mp4"
        case .audio: "mp3"
        }
    }
}
