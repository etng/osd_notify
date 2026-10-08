import Foundation

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
