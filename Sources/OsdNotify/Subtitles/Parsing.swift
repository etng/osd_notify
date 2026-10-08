import Foundation

func loadTimedTextLines(from fileURL: URL) throws -> [TimedTextLine] {
    let text: String
    do {
        text = try String(contentsOf: fileURL, encoding: .utf8)
    } catch {
        text = try String(contentsOf: fileURL)
    }
    let ext = fileURL.pathExtension.lowercased()
    let lines: [TimedTextLine]

    switch ext {
    case "lrc":
        lines = parseLRC(text)
    case "srt":
        lines = parseSRT(text)
    default:
        let lrcLines = parseLRC(text)
        lines = lrcLines.isEmpty ? parseSRT(text) : lrcLines
    }

    return mergeTimedTextLines(lines)
}

func parseLRC(_ text: String) -> [TimedTextLine] {
    let normalized = normalizedLineEndings(text)
    var timedLines: [TimedTextLine] = []

    for rawLine in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
        let line = String(rawLine)
        let tags = lrcTimestampTags(in: line)
        guard !tags.isEmpty else {
            continue
        }

        var pendingTimes: [TimeInterval] = []
        for index in tags.indices {
            let tag = tags[index]
            pendingTimes.append(tag.time)

            let contentStart = tag.end
            let contentEnd = index + 1 < tags.count ? tags[index + 1].start : line.endIndex
            let content = cleanTimedText(String(line[contentStart..<contentEnd]))
            guard !content.isEmpty else {
                continue
            }

            for time in pendingTimes {
                timedLines.append(TimedTextLine(start: time, end: nil, text: content))
            }
            pendingTimes.removeAll()
        }
    }

    return timedLines.sorted { $0.start < $1.start }
}

func lrcTimestampTags(in line: String) -> [(start: String.Index, end: String.Index, time: TimeInterval)] {
    var tags: [(start: String.Index, end: String.Index, time: TimeInterval)] = []
    var searchStart = line.startIndex

    while searchStart < line.endIndex,
          let open = line[searchStart...].firstIndex(of: "["),
          let close = line[open...].firstIndex(of: "]") {
        let tagStart = line.index(after: open)
        let tag = String(line[tagStart..<close])
        if let time = parseLRCTimestamp(tag) {
            tags.append((start: open, end: line.index(after: close), time: time))
        }
        searchStart = line.index(after: close)
    }

    return tags
}

func parseLRCTimestamp(_ rawValue: String) -> TimeInterval? {
    let parts = rawValue.split(separator: ":")
    guard parts.count == 2 || parts.count == 3 else {
        return nil
    }

    guard let secondsText = parts.last,
          let seconds = Double(secondsText) else {
        return nil
    }

    if parts.count == 2 {
        guard let minutes = Double(parts[0]) else {
            return nil
        }
        return minutes * 60.0 + seconds
    }

    guard let hours = Double(parts[0]),
          let minutes = Double(parts[1]) else {
        return nil
    }
    return hours * 3600.0 + minutes * 60.0 + seconds
}

func parseSRT(_ text: String) -> [TimedTextLine] {
    let normalized = normalizedLineEndings(text)
    let blocks = splitSubtitleBlocks(normalized)
    var timedLines: [TimedTextLine] = []

    for block in blocks {
        if let line = parseSRTBlock(block) {
            timedLines.append(line)
        }
    }

    return timedLines.sorted { $0.start < $1.start }
}

func parseSRTBlock(_ block: String) -> TimedTextLine? {
    let normalized = normalizedLineEndings(block)
    let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    guard let timingIndex = lines.firstIndex(where: { $0.contains("-->") }) else {
        return nil
    }

    let timingParts = lines[timingIndex].components(separatedBy: "-->")
    guard timingParts.count >= 2,
          let start = parseSRTTimestamp(timingParts[0]),
          let end = parseSRTTimestamp(timingParts[1]) else {
        return nil
    }

    let content = lines.dropFirst(timingIndex + 1)
        .map(cleanTimedText)
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
    guard !content.isEmpty else {
        return nil
    }

    return TimedTextLine(start: start, end: end, text: content)
}

func firstSRTBlockSeparator(in data: Data) -> Range<Data.Index>? {
    guard data.count >= 2 else {
        return nil
    }

    var index = data.startIndex
    while index < data.endIndex {
        let next = data.index(after: index)
        if next < data.endIndex,
           data[index] == 10,
           data[next] == 10 {
            return index..<data.index(after: next)
        }

        if data[index] == 13,
           next < data.endIndex,
           data[next] == 10 {
            let third = data.index(after: next)
            if third < data.endIndex,
               data[third] == 13 {
                let fourth = data.index(after: third)
                if fourth < data.endIndex,
                   data[fourth] == 10 {
                    return index..<data.index(after: fourth)
                }
            }
        }

        index = data.index(after: index)
    }

    return nil
}

func parseSRTTimestamp(_ rawValue: String) -> TimeInterval? {
    let cleaned = rawValue
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .components(separatedBy: CharacterSet.whitespaces)
        .first ?? ""
    let normalized = cleaned.replacingOccurrences(of: ",", with: ".")
    let parts = normalized.split(separator: ":")
    guard parts.count == 3,
          let hours = Double(parts[0]),
          let minutes = Double(parts[1]),
          let seconds = Double(parts[2]) else {
        return nil
    }

    return hours * 3600.0 + minutes * 60.0 + seconds
}

func splitSubtitleBlocks(_ text: String) -> [String] {
    var blocks: [String] = []
    var current: [String] = []

    for line in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
        if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if !current.isEmpty {
                blocks.append(current.joined(separator: "\n"))
                current.removeAll()
            }
        } else {
            current.append(line)
        }
    }

    if !current.isEmpty {
        blocks.append(current.joined(separator: "\n"))
    }

    return blocks
}

func normalizedLineEndings(_ text: String) -> String {
    text
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
}

func cleanTimedText(_ rawValue: String) -> String {
    var text = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    text = text.replacingOccurrences(of: #"(<[^>]+>)"#, with: "", options: .regularExpression)
    text = text.replacingOccurrences(of: #"\{[^}]+\}"#, with: "", options: .regularExpression)
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
}

func mergeTimedTextLines(_ lines: [TimedTextLine]) -> [TimedTextLine] {
    let sorted = lines
        .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .sorted { lhs, rhs in
            if lhs.start == rhs.start {
                return (lhs.end ?? lhs.start) < (rhs.end ?? rhs.start)
            }
            return lhs.start < rhs.start
        }

    var merged: [TimedTextLine] = []
    for line in sorted {
        if let last = merged.last,
           abs(last.start - line.start) < 0.001,
           abs((last.end ?? -1.0) - (line.end ?? -1.0)) < 0.001 {
            merged.removeLast()
            merged.append(TimedTextLine(
                start: last.start,
                end: last.end,
                text: [last.text, line.text].joined(separator: "\n")
            ))
        } else {
            merged.append(line)
        }
    }

    return merged
}
