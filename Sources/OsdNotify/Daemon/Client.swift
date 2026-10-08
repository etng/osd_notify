import Foundation
import Darwin

let stateDirectoryURL: URL = {
    if let override = ProcessInfo.processInfo.environment["OSD_NOTIFY_STATE_DIRECTORY"]?
        .trimmingCharacters(in: .whitespacesAndNewlines),
       !override.isEmpty {
        return URL(fileURLWithPath: override, isDirectory: true).standardizedFileURL
    }
    return FileManager.default.temporaryDirectory.appendingPathComponent("osd-notify", isDirectory: true)
}()
let placementDirectoryURL = stateDirectoryURL.appendingPathComponent("placements", isDirectory: true)
let legacyPIDFileURL = FileManager.default.temporaryDirectory.appendingPathComponent("osd-notify.pid")
let daemonSocketURL = stateDirectoryURL.appendingPathComponent("daemon.sock")
let daemonPIDFileURL = stateDirectoryURL.appendingPathComponent("daemon.pid")
let daemonRestartLockFileURL = stateDirectoryURL.appendingPathComponent("daemon.restart.lock")
let socketRetryDelay: TimeInterval = 0.05
func daemonPIDFileBelongsToCurrentProcess() -> Bool {
    guard let pidText = try? String(contentsOf: daemonPIDFileURL, encoding: .utf8) else {
        return false
    }
    return Int32(pidText.trimmingCharacters(in: .whitespacesAndNewlines)) == getpid()
}

func removeDaemonPIDFileIfOwned() {
    guard daemonPIDFileBelongsToCurrentProcess() else {
        return
    }
    try? FileManager.default.removeItem(at: daemonPIDFileURL)
}
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

    return try withDaemonRestartLock {
        do {
            return try sendDaemonRequestOnce(request)
        } catch {
            appendDiagnosticEvent("daemon-restart-confirmed")
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
}

func withDaemonRestartLock<T>(_ operation: () throws -> T) throws -> T {
    ensureStateDirectory()
    let descriptor = open(
        daemonRestartLockFileURL.path,
        O_RDWR | O_CREAT,
        S_IRUSR | S_IWUSR
    )
    guard descriptor >= 0 else {
        throw CLIError.message("Failed to open daemon restart lock: errno \(errno).")
    }
    defer {
        _ = flock(descriptor, LOCK_UN)
        close(descriptor)
    }

    guard flock(descriptor, LOCK_EX) == 0 else {
        throw CLIError.message("Failed to lock daemon restart: errno \(errno).")
    }
    return try operation()
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
    appendDiagnosticEvent("daemon-spawned", detail: "pid=\(process.processIdentifier)")
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
    appendDiagnosticEvent("daemon-restart-requested", detail: "pid=\(pid)")
    let deadline = Date().addingTimeInterval(1.0)
    while Date() < deadline {
        if !isProcessAlive(pid_t(pid)) {
            break
        }
        Thread.sleep(forTimeInterval: 0.05)
    }
    try? FileManager.default.removeItem(at: daemonPIDFileURL)
}

func isProcessAlive(_ pid: pid_t) -> Bool {
    errno = 0
    if kill(pid, 0) == 0 {
        return true
    }
    return errno == EPERM
}
