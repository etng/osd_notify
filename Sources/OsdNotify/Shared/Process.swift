import Foundation
import Darwin

struct ProcessResult {
    let status: Int32
    let stdout: String
    let stderr: String
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
