import AppKit
import QuartzCore

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

        case .ping:
            return DaemonResponse(ok: true, message: "ok")
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
            options: options,
            closeAction: { [weak self] in
                self?.dismiss(animated: true, notify: true)
            }
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

let stackSpacing: CGFloat = 12.0
let overlayFadeInDuration: TimeInterval = 0.16
let overlayFadeOutDuration: TimeInterval = 0.18
