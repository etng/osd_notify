import Foundation
import Darwin

func printSubtitleStreams(_ streams: [SubtitleStream]) {
    guard !streams.isEmpty else {
        print("未检测到内封字幕流。")
        return
    }

    print("检测到 \(streams.count) 条内封字幕流：")
    var displayIndex = 1
    for stream in streams {
        let status = stream.isTextConvertible ? "可展示" : "跳过"
        let reason = stream.isTextConvertible ? "" : "；非文本字幕，不能直接转成 SRT/LRC 显示"
        let prefix: String
        if stream.isTextConvertible {
            prefix = "\(displayIndex). "
            displayIndex += 1
        } else {
            prefix = ""
        }
        print("  [\(status)] \(prefix)\(subtitleStreamLabel(stream))\(reason)")
    }
}

func selectSubtitleStreams(from streams: [SubtitleStream], options: PlayOptions) throws -> [SubtitleStream] {
    let compatibleStreams = streams.filter(\.isTextConvertible)

    if !options.streamIndices.isEmpty {
        return try options.streamIndices.map { requestedIndex in
            guard let stream = streams.first(where: { $0.index == requestedIndex }) else {
                throw CLIError.message("没有找到 stream index \(requestedIndex)。请先用 --list-subtitles 查看可用字幕流。")
            }
            guard stream.isTextConvertible else {
                throw CLIError.message("stream index \(requestedIndex) 是 \(stream.codecName)，不是可直接展示的文本字幕。")
            }
            return stream
        }
    }

    guard !compatibleStreams.isEmpty else {
        throw CLIError.message("没有可直接展示的文本字幕流。PGS/DVD/DVB 这类图形字幕需要 OCR，当前不会自动转换。")
    }

    if compatibleStreams.count == 1 {
        print("只有 1 条可展示字幕，自动选择：\(subtitleStreamLabel(compatibleStreams[0]))")
        return compatibleStreams
    }

    print("可展示字幕流：")
    print(numberedSubtitleStreamList(compatibleStreams))

    return try selectSubtitleStreamsInteractively(compatibleStreams, gumPath: findExecutable("gum"))
}

func selectSubtitleStreamsWithGum(_ streams: [SubtitleStream], gumPath: String) throws -> [SubtitleStream] {
    let choices = streams.enumerated().map { displayIndex, stream in
        numberedSubtitleStreamChoice(stream, displayIndex: displayIndex)
    }
    let selectedChoices = try runGumChooseMultiple(
        gumPath: gumPath,
        header: "选择要显示的字幕。可空格多选；输出顺序就是屏幕从上到下。",
        choices: choices
    )
    return try selectedChoices.map { choice in
        guard let displayIndex = parseSubtitleChoiceDisplayIndex(choice),
              displayIndex >= 0,
              displayIndex < streams.count else {
            throw CLIError.message("无法识别 gum 返回的字幕选择：\(choice)")
        }
        return streams[displayIndex]
    }
}

func selectSubtitleStreamsInteractively(_ streams: [SubtitleStream], gumPath: String?) throws -> [SubtitleStream] {
    let canOpenTUI = gumPath != nil && canUseGumTUI()
    if canOpenTUI {
        fputs("请输入要显示的编号，可用逗号或空格分隔；顺序表示从上到下。直接回车打开 gum TUI：", stderr)
    } else {
        fputs("请输入要显示的编号，可用逗号或空格分隔；顺序表示从上到下：", stderr)
    }
    fflush(stderr)
    guard let line = readLine() else {
        throw CLIError.message("没有读取到字幕选择。")
    }
    if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return try parseSubtitleSelectionInput(line, streams: streams)
    }

    guard canOpenTUI, let gumPath else {
        throw CLIError.message("没有选择任何字幕。")
    }

    do {
        return try selectSubtitleStreamsWithGum(streams, gumPath: gumPath)
    } catch {
        fputs("gum TUI 不可用，回退到编号输入：\(error)\n", stderr)
        fflush(stderr)
        fputs("请输入要显示的编号，可用逗号或空格分隔；顺序表示从上到下：", stderr)
        fflush(stderr)
        guard let fallbackLine = readLine() else {
            throw CLIError.message("没有读取到字幕选择。")
        }
        return try parseSubtitleSelectionInput(fallbackLine, streams: streams)
    }
}

func parseSubtitleSelectionInput(_ rawValue: String, streams: [SubtitleStream]) throws -> [SubtitleStream] {
    let tokens = rawValue
        .split(whereSeparator: { character in
            character == "," || character == " " || character == "\t" || character == "\n"
        })
        .map(String.init)

    guard !tokens.isEmpty else {
        throw CLIError.message("没有选择任何字幕。")
    }

    var selected: [SubtitleStream] = []
    var selectedStreamIndices: Set<Int> = []
    for token in tokens {
        guard let number = Int(token) else {
            throw CLIError.message("无法识别字幕编号：\(token)")
        }

        let stream: SubtitleStream?
        if number >= 1 && number <= streams.count {
            stream = streams[number - 1]
        } else {
            stream = streams.first(where: { $0.index == number })
        }

        guard let stream else {
            throw CLIError.message("没有找到字幕编号或 stream index：\(number)")
        }
        guard !selectedStreamIndices.contains(stream.index) else {
            throw CLIError.message("字幕 \(number) 被重复选择。")
        }
        selected.append(stream)
        selectedStreamIndices.insert(stream.index)
    }

    return selected
}

func canUseGumTUI() -> Bool {
    guard isatty(STDIN_FILENO) == 1,
          isatty(STDERR_FILENO) == 1 else {
        return false
    }

    let fd = open("/dev/tty", O_RDWR)
    guard fd >= 0 else {
        return false
    }
    close(fd)
    return true
}

func runGumChooseMultiple(gumPath: String, header: String, choices: [String]) throws -> [String] {
    let result = try runCapturedTUIProcess(
        executable: gumPath,
        arguments: ["choose", "--no-limit", "--ordered", "--header", header] + choices
    )
    guard result.status == 0 else {
        throw CLIError.message("gum 选择失败或已取消。")
    }

    let choices = result.stdout
        .split(separator: "\n", omittingEmptySubsequences: true)
        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    guard !choices.isEmpty else {
        throw CLIError.message("gum 没有返回选择结果。")
    }
    return choices
}

func subtitleStreamChoice(_ stream: SubtitleStream) -> String {
    "\(stream.index) | \(subtitleStreamLabel(stream))"
}

func numberedSubtitleStreamChoice(_ stream: SubtitleStream, displayIndex: Int) -> String {
    "\(displayIndex + 1). \(subtitleStreamLabel(stream))"
}

func numberedSubtitleStreamList(_ streams: [SubtitleStream]) -> String {
    streams.enumerated()
        .map { displayIndex, stream in
            "  \(numberedSubtitleStreamChoice(stream, displayIndex: displayIndex))"
        }
        .joined(separator: "\n")
}

func parseSubtitleChoiceDisplayIndex(_ choice: String) -> Int? {
    let trimmed = choice.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let dot = trimmed.firstIndex(of: "."),
          let displayNumber = Int(trimmed[..<dot]),
          displayNumber > 0 else {
        return nil
    }
    return displayNumber - 1
}

func subtitleStreamLabel(_ stream: SubtitleStream) -> String {
    var parts: [String] = ["stream \(stream.index)", stream.codecName]
    if let language = stream.language, !language.isEmpty {
        parts.append(languageDisplayName(language))
    }
    if let title = stream.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
        parts.append(title)
    }
    if stream.isDefault {
        parts.append("default")
    }
    if stream.isForced {
        parts.append("forced")
    }
    return parts.joined(separator: " | ")
}

func subtitleStreamDisplayTitle(_ stream: SubtitleStream) -> String {
    var parts = ["字幕 \(stream.index)"]
    if let language = stream.language, !language.isEmpty {
        parts.append(languageDisplayName(language))
    }
    if let title = stream.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
        parts.append(title)
    }
    return parts.joined(separator: " · ")
}

func languageDisplayName(_ language: String) -> String {
    let normalized = language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let knownNames: [String: String] = [
        "chi": "中文",
        "chs": "简体中文",
        "cht": "繁体中文",
        "eng": "English",
        "en": "English",
        "jpn": "日本語",
        "ja": "日本語",
        "kor": "한국어",
        "ko": "한국어",
        "zho": "中文",
        "zh": "中文"
    ]
    if let knownName = knownNames[normalized] {
        return "\(language)/\(knownName)"
    }
    return language
}
