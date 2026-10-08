import Foundation

struct ClearOptions: Codable {
    var source: String = inferredSourceName()
    var all: Bool = false
}

func parseClearOptions(_ args: [String]) throws -> ClearOptions {
    var options = ClearOptions()
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

        case "--all":
            options.all = true

        case "--help", "-h":
            printUsage()
            exit(0)

        default:
            throw CLIError.message("Unknown clear option: \(arg)")
        }

        index += 1
    }

    return options
}

func parseOptions(_ args: [String]) throws -> Options {

    var options = Options()
    var opacityWasSet = false
    var passThroughWasSet = false
    var ttlWasSet = false
    var levelWasSet = false
    var messageParts: [String] = []
    var index = 0

    while index < args.count {
        let arg = args[index]

        if arg == "--" {
            messageParts.append(contentsOf: args.dropFirst(index + 1))
            break
        }

        switch arg {
        case "--source":
            index += 1
            guard index < args.count, !args[index].hasPrefix("--") else {
                throw CLIError.message("--source expects a source name.")
            }
            options.source = args[index]
            options.sourceWasProvidedByCaller = true

        case "--url", "--link":
            index += 1
            guard index < args.count, let linkURL = parseDisplayLinkURL(args[index]) else {
                throw CLIError.message("\(arg) expects an http or https URL.")
            }
            options.linkURL = linkURL

        case "--ttl":
            index += 1
            guard index < args.count, let ttl = TimeInterval(args[index]), ttl > 0 else {
                throw CLIError.message("--ttl expects a positive number of seconds.")
            }
            options.ttl = ttl
            ttlWasSet = true

        case "--level":
            index += 1
            guard index < args.count, let level = NoticeLevel(rawValue: args[index]) else {
                throw CLIError.message("--level expects one of: info, warn, busy, done.")
            }
            options.level = level
            levelWasSet = true

        case "--position":
            index += 1
            guard index < args.count, let position = NoticePosition(rawValue: args[index]) else {
                throw CLIError.message("--position expects one of: top, center, bottom.")
            }
            options.position = position

        case "--style":
            index += 1
            guard index < args.count, let style = parseOverlayStyle(args[index]) else {
                throw CLIError.message("--style expects one of: soft, glass, lyric.")
            }
            options.style = style
            if !opacityWasSet {
                options.opacity = style.defaultOpacity
            }
            if !passThroughWasSet {
                options.passThrough = style.defaultPassThrough
            }

        case "--font", "--font-family":
            index += 1
            guard index < args.count, !args[index].hasPrefix("--") else {
                throw CLIError.message("\(arg) expects a font family name.")
            }
            options.fontFamily = args[index]

        case "--font-size", "--message-size":
            index += 1
            guard index < args.count, let size = Double(args[index]), size > 0 else {
                throw CLIError.message("\(arg) expects a positive point size.")
            }
            options.messageSize = CGFloat(size)

        case "--title-size":
            index += 1
            guard index < args.count, let size = Double(args[index]), size > 0 else {
                throw CLIError.message("--title-size expects a positive point size.")
            }
            options.titleSize = CGFloat(size)

        case "--opacity", "--background-opacity":
            index += 1
            guard index < args.count, let opacity = parseOpacity(args[index]) else {
                throw CLIError.message("\(arg) expects 0...1 or a percentage like 65%.")
            }
            options.opacity = opacity
            opacityWasSet = true

        case "--window-opacity":
            index += 1
            guard index < args.count, let opacity = parseOpacity(args[index]) else {
                throw CLIError.message("--window-opacity expects 0...1 or a percentage like 65%.")
            }
            options.windowOpacity = opacity

        case "--blocks-clicks":
            options.passThrough = false
            passThroughWasSet = true

        case "--click-through":
            options.passThrough = true
            passThroughWasSet = true

        case "--help", "-h":
            printUsage()
            exit(0)

        default:
            if arg.hasPrefix("--") {
                throw CLIError.message("Unknown show option: \(arg)")
            }
            messageParts.append(arg)
        }

        index += 1
    }

    if !messageParts.isEmpty {
        options.message = messageParts.joined(separator: " ")
    } else {
        options.titleOverride = "欢迎使用OSD Notify"
        if !ttlWasSet { options.ttl = 60 }
        if !levelWasSet { options.level = .info }
    }

    return options
}

func parseOverlayStyle(_ rawValue: String) -> OverlayStyle? {
    switch rawValue.lowercased() {
    case "lyric", "lyrics":
        return .lyric
    default:
        return OverlayStyle(rawValue: rawValue)
    }
}

func parseOpacity(_ rawValue: String) -> CGFloat? {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    let valueText: String
    let divisor: Double

    if trimmed.hasSuffix("%") {
        valueText = String(trimmed.dropLast())
        divisor = 100.0
    } else {
        valueText = trimmed
        divisor = 1.0
    }

    guard let value = Double(valueText) else {
        return nil
    }

    let opacity = value / divisor
    guard opacity >= 0.0, opacity <= 1.0 else {
        return nil
    }

    return CGFloat(opacity)
}

func parseDisplayLinkURL(_ rawValue: String) -> String? {
    let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
          let url = URL(string: trimmed),
          let scheme = url.scheme?.lowercased(),
          ["http", "https"].contains(scheme) else {
        return nil
    }
    return trimmed
}
