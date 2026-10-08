import AppKit

enum NoticeLevel: String, Codable {
    case info
    case warn
    case busy
    case done

    var title: String {
        switch self {
        case .info:
            return "Automation notice"
        case .warn:
            return "Attention needed"
        case .busy:
            return "Automation in progress"
        case .done:
            return "Automation finished"
        }
    }

    var accent: NSColor {
        switch self {
        case .info:
            return NSColor(calibratedRed: 0.39, green: 0.58, blue: 0.76, alpha: 1.0)
        case .warn:
            return NSColor(calibratedRed: 0.72, green: 0.58, blue: 0.30, alpha: 1.0)
        case .busy:
            return NSColor(calibratedRed: 0.35, green: 0.55, blue: 0.68, alpha: 1.0)
        case .done:
            return NSColor(calibratedRed: 0.42, green: 0.64, blue: 0.50, alpha: 1.0)
        }
    }

    func background(opacity: CGFloat) -> NSColor {
        switch self {
        case .info:
            return NSColor(calibratedRed: 0.86, green: 0.94, blue: 0.99, alpha: opacity)
        case .warn:
            return NSColor(calibratedRed: 1.00, green: 0.96, blue: 0.84, alpha: opacity)
        case .busy:
            return NSColor(calibratedRed: 0.86, green: 0.96, blue: 0.93, alpha: opacity)
        case .done:
            return NSColor(calibratedRed: 0.88, green: 0.96, blue: 0.89, alpha: opacity)
        }
    }
}

enum NoticePosition: String, Codable {
    case top
    case center
    case bottom
}

enum OverlayStyle: String, Codable {
    case soft
    case glass
    case lyric

    var defaultOpacity: CGFloat {
        switch self {
        case .soft:
            return 0.18
        case .glass:
            return 0.42
        case .lyric:
            return 0.60
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .soft:
            return 16.0
        case .glass:
            return 20.0
        case .lyric:
            return 12.0
        }
    }

    var defaultPassThrough: Bool {
        switch self {
        case .soft:
            return true
        case .glass, .lyric:
            return false
        }
    }
}

struct Options: Codable {
    var message: String = """
    显示提示：osd-notify show "提示内容"
    定时关闭（10 秒后）：osd-notify show "提示内容" --ttl 10
    查看完整帮助：osd-notify --help
    主动关闭：双击标题栏会显示关闭图标,点击即可关闭
    """
    var source: String = inferredSourceName()
    var sourceWasProvidedByCaller: Bool = sourceWasConfiguredByEnvironment()
    var parentApplicationName: String? = parentApplicationDisplayName()
    var titleOverride: String?
    var ttl: TimeInterval = 3600.0
    var level: NoticeLevel = .busy
    var position: NoticePosition = .bottom
    var style: OverlayStyle = .glass
    var passThrough: Bool = OverlayStyle.glass.defaultPassThrough
    var fontFamily: String? = "PingFang SC"
    var titleSize: CGFloat = 16.0
    var messageSize: CGFloat = 36.0
    var linkURL: String?
    var opacity: CGFloat = OverlayStyle.glass.defaultOpacity
    var windowOpacity: CGFloat = 1.0
    var stackGroup: String?
    var stackIndex: Int?
}

func lyricPlaybackOptions() -> Options {
    var options = Options()
    options.style = .lyric
    options.opacity = OverlayStyle.lyric.defaultOpacity
    options.passThrough = OverlayStyle.lyric.defaultPassThrough
    return options
}
