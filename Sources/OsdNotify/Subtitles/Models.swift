import Foundation

struct TimedTextLine {
    let start: TimeInterval
    let end: TimeInterval?
    let text: String
}

struct SubtitleStream {
    let index: Int
    let codecName: String
    let language: String?
    let title: String?
    let isDefault: Bool
    let isForced: Bool

    var isTextConvertible: Bool {
        textConvertibleSubtitleCodecs.contains(codecName.lowercased())
    }
}

struct SubtitlePlaybackTrack {
    let source: String
    let title: String
    let stackIndex: Int?
    let lines: [TimedTextLine]
}

struct BufferedSubtitlePlaybackTrack {
    let source: String
    let title: String
    let stackIndex: Int?
    let buffer: SubtitleTrackBuffer
}

struct SubtitlePlaybackEvent {
    let trackIndex: Int
    let lineIndex: Int
    let start: TimeInterval
}

struct FFProbeOutput: Decodable {
    let streams: [FFProbeStream]
}

struct FFProbeStream: Decodable {
    let index: Int
    let codecName: String?
    let tags: [String: String]?
    let disposition: [String: Int]?

    enum CodingKeys: String, CodingKey {
        case index
        case codecName = "codec_name"
        case tags
        case disposition
    }
}
