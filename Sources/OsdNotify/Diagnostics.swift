import Darwin
import Foundation

private let diagnosticLogDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Logs/osd-notify", isDirectory: true)
private let diagnosticLogURL = diagnosticLogDirectoryURL.appendingPathComponent("events.jsonl")
private let diagnosticLogBackupURL = diagnosticLogDirectoryURL.appendingPathComponent("events.previous.jsonl")
private let diagnosticLogMaximumBytes: UInt64 = 1_048_576

struct DiagnosticRecord: Codable {
    let timestamp: String
    let version: String
    let pid: Int32
    let event: String
    let source: String?
    let messageCharacters: Int?
    let messageContainsDoubleDash: Bool?
    let arguments: [String]?
    let detail: String?
}

func appendDiagnosticEvent(
    _ event: String,
    source: String? = nil,
    message: String? = nil,
    arguments: [String]? = nil,
    detail: String? = nil
) {
    let record = DiagnosticRecord(
        timestamp: ISO8601DateFormatter().string(from: Date()),
        version: AppVersion.currentString,
        pid: getpid(),
        event: event,
        source: source,
        messageCharacters: message?.count,
        messageContainsDoubleDash: message?.contains("--"),
        arguments: arguments,
        detail: detail
    )

    guard let data = try? JSONEncoder().encode(record) else {
        return
    }

    do {
        try FileManager.default.createDirectory(
            at: diagnosticLogDirectoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: diagnosticLogDirectoryURL.path
        )
        rotateDiagnosticLogIfNeeded()

        let descriptor = open(diagnosticLogURL.path, O_WRONLY | O_CREAT | O_APPEND, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            return
        }
        defer {
            close(descriptor)
        }

        var line = data
        line.append(0x0A)
        _ = writeAll(line, to: descriptor)
    } catch {
        return
    }
}

private func rotateDiagnosticLogIfNeeded() {
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: diagnosticLogURL.path),
          let fileSize = attributes[.size] as? NSNumber,
          fileSize.uint64Value >= diagnosticLogMaximumBytes else {
        return
    }

    try? FileManager.default.removeItem(at: diagnosticLogBackupURL)
    try? FileManager.default.moveItem(at: diagnosticLogURL, to: diagnosticLogBackupURL)
}

func printRecentDiagnosticEvents(limit: Int = 100) {
    guard let data = try? Data(contentsOf: diagnosticLogURL),
          let text = String(data: data, encoding: .utf8) else {
        print("暂无诊断事件。")
        return
    }

    let lines = text.split(separator: "\n").suffix(limit)
    if lines.isEmpty {
        print("暂无诊断事件。")
        return
    }

    let decoder = JSONDecoder()
    for line in lines {
        guard let record = try? decoder.decode(DiagnosticRecord.self, from: Data(line.utf8)) else {
            continue
        }

        var fields = [record.timestamp, record.event, "pid=\(record.pid)"]
        if let source = record.source {
            fields.append("source=\(source)")
        }
        if let characters = record.messageCharacters {
            fields.append("chars=\(characters)")
        }
        if record.messageContainsDoubleDash == true {
            fields.append("contains-double-dash=yes")
        }
        if let arguments = record.arguments,
           let encodedArguments = try? JSONEncoder().encode(arguments),
           let argumentText = String(data: encodedArguments, encoding: .utf8) {
            fields.append("args=\(argumentText)")
        }
        if let detail = record.detail {
            fields.append("detail=\(detail)")
        }
        print(fields.joined(separator: "  "))
    }
}

func runningDaemonProcessIDs() -> [Int32] {
    guard let pgrepExecutable = findExecutable("pgrep"),
          let result = try? runCapturedProcess(
              executable: pgrepExecutable,
              arguments: ["-f", "osd-notify --daemon$"]
          ),
          result.status == 0 else {
        return []
    }

    return result.stdout
        .split(whereSeparator: \.isWhitespace)
        .compactMap { Int32($0) }
        .sorted()
}

func printRuntimeStatus() {
    printVersion()

    let processIDs = runningDaemonProcessIDs()
    if processIDs.isEmpty {
        print("守护进程：未运行")
    } else if processIDs.count == 1 {
        print("守护进程：运行中（PID \(processIDs[0])）")
    } else {
        print("守护进程：检测到 \(processIDs.count) 个（PID \(processIDs.map(String.init).joined(separator: ", "))）")
        print("建议更新后重新启动，清理旧版本遗留进程。")
    }

    do {
        let response = try sendDaemonRequest(.ping(), autostart: false)
        print(response.ok ? "本地服务：可用" : "本地服务：可连接，但响应异常")
    } catch {
        print("本地服务：不可用")
    }
}
