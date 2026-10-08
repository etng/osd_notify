import Foundation

struct PlayOptions {
    var filePaths: [String] = []
    var source: String?
    var speed: Double = 1.0
    var limit: Int?
    var clearWhenFinished: Bool = true
    var streamIndices: [Int] = []
    var listSubtitlesOnly: Bool = false
    var useCache: Bool = true
    var refreshCache: Bool = false
    var warmCacheOnly: Bool = false
    var displayOptions: Options = lyricPlaybackOptions()
}

func parsePlayOptions(_ args: [String]) throws -> PlayOptions {
    var options = PlayOptions()
    var opacityWasSet = false
    var passThroughWasSet = false
    var index = 0

    while index < args.count {
        let arg = args[index]

        switch arg {
        case "--source":
            index += 1
            guard index < args.count, !args[index].hasPrefix("--") else {
                throw CLIError.message("--source expects a source name.")
            }
            options.source = args[index]

        case "--url", "--link":
            index += 1
            guard index < args.count, let linkURL = parseDisplayLinkURL(args[index]) else {
                throw CLIError.message("\(arg) expects an http or https URL.")
            }
            options.displayOptions.linkURL = linkURL

        case "--speed":
            index += 1
            guard index < args.count,
                  let speed = Double(args[index]),
                  speed > 0 else {
                throw CLIError.message("--speed expects a positive playback rate.")
            }
            options.speed = speed

        case "--limit":
            index += 1
            guard index < args.count,
                  let limit = Int(args[index]),
                  limit > 0 else {
                throw CLIError.message("--limit expects a positive integer.")
            }
            options.limit = limit

        case "--stream", "--subtitle-stream":
            index += 1
            guard index < args.count,
                  let streamIndex = Int(args[index]),
                  streamIndex >= 0 else {
                throw CLIError.message("\(arg) expects a non-negative ffprobe stream index.")
            }
            options.streamIndices.append(streamIndex)

        case "--list-subtitles":
            options.listSubtitlesOnly = true

        case "--no-cache":
            options.useCache = false

        case "--refresh-cache":
            options.refreshCache = true

        case "--warm-cache":
            options.warmCacheOnly = true

        case "--no-clear":
            options.clearWhenFinished = false

        case "--position":
            index += 1
            guard index < args.count, let position = NoticePosition(rawValue: args[index]) else {
                throw CLIError.message("--position expects one of: top, center, bottom.")
            }
            options.displayOptions.position = position

        case "--font", "--font-family":
            index += 1
            guard index < args.count, !args[index].hasPrefix("--") else {
                throw CLIError.message("\(arg) expects a font family name.")
            }
            options.displayOptions.fontFamily = args[index]

        case "--font-size", "--message-size":
            index += 1
            guard index < args.count, let size = Double(args[index]), size > 0 else {
                throw CLIError.message("\(arg) expects a positive point size.")
            }
            options.displayOptions.messageSize = CGFloat(size)

        case "--title-size":
            index += 1
            guard index < args.count, let size = Double(args[index]), size > 0 else {
                throw CLIError.message("--title-size expects a positive point size.")
            }
            options.displayOptions.titleSize = CGFloat(size)

        case "--opacity", "--background-opacity":
            index += 1
            guard index < args.count, let opacity = parseOpacity(args[index]) else {
                throw CLIError.message("\(arg) expects 0...1 or a percentage like 65%.")
            }
            options.displayOptions.opacity = opacity
            opacityWasSet = true

        case "--window-opacity":
            index += 1
            guard index < args.count, let opacity = parseOpacity(args[index]) else {
                throw CLIError.message("--window-opacity expects 0...1 or a percentage like 65%.")
            }
            options.displayOptions.windowOpacity = opacity

        case "--blocks-clicks":
            options.displayOptions.passThrough = false
            passThroughWasSet = true

        case "--click-through":
            options.displayOptions.passThrough = true
            passThroughWasSet = true

        case "--help", "-h":
            printUsage()
            exit(0)

        default:
            if arg.hasPrefix("--") {
                throw CLIError.message("Unknown play option: \(arg)")
            }
            options.filePaths.append(arg)
        }

        index += 1
    }

    guard !options.filePaths.isEmpty else {
        throw CLIError.message("play expects at least one .lrc, .srt, or video file path.")
    }
    if !options.useCache && options.refreshCache {
        throw CLIError.message("--no-cache and --refresh-cache cannot be used together.")
    }
    if !options.useCache && options.warmCacheOnly {
        throw CLIError.message("--warm-cache requires cache to be enabled.")
    }
    if options.warmCacheOnly && options.limit != nil {
        throw CLIError.message("--warm-cache cannot be combined with --limit because a limited extraction would create an incomplete cache.")
    }

    if !opacityWasSet {
        options.displayOptions.opacity = OverlayStyle.lyric.defaultOpacity
    }
    if !passThroughWasSet {
        options.displayOptions.passThrough = OverlayStyle.lyric.defaultPassThrough
    }

    return options
}
