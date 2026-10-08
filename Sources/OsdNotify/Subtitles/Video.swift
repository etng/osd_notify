import Foundation
import Darwin

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
