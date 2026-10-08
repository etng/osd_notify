import AppKit
import QuartzCore

final class OverlayView: NSView {
    private let contentView: OverlayContentView
    private var effectView: NSVisualEffectView?

    init(
        frame: NSRect,
        title: String,
        message: String,
        level: NoticeLevel,
        options: Options,
        closeAction: @escaping () -> Void
    ) {
        contentView = OverlayContentView(
            frame: frame,
            title: title,
            message: message,
            level: level,
            options: options,
            closeAction: closeAction
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

struct OverlayCloseAffordance {
    static let closeButtonSize: CGFloat = 24.0
    static let closeButtonTrailingInset: CGFloat = 20.0
    static let closeButtonTopInset: CGFloat = 20.0
    static let titleHitVerticalPadding: CGFloat = 6.0
    static let closeButtonRevealDuration: TimeInterval = 6.0

    static func closeButtonRect(in bounds: NSRect) -> NSRect {
        NSRect(
            x: bounds.maxX - closeButtonTrailingInset - closeButtonSize,
            y: bounds.maxY - closeButtonTopInset - closeButtonSize,
            width: closeButtonSize,
            height: closeButtonSize
        )
    }

    static func titleHitRect(
        contentRect: NSRect,
        titleY: CGFloat,
        titleHeight: CGFloat,
        textX: CGFloat,
        textWidth: CGFloat
    ) -> NSRect {
        let minY = max(contentRect.minY, titleY - titleHitVerticalPadding)
        let maxY = min(contentRect.maxY, titleY + titleHeight + titleHitVerticalPadding)
        return NSRect(
            x: textX,
            y: minY,
            width: textWidth,
            height: max(0.0, maxY - minY)
        )
    }
}

struct OverlayLinkAffordance {
    static let linkButtonSize: CGFloat = 24.0
    static let linkButtonTrailingInset: CGFloat = 20.0
    static let linkButtonBottomInset: CGFloat = 20.0

    static func linkButtonRect(in bounds: NSRect) -> NSRect {
        NSRect(
            x: bounds.maxX - linkButtonTrailingInset - linkButtonSize,
            y: bounds.minY + linkButtonBottomInset,
            width: linkButtonSize,
            height: linkButtonSize
        )
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
    private let linkURL: URL?
    private let closeAction: () -> Void
    private var isCloseButtonVisible = false
    private var closeButtonHideTimer: Timer?
    private var lastTitleHitRect: NSRect = .zero

    init(
        frame: NSRect,
        title: String,
        message: String,
        level: NoticeLevel,
        options: Options,
        closeAction: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.level = level
        self.options = options
        self.linkURL = Self.validatedLinkURL(options.linkURL)
        self.closeAction = closeAction
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
        let point = convert(event.locationInWindow, from: nil)
        if let linkURL,
           OverlayLinkAffordance.linkButtonRect(in: bounds).contains(point) {
            NSWorkspace.shared.open(linkURL)
            return
        }

        if isCloseButtonVisible,
           OverlayCloseAffordance.closeButtonRect(in: bounds).contains(point) {
            closeButtonHideTimer?.invalidate()
            closeButtonHideTimer = nil
            closeAction()
            return
        }

        if event.clickCount >= 2,
           lastTitleHitRect.contains(point) {
            revealCloseButton()
            return
        }

        window?.performDrag(with: event)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            closeButtonHideTimer?.invalidate()
            closeButtonHideTimer = nil
        }
        super.viewWillMove(toWindow: newWindow)
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
        lastTitleHitRect = OverlayCloseAffordance.titleHitRect(
            contentRect: rect,
            titleY: y,
            titleHeight: ceil(titleSize.height),
            textX: textX,
            textWidth: textWidth
        )

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

        if isCloseButtonVisible {
            drawCloseButton()
        }
        if linkURL != nil {
            drawLinkButton()
        }
    }

    private func revealCloseButton() {
        isCloseButtonVisible = true
        needsDisplay = true
        closeButtonHideTimer?.invalidate()
        closeButtonHideTimer = Timer.scheduledTimer(withTimeInterval: OverlayCloseAffordance.closeButtonRevealDuration, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.isCloseButtonVisible = false
                self?.needsDisplay = true
            }
        }
    }

    private func drawCloseButton() {
        let rect = OverlayCloseAffordance.closeButtonRect(in: bounds)
        let path = NSBezierPath(ovalIn: rect)
        NSColor(calibratedWhite: 0.0, alpha: 0.58).setFill()
        path.fill()
        NSColor(calibratedWhite: 1.0, alpha: 0.24).setStroke()
        path.lineWidth = 1.0
        path.stroke()

        let inset: CGFloat = 7.0
        let linePath = NSBezierPath()
        linePath.move(to: NSPoint(x: rect.minX + inset, y: rect.minY + inset))
        linePath.line(to: NSPoint(x: rect.maxX - inset, y: rect.maxY - inset))
        linePath.move(to: NSPoint(x: rect.maxX - inset, y: rect.minY + inset))
        linePath.line(to: NSPoint(x: rect.minX + inset, y: rect.maxY - inset))
        NSColor(calibratedWhite: 1.0, alpha: 0.92).setStroke()
        linePath.lineWidth = 2.0
        linePath.lineCapStyle = .round
        linePath.stroke()
    }

    private func drawLinkButton() {
        let rect = OverlayLinkAffordance.linkButtonRect(in: bounds)
        let path = NSBezierPath(ovalIn: rect)
        NSColor(calibratedWhite: 0.0, alpha: 0.48).setFill()
        path.fill()
        NSColor(calibratedWhite: 1.0, alpha: 0.22).setStroke()
        path.lineWidth = 1.0
        path.stroke()

        let iconRect = rect.insetBy(dx: 6.0, dy: 6.0)
        let arrowPath = NSBezierPath()
        arrowPath.move(to: NSPoint(x: iconRect.minX + 1.0, y: iconRect.minY + 1.0))
        arrowPath.line(to: NSPoint(x: iconRect.maxX - 1.0, y: iconRect.maxY - 1.0))
        arrowPath.move(to: NSPoint(x: iconRect.maxX - 1.0, y: iconRect.maxY - 1.0))
        arrowPath.line(to: NSPoint(x: iconRect.maxX - 1.0, y: iconRect.midY + 1.0))
        arrowPath.move(to: NSPoint(x: iconRect.maxX - 1.0, y: iconRect.maxY - 1.0))
        arrowPath.line(to: NSPoint(x: iconRect.midX + 1.0, y: iconRect.maxY - 1.0))
        NSColor(calibratedWhite: 1.0, alpha: 0.92).setStroke()
        arrowPath.lineWidth = 2.0
        arrowPath.lineCapStyle = .round
        arrowPath.lineJoinStyle = .round
        arrowPath.stroke()
    }

    private static func validatedLinkURL(_ rawValue: String?) -> URL? {
        guard let rawValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawValue.isEmpty,
              let url = URL(string: rawValue),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else {
            return nil
        }
        return url
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
