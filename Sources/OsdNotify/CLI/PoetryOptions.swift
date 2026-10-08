import Foundation

enum PoetryMode: Equatable {
    case random
}

struct PoetryOptions {
    var mode: PoetryMode = .random
    var lang: String = "zh-Hans"
    var source: String?
    var interval: TimeInterval = 15.0
    var speed: Double = 1.0
    var limit: Int?
    var clearWhenFinished: Bool = true
    var dryRun: Bool = false
    var displayOptions: Options = lyricPlaybackOptions()
}

func parsePoetryOptions(_ args: [String]) throws -> PoetryOptions {
    var options = PoetryOptions()
    var opacityWasSet = false
    var passThroughWasSet = false
    var modeWasSet = false
    var index = 0

    while index < args.count {
        let arg = args[index]

        switch arg {
        case "random":
            guard !modeWasSet else {
                throw CLIError.message("poetry only supports one mode.")
            }
            options.mode = .random
            modeWasSet = true

        case "--lang":
            index += 1
            guard index < args.count, !args[index].hasPrefix("--") else {
                throw CLIError.message("--lang expects a language code such as zh-Hans.")
            }
            options.lang = args[index]

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

        case "--interval", "--line-interval":
            index += 1
            guard index < args.count,
                  let interval = TimeInterval(args[index]),
                  interval > 0 else {
                throw CLIError.message("\(arg) expects a positive number of seconds.")
            }
            options.interval = interval

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

        case "--dry-run", "--preview":
            options.dryRun = true

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
                throw CLIError.message("Unknown poetry option: \(arg)")
            }
            throw CLIError.message("Unknown poetry mode: \(arg). Only random is supported.")
        }

        index += 1
    }

    if !opacityWasSet {
        options.displayOptions.opacity = OverlayStyle.lyric.defaultOpacity
    }
    if !passThroughWasSet {
        options.displayOptions.passThrough = OverlayStyle.lyric.defaultPassThrough
    }

    return options
}
