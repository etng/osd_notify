import AppKit
import Darwin

@MainActor
final class DaemonAppDelegate: NSObject, NSApplicationDelegate {
    private let manager = OverlayManager()
    private lazy var server = DaemonServer(manager: manager)

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try server.start()
        } catch {
            appendDiagnosticEvent("daemon-start-failed", detail: "server-start")
            fputs("osd-notify daemon: \(error)\n", stderr)
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        server.stop()
        manager.clearManagedOverlays()
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
        appendDiagnosticEvent("daemon-started")

        queue.async { [weak self] in
            self?.acceptLoop()
        }
    }

    func stop() {
        isRunning = false
        let ownsState = daemonPIDFileBelongsToCurrentProcess()
        if serverFD >= 0 {
            close(serverFD)
            serverFD = -1
        }
        if ownsState {
            try? FileManager.default.removeItem(at: daemonSocketURL)
        }
        removeDaemonPIDFileIfOwned()
        appendDiagnosticEvent("daemon-stopped")
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
