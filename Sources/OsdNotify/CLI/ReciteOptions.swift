import Foundation

enum ReciteInput {
    case text(String)
    case file(String)
    case standardInput
}

struct ReciteOptions {
    var inputs: [ReciteInput] = []
    var source: String?
    var interval: TimeInterval = 6.0
    var speed: Double = 1.0
    var limit: Int?
    var clearWhenFinished: Bool = true
    var delimiters: String = "，,。！？；;.!?"
    var minCharacters: Int = 7
    var preferredMaxCharacters: Int = 20
    var dryRun: Bool = false
    var displayOptions: Options = lyricPlaybackOptions()
}

func parseReciteOptions(_ args: [String]) throws -> ReciteOptions {
    var options = ReciteOptions()
    var opacityWasSet = false
    var passThroughWasSet = false
    var positionalTextParts: [String] = []
    var index = 0

    func flushPositionalText() {
        guard !positionalTextParts.isEmpty else {
            return
        }
        options.inputs.append(.text(positionalTextParts.joined(separator: " ")))
        positionalTextParts.removeAll()
    }

    while index < args.count {
        let arg = args[index]

        switch arg {
        case "--source", "--title":
            index += 1
            guard index < args.count, !args[index].hasPrefix("--") else {
                throw CLIError.message("\(arg) expects a source name.")
            }
            options.source = args[index]

        case "--url", "--link":
            index += 1
            guard index < args.count, let linkURL = parseDisplayLinkURL(args[index]) else {
                throw CLIError.message("\(arg) expects an http or https URL.")
            }
            options.displayOptions.linkURL = linkURL

        case "--file":
            index += 1
            guard index < args.count, !args[index].hasPrefix("--") else {
                throw CLIError.message("--file expects a text file path.")
            }
            flushPositionalText()
            options.inputs.append(.file(args[index]))

        case "--text":
            index += 1
            guard index < args.count, !args[index].hasPrefix("--") else {
                throw CLIError.message("--text expects text content.")
            }
            flushPositionalText()
            options.inputs.append(.text(args[index]))

        case "--stdin":
            flushPositionalText()
            options.inputs.append(.standardInput)

        case "--interval", "--line-interval":
            index += 1
            guard index < args.count,
                  let interval = TimeInterval(args[index]),
                  interval > 0 else {
                throw CLIError.message("\(arg) expects a positive number of seconds.")
            }
            options.interval = interval

        case "--delimiters":
            index += 1
            guard index < args.count, !args[index].isEmpty else {
                throw CLIError.message("--delimiters expects one or more split characters.")
            }
            options.delimiters = args[index]

        case "--min-chars", "--min-characters":
            index += 1
            guard index < args.count,
                  let minCharacters = Int(args[index]),
                  minCharacters > 0 else {
                throw CLIError.message("\(arg) expects a positive integer.")
            }
            options.minCharacters = minCharacters

        case "--max-chars", "--preferred-max-chars", "--max-characters":
            index += 1
            guard index < args.count,
                  let maxCharacters = Int(args[index]),
                  maxCharacters > 0 else {
                throw CLIError.message("\(arg) expects a positive integer.")
            }
            options.preferredMaxCharacters = maxCharacters

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
                throw CLIError.message("Unknown recite option: \(arg)")
            }
            let expandedPath = (arg as NSString).expandingTildeInPath
            if positionalTextParts.isEmpty, FileManager.default.fileExists(atPath: expandedPath) {
                options.inputs.append(.file(arg))
            } else {
                positionalTextParts.append(arg)
            }
        }

        index += 1
    }

    flushPositionalText()

    guard !options.inputs.isEmpty else {
        throw CLIError.message("recite expects text content, --file path, --stdin, or an existing text file path.")
    }
    if options.preferredMaxCharacters < options.minCharacters {
        throw CLIError.message("--max-chars must be greater than or equal to --min-chars.")
    }

    if !opacityWasSet {
        options.displayOptions.opacity = OverlayStyle.lyric.defaultOpacity
    }
    if !passThroughWasSet {
        options.displayOptions.passThrough = OverlayStyle.lyric.defaultPassThrough
    }

    return options
}
