import AppKit
import Darwin

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
