import Foundation
import Darwin

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
