import AppKit
import Darwin
import QuartzCore

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
    var message: String = "请暂停手动操作，Codex 正在控制 Chrome"
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
    var opacity: CGFloat = OverlayStyle.glass.defaultOpacity
    var windowOpacity: CGFloat = 1.0
    var stackGroup: String?
    var stackIndex: Int?
}

struct ClearOptions: Codable {
    var source: String = inferredSourceName()
    var all: Bool = false
}

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

let guwendaoBaseURL = URL(string: "https://www.guwendao.net")!
let guwendaoGaowenEntryURL = URL(string: "https://www.guwendao.net/wenyan/gaowen.aspx")!

struct GuwendaoPoemLink {
    let id: String
    let entryTitle: String
    let url: URL
}

struct GuwendaoPoemItem: Codable {
    let id: String
    let title: String
    let entryTitle: String
    let author: String
    let dynasty: String
    let url: String
    let content: String
}

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

struct ProcessResult {
    let status: Int32
    let stdout: String
    let stderr: String
}

enum SubtitleBufferStatus {
    case line(TimedTextLine)
    case pending
    case completed
}

final class SubtitleTrackBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [TimedTextLine] = []
    private var isCompleted = false
    private var failure: Error?

    init(lines: [TimedTextLine] = [], completed: Bool = false) {
        self.lines = lines
        self.isCompleted = completed
    }

    func append(_ line: TimedTextLine) {
        lock.lock()
        lines.append(line)
        lock.unlock()
    }

    func finish() {
        lock.lock()
        isCompleted = true
        lock.unlock()
    }

    func fail(_ error: Error) {
        lock.lock()
        failure = error
        isCompleted = true
        lock.unlock()
    }

    func status(at index: Int) throws -> SubtitleBufferStatus {
        lock.lock()
        defer {
            lock.unlock()
        }

        if let failure {
            throw failure
        }
        if index < lines.count {
            return .line(lines[index])
        }
        return isCompleted ? .completed : .pending
    }
}

final class StreamingSubtitleExtraction: @unchecked Sendable {
    private let process: Process
    private let done = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var didFinish = false

    init(process: Process) {
        self.process = process
    }

    func markFinished() {
        lock.lock()
        didFinish = true
        lock.unlock()
        done.signal()
    }

    func terminate() {
        lock.lock()
        let shouldTerminate = !didFinish && process.isRunning
        lock.unlock()
        if shouldTerminate {
            process.terminate()
        }
    }

    func wait() {
        done.wait()
    }
}

final class IncrementalSRTParser {
    private var data = Data()

    func append(_ newData: Data) -> [TimedTextLine] {
        data.append(newData)
        return drainCompleteBlocks()
    }

    func finish() -> [TimedTextLine] {
        var lines = drainCompleteBlocks()
        let remaining = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !remaining.isEmpty, let line = parseSRTBlock(remaining) {
            lines.append(line)
        }
        data.removeAll(keepingCapacity: false)
        return lines
    }

    private func drainCompleteBlocks() -> [TimedTextLine] {
        var lines: [TimedTextLine] = []
        while let separator = firstSRTBlockSeparator(in: data) {
            let blockData = data[..<separator.lowerBound]
            data.removeSubrange(data.startIndex..<separator.upperBound)
            let block = String(decoding: blockData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !block.isEmpty, let line = parseSRTBlock(block) {
                lines.append(line)
            }
        }
        return lines
    }
}

enum Command {
    case show(Options)
    case clear(ClearOptions)
    case play(PlayOptions)
    case recite(ReciteOptions)
    case daemon
}

struct DaemonRequest: Codable {
    enum Kind: String, Codable {
        case show
        case clear
    }

    let kind: Kind
    let showOptions: Options?
    let clearOptions: ClearOptions?

    static func show(_ options: Options) -> DaemonRequest {
        DaemonRequest(kind: .show, showOptions: options, clearOptions: nil)
    }

    static func clear(_ options: ClearOptions) -> DaemonRequest {
        DaemonRequest(kind: .clear, showOptions: nil, clearOptions: options)
    }
}

struct DaemonResponse: Codable {
    let ok: Bool
    let message: String
}

struct OverlayRecord: Codable {
    let source: String
    let pid: Int32
    let position: String
    let height: Double
    let createdAt: TimeInterval
    let stackGroup: String?
    let stackIndex: Int?
}

struct OverlayPlacement: Codable {
    var screens: [String: OverlayScreenPlacement] = [:]
    var updatedAt: TimeInterval = 0.0
}

struct OverlayScreenPlacement: Codable {
    let xRatio: Double
    let yRatio: Double
}

enum CLIError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case .message(let text):
            return text
        }
    }
}

@MainActor
final class DaemonAppDelegate: NSObject, NSApplicationDelegate {
    private let manager = OverlayManager()
    private lazy var server = DaemonServer(manager: manager)

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try server.start()
        } catch {
            fputs("osd-notify daemon: \(error)\n", stderr)
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        server.stop()
        manager.clearManagedOverlays()
        try? FileManager.default.removeItem(at: daemonPIDFileURL)
    }
}

@MainActor
final class OverlayManager {
    private var overlays: [String: OverlayInstance] = [:]

    func handle(_ request: DaemonRequest) -> DaemonResponse {
        switch request.kind {
        case .show:
            guard let options = request.showOptions else {
                return DaemonResponse(ok: false, message: "Invalid show request.")
            }
            show(options)
            return DaemonResponse(ok: true, message: "Shown OSD source '\(options.source)'.")

        case .clear:
            guard let options = request.clearOptions else {
                return DaemonResponse(ok: false, message: "Invalid clear request.")
            }
            let cleared = options.all ? clearAll(quiet: true) : clear(source: options.source, quiet: true)
            if cleared {
                return DaemonResponse(ok: true, message: options.all ? "Cleared all OSD sources." : "Cleared OSD source '\(options.source)'.")
            }
            return DaemonResponse(ok: true, message: options.all ? "No active OSD processes found." : "No active OSD process found for source '\(options.source)'.")
        }
    }

    func show(_ options: Options) {
        if let existingOverlay = overlays.removeValue(forKey: options.source) {
            existingOverlay.dismiss(animated: true, notify: false)
        } else {
            clearExistingOverlay(source: options.source, quiet: true)
        }

        let inProcessRecords = overlays.values.compactMap(\.record)
        let stackOffset = activeStackOffset(
            for: options,
            excluding: options.source,
            additionalRecords: inProcessRecords
        )
        let overlay = OverlayInstance(options: options) { [weak self] source in
            self?.overlays.removeValue(forKey: source)
        }
        overlays[options.source] = overlay
        overlay.show(stackOffset: stackOffset)
    }

    @discardableResult
    func clear(source: String, quiet: Bool) -> Bool {
        if let overlay = overlays.removeValue(forKey: source) {
            overlay.dismiss(animated: true, notify: false)
            return true
        }

        return clearExistingOverlay(source: source, quiet: quiet)
    }

    @discardableResult
    func clearAll(quiet: Bool) -> Bool {
        var clearedAny = false

        for overlay in overlays.values {
            overlay.dismiss(animated: false, notify: false)
            clearedAny = true
        }
        overlays.removeAll()

        if closeAllProcessOverlayPanels() {
            clearedAny = true
        }

        if removeAllOverlayRecords() {
            clearedAny = true
        }

        if clearAllOverlays(quiet: quiet) {
            clearedAny = true
        }

        return clearedAny
    }

    func clearManagedOverlays() {
        for overlay in overlays.values {
            overlay.dismiss(animated: false, notify: false)
        }
        overlays.removeAll()
    }
}

@MainActor
final class OverlayDismissal: @unchecked Sendable {
    private let panels: [NSPanel]
    private let source: String
    private let notify: Bool
    private let onDismiss: (String) -> Void

    init(panels: [NSPanel], source: String, notify: Bool, onDismiss: @escaping (String) -> Void) {
        self.panels = panels
        self.source = source
        self.notify = notify
        self.onDismiss = onDismiss
    }

    func finish() {
        for panel in panels {
            panel.orderOut(nil)
            panel.close()
        }
        if notify {
            onDismiss(source)
        }
    }
}

@MainActor
final class OverlayInstance: NSObject, NSWindowDelegate {
    private let options: Options
    private var panels: [NSPanel] = []
    private var panelScreenKeys: [ObjectIdentifier: String] = [:]
    private var dismissTimer: Timer?
    private var moveTrackingTimer: Timer?
    private let onDismiss: (String) -> Void
    private var isDismissing = false
    private var moveTrackingEnabled = false
    private var placement: OverlayPlacement
    private(set) var record: OverlayRecord?

    init(options: Options, onDismiss: @escaping (String) -> Void) {
        self.options = options
        self.onDismiss = onDismiss
        self.placement = readOverlayPlacement(source: options.source) ?? OverlayPlacement()
        super.init()
    }

    func show(stackOffset: CGFloat) {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            return
        }
        moveTrackingEnabled = false
        moveTrackingTimer?.invalidate()

        panels = screens.map { makePanel(for: $0, stackOffset: stackOffset) }
        let maxPanelHeight = panels.map(\.frame.height).max() ?? 108.0
        let overlayRecord = OverlayRecord(
            source: options.source,
            pid: getpid(),
            position: options.position.rawValue,
            height: Double(maxPanelHeight),
            createdAt: Date().timeIntervalSince1970,
            stackGroup: options.stackGroup,
            stackIndex: options.stackIndex
        )
        record = overlayRecord
        writeOverlayRecord(overlayRecord)

        for panel in panels {
            panel.alphaValue = 0.0
            panel.orderFrontRegardless()
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = overlayFadeInDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            for panel in panels {
                panel.animator().alphaValue = options.windowOpacity
            }
        }

        moveTrackingTimer = Timer.scheduledTimer(withTimeInterval: overlayFadeInDuration + 0.10, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.moveTrackingEnabled = true
            }
        }

        dismissTimer = Timer.scheduledTimer(withTimeInterval: options.ttl, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.dismiss(animated: true, notify: true)
            }
        }
    }

    private func makePanel(for screen: NSScreen, stackOffset: CGFloat) -> NSPanel {
        let visibleFrame = screen.visibleFrame
        let maxWidth = max(420.0, min(visibleFrame.width * 0.80, visibleFrame.width - 64.0))
        let title = displayTitle(for: options)
        let contentSize = OverlayView.size(
            title: title,
            message: options.message,
            constrainedTo: maxWidth,
            options: options
        )

        let defaultOriginX = visibleFrame.midX - contentSize.width / 2.0
        let defaultOriginY: CGFloat

        switch options.position {
        case .top:
            defaultOriginY = max(
                visibleFrame.minY + 32.0,
                visibleFrame.maxY - contentSize.height - 32.0 - stackOffset
            )
        case .center:
            defaultOriginY = clamp(
                visibleFrame.midY - contentSize.height / 2.0 + stackOffset,
                min: visibleFrame.minY + 32.0,
                max: visibleFrame.maxY - contentSize.height - 32.0
            )
        case .bottom:
            defaultOriginY = min(
                visibleFrame.maxY - contentSize.height - 32.0,
                visibleFrame.minY + 32.0 + stackOffset
            )
        }

        let restoredOrigin = restoredOrigin(
            for: screen,
            contentSize: contentSize,
            fallback: NSPoint(x: defaultOriginX, y: defaultOriginY)
        )
        let frame = NSRect(
            x: restoredOrigin.x.rounded(),
            y: restoredOrigin.y.rounded(),
            width: contentSize.width.rounded(.up),
            height: contentSize.height.rounded(.up)
        )

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .ignoresCycle,
            .stationary
        ]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = options.passThrough
        panel.isMovableByWindowBackground = !options.passThrough
        panel.hidesOnDeactivate = false
        panel.delegate = self
        panel.identifier = NSUserInterfaceItemIdentifier("osd-notify.\(stableSourceHash(options.source))")
        panel.contentView = OverlayView(
            frame: NSRect(origin: .zero, size: frame.size),
            title: title,
            message: options.message,
            level: options.level,
            options: options
        )
        panelScreenKeys[ObjectIdentifier(panel)] = screenKey(for: screen)

        return panel
    }

    private func restoredOrigin(for screen: NSScreen, contentSize: NSSize, fallback: NSPoint) -> NSPoint {
        let key = screenKey(for: screen)
        let screenPlacement = placement.screens[key] ?? (placement.screens.count == 1 ? placement.screens.values.first : nil)
        guard let screenPlacement else {
            return fallback
        }

        let visibleFrame = screen.visibleFrame
        let xRange = max(visibleFrame.width - contentSize.width, 0.0)
        let yRange = max(visibleFrame.height - contentSize.height, 0.0)
        let xRatio = clamp(CGFloat(screenPlacement.xRatio), min: 0.0, max: 1.0)
        let yRatio = clamp(CGFloat(screenPlacement.yRatio), min: 0.0, max: 1.0)

        return NSPoint(
            x: visibleFrame.minX + xRange * xRatio,
            y: visibleFrame.minY + yRange * yRatio
        )
    }

    func windowDidMove(_ notification: Notification) {
        guard moveTrackingEnabled,
              !isDismissing,
              let panel = notification.object as? NSPanel,
              panels.contains(where: { $0 === panel }),
              let screen = panel.screen else {
            return
        }

        let key = screenKey(for: screen)
        panelScreenKeys[ObjectIdentifier(panel)] = key
        let visibleFrame = screen.visibleFrame
        let frame = panel.frame
        let xRange = max(visibleFrame.width - frame.width, 1.0)
        let yRange = max(visibleFrame.height - frame.height, 1.0)
        let xRatio = clamp((frame.minX - visibleFrame.minX) / xRange, min: 0.0, max: 1.0)
        let yRatio = clamp((frame.minY - visibleFrame.minY) / yRange, min: 0.0, max: 1.0)

        placement.screens[key] = OverlayScreenPlacement(
            xRatio: Double(xRatio),
            yRatio: Double(yRatio)
        )
        placement.updatedAt = Date().timeIntervalSince1970
        writeOverlayPlacement(placement, source: options.source)
    }

    func dismiss(animated: Bool, notify: Bool) {
        guard !isDismissing else {
            return
        }
        isDismissing = true
        dismissTimer?.invalidate()
        dismissTimer = nil
        moveTrackingTimer?.invalidate()
        moveTrackingTimer = nil
        moveTrackingEnabled = false
        removeRecordIfOwnedByCurrentProcess(source: options.source)

        guard !panels.isEmpty else {
            if notify {
                onDismiss(options.source)
            }
            return
        }

        let panelsToClose = panels
        panels = []
        panelScreenKeys.removeAll()
        record = nil

        let dismissal = OverlayDismissal(
            panels: panelsToClose,
            source: options.source,
            notify: notify,
            onDismiss: onDismiss
        )

        guard animated else {
            dismissal.finish()
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = overlayFadeOutDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            for panel in panelsToClose {
                panel.animator().alphaValue = 0.0
            }
        } completionHandler: {
            Task { @MainActor in
                dismissal.finish()
            }
        }
    }
}

final class OverlayView: NSView {
    private let contentView: OverlayContentView
    private var effectView: NSVisualEffectView?

    init(frame: NSRect, title: String, message: String, level: NoticeLevel, options: Options) {
        contentView = OverlayContentView(
            frame: frame,
            title: title,
            message: message,
            level: level,
            options: options
        )
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.isOpaque = false

        if options.style == .glass {
            let effectView = NSVisualEffectView(frame: .zero)
            effectView.material = .hudWindow
            effectView.blendingMode = .behindWindow
            effectView.state = .active
            effectView.wantsLayer = true
            effectView.layer?.cornerRadius = options.style.cornerRadius
            effectView.layer?.masksToBounds = true
            addSubview(effectView)
            self.effectView = effectView
        }

        addSubview(contentView)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isOpaque: Bool {
        false
    }

    override func layout() {
        super.layout()
        effectView?.frame = bounds.insetBy(dx: 2.0, dy: 2.0)
        contentView.frame = bounds
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    static func size(title: String, message: String, constrainedTo maxWidth: CGFloat, options: Options) -> NSSize {
        OverlayContentView.size(title: title, message: message, constrainedTo: maxWidth, options: options)
    }
}

final class OverlayContentView: NSView {
    private static let horizontalPadding: CGFloat = 30.0
    private static let verticalPadding: CGFloat = 22.0
    private static let accentWidth: CGFloat = 8.0
    private static let titleMessageGap: CGFloat = 8.0

    private let title: String
    private let message: String
    private let level: NoticeLevel
    private let options: Options

    init(frame: NSRect, title: String, message: String, level: NoticeLevel, options: Options) {
        self.title = title
        self.message = message
        self.level = level
        self.options = options
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.isOpaque = false
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isOpaque: Bool {
        false
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let rect = bounds.insetBy(dx: 2.0, dy: 2.0)
        let backgroundPath = NSBezierPath(
            roundedRect: rect,
            xRadius: options.style.cornerRadius,
            yRadius: options.style.cornerRadius
        )
        backgroundColor().setFill()
        backgroundPath.fill()

        if options.style == .glass || options.style == .lyric {
            NSColor(calibratedWhite: 1.0, alpha: 0.18).setStroke()
            backgroundPath.lineWidth = 1.0
            backgroundPath.stroke()
        }

        let accentRect = NSRect(
            x: rect.minX,
            y: rect.minY,
            width: Self.accentWidth,
            height: rect.height
        )
        let clipPath = NSBezierPath(
            roundedRect: rect,
            xRadius: options.style.cornerRadius,
            yRadius: options.style.cornerRadius
        )
        NSGraphicsContext.saveGraphicsState()
        clipPath.addClip()
        accentColor().setFill()
        accentRect.fill()
        NSGraphicsContext.restoreGraphicsState()

        let textX = rect.minX + Self.horizontalPadding + Self.accentWidth
        let textWidth = rect.width - Self.horizontalPadding * 2.0 - Self.accentWidth
        let titleAttributes = Self.titleAttributes(accent: level.accent, options: options)
        let messageAttributes = Self.messageAttributes(options: options)
        let titleSize = (title as NSString).boundingRect(
            with: NSSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: titleAttributes
        ).size
        let messageSize = (message as NSString).boundingRect(
            with: NSSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: messageAttributes
        ).size
        let totalTextHeight = ceil(titleSize.height) + Self.titleMessageGap + ceil(messageSize.height)
        var y = rect.midY + totalTextHeight / 2.0 - ceil(titleSize.height)

        (title as NSString).draw(
            with: NSRect(x: textX, y: y, width: textWidth, height: ceil(titleSize.height) + 2.0),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: titleAttributes
        )

        y -= Self.titleMessageGap + ceil(messageSize.height)
        (message as NSString).draw(
            with: NSRect(x: textX, y: y, width: textWidth, height: ceil(messageSize.height) + 4.0),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: messageAttributes
        )
    }

    static func size(title: String, message: String, constrainedTo maxWidth: CGFloat, options: Options) -> NSSize {
        let minWidth = min(maxWidth, 560.0)
        let naturalTextWidth = max(
            naturalWidth(title, attributes: titleAttributes(accent: .black, options: options)),
            naturalWidth(message, attributes: messageAttributes(options: options))
        )
        let desiredWidth = naturalTextWidth + horizontalPadding * 2.0 + accentWidth + 24.0
        let measuredWidth = min(maxWidth, max(minWidth, ceil(desiredWidth)))
        let textWidth = measuredWidth - horizontalPadding * 2.0 - accentWidth
        let titleHeight = ceil((title as NSString).boundingRect(
            with: NSSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: titleAttributes(accent: .black, options: options)
        ).height)
        let messageHeight = ceil((message as NSString).boundingRect(
            with: NSSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: messageAttributes(options: options)
        ).height)
        let height = verticalPadding * 2.0 + titleHeight + titleMessageGap + messageHeight

        return NSSize(width: measuredWidth, height: max(108.0, height))
    }

    private static func naturalWidth(_ text: String, attributes: [NSAttributedString.Key: Any]) -> CGFloat {
        ceil((text as NSString).boundingRect(
            with: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        ).width)
    }

    private static func titleAttributes(accent: NSColor, options: Options) -> [NSAttributedString.Key: Any] {
        let titleColor: NSColor
        switch options.style {
        case .soft:
            titleColor = NSColor(calibratedRed: 0.78, green: 0.92, blue: 0.98, alpha: 1.0)
        case .glass:
            titleColor = accent.blended(withFraction: 0.36, of: .white) ?? accent
        case .lyric:
            titleColor = accent.blended(withFraction: 0.70, of: .white) ?? .white
        }

        var attributes: [NSAttributedString.Key: Any] = [
            .font: font(named: options.fontFamily, size: options.titleSize, weight: .semibold),
            .foregroundColor: titleColor,
            .shadow: textShadow(blur: options.style == .lyric ? 4.0 : 3.0, offsetY: -1.0, alpha: 0.82)
        ]
        if options.style == .lyric {
            attributes[.strokeColor] = NSColor(calibratedWhite: 0.0, alpha: 0.70)
            attributes[.strokeWidth] = -1.8
        }
        return attributes
    }

    private static func messageAttributes(options: Options) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font(named: options.fontFamily, size: options.messageSize, weight: .bold),
            .foregroundColor: options.style == .lyric
                ? NSColor(calibratedRed: 1.0, green: 0.98, blue: 0.94, alpha: 1.0)
                : NSColor(calibratedRed: 0.96, green: 0.99, blue: 0.97, alpha: 1.0),
            .shadow: textShadow(
                blur: options.style == .lyric ? 6.0 : (options.style == .glass ? 4.0 : 5.0),
                offsetY: -1.0,
                alpha: options.style == .lyric ? 1.0 : (options.style == .glass ? 0.88 : 0.95)
            )
        ]
        if options.style == .lyric {
            attributes[.strokeColor] = NSColor(calibratedWhite: 0.0, alpha: 0.82)
            attributes[.strokeWidth] = -2.6
        }
        return attributes
    }

    private func backgroundColor() -> NSColor {
        switch options.style {
        case .soft:
            return level.background(opacity: options.opacity)
        case .glass:
            return NSColor(calibratedRed: 0.05, green: 0.07, blue: 0.08, alpha: options.opacity)
        case .lyric:
            return NSColor(calibratedRed: 0.02, green: 0.02, blue: 0.018, alpha: options.opacity)
        }
    }

    private func accentColor() -> NSColor {
        switch options.style {
        case .soft:
            return level.accent.withAlphaComponent(options.opacity)
        case .glass:
            return level.accent.withAlphaComponent(0.58)
        case .lyric:
            return level.accent.withAlphaComponent(0.88)
        }
    }

    private static func textShadow(blur: CGFloat, offsetY: CGFloat, alpha: CGFloat) -> NSShadow {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(calibratedWhite: 0.0, alpha: alpha)
        shadow.shadowBlurRadius = blur
        shadow.shadowOffset = NSSize(width: 0.0, height: offsetY)
        return shadow
    }

    private static func font(named family: String?, size: CGFloat, weight: NSFont.Weight) -> NSFont {
        if let family, let font = NSFont(name: family, size: size) {
            return font
        }

        if let family,
           let members = NSFontManager.shared.availableMembers(ofFontFamily: family),
           let fontName = bestFontName(from: members, weight: weight),
           let font = NSFont(name: fontName, size: size) {
            return font
        }

        return NSFont.systemFont(ofSize: size, weight: weight)
    }

    private static func bestFontName(from members: [[Any]], weight: NSFont.Weight) -> String? {
        let preferredNames: [String]
        if weight == .bold {
            preferredNames = ["bold", "semibold", "medium"]
        } else {
            preferredNames = ["semibold", "medium", "regular"]
        }

        for preferredName in preferredNames {
            if let member = members.first(where: { member in
                guard member.count >= 2,
                      let fontName = member[0] as? String,
                      let displayName = member[1] as? String else {
                    return false
                }

                return fontName.localizedCaseInsensitiveContains(preferredName)
                    || displayName.localizedCaseInsensitiveContains(preferredName)
            }), let fontName = member[0] as? String {
                return fontName
            }
        }

        return members.first?.first as? String
    }
}

final class DaemonServer: @unchecked Sendable {
    private let manager: OverlayManager
    private var serverFD: Int32 = -1
    private let queue = DispatchQueue(label: "osd-notify.daemon.socket", qos: .utility)
    private var isRunning = false

    init(manager: OverlayManager) {
        self.manager = manager
    }

    func start() throws {
        ensureStateDirectory()
        terminateRecordedDaemonForRestart()
        try? FileManager.default.removeItem(at: daemonSocketURL)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw CLIError.message("Failed to create daemon socket: errno \(errno).")
        }

        do {
            try bindUnixSocket(fd: fd, path: daemonSocketURL.path)
        } catch {
            close(fd)
            throw error
        }

        guard listen(fd, 16) == 0 else {
            let currentErrno = errno
            close(fd)
            throw CLIError.message("Failed to listen on daemon socket: errno \(currentErrno).")
        }

        serverFD = fd
        isRunning = true
        try? "\(getpid())\n".write(to: daemonPIDFileURL, atomically: true, encoding: .utf8)

        queue.async { [weak self] in
            self?.acceptLoop()
        }
    }

    func stop() {
        isRunning = false
        if serverFD >= 0 {
            close(serverFD)
            serverFD = -1
        }
        try? FileManager.default.removeItem(at: daemonSocketURL)
    }

    private func acceptLoop() {
        while isRunning {
            let clientFD = accept(serverFD, nil, nil)
            if clientFD < 0 {
                if errno == EBADF || errno == EINVAL {
                    break
                }
                continue
            }

            handleClient(fd: clientFD)
        }
    }

    private func handleClient(fd: Int32) {
        let requestData = readAll(from: fd)
        guard !requestData.isEmpty else {
            sendResponse(DaemonResponse(ok: false, message: "Empty daemon request."), to: fd)
            close(fd)
            return
        }

        do {
            let request = try JSONDecoder().decode(DaemonRequest.self, from: requestData)
            Task { @MainActor in
                let response = self.manager.handle(request)
                self.sendResponse(response, to: fd)
                close(fd)
            }
        } catch {
            sendResponse(DaemonResponse(ok: false, message: "Invalid daemon request: \(error)."), to: fd)
            close(fd)
        }
    }

    private func sendResponse(_ response: DaemonResponse, to fd: Int32) {
        if let data = try? JSONEncoder().encode(response) {
            _ = writeAll(data, to: fd)
        }
    }
}

func printUsage() {
    let usage = """
    用法:
      osd-notify show [message] [--source name] [--ttl seconds] [--level info|warn|busy|done] [--position top|center|bottom] [--style soft|glass|lyric] [--font name] [--font-size points] [--title-size points] [--opacity 0...1] [--window-opacity 0...1] [--click-through|--blocks-clicks]
      osd-notify play file.lrc|file.srt|video.mkv [...] [--source name] [--speed rate] [--limit count] [--stream index ...] [--list-subtitles] [--no-cache|--refresh-cache|--warm-cache] [--position top|center|bottom] [--font name] [--font-size points] [--title-size points] [--opacity 0...1] [--window-opacity 0...1] [--click-through|--blocks-clicks]
      osd-notify recite [text|file.txt ...] [--file path] [--text text] [--stdin] [--source name] [--interval seconds] [--delimiters chars] [--min-chars count] [--max-chars count] [--speed rate] [--limit count] [--dry-run] [--no-clear] [--position top|center|bottom] [--font name] [--font-size points] [--title-size points] [--opacity 0...1] [--window-opacity 0...1] [--click-through|--blocks-clicks]
      osd-notify clear [--source name] [--all]

    示例:
      osd-notify show
      osd-notify show --source codex
      osd-notify show "Glass test" --style glass
      osd-notify show "Lyric test" --style lyric
      osd-notify show "Automation finished" --ttl 3 --level done
      osd-notify play ./song.lrc
      osd-notify play ./subtitle.srt --speed 20 --limit 8
      osd-notify play ./zh.srt ./en.srt
      osd-notify play ./movie.mkv
      osd-notify play ./movie.mkv --list-subtitles
      osd-notify play ./movie.mkv --stream 8 --stream 9
      osd-notify play ./movie.mkv --warm-cache --stream 8 --stream 9
      osd-notify recite ./lantingxu.txt --source 兰亭序 --interval 8
      osd-notify recite --text "永和九年，岁在癸丑，暮春之初。" --source 兰亭序 --interval 5
      osd-notify recite ./lantingxu.txt --source 兰亭序 --dry-run
      osd-notify clear
      osd-notify clear --source codex
      osd-notify clear --all

    说明:
      show 默认消息: 请暂停手动操作，Codex 正在控制 Chrome
      默认样式: glass、bottom、PingFang SC、36pt 主文字、42% 背景透明度、3600 秒 TTL。
      OSD 会同时显示在所有已连接显示器上。
      不同来源可以同时显示；相同位置已有 OSD 时会自动错开堆叠。
      clear 默认只清理当前来源；只有 --all 会清理所有来源。
      标题优先使用显式 source / 环境 source；否则读取直接父进程 PID 对应的 macOS 应用名。
      play 默认用输入文件 basename 作为 source，并始终用 lyric 样式按时间戳播放。多个 LRC/SRT 文件会按命令顺序从上到下堆叠显示。
      视频文件会先用 ffprobe 探测文本字幕流；多字幕流时会列出编号，直接输入 1,3 或 1 3 回车即可；空回车才尝试打开 gum TUI。视频字幕默认边抽边播，并缓存到 ~/Library/Caches/osd-notify/subtitles/。
      recite 读取普通文本，默认按中文/英文逗号、句号、问号、叹号和分号初拆，再均衡组合成 7-20 字左右的字幕句；--delimiters 可自定义切分字符。
      glass 默认可拖动；soft 默认鼠标穿透。
    """
    print(usage)
}

func parseCommand() throws -> Command {
    var args = Array(CommandLine.arguments.dropFirst())

    if args.first == "help" || args.first == "--help" || args.first == "-h" {
        printUsage()
        exit(0)
    }

    if args.first == "--daemon" {
        return .daemon
    }

    if args.first == "clear" {
        args.removeFirst()
        return .clear(try parseClearOptions(args))
    }

    if args.first == "play" {
        args.removeFirst()
        return .play(try parsePlayOptions(args))
    }

    if args.first == "recite" {
        args.removeFirst()
        return .recite(try parseReciteOptions(args))
    }

    if args.first == "show" {
        args.removeFirst()
    }

    return .show(try parseOptions(args))
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

func lyricPlaybackOptions() -> Options {
    var options = Options()
    options.style = .lyric
    options.opacity = OverlayStyle.lyric.defaultOpacity
    options.passThrough = OverlayStyle.lyric.defaultPassThrough
    return options
}

func parseOptions(_ args: [String]) throws -> Options {

    var options = Options()
    var opacityWasSet = false
    var passThroughWasSet = false
    var messageParts: [String] = []
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
            options.sourceWasProvidedByCaller = true

        case "--ttl":
            index += 1
            guard index < args.count, let ttl = TimeInterval(args[index]), ttl > 0 else {
                throw CLIError.message("--ttl expects a positive number of seconds.")
            }
            options.ttl = ttl

        case "--level":
            index += 1
            guard index < args.count, let level = NoticeLevel(rawValue: args[index]) else {
                throw CLIError.message("--level expects one of: info, warn, busy, done.")
            }
            options.level = level

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
            messageParts.append(arg)
        }

        index += 1
    }

    if !messageParts.isEmpty {
        options.message = messageParts.joined(separator: " ")
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

let stateDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent("osd-notify", isDirectory: true)
let placementDirectoryURL = stateDirectoryURL.appendingPathComponent("placements", isDirectory: true)
let legacyPIDFileURL = FileManager.default.temporaryDirectory.appendingPathComponent("osd-notify.pid")
let daemonSocketURL = stateDirectoryURL.appendingPathComponent("daemon.sock")
let daemonPIDFileURL = stateDirectoryURL.appendingPathComponent("daemon.pid")
let stackSpacing: CGFloat = 12.0
let socketRetryDelay: TimeInterval = 0.05
let overlayFadeInDuration: TimeInterval = 0.16
let overlayFadeOutDuration: TimeInterval = 0.18
let textConvertibleSubtitleCodecs: Set<String> = [
    "ass",
    "microdvd",
    "mov_text",
    "mpl2",
    "ssa",
    "srt",
    "subrip",
    "subviewer",
    "subviewer1",
    "text",
    "webvtt"
]
let videoContainerExtensions: Set<String> = [
    "3gp",
    "avi",
    "m2ts",
    "m4v",
    "mkv",
    "mov",
    "mp4",
    "mpeg",
    "mpg",
    "mts",
    "ts",
    "webm"
]
let subtitleExtractionQueue = DispatchQueue(label: "osd-notify.subtitle.extract", qos: .utility, attributes: .concurrent)
let subtitleSchedulerPollInterval: TimeInterval = 0.03

func bindUnixSocket(fd: Int32, path: String) throws {
    var address = try unixSocketAddress(path: path)
    let result = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
            bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard result == 0 else {
        throw CLIError.message("Failed to bind daemon socket at \(path): errno \(errno).")
    }
}

func connectUnixSocket(fd: Int32, path: String) throws {
    var address = try unixSocketAddress(path: path)
    let result = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
            connect(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard result == 0 else {
        throw CLIError.message("Failed to connect daemon socket at \(path): errno \(errno).")
    }
}

func unixSocketAddress(path: String) throws -> sockaddr_un {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = Array(path.utf8CString)
    let maxPathLength = MemoryLayout.size(ofValue: address.sun_path)
    guard pathBytes.count <= maxPathLength else {
        throw CLIError.message("Daemon socket path is too long: \(path).")
    }

    withUnsafeMutableBytes(of: &address.sun_path) { buffer in
        for index in 0..<buffer.count {
            buffer[index] = 0
        }
        for (index, byte) in pathBytes.enumerated() {
            buffer[index] = UInt8(bitPattern: byte)
        }
    }

    return address
}

func readAll(from fd: Int32) -> Data {
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4096)

    while true {
        let count = buffer.withUnsafeMutableBytes { rawBuffer in
            read(fd, rawBuffer.baseAddress, rawBuffer.count)
        }
        if count > 0 {
            data.append(buffer, count: count)
        } else {
            break
        }
    }

    return data
}

@discardableResult
func writeAll(_ data: Data, to fd: Int32) -> Bool {
    var offset = 0
    return data.withUnsafeBytes { rawBuffer in
        guard let baseAddress = rawBuffer.baseAddress else {
            return true
        }

        while offset < data.count {
            let written = write(fd, baseAddress.advanced(by: offset), data.count - offset)
            if written <= 0 {
                return false
            }
            offset += written
        }

        return true
    }
}

func sendDaemonRequest(_ request: DaemonRequest, autostart: Bool) throws -> DaemonResponse {
    do {
        return try sendDaemonRequestOnce(request)
    } catch {
        guard autostart else {
            throw error
        }
    }

    terminateRecordedDaemonForRestart()
    try? FileManager.default.removeItem(at: daemonSocketURL)
    try startDaemonProcess()

    let deadline = Date().addingTimeInterval(2.0)
    var lastError: Error?
    while Date() < deadline {
        do {
            return try sendDaemonRequestOnce(request)
        } catch {
            lastError = error
            Thread.sleep(forTimeInterval: socketRetryDelay)
        }
    }

    throw lastError ?? CLIError.message("Timed out waiting for osd-notify daemon.")
}

func sendDaemonRequestOnce(_ request: DaemonRequest) throws -> DaemonResponse {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else {
        throw CLIError.message("Failed to create client socket: errno \(errno).")
    }
    defer {
        close(fd)
    }

    try connectUnixSocket(fd: fd, path: daemonSocketURL.path)
    let requestData = try JSONEncoder().encode(request)
    guard writeAll(requestData, to: fd) else {
        throw CLIError.message("Failed to write daemon request: errno \(errno).")
    }
    shutdown(fd, SHUT_WR)

    let responseData = readAll(from: fd)
    guard !responseData.isEmpty else {
        throw CLIError.message("Daemon returned an empty response.")
    }

    return try JSONDecoder().decode(DaemonResponse.self, from: responseData)
}

func startDaemonProcess() throws {
    let executableURL = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
    let process = Process()
    process.executableURL = executableURL
    process.arguments = ["--daemon"]

    let nullInput = FileHandle(forReadingAtPath: "/dev/null")
    let nullOutput = FileHandle(forWritingAtPath: "/dev/null")
    process.standardInput = nullInput
    process.standardOutput = nullOutput
    process.standardError = nullOutput

    try process.run()
}

func terminateRecordedDaemonForRestart() {
    guard let pidText = try? String(contentsOf: daemonPIDFileURL, encoding: .utf8),
          let pid = Int32(pidText.trimmingCharacters(in: .whitespacesAndNewlines)),
          pid > 0,
          pid != getpid(),
          isProcessAlive(pid_t(pid)) else {
        try? FileManager.default.removeItem(at: daemonPIDFileURL)
        return
    }

    _ = kill(pid_t(pid), SIGTERM)
    let deadline = Date().addingTimeInterval(1.0)
    while Date() < deadline {
        if !isProcessAlive(pid_t(pid)) {
            break
        }
        Thread.sleep(forTimeInterval: 0.05)
    }
    try? FileManager.default.removeItem(at: daemonPIDFileURL)
}

func configuredSourceNameFromEnvironment() -> String? {
    let environment = ProcessInfo.processInfo.environment
    for key in ["OSD_NOTIFY_SOURCE", "CODEX_OSD_SOURCE"] {
        if let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty {
            return value
        }
    }
    return nil
}

func sourceWasConfiguredByEnvironment() -> Bool {
    configuredSourceNameFromEnvironment() != nil
}

func inferredSourceName() -> String {
    if let configuredSource = configuredSourceNameFromEnvironment() {
        return configuredSource
    }

    var nameBuffer = [CChar](repeating: 0, count: 1024)
    let length = proc_name(getppid(), &nameBuffer, UInt32(nameBuffer.count))
    if length > 0 {
        let name = String(decoding: nameBuffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            return name
        }
    }

    return "default"
}

func parentApplicationDisplayName() -> String? {
    applicationDisplayName(for: getppid())
}

func applicationDisplayName(for pid: pid_t) -> String? {
    guard pid > 1,
          let application = NSRunningApplication(processIdentifier: pid) else {
        return nil
    }

    if let localizedName = cleanedDisplayName(application.localizedName),
       !isNonApplicationSourceName(localizedName) {
        return localizedName
    }

    if let bundleURL = application.bundleURL,
       let bundleName = bundleDisplayName(at: bundleURL) {
        return bundleName
    }

    return nil
}

func bundleDisplayName(at url: URL) -> String? {
    guard let bundle = Bundle(url: url) else {
        return cleanedDisplayName(url.deletingPathExtension().lastPathComponent)
    }

    for key in ["CFBundleDisplayName", "CFBundleName"] {
        if let value = bundle.object(forInfoDictionaryKey: key) as? String,
           let displayName = cleanedDisplayName(value),
           !isNonApplicationSourceName(displayName) {
            return displayName
        }
    }

    return cleanedDisplayName(url.deletingPathExtension().lastPathComponent)
}

func cleanedDisplayName(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
          !trimmed.isEmpty else {
        return nil
    }
    return trimmed
}

func safeSourceName(_ source: String) -> String {
    let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
    let sanitized = source.map { allowed.contains($0) ? $0 : "_" }
    var name = String(sanitized).trimmingCharacters(in: CharacterSet(charactersIn: "._-"))
    if name.isEmpty {
        name = "source"
    }

    if name == source {
        return String(name.prefix(80))
    }

    return "\(String(name.prefix(48)))-\(stableSourceHash(source))"
}

func stableSourceHash(_ source: String) -> String {
    var hash: UInt64 = 0xcbf29ce484222325
    for byte in source.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 0x100000001b3
    }
    return String(hash, radix: 16)
}

func displayTitle(for options: Options) -> String {
    if let titleOverride = cleanedDisplayName(options.titleOverride) {
        return titleOverride
    }

    if options.sourceWasProvidedByCaller {
        return sourceDisplayName(options.source) ?? options.parentApplicationName ?? options.level.title
    }

    return options.parentApplicationName ?? sourceDisplayName(options.source) ?? options.level.title
}

func isNonApplicationSourceName(_ source: String) -> Bool {
    let lowercased = source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let nonApplicationSources: Set<String> = [
        "default",
        "unknown",
        "osd-notify",
        "swift",
        "zsh",
        "bash",
        "sh",
        "fish",
        "env",
        "make",
        "login"
    ]
    return nonApplicationSources.contains(lowercased)
}

func sourceDisplayName(_ source: String) -> String? {
    let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return nil
    }

    let lowercased = trimmed.lowercased()
    guard !isNonApplicationSourceName(trimmed) else {
        return nil
    }

    let knownNames: [String: String] = [
        "browser": "Browser",
        "chrome": "Chrome",
        "codex": "Codex",
        "com.google.chrome": "Google Chrome",
        "computer-use": "Computer Use",
        "computer use": "Computer Use",
        "github-desktop": "GitHub Desktop",
        "github desktop": "GitHub Desktop",
        "google chrome": "Google Chrome",
        "playwright": "Playwright"
    ]
    if let knownName = knownNames[lowercased] {
        return knownName
    }

    let pathName = (trimmed as NSString).lastPathComponent
    let appName = pathName.hasSuffix(".app") ? String(pathName.dropLast(4)) : pathName
    let separated = appName
        .replacingOccurrences(of: "_", with: " ")
        .replacingOccurrences(of: "-", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !separated.isEmpty else {
        return nil
    }

    if separated == separated.uppercased() {
        return separated
    }

    if separated.rangeOfCharacter(from: .uppercaseLetters) != nil {
        return separated
    }

    return separated
        .split(separator: " ")
        .map { word in
            let lower = word.lowercased()
            return lower.prefix(1).uppercased() + String(lower.dropFirst())
        }
        .joined(separator: " ")
}

func ensureStateDirectory() {
    try? FileManager.default.createDirectory(at: stateDirectoryURL, withIntermediateDirectories: true)
}

func ensurePlacementDirectory() {
    ensureStateDirectory()
    try? FileManager.default.createDirectory(at: placementDirectoryURL, withIntermediateDirectories: true)
}

func recordFileURL(for source: String) -> URL {
    ensureStateDirectory()
    return stateDirectoryURL.appendingPathComponent("\(safeSourceName(source)).json")
}

func placementFileURL(for source: String) -> URL {
    ensurePlacementDirectory()
    return placementDirectoryURL.appendingPathComponent("\(safeSourceName(source)).json")
}

func readOverlayPlacement(source: String) -> OverlayPlacement? {
    let url = placementFileURL(for: source)
    guard let data = try? Data(contentsOf: url) else {
        return nil
    }
    return try? JSONDecoder().decode(OverlayPlacement.self, from: data)
}

func writeOverlayPlacement(_ placement: OverlayPlacement, source: String) {
    let url = placementFileURL(for: source)
    if let data = try? JSONEncoder().encode(placement) {
        try? data.write(to: url, options: .atomic)
    }
}

func screenKey(for screen: NSScreen) -> String {
    if let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
        return "screen-\(screenNumber.uint32Value)"
    }

    let frame = screen.frame
    return "screen-\(Int(frame.minX))-\(Int(frame.minY))-\(Int(frame.width))-\(Int(frame.height))"
}

func readOverlayRecord(source: String) -> OverlayRecord? {
    let url = recordFileURL(for: source)
    guard let data = try? Data(contentsOf: url) else {
        return nil
    }
    return try? JSONDecoder().decode(OverlayRecord.self, from: data)
}

func writeOverlayRecord(_ record: OverlayRecord) {
    let url = recordFileURL(for: record.source)
    if let data = try? JSONEncoder().encode(record) {
        try? data.write(to: url, options: .atomic)
    }
}

func removeOverlayRecord(source: String) {
    try? FileManager.default.removeItem(at: recordFileURL(for: source))
}

@discardableResult
func removeAllOverlayRecords() -> Bool {
    ensureStateDirectory()
    guard let urls = try? FileManager.default.contentsOfDirectory(
        at: stateDirectoryURL,
        includingPropertiesForKeys: nil
    ) else {
        return false
    }

    var removedAny = false
    for url in urls where url.pathExtension == "json" {
        if (try? FileManager.default.removeItem(at: url)) != nil {
            removedAny = true
        }
    }
    return removedAny
}

func removeRecordIfOwnedByCurrentProcess(source: String) {
    guard let record = readOverlayRecord(source: source),
          record.pid == getpid() else {
        return
    }

    removeOverlayRecord(source: source)
}

func isProcessAlive(_ pid: pid_t) -> Bool {
    errno = 0
    if kill(pid, 0) == 0 {
        return true
    }
    return errno == EPERM
}

func activeOverlayRecords() -> [OverlayRecord] {
    ensureStateDirectory()
    guard let urls = try? FileManager.default.contentsOfDirectory(
        at: stateDirectoryURL,
        includingPropertiesForKeys: nil
    ) else {
        return []
    }

    var records: [OverlayRecord] = []
    for url in urls where url.pathExtension == "json" {
        guard let data = try? Data(contentsOf: url),
              let record = try? JSONDecoder().decode(OverlayRecord.self, from: data) else {
            try? FileManager.default.removeItem(at: url)
            continue
        }

        if record.pid != getpid(), isProcessAlive(pid_t(record.pid)) {
            records.append(record)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }

    return records.sorted { $0.createdAt < $1.createdAt }
}

@MainActor
@discardableResult
func closeAllProcessOverlayPanels() -> Bool {
    var closedAny = false
    for window in NSApp.windows {
        guard let panel = window as? NSPanel else {
            continue
        }
        panel.orderOut(nil)
        panel.close()
        closedAny = true
    }
    return closedAny
}

func activeStackOffset(for options: Options, excluding source: String, additionalRecords: [OverlayRecord] = []) -> CGFloat {
    let records = (activeOverlayRecords() + additionalRecords)
        .filter { $0.position == options.position.rawValue && $0.source != source }

    if let stackGroup = options.stackGroup,
       let stackIndex = options.stackIndex {
        let nonGroupOffset = records
            .filter { $0.stackGroup != stackGroup }
            .reduce(0.0) { offset, record in
                offset + max(CGFloat(record.height), 108.0) + stackSpacing
            }
        let sameGroupBelow = records
            .filter { $0.stackGroup == stackGroup && ($0.stackIndex ?? Int.max) < stackIndex }
        let actualBelowOffset = sameGroupBelow.reduce(0.0) { offset, record in
            offset + max(CGFloat(record.height), 108.0) + stackSpacing
        }
        let reservedSlots = max(0, stackIndex - sameGroupBelow.count)
        return nonGroupOffset + actualBelowOffset + CGFloat(reservedSlots) * (108.0 + stackSpacing)
    }

    return records.reduce(0.0) { offset, record in
        offset + max(CGFloat(record.height), 108.0) + stackSpacing
    }
}

func clamp(_ value: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> CGFloat {
    Swift.max(minValue, Swift.min(value, maxValue))
}

@discardableResult
func clearExistingOverlay(source: String, quiet: Bool) -> Bool {
    guard let record = readOverlayRecord(source: source) else {
        if !quiet {
            print("No active OSD process found for source '\(source)'.")
        }
        return false
    }

    let pid = pid_t(record.pid)
    if pid == getpid() {
        return false
    }

    if kill(pid, SIGTERM) == 0 {
        removeOverlayRecord(source: source)
        if !quiet {
            print("Cleared OSD source '\(source)' process \(pid).")
        }
        return true
    }

    if errno == ESRCH {
        removeOverlayRecord(source: source)
        if !quiet {
            print("No active OSD process found for source '\(source)'.")
        }
        return false
    }

    if !quiet {
        fputs("Failed to clear OSD source '\(source)' process \(pid): errno \(errno)\n", stderr)
    }
    return false
}

@discardableResult
func clearAllOverlays(quiet: Bool) -> Bool {
    let records = activeOverlayRecords()
    var clearedAny = false

    for record in records {
        if clearExistingOverlay(source: record.source, quiet: true) {
            clearedAny = true
            if !quiet {
                print("Cleared OSD source '\(record.source)' process \(record.pid).")
            }
        }
    }

    if clearLegacyOverlay(quiet: quiet) {
        clearedAny = true
    }

    if !clearedAny, !quiet {
        print("No active OSD processes found.")
    }

    return clearedAny
}

@discardableResult
func clearLegacyOverlay(quiet: Bool) -> Bool {
    guard let pidText = try? String(contentsOf: legacyPIDFileURL, encoding: .utf8),
          let pid = Int32(pidText.trimmingCharacters(in: .whitespacesAndNewlines)),
          pid > 0,
          pid != getpid() else {
        try? FileManager.default.removeItem(at: legacyPIDFileURL)
        return false
    }

    if kill(pid_t(pid), SIGTERM) == 0 {
        try? FileManager.default.removeItem(at: legacyPIDFileURL)
        if !quiet {
            print("Cleared legacy OSD process \(pid).")
        }
        return true
    }

    if errno == ESRCH {
        try? FileManager.default.removeItem(at: legacyPIDFileURL)
    } else if !quiet {
        fputs("Failed to clear legacy OSD process \(pid): errno \(errno)\n", stderr)
    }

    return false
}

func isVideoContainer(_ fileURL: URL) -> Bool {
    videoContainerExtensions.contains(fileURL.pathExtension.lowercased())
}

func probeSubtitleStreams(in fileURL: URL) throws -> [SubtitleStream] {
    guard let ffprobe = findExecutable("ffprobe") else {
        throw CLIError.message("需要 ffprobe 探测视频字幕流，但 PATH 中没有找到 ffprobe。")
    }

    let result = try runCapturedProcess(
        executable: ffprobe,
        arguments: [
            "-v", "error",
            "-select_streams", "s",
            "-show_entries", "stream=index,codec_name:stream_tags=language,title:stream_disposition=default,forced",
            "-of", "json",
            fileURL.path
        ]
    )
    guard result.status == 0 else {
        throw CLIError.message("ffprobe 探测字幕流失败：\(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
    }

    let data = Data(result.stdout.utf8)
    let output = try JSONDecoder().decode(FFProbeOutput.self, from: data)
    return output.streams.map { stream in
        SubtitleStream(
            index: stream.index,
            codecName: stream.codecName ?? "unknown",
            language: stream.tags?["language"],
            title: stream.tags?["title"],
            isDefault: (stream.disposition?["default"] ?? 0) != 0,
            isForced: (stream.disposition?["forced"] ?? 0) != 0
        )
    }
}

func printSubtitleStreams(_ streams: [SubtitleStream]) {
    guard !streams.isEmpty else {
        print("未检测到内封字幕流。")
        return
    }

    print("检测到 \(streams.count) 条内封字幕流：")
    var displayIndex = 1
    for stream in streams {
        let status = stream.isTextConvertible ? "可展示" : "跳过"
        let reason = stream.isTextConvertible ? "" : "；非文本字幕，不能直接转成 SRT/LRC 显示"
        let prefix: String
        if stream.isTextConvertible {
            prefix = "\(displayIndex). "
            displayIndex += 1
        } else {
            prefix = ""
        }
        print("  [\(status)] \(prefix)\(subtitleStreamLabel(stream))\(reason)")
    }
}

func selectSubtitleStreams(from streams: [SubtitleStream], options: PlayOptions) throws -> [SubtitleStream] {
    let compatibleStreams = streams.filter(\.isTextConvertible)

    if !options.streamIndices.isEmpty {
        return try options.streamIndices.map { requestedIndex in
            guard let stream = streams.first(where: { $0.index == requestedIndex }) else {
                throw CLIError.message("没有找到 stream index \(requestedIndex)。请先用 --list-subtitles 查看可用字幕流。")
            }
            guard stream.isTextConvertible else {
                throw CLIError.message("stream index \(requestedIndex) 是 \(stream.codecName)，不是可直接展示的文本字幕。")
            }
            return stream
        }
    }

    guard !compatibleStreams.isEmpty else {
        throw CLIError.message("没有可直接展示的文本字幕流。PGS/DVD/DVB 这类图形字幕需要 OCR，当前不会自动转换。")
    }

    if compatibleStreams.count == 1 {
        print("只有 1 条可展示字幕，自动选择：\(subtitleStreamLabel(compatibleStreams[0]))")
        return compatibleStreams
    }

    print("可展示字幕流：")
    print(numberedSubtitleStreamList(compatibleStreams))

    return try selectSubtitleStreamsInteractively(compatibleStreams, gumPath: findExecutable("gum"))
}

func selectSubtitleStreamsWithGum(_ streams: [SubtitleStream], gumPath: String) throws -> [SubtitleStream] {
    let choices = streams.enumerated().map { displayIndex, stream in
        numberedSubtitleStreamChoice(stream, displayIndex: displayIndex)
    }
    let selectedChoices = try runGumChooseMultiple(
        gumPath: gumPath,
        header: "选择要显示的字幕。可空格多选；输出顺序就是屏幕从上到下。",
        choices: choices
    )
    return try selectedChoices.map { choice in
        guard let displayIndex = parseSubtitleChoiceDisplayIndex(choice),
              displayIndex >= 0,
              displayIndex < streams.count else {
            throw CLIError.message("无法识别 gum 返回的字幕选择：\(choice)")
        }
        return streams[displayIndex]
    }
}

func selectSubtitleStreamsInteractively(_ streams: [SubtitleStream], gumPath: String?) throws -> [SubtitleStream] {
    let canOpenTUI = gumPath != nil && canUseGumTUI()
    if canOpenTUI {
        fputs("请输入要显示的编号，可用逗号或空格分隔；顺序表示从上到下。直接回车打开 gum TUI：", stderr)
    } else {
        fputs("请输入要显示的编号，可用逗号或空格分隔；顺序表示从上到下：", stderr)
    }
    fflush(stderr)
    guard let line = readLine() else {
        throw CLIError.message("没有读取到字幕选择。")
    }
    if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return try parseSubtitleSelectionInput(line, streams: streams)
    }

    guard canOpenTUI, let gumPath else {
        throw CLIError.message("没有选择任何字幕。")
    }

    do {
        return try selectSubtitleStreamsWithGum(streams, gumPath: gumPath)
    } catch {
        fputs("gum TUI 不可用，回退到编号输入：\(error)\n", stderr)
        fflush(stderr)
        fputs("请输入要显示的编号，可用逗号或空格分隔；顺序表示从上到下：", stderr)
        fflush(stderr)
        guard let fallbackLine = readLine() else {
            throw CLIError.message("没有读取到字幕选择。")
        }
        return try parseSubtitleSelectionInput(fallbackLine, streams: streams)
    }
}

func parseSubtitleSelectionInput(_ rawValue: String, streams: [SubtitleStream]) throws -> [SubtitleStream] {
    let tokens = rawValue
        .split(whereSeparator: { character in
            character == "," || character == " " || character == "\t" || character == "\n"
        })
        .map(String.init)

    guard !tokens.isEmpty else {
        throw CLIError.message("没有选择任何字幕。")
    }

    var selected: [SubtitleStream] = []
    var selectedStreamIndices: Set<Int> = []
    for token in tokens {
        guard let number = Int(token) else {
            throw CLIError.message("无法识别字幕编号：\(token)")
        }

        let stream: SubtitleStream?
        if number >= 1 && number <= streams.count {
            stream = streams[number - 1]
        } else {
            stream = streams.first(where: { $0.index == number })
        }

        guard let stream else {
            throw CLIError.message("没有找到字幕编号或 stream index：\(number)")
        }
        guard !selectedStreamIndices.contains(stream.index) else {
            throw CLIError.message("字幕 \(number) 被重复选择。")
        }
        selected.append(stream)
        selectedStreamIndices.insert(stream.index)
    }

    return selected
}

func canUseGumTUI() -> Bool {
    guard isatty(STDIN_FILENO) == 1,
          isatty(STDERR_FILENO) == 1 else {
        return false
    }

    let fd = open("/dev/tty", O_RDWR)
    guard fd >= 0 else {
        return false
    }
    close(fd)
    return true
}

func runGumChooseMultiple(gumPath: String, header: String, choices: [String]) throws -> [String] {
    let result = try runCapturedTUIProcess(
        executable: gumPath,
        arguments: ["choose", "--no-limit", "--ordered", "--header", header] + choices
    )
    guard result.status == 0 else {
        throw CLIError.message("gum 选择失败或已取消。")
    }

    let choices = result.stdout
        .split(separator: "\n", omittingEmptySubsequences: true)
        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    guard !choices.isEmpty else {
        throw CLIError.message("gum 没有返回选择结果。")
    }
    return choices
}

func subtitleCacheDirectoryURL() throws -> URL {
    let baseURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches", isDirectory: true)
    let url = baseURL
        .appendingPathComponent("osd-notify", isDirectory: true)
        .appendingPathComponent("subtitles", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func subtitleCacheFileURL(for videoURL: URL, stream: SubtitleStream) throws -> URL {
    let attributes = try FileManager.default.attributesOfItem(atPath: videoURL.path)
    let fileSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
    let modifiedAt = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
    let key = [
        videoURL.path,
        "\(fileSize)",
        "\(modifiedAt)",
        "\(stream.index)",
        stream.codecName,
        "srt-v1"
    ].joined(separator: "|")
    let basename = safeSourceName(videoURL.deletingPathExtension().lastPathComponent)
    return try subtitleCacheDirectoryURL()
        .appendingPathComponent("\(basename)-stream-\(stream.index)-\(stableSourceHash(key)).srt")
}

func startStreamingSubtitleExtraction(
    stream: SubtitleStream,
    from fileURL: URL,
    cacheURL: URL?,
    buffer: SubtitleTrackBuffer,
    limit: Int?
) throws -> StreamingSubtitleExtraction {
    guard let ffmpeg = findExecutable("ffmpeg") else {
        throw CLIError.message("需要 ffmpeg 抽取字幕流，但 PATH 中没有找到 ffmpeg。")
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: ffmpeg)
    process.arguments = [
        "-nostdin",
        "-hide_banner",
        "-loglevel", "error",
        "-i", fileURL.path,
        "-map", "0:\(stream.index)",
        "-c:s", "srt",
        "-f", "srt",
        "pipe:1"
    ]

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    let extraction = StreamingSubtitleExtraction(process: process)
    let partURL = cacheURL?.appendingPathExtension("part")
    let cacheHandle: FileHandle?
    if let partURL {
        try? FileManager.default.removeItem(at: partURL)
        guard FileManager.default.createFile(atPath: partURL.path, contents: nil),
              let handle = FileHandle(forWritingAtPath: partURL.path) else {
            throw CLIError.message("无法创建字幕缓存临时文件：\(partURL.path)")
        }
        cacheHandle = handle
    } else {
        cacheHandle = nil
    }

    try process.run()

    subtitleExtractionQueue.async {
        let parser = IncrementalSRTParser()
        let stdout = stdoutPipe.fileHandleForReading
        let stderr = stderrPipe.fileHandleForReading
        var parsedCount = 0
        var limitReached = false

        while true {
            let chunk = stdout.readData(ofLength: 64 * 1024)
            if chunk.isEmpty {
                break
            }
            cacheHandle?.write(chunk)

            for line in parser.append(chunk) {
                buffer.append(line)
                parsedCount += 1
                if let limit, parsedCount >= limit {
                    limitReached = true
                    if process.isRunning {
                        process.terminate()
                    }
                    break
                }
            }

            if limitReached {
                break
            }
        }

        if !limitReached {
            for line in parser.finish() {
                buffer.append(line)
                parsedCount += 1
                if let limit, parsedCount >= limit {
                    limitReached = true
                    if process.isRunning {
                        process.terminate()
                    }
                    break
                }
            }
        }

        cacheHandle?.closeFile()
        process.waitUntilExit()
        let stderrText = String(decoding: stderr.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if limitReached {
            if let partURL {
                try? FileManager.default.removeItem(at: partURL)
            }
            buffer.finish()
        } else if process.terminationStatus == 0 {
            if let cacheURL, let partURL {
                try? FileManager.default.removeItem(at: cacheURL)
                do {
                    try FileManager.default.moveItem(at: partURL, to: cacheURL)
                    print("已缓存字幕 stream \(stream.index)：\(cacheURL.path)")
                } catch {
                    buffer.fail(CLIError.message("写入字幕缓存失败：\(error)"))
                    extraction.markFinished()
                    return
                }
            }
            buffer.finish()
        } else {
            if let partURL {
                try? FileManager.default.removeItem(at: partURL)
            }
            let reason = stderrText.isEmpty ? "ffmpeg exit \(process.terminationStatus)" : stderrText
            buffer.fail(CLIError.message("ffmpeg 流式抽取 stream \(stream.index) 失败：\(reason)"))
        }

        extraction.markFinished()
    }

    return extraction
}

func playVideoSubtitles(_ options: PlayOptions, fileURL: URL) throws {
    let streams = try probeSubtitleStreams(in: fileURL)
    printSubtitleStreams(streams)

    if options.listSubtitlesOnly {
        return
    }

    let selectedStreams = try selectSubtitleStreams(from: streams, options: options)
    let baseSource = options.source ?? fileURL.lastPathComponent
    var tracks: [BufferedSubtitlePlaybackTrack] = []
    var extractions: [StreamingSubtitleExtraction] = []
    var finishedNormally = false
    defer {
        if !finishedNormally {
            for extraction in extractions {
                extraction.terminate()
            }
        }
    }

    for (orderIndex, stream) in selectedStreams.enumerated() {
        let stackIndex = selectedStreams.count > 1 ? selectedStreams.count - 1 - orderIndex : nil
        let cacheURL = options.useCache ? try subtitleCacheFileURL(for: fileURL, stream: stream) : nil
        let buffer: SubtitleTrackBuffer

        if let cacheURL,
           !options.refreshCache,
           FileManager.default.fileExists(atPath: cacheURL.path) {
            var lines = try loadTimedTextLines(from: cacheURL)
            if let limit = options.limit {
                lines = Array(lines.prefix(limit))
            }
            buffer = SubtitleTrackBuffer(lines: lines, completed: true)
            print("命中字幕缓存 stream \(stream.index)：\(cacheURL.path)")
        } else {
            buffer = SubtitleTrackBuffer()
            if let cacheURL, options.refreshCache {
                try? FileManager.default.removeItem(at: cacheURL)
            }
            let extraction = try startStreamingSubtitleExtraction(
                stream: stream,
                from: fileURL,
                cacheURL: cacheURL,
                buffer: buffer,
                limit: options.limit
            )
            extractions.append(extraction)
            if let cacheURL {
                print("开始流式抽取 stream \(stream.index)，并写入缓存：\(cacheURL.path)")
            } else {
                print("开始流式抽取 stream \(stream.index)，本次不写缓存。")
            }
        }

        tracks.append(BufferedSubtitlePlaybackTrack(
            source: "\(baseSource)::stream-\(stream.index)",
            title: subtitleStreamDisplayTitle(stream),
            stackIndex: stackIndex,
            buffer: buffer
        ))
    }

    guard !tracks.isEmpty else {
        throw CLIError.message("选中的字幕流没有可播放文本。")
    }

    if tracks.count > 1 {
        print("显示顺序为从上到下：\(tracks.map(\.title).joined(separator: " / "))")
    }

    if options.warmCacheOnly {
        for extraction in extractions {
            extraction.wait()
        }
        for track in tracks {
            _ = try track.buffer.status(at: Int.max)
        }
        finishedNormally = true
        print("字幕缓存预热完成。")
        return
    }

    try playBufferedSubtitleTracks(
        tracks,
        baseOptions: options,
        stackGroup: tracks.count > 1 ? "video:\(baseSource)" : nil
    )
    for extraction in extractions {
        extraction.wait()
    }
    finishedNormally = true
}

func playSubtitleTracks(_ tracks: [SubtitlePlaybackTrack], baseOptions: PlayOptions, stackGroup: String?) throws {
    let bufferedTracks = tracks.map { track in
        BufferedSubtitlePlaybackTrack(
            source: track.source,
            title: track.title,
            stackIndex: track.stackIndex,
            buffer: SubtitleTrackBuffer(lines: track.lines, completed: true)
        )
    }
    try playBufferedSubtitleTracks(bufferedTracks, baseOptions: baseOptions, stackGroup: stackGroup)
}

func playBufferedSubtitleTracks(_ tracks: [BufferedSubtitlePlaybackTrack], baseOptions: PlayOptions, stackGroup: String?) throws {
    var cursors = Array(repeating: 0, count: tracks.count)
    var previousStart: TimeInterval = 0.0
    var lastVisibleDuration: TimeInterval = 0.0
    var didAlignPlaybackStart = false

    while true {
        var candidates: [(trackIndex: Int, line: TimedTextLine)] = []
        var hasPendingTrack = false

        for index in tracks.indices {
            switch try tracks[index].buffer.status(at: cursors[index]) {
            case .line(let line):
                candidates.append((trackIndex: index, line: line))
            case .pending:
                hasPendingTrack = true
            case .completed:
                break
            }
        }

        if candidates.isEmpty {
            if hasPendingTrack {
                Thread.sleep(forTimeInterval: subtitleSchedulerPollInterval)
                continue
            }
            break
        }

        if hasPendingTrack {
            Thread.sleep(forTimeInterval: subtitleSchedulerPollInterval)
            continue
        }

        let selected = candidates.min { lhs, rhs in
            if abs(lhs.line.start - rhs.line.start) < 0.001 {
                let lhsStackIndex = tracks[lhs.trackIndex].stackIndex ?? lhs.trackIndex
                let rhsStackIndex = tracks[rhs.trackIndex].stackIndex ?? rhs.trackIndex
                return lhsStackIndex < rhsStackIndex
            }
            return lhs.line.start < rhs.line.start
        }!
        let track = tracks[selected.trackIndex]
        let line = selected.line
        let nextLine: TimedTextLine?
        if case .line(let upcomingLine) = try track.buffer.status(at: cursors[selected.trackIndex] + 1) {
            nextLine = upcomingLine
        } else {
            nextLine = nil
        }

        if !didAlignPlaybackStart {
            previousStart = line.start
            didAlignPlaybackStart = true
            if line.start > 0.001 {
                print("播放时间基准从第一条字幕 \(formatTimedTextTimestamp(line.start)) 开始。")
            }
        }

        let wait = max(0.0, (line.start - previousStart) / baseOptions.speed)
        if wait > 0 {
            Thread.sleep(forTimeInterval: wait)
        }

        let visibleDuration = displayDuration(for: line, nextStart: nextLine?.start, speed: baseOptions.speed)
        lastVisibleDuration = visibleDuration

        var displayOptions = baseOptions.displayOptions
        displayOptions.message = line.text
        displayOptions.source = track.source
        displayOptions.sourceWasProvidedByCaller = true
        displayOptions.parentApplicationName = nil
        displayOptions.titleOverride = track.title
        displayOptions.ttl = visibleDuration
        displayOptions.style = .lyric
        displayOptions.stackGroup = stackGroup
        displayOptions.stackIndex = track.stackIndex
        let response = try sendDaemonRequest(.show(displayOptions), autostart: true)
        if !response.ok {
            throw CLIError.message(response.message)
        }

        previousStart = line.start
        cursors[selected.trackIndex] += 1
    }

    guard cursors.contains(where: { $0 > 0 }) else {
        throw CLIError.message("没有可播放的定时文本。")
    }

    if baseOptions.clearWhenFinished {
        Thread.sleep(forTimeInterval: lastVisibleDuration)
        for track in tracks {
            _ = try? sendDaemonRequest(.clear(ClearOptions(source: track.source, all: false)), autostart: false)
        }
    }
}

func subtitleStreamChoice(_ stream: SubtitleStream) -> String {
    "\(stream.index) | \(subtitleStreamLabel(stream))"
}

func numberedSubtitleStreamChoice(_ stream: SubtitleStream, displayIndex: Int) -> String {
    "\(displayIndex + 1). \(subtitleStreamLabel(stream))"
}

func numberedSubtitleStreamList(_ streams: [SubtitleStream]) -> String {
    streams.enumerated()
        .map { displayIndex, stream in
            "  \(numberedSubtitleStreamChoice(stream, displayIndex: displayIndex))"
        }
        .joined(separator: "\n")
}

func parseSubtitleChoiceDisplayIndex(_ choice: String) -> Int? {
    let trimmed = choice.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let dot = trimmed.firstIndex(of: "."),
          let displayNumber = Int(trimmed[..<dot]),
          displayNumber > 0 else {
        return nil
    }
    return displayNumber - 1
}

func subtitleStreamLabel(_ stream: SubtitleStream) -> String {
    var parts: [String] = ["stream \(stream.index)", stream.codecName]
    if let language = stream.language, !language.isEmpty {
        parts.append(languageDisplayName(language))
    }
    if let title = stream.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
        parts.append(title)
    }
    if stream.isDefault {
        parts.append("default")
    }
    if stream.isForced {
        parts.append("forced")
    }
    return parts.joined(separator: " | ")
}

func subtitleStreamDisplayTitle(_ stream: SubtitleStream) -> String {
    var parts = ["字幕 \(stream.index)"]
    if let language = stream.language, !language.isEmpty {
        parts.append(languageDisplayName(language))
    }
    if let title = stream.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
        parts.append(title)
    }
    return parts.joined(separator: " · ")
}

func languageDisplayName(_ language: String) -> String {
    let normalized = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let knownNames: [String: String] = [
        "chi": "中文",
        "chs": "简体中文",
        "cht": "繁体中文",
        "eng": "English",
        "en": "English",
        "jpn": "日本語",
        "ja": "日本語",
        "kor": "한국어",
        "ko": "한국어",
        "zho": "中文",
        "zh": "中文"
    ]
    if let knownName = knownNames[normalized] {
        return "\(language)/\(knownName)"
    }
    return language
}

func findExecutable(_ name: String) -> String? {
    let fileManager = FileManager.default
    if name.contains("/") {
        return fileManager.isExecutableFile(atPath: name) ? name : nil
    }

    let pathValue = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    for directory in pathValue.split(separator: ":") {
        let candidate = URL(fileURLWithPath: String(directory)).appendingPathComponent(name).path
        if fileManager.isExecutableFile(atPath: candidate) {
            return candidate
        }
    }
    return nil
}

func runCapturedProcess(
    executable: String,
    arguments: [String],
    inheritStandardInput: Bool = false,
    inheritStandardError: Bool = false
) throws -> ProcessResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    if inheritStandardInput {
        process.standardInput = FileHandle.standardInput
    }

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = inheritStandardError ? FileHandle.standardError : stderrPipe

    try process.run()
    process.waitUntilExit()

    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let stderrData = inheritStandardError ? Data() : stderrPipe.fileHandleForReading.readDataToEndOfFile()
    return ProcessResult(
        status: process.terminationStatus,
        stdout: String(decoding: stdoutData, as: UTF8.self),
        stderr: String(decoding: stderrData, as: UTF8.self)
    )
}

func runCapturedTUIProcess(
    executable: String,
    arguments: [String]
) throws -> ProcessResult {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardInput = FileHandle.standardInput

    let stdoutPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = FileHandle.standardError

    let ttyFD = STDIN_FILENO
    let hasTTY = isatty(ttyFD) == 1
    let originalForegroundPgrp = hasTTY ? tcgetpgrp(ttyFD) : -1
    let oldSIGTTOU = Darwin.signal(SIGTTOU, SIG_IGN)
    defer {
        _ = Darwin.signal(SIGTTOU, oldSIGTTOU)
    }

    try process.run()

    var movedToForeground = false
    let childPgrp = process.processIdentifier
    if hasTTY, originalForegroundPgrp > 0 {
        for _ in 0..<20 {
            if tcsetpgrp(ttyFD, childPgrp) == 0 {
                movedToForeground = true
                break
            }
            usleep(10_000)
        }

        if movedToForeground {
            _ = kill(-childPgrp, SIGCONT)
        } else {
            process.terminate()
            process.waitUntilExit()
            throw CLIError.message("无法把 TUI 子进程切到终端前台。")
        }
    }

    process.waitUntilExit()

    if movedToForeground {
        _ = tcsetpgrp(ttyFD, originalForegroundPgrp)
    }

    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    return ProcessResult(
        status: process.terminationStatus,
        stdout: String(decoding: stdoutData, as: UTF8.self),
        stderr: ""
    )
}

func parseGuwendaoEntryLinks(_ html: String, baseURL: URL) -> [GuwendaoPoemLink] {
    guard let mainRange = html.range(of: #"<div\s+class=["']main3["'][^>]*>"#, options: .regularExpression),
          let leftRange = html.range(
            of: #"<div\s+class=["']left["'][^>]*>"#,
            options: .regularExpression,
            range: mainRange.upperBound..<html.endIndex
          ),
          let leftHTML = balancedHTMLElement(in: html, openingTagRange: leftRange, tagName: "div") else {
        return []
    }

    let pattern = #"<a\b[^>]*href=["']([^"']*?/shiwenv_([0-9a-fA-F]+)\.aspx)["'][^>]*>(.*?)</a>"#
    let matches = regexMatches(pattern, in: leftHTML, options: [.caseInsensitive, .dotMatchesLineSeparators])
    var links: [GuwendaoPoemLink] = []
    var seenIDs = Set<String>()

    for match in matches {
        guard match.numberOfRanges >= 4,
              let hrefRange = Range(match.range(at: 1), in: leftHTML),
              let idRange = Range(match.range(at: 2), in: leftHTML),
              let titleRange = Range(match.range(at: 3), in: leftHTML) else {
            continue
        }

        let id = String(leftHTML[idRange]).lowercased()
        guard !seenIDs.contains(id) else {
            continue
        }
        let href = String(leftHTML[hrefRange])
        guard let url = URL(string: href, relativeTo: baseURL)?.absoluteURL else {
            continue
        }
        let title = htmlToSingleLineText(String(leftHTML[titleRange]))
        guard !title.isEmpty else {
            continue
        }

        links.append(GuwendaoPoemLink(id: id, entryTitle: title, url: url))
        seenIDs.insert(id)
    }

    return links
}

func parseGuwendaoPoemPage(_ html: String, link: GuwendaoPoemLink) throws -> GuwendaoPoemItem {
    let zhengwenHTML: String
    if let zhengwenRange = html.range(
        of: #"<div\s+id=["']zhengwen\#(NSRegularExpression.escapedPattern(for: link.id))["'][^>]*>"#,
        options: .regularExpression
    ), let extracted = balancedHTMLElement(in: html, openingTagRange: zhengwenRange, tagName: "div") {
        zhengwenHTML = extracted
    } else {
        zhengwenHTML = html
    }

    let title = firstRegexCapture(#"<h1\b[^>]*>(.*?)</h1>"#, in: zhengwenHTML)
        .map(htmlToSingleLineText) ?? link.entryTitle
    let sourceHTML = firstRegexCapture(#"<p\b[^>]*class=["'][^"']*\bsource\b[^"']*["'][^>]*>(.*?)</p>"#, in: zhengwenHTML) ?? ""
    let sourceParts = regexMatches(#"<a\b[^>]*>(.*?)</a>"#, in: sourceHTML, options: [.caseInsensitive, .dotMatchesLineSeparators])
        .compactMap { match -> String? in
            guard let range = Range(match.range(at: 1), in: sourceHTML) else {
                return nil
            }
            let text = htmlToSingleLineText(String(sourceHTML[range]))
                .trimmingCharacters(in: CharacterSet(charactersIn: "[]〔〕"))
            return text.isEmpty ? nil : text
        }
    let author = sourceParts.first ?? ""
    let dynasty = sourceParts.dropFirst().first ?? ""

    guard let contsonRange = html.range(
        of: #"<div\b[^>]*id=["']contson\#(NSRegularExpression.escapedPattern(for: link.id))["'][^>]*>"#,
        options: .regularExpression
    ), let contsonHTML = balancedHTMLElement(in: html, openingTagRange: contsonRange, tagName: "div") else {
        throw CLIError.message("无法从 \(link.url.absoluteString) 提取原文。")
    }

    let content = poemContentText(from: contsonHTML)
    guard !content.isEmpty else {
        throw CLIError.message("从 \(link.url.absoluteString) 提取到的原文为空。")
    }

    return GuwendaoPoemItem(
        id: link.id,
        title: title,
        entryTitle: link.entryTitle,
        author: author,
        dynasty: dynasty,
        url: link.url.absoluteString,
        content: content
    )
}

func poemContentText(from html: String) -> String {
    let paragraphs = regexMatches(#"<p\b[^>]*>(.*?)</p>"#, in: html, options: [.caseInsensitive, .dotMatchesLineSeparators])
        .compactMap { match -> String? in
            guard let range = Range(match.range(at: 1), in: html) else {
                return nil
            }
            let text = htmlToMultilineText(String(html[range]))
            return text.isEmpty ? nil : text
        }

    if !paragraphs.isEmpty {
        return paragraphs.joined(separator: "\n")
    }

    return htmlToMultilineText(html)
}

func bestPoemMatch(for rawQuery: String, in items: [GuwendaoPoemItem]) throws -> GuwendaoPoemItem {
    let query = normalizedPoemTitle(rawQuery)
    guard !query.isEmpty else {
        throw CLIError.message("标题不能为空。")
    }
    guard !items.isEmpty else {
        throw CLIError.message("古文池为空。")
    }

    let scored = items.map { item -> (item: GuwendaoPoemItem, score: Int) in
        let title = normalizedPoemTitle(item.title)
        let entryTitle = normalizedPoemTitle(item.entryTitle)
        let score = max(poemTitleScore(query: query, candidate: title), poemTitleScore(query: query, candidate: entryTitle))
        return (item, score)
    }
    guard let best = scored.max(by: { $0.score < $1.score }), best.score > 0 else {
        let candidates = items.prefix(5).map(\.title).joined(separator: "、")
        throw CLIError.message("没有找到匹配标题 '\(rawQuery)' 的古文。候选示例：\(candidates)")
    }
    return best.item
}

func poemTitleScore(query: String, candidate: String) -> Int {
    guard !query.isEmpty, !candidate.isEmpty else {
        return 0
    }
    if query == candidate {
        return 10_000 + candidate.count
    }
    if candidate.contains(query) {
        return 8_000 + query.count * 10 - abs(candidate.count - query.count)
    }
    if query.contains(candidate) {
        return 7_000 + candidate.count * 10 - abs(candidate.count - query.count)
    }
    let overlap = longestCommonSubsequenceLength(query, candidate)
    return overlap * 100 - abs(candidate.count - query.count)
}

func longestCommonSubsequenceLength(_ lhs: String, _ rhs: String) -> Int {
    let left = Array(lhs)
    let right = Array(rhs)
    guard !left.isEmpty, !right.isEmpty else {
        return 0
    }

    var previous = Array(repeating: 0, count: right.count + 1)
    var current = previous
    for leftIndex in left.indices {
        current[0] = 0
        for rightIndex in right.indices {
            if left[leftIndex] == right[rightIndex] {
                current[rightIndex + 1] = previous[rightIndex] + 1
            } else {
                current[rightIndex + 1] = max(previous[rightIndex + 1], current[rightIndex])
            }
        }
        swap(&previous, &current)
    }
    return previous[right.count]
}

func normalizedPoemTitle(_ title: String) -> String {
    htmlToSingleLineText(title)
        .filter { character in
            !character.unicodeScalars.allSatisfy { scalar in
                CharacterSet.whitespacesAndNewlines.contains(scalar)
                    || CharacterSet.punctuationCharacters.contains(scalar)
                    || CharacterSet.symbols.contains(scalar)
            }
        }
}

func balancedHTMLElement(in html: String, openingTagRange: Range<String.Index>, tagName: String) -> String? {
    let openPattern = "<\(tagName)\\b"
    let closePattern = "</\(tagName)>"
    var depth = 1
    var searchStart = openingTagRange.upperBound

    while searchStart < html.endIndex {
        let nextOpen = html.range(of: openPattern, options: [.regularExpression, .caseInsensitive], range: searchStart..<html.endIndex)
        let nextClose = html.range(of: closePattern, options: [.caseInsensitive], range: searchStart..<html.endIndex)

        guard let close = nextClose else {
            return nil
        }
        if let open = nextOpen, open.lowerBound < close.lowerBound {
            depth += 1
            searchStart = open.upperBound
            continue
        }

        depth -= 1
        searchStart = close.upperBound
        if depth == 0 {
            return String(html[openingTagRange.lowerBound..<close.upperBound])
        }
    }

    return nil
}

func firstRegexCapture(_ pattern: String, in text: String) -> String? {
    guard let match = regexMatches(pattern, in: text, options: [.caseInsensitive, .dotMatchesLineSeparators]).first,
          match.numberOfRanges >= 2,
          let range = Range(match.range(at: 1), in: text) else {
        return nil
    }
    return String(text[range])
}

func regexMatches(
    _ pattern: String,
    in text: String,
    options: NSRegularExpression.Options = []
) -> [NSTextCheckingResult] {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
        return []
    }
    return regex.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text))
}

func htmlToSingleLineText(_ html: String) -> String {
    htmlToMultilineText(html)
        .split(whereSeparator: \.isNewline)
        .map(String.init)
        .joined(separator: " ")
        .replacingOccurrences(of: #"[ \t\u{00a0}\u{3000}]+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

func htmlToMultilineText(_ html: String) -> String {
    var text = normalizedLineEndings(html)
    text = text.replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression)
    text = text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
    text = decodeHTMLEntities(text)
    let lines = text
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map { line in
            String(line)
                .replacingOccurrences(of: #"[ \t\u{00a0}\u{3000}]+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .filter { !$0.isEmpty }
    return lines.joined(separator: "\n")
}

func decodeHTMLEntities(_ value: String) -> String {
    var text = value
        .replacingOccurrences(of: "&nbsp;", with: " ")
        .replacingOccurrences(of: "&amp;", with: "&")
        .replacingOccurrences(of: "&lt;", with: "<")
        .replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&quot;", with: "\"")
        .replacingOccurrences(of: "&#39;", with: "'")
        .replacingOccurrences(of: "&apos;", with: "'")

    let pattern = #"&#(x?[0-9a-fA-F]+);"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
        return text
    }
    let matches = regex.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)).reversed()
    for match in matches {
        guard match.numberOfRanges >= 2,
              let fullRange = Range(match.range(at: 0), in: text),
              let numberRange = Range(match.range(at: 1), in: text) else {
            continue
        }
        let rawNumber = String(text[numberRange])
        let scalarValue: UInt32?
        if rawNumber.lowercased().hasPrefix("x") {
            scalarValue = UInt32(rawNumber.dropFirst(), radix: 16)
        } else {
            scalarValue = UInt32(rawNumber, radix: 10)
        }
        if let scalarValue, let scalar = UnicodeScalar(scalarValue) {
            text.replaceSubrange(fullRange, with: String(Character(scalar)))
        }
    }
    return text
}

func recitePlainText(_ options: ReciteOptions) throws {
    let inputText = try options.inputs
        .map(readRecitationInput)
        .joined(separator: "\n")
    var segments = balanceRecitationSegments(
        splitRecitationText(inputText, delimiters: options.delimiters),
        minCharacters: options.minCharacters,
        preferredMaxCharacters: options.preferredMaxCharacters
    )
    if let limit = options.limit {
        segments = Array(segments.prefix(limit))
    }
    guard !segments.isEmpty else {
        throw CLIError.message("没有可背诵的文本片段。")
    }

    let lines = segments.enumerated().map { index, segment in
        let start = TimeInterval(index) * options.interval
        return TimedTextLine(
            start: start,
            end: start + options.interval,
            text: segment
        )
    }
    let source = options.source ?? defaultRecitationSource(from: options.inputs)
    let track = SubtitlePlaybackTrack(
        source: source,
        title: source,
        stackIndex: nil,
        lines: lines
    )

    if options.dryRun {
        print("按分隔符「\(options.delimiters)」初拆并均衡组合后得到 \(lines.count) 句，min=\(options.minCharacters) 字，max≈\(options.preferredMaxCharacters) 字，interval=\(formatSeconds(options.interval)) 秒，source='\(source)'：")
        for line in lines {
            print("[\(formatTimedTextTimestamp(line.start))] \(line.text)")
        }
        return
    }

    var playbackOptions = PlayOptions()
    playbackOptions.speed = options.speed
    playbackOptions.limit = options.limit
    playbackOptions.clearWhenFinished = options.clearWhenFinished
    playbackOptions.displayOptions = options.displayOptions

    print("正在用 lyric 样式按 \(formatSeconds(options.interval)) 秒间隔背诵 \(lines.count) 句：\(source)。")
    try playSubtitleTracks([track], baseOptions: playbackOptions, stackGroup: nil)
}

func balanceRecitationSegments(
    _ segments: [String],
    minCharacters: Int,
    preferredMaxCharacters: Int
) -> [String] {
    let count = segments.count
    guard count > 0 else {
        return []
    }

    let lengths = segments.map(recitationCharacterCount)
    var prefixLengths = Array(repeating: 0, count: count + 1)
    var strongBreakPrefix = Array(repeating: 0, count: count + 1)
    for index in 0..<count {
        prefixLengths[index + 1] = prefixLengths[index] + lengths[index]
        strongBreakPrefix[index + 1] = strongBreakPrefix[index] + (recitationSegmentEndsWithStrongBreak(segments[index]) ? 1 : 0)
    }

    let targetCharacters = Double(minCharacters + preferredMaxCharacters) / 2.0
    var bestCosts = Array(repeating: Double.greatestFiniteMagnitude, count: count + 1)
    var nextBreaks = Array(repeating: count, count: count + 1)
    bestCosts[count] = 0.0

    for start in stride(from: count - 1, through: 0, by: -1) {
        for end in (start + 1)...count {
            let segmentLength = prefixLengths[end] - prefixLengths[start]
            let internalStrongBreaks = strongBreakPrefix[end - 1] - strongBreakPrefix[start]
            let cost = balancedRecitationSegmentCost(
                length: segmentLength,
                internalStrongBreakCount: internalStrongBreaks,
                minCharacters: minCharacters,
                preferredMaxCharacters: preferredMaxCharacters,
                targetCharacters: targetCharacters
            ) + bestCosts[end]

            if cost < bestCosts[start] {
                bestCosts[start] = cost
                nextBreaks[start] = end
            }

            if segmentLength > preferredMaxCharacters + minCharacters,
               end > start + 1 {
                break
            }
        }
    }

    var balanced: [String] = []
    var index = 0
    while index < count {
        let next = max(index + 1, nextBreaks[index])
        balanced.append(segments[index..<next].joined())
        index = next
    }
    return balanced
}

func balancedRecitationSegmentCost(
    length: Int,
    internalStrongBreakCount: Int,
    minCharacters: Int,
    preferredMaxCharacters: Int,
    targetCharacters: Double
) -> Double {
    let distance = Double(length) - targetCharacters
    var cost = distance * distance

    if length < minCharacters {
        let shortage = Double(minCharacters - length)
        cost += shortage * shortage * 18.0 + 20.0
    }

    if length > preferredMaxCharacters {
        let excess = Double(length - preferredMaxCharacters)
        cost += excess * excess * 24.0 + 40.0
    }

    cost += Double(internalStrongBreakCount) * 90.0
    return cost
}

func readRecitationInput(_ input: ReciteInput) throws -> String {
    switch input {
    case .text(let text):
        return text

    case .file(let path):
        let fileURL = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        do {
            return try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            return try String(contentsOf: fileURL)
        }

    case .standardInput:
        let data = FileHandle.standardInput.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
    }
}

func defaultRecitationSource(from inputs: [ReciteInput]) -> String {
    if inputs.count == 1,
       case .file(let path) = inputs[0] {
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath).lastPathComponent
    }
    return "古诗词背诵"
}

func splitRecitationText(_ text: String, delimiters: String) -> [String] {
    let delimiterSet = Set(delimiters)
    let closingPunctuation = Set("”’」』》〉）)]】")
    let characters = Array(normalizedLineEndings(text))
    var segments: [String] = []
    var current = ""
    var index = 0

    while index < characters.count {
        let character = characters[index]
        if isRecitationWhitespace(character) {
            if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !current.hasSuffix(" ") {
                current.append(" ")
            }
        } else {
            current.append(character)
        }

        if delimiterSet.contains(character) {
            var lookahead = index + 1
            while lookahead < characters.count,
                  closingPunctuation.contains(characters[lookahead]) {
                current.append(characters[lookahead])
                lookahead += 1
            }
            appendRecitationSegment(current, to: &segments)
            current.removeAll(keepingCapacity: true)
            index = lookahead
        } else {
            index += 1
        }
    }

    appendRecitationSegment(current, to: &segments)
    return segments
}

func appendRecitationSegment(_ rawValue: String, to segments: inout [String]) {
    let segment = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !segment.isEmpty else {
        return
    }
    segments.append(segment)
}

func recitationCharacterCount(_ text: String) -> Int {
    text.reduce(0) { count, character in
        if isRecitationWhitespace(character) || isRecitationPunctuation(character) {
            return count
        }
        return count + 1
    }
}

func recitationSegmentEndsWithStrongBreak(_ text: String) -> Bool {
    guard let last = text.trimmingCharacters(in: .whitespacesAndNewlines).last else {
        return false
    }
    return Set("。！？；;.!?").contains(last)
}

func isRecitationWhitespace(_ character: Character) -> Bool {
    character.unicodeScalars.allSatisfy { scalar in
        CharacterSet.whitespacesAndNewlines.contains(scalar)
    }
}

func isRecitationPunctuation(_ character: Character) -> Bool {
    character.unicodeScalars.allSatisfy { scalar in
        CharacterSet.punctuationCharacters.contains(scalar)
            || CharacterSet.symbols.contains(scalar)
    }
}

func formatSeconds(_ value: TimeInterval) -> String {
    if abs(value.rounded() - value) < 0.001 {
        return String(Int(value.rounded()))
    }
    return String(format: "%.2f", value)
}

func playTimedText(_ options: PlayOptions) throws {
    let fileURLs = options.filePaths.map { path in
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }
    let videoURLs = fileURLs.filter(isVideoContainer)

    if fileURLs.count == 1, let fileURL = fileURLs.first, isVideoContainer(fileURL) {
        try playVideoSubtitles(options, fileURL: fileURL)
        return
    }

    if !videoURLs.isEmpty {
        throw CLIError.message("一次 play 只能传入一个视频文件；多个位置参数仅支持 LRC/SRT 等文本字幕文件。")
    }

    if options.listSubtitlesOnly {
        throw CLIError.message("--list-subtitles 只适用于视频容器文件。")
    }
    if !options.streamIndices.isEmpty {
        throw CLIError.message("--stream 只适用于视频容器文件。")
    }
    if options.warmCacheOnly || options.refreshCache || !options.useCache {
        throw CLIError.message("--no-cache、--refresh-cache、--warm-cache 只适用于视频容器字幕抽取。")
    }

    try playTextSubtitleFiles(options, fileURLs: fileURLs)
}

func playTextSubtitleFiles(_ options: PlayOptions, fileURLs: [URL]) throws {
    var tracks: [SubtitlePlaybackTrack] = []
    for (orderIndex, fileURL) in fileURLs.enumerated() {
        let source: String
        if let providedSource = options.source {
            source = fileURLs.count == 1 ? providedSource : "\(providedSource)::\(fileURL.lastPathComponent)"
        } else {
            source = fileURL.lastPathComponent
        }
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CLIError.message("Cannot infer source name from file path: \(fileURL.path).")
        }

        var lines = try loadTimedTextLines(from: fileURL)
        if let limit = options.limit {
            lines = Array(lines.prefix(limit))
        }
        guard !lines.isEmpty else {
            throw CLIError.message("No timed text lines found in \(fileURL.path).")
        }

        let stackIndex = fileURLs.count > 1 ? fileURLs.count - 1 - orderIndex : nil
        tracks.append(SubtitlePlaybackTrack(
            source: source,
            title: fileURL.lastPathComponent,
            stackIndex: stackIndex,
            lines: lines
        ))
    }

    if tracks.count == 1 {
        print("正在用 lyric 样式播放 \(tracks[0].lines.count) 行定时文本：\(tracks[0].title)，source='\(tracks[0].source)'。")
    } else {
        print("正在用 lyric 样式播放 \(tracks.count) 个定时文本文件。显示顺序为从上到下：\(tracks.map(\.title).joined(separator: " / "))")
    }

    let stackGroup = tracks.count > 1
        ? "files:\(stableSourceHash(fileURLs.map(\.path).joined(separator: "|")))"
        : nil
    try playSubtitleTracks(tracks, baseOptions: options, stackGroup: stackGroup)
}

func displayDuration(for line: TimedTextLine, nextStart: TimeInterval?, speed: Double) -> TimeInterval {
    let sourceDuration: TimeInterval
    if let end = line.end, end > line.start {
        sourceDuration = end - line.start
    } else if let nextStart, nextStart > line.start {
        sourceDuration = nextStart - line.start
    } else {
        sourceDuration = 3.0
    }

    return max(0.45, sourceDuration / speed + 0.15)
}

func formatTimedTextTimestamp(_ value: TimeInterval) -> String {
    let totalCentiseconds = max(0, Int((value * 100).rounded()))
    let centiseconds = totalCentiseconds % 100
    let totalSeconds = totalCentiseconds / 100
    let seconds = totalSeconds % 60
    let totalMinutes = totalSeconds / 60
    let minutes = totalMinutes % 60
    let hours = totalMinutes / 60
    if hours > 0 {
        return String(format: "%02d:%02d:%02d.%02d", hours, minutes, seconds, centiseconds)
    }
    return String(format: "%02d:%02d.%02d", minutes, seconds, centiseconds)
}

func loadTimedTextLines(from fileURL: URL) throws -> [TimedTextLine] {
    let text: String
    do {
        text = try String(contentsOf: fileURL, encoding: .utf8)
    } catch {
        text = try String(contentsOf: fileURL)
    }
    let ext = fileURL.pathExtension.lowercased()
    let lines: [TimedTextLine]

    switch ext {
    case "lrc":
        lines = parseLRC(text)
    case "srt":
        lines = parseSRT(text)
    default:
        let lrcLines = parseLRC(text)
        lines = lrcLines.isEmpty ? parseSRT(text) : lrcLines
    }

    return mergeTimedTextLines(lines)
}

func parseLRC(_ text: String) -> [TimedTextLine] {
    let normalized = normalizedLineEndings(text)
    var timedLines: [TimedTextLine] = []

    for rawLine in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
        let line = String(rawLine)
        let tags = lrcTimestampTags(in: line)
        guard !tags.isEmpty else {
            continue
        }

        var pendingTimes: [TimeInterval] = []
        for index in tags.indices {
            let tag = tags[index]
            pendingTimes.append(tag.time)

            let contentStart = tag.end
            let contentEnd = index + 1 < tags.count ? tags[index + 1].start : line.endIndex
            let content = cleanTimedText(String(line[contentStart..<contentEnd]))
            guard !content.isEmpty else {
                continue
            }

            for time in pendingTimes {
                timedLines.append(TimedTextLine(start: time, end: nil, text: content))
            }
            pendingTimes.removeAll()
        }
    }

    return timedLines.sorted { $0.start < $1.start }
}

func lrcTimestampTags(in line: String) -> [(start: String.Index, end: String.Index, time: TimeInterval)] {
    var tags: [(start: String.Index, end: String.Index, time: TimeInterval)] = []
    var searchStart = line.startIndex

    while searchStart < line.endIndex,
          let open = line[searchStart...].firstIndex(of: "["),
          let close = line[open...].firstIndex(of: "]") {
        let tagStart = line.index(after: open)
        let tag = String(line[tagStart..<close])
        if let time = parseLRCTimestamp(tag) {
            tags.append((start: open, end: line.index(after: close), time: time))
        }
        searchStart = line.index(after: close)
    }

    return tags
}

func parseLRCTimestamp(_ rawValue: String) -> TimeInterval? {
    let parts = rawValue.split(separator: ":")
    guard parts.count == 2 || parts.count == 3 else {
        return nil
    }

    guard let secondsText = parts.last,
          let seconds = Double(secondsText) else {
        return nil
    }

    if parts.count == 2 {
        guard let minutes = Double(parts[0]) else {
            return nil
        }
        return minutes * 60.0 + seconds
    }

    guard let hours = Double(parts[0]),
          let minutes = Double(parts[1]) else {
        return nil
    }
    return hours * 3600.0 + minutes * 60.0 + seconds
}

func parseSRT(_ text: String) -> [TimedTextLine] {
    let normalized = normalizedLineEndings(text)
    let blocks = splitSubtitleBlocks(normalized)
    var timedLines: [TimedTextLine] = []

    for block in blocks {
        if let line = parseSRTBlock(block) {
            timedLines.append(line)
        }
    }

    return timedLines.sorted { $0.start < $1.start }
}

func parseSRTBlock(_ block: String) -> TimedTextLine? {
    let normalized = normalizedLineEndings(block)
    let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    guard let timingIndex = lines.firstIndex(where: { $0.contains("-->") }) else {
        return nil
    }

    let timingParts = lines[timingIndex].components(separatedBy: "-->")
    guard timingParts.count >= 2,
          let start = parseSRTTimestamp(timingParts[0]),
          let end = parseSRTTimestamp(timingParts[1]) else {
        return nil
    }

    let content = lines.dropFirst(timingIndex + 1)
        .map(cleanTimedText)
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
    guard !content.isEmpty else {
        return nil
    }

    return TimedTextLine(start: start, end: end, text: content)
}

func firstSRTBlockSeparator(in data: Data) -> Range<Data.Index>? {
    guard data.count >= 2 else {
        return nil
    }

    var index = data.startIndex
    while index < data.endIndex {
        let next = data.index(after: index)
        if next < data.endIndex,
           data[index] == 10,
           data[next] == 10 {
            return index..<data.index(after: next)
        }

        if data[index] == 13,
           next < data.endIndex,
           data[next] == 10 {
            let third = data.index(after: next)
            if third < data.endIndex,
               data[third] == 13 {
                let fourth = data.index(after: third)
                if fourth < data.endIndex,
                   data[fourth] == 10 {
                    return index..<data.index(after: fourth)
                }
            }
        }

        index = data.index(after: index)
    }

    return nil
}

func parseSRTTimestamp(_ rawValue: String) -> TimeInterval? {
    let cleaned = rawValue
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .components(separatedBy: CharacterSet.whitespaces)
        .first ?? ""
    let normalized = cleaned.replacingOccurrences(of: ",", with: ".")
    let parts = normalized.split(separator: ":")
    guard parts.count == 3,
          let hours = Double(parts[0]),
          let minutes = Double(parts[1]),
          let seconds = Double(parts[2]) else {
        return nil
    }

    return hours * 3600.0 + minutes * 60.0 + seconds
}

func splitSubtitleBlocks(_ text: String) -> [String] {
    var blocks: [String] = []
    var current: [String] = []

    for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
        if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if !current.isEmpty {
                blocks.append(current.joined(separator: "\n"))
                current.removeAll()
            }
        } else {
            current.append(line)
        }
    }

    if !current.isEmpty {
        blocks.append(current.joined(separator: "\n"))
    }

    return blocks
}

func normalizedLineEndings(_ text: String) -> String {
    text
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
}

func cleanTimedText(_ rawValue: String) -> String {
    var text = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    text = text.replacingOccurrences(of: #"(<[^>]+>)"#, with: "", options: .regularExpression)
    text = text.replacingOccurrences(of: #"\{[^}]+\}"#, with: "", options: .regularExpression)
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
}

func mergeTimedTextLines(_ lines: [TimedTextLine]) -> [TimedTextLine] {
    let sorted = lines
        .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .sorted { lhs, rhs in
            if lhs.start == rhs.start {
                return (lhs.end ?? lhs.start) < (rhs.end ?? rhs.start)
            }
            return lhs.start < rhs.start
        }

    var merged: [TimedTextLine] = []
    for line in sorted {
        if let last = merged.last,
           abs(last.start - line.start) < 0.001,
           abs((last.end ?? -1.0) - (line.end ?? -1.0)) < 0.001 {
            merged.removeLast()
            merged.append(TimedTextLine(
                start: last.start,
                end: last.end,
                text: [last.text, line.text].joined(separator: "\n")
            ))
        } else {
            merged.append(line)
        }
    }

    return merged
}

@main
struct OsdNotifyApp {
    @MainActor
    static func main() {
        do {
            let command = try parseCommand()

            switch command {
            case .daemon:
                runDaemon()
                return

            case .clear(let options):
                do {
                    let response = try sendDaemonRequest(.clear(options), autostart: false)
                    if !response.message.isEmpty {
                        print(response.message)
                    }
                    if !response.ok {
                        exit(1)
                    }
                } catch {
                    if options.all {
                        clearAllOverlays(quiet: false)
                    } else {
                        clearExistingOverlay(source: options.source, quiet: false)
                    }
                }
                return

            case .show(let options):
                let response = try sendDaemonRequest(.show(options), autostart: true)
                if !response.ok {
                    throw CLIError.message(response.message)
                }
                return

            case .play(let options):
                try playTimedText(options)
                return

            case .recite(let options):
                try recitePlainText(options)
                return
            }
        } catch {
            fputs("osd-notify: \(error)\n\n", stderr)
            printUsage()
            exit(2)
        }
    }

    @MainActor
    private static func runDaemon() {
        let app = NSApplication.shared
        let delegate = DaemonAppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        _ = delegate
    }
}
