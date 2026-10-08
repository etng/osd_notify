import Foundation

func recitePlainText(_ options: ReciteOptions) throws {
    let inputText = try options.inputs
        .map(readRecitationInput)
        .joined(separator: "\n")
    var segments = balanceRecitationSegments(
        splitRecitationText(inputText, delimiters: options.delimiters),
        minCharacters: options.minCharacters,
        preferredMaxCharacters: options.preferredMaxCharacters
    )
    if let limit = options.limit {
        segments = Array(segments.prefix(limit))
    }
    guard !segments.isEmpty else {
        throw CLIError.message("没有可背诵的文本片段。")
    }

    let lines = segments.enumerated().map { index, segment in
        let start = TimeInterval(index) * options.interval
        return TimedTextLine(
            start: start,
            end: start + options.interval,
            text: segment
        )
    }
    let source = options.source ?? defaultRecitationSource(from: options.inputs)
    let track = SubtitlePlaybackTrack(
        source: source,
        title: source,
        stackIndex: nil,
        lines: lines
    )

    if options.dryRun {
        print("按分隔符「\(options.delimiters)」初拆并均衡组合后得到 \(lines.count) 句，min=\(options.minCharacters) 字，max≈\(options.preferredMaxCharacters) 字，interval=\(formatSeconds(options.interval)) 秒，source='\(source)'：")
        for line in lines {
            print("[\(formatTimedTextTimestamp(line.start))] \(line.text)")
        }
        return
    }

    var playbackOptions = PlayOptions()
    playbackOptions.speed = options.speed
    playbackOptions.limit = options.limit
    playbackOptions.clearWhenFinished = options.clearWhenFinished
    playbackOptions.displayOptions = options.displayOptions

    print("正在用 lyric 样式按 \(formatSeconds(options.interval)) 秒间隔背诵 \(lines.count) 句：\(source)。")
    try playSubtitleTracks([track], baseOptions: playbackOptions, stackGroup: nil)
}

func balanceRecitationSegments(
    _ segments: [String],
    minCharacters: Int,
    preferredMaxCharacters: Int
) -> [String] {
    let count = segments.count
    guard count > 0 else {
        return []
    }

    let lengths = segments.map(recitationCharacterCount)
    var prefixLengths = Array(repeating: 0, count: count + 1)
    var strongBreakPrefix = Array(repeating: 0, count: count + 1)
    for index in 0..<count {
        prefixLengths[index + 1] = prefixLengths[index] + lengths[index]
        strongBreakPrefix[index + 1] = strongBreakPrefix[index] + (recitationSegmentEndsWithStrongBreak(segments[index]) ? 1 : 0)
    }

    let targetCharacters = Double(minCharacters + preferredMaxCharacters) / 2.0
    var bestCosts = Array(repeating: Double.greatestFiniteMagnitude, count: count + 1)
    var nextBreaks = Array(repeating: count, count: count + 1)
    bestCosts[count] = 0.0

    for start in stride(from: count - 1, through: 0, by: -1) {
        for end in (start + 1)...count {
            let segmentLength = prefixLengths[end] - prefixLengths[start]
            let internalStrongBreaks = strongBreakPrefix[end - 1] - strongBreakPrefix[start]
            let cost = balancedRecitationSegmentCost(
                length: segmentLength,
                internalStrongBreakCount: internalStrongBreaks,
                minCharacters: minCharacters,
                preferredMaxCharacters: preferredMaxCharacters,
                targetCharacters: targetCharacters
            ) + bestCosts[end]

            if cost < bestCosts[start] {
                bestCosts[start] = cost
                nextBreaks[start] = end
            }

            if segmentLength > preferredMaxCharacters + minCharacters,
               end > start + 1 {
                break
            }
        }
    }

    var balanced: [String] = []
    var index = 0
    while index < count {
        let next = max(index + 1, nextBreaks[index])
        balanced.append(segments[index..<next].joined())
        index = next
    }
    return balanced
}

func balancedRecitationSegmentCost(
    length: Int,
    internalStrongBreakCount: Int,
    minCharacters: Int,
    preferredMaxCharacters: Int,
    targetCharacters: Double
) -> Double {
    let distance = Double(length) - targetCharacters
    var cost = distance * distance

    if length < minCharacters {
        let shortage = Double(minCharacters - length)
        cost += shortage * shortage * 18.0 + 20.0
    }

    if length > preferredMaxCharacters {
        let excess = Double(length - preferredMaxCharacters)
        cost += excess * excess * 24.0 + 40.0
    }

    cost += Double(internalStrongBreakCount) * 90.0
    return cost
}

func readRecitationInput(_ input: ReciteInput) throws -> String {
    switch input {
    case .text(let text):
        return text

    case .file(let path):
        let fileURL = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        do {
            return try String(contentsOf: fileURL, encoding: .utf8)
        } catch {
            return try String(contentsOf: fileURL)
        }

    case .standardInput:
        let data = FileHandle.standardInput.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
    }
}

func defaultRecitationSource(from inputs: [ReciteInput]) -> String {
    if inputs.count == 1,
       case .file(let path) = inputs[0] {
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath).lastPathComponent
    }
    return "古诗词背诵"
}

func splitRecitationText(_ text: String, delimiters: String) -> [String] {
    let delimiterSet = Set(delimiters)
    let closingPunctuation = Set("”’」』》〉）)]】")
    let characters = Array(normalizedLineEndings(text))
    var segments: [String] = []
    var current = ""
    var index = 0

    while index < characters.count {
        let character = characters[index]
        if isRecitationWhitespace(character) {
            if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !current.hasSuffix(" ") {
                current.append(" ")
            }
        } else {
            current.append(character)
        }

        if delimiterSet.contains(character) {
            var lookahead = index + 1
            while lookahead < characters.count,
                  closingPunctuation.contains(characters[lookahead]) {
                current.append(characters[lookahead])
                lookahead += 1
            }
            appendRecitationSegment(current, to: &segments)
            current.removeAll(keepingCapacity: true)
            index = lookahead
        } else {
            index += 1
        }
    }

    appendRecitationSegment(current, to: &segments)
    return segments
}

func appendRecitationSegment(_ rawValue: String, to segments: inout [String]) {
    let segment = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !segment.isEmpty else {
        return
    }
    segments.append(segment)
}

func recitationCharacterCount(_ text: String) -> Int {
    text.reduce(0) { count, character in
        if isRecitationWhitespace(character) || isRecitationPunctuation(character) {
            return count
        }
        return count + 1
    }
}

func recitationSegmentEndsWithStrongBreak(_ text: String) -> Bool {
    guard let last = text.trimmingCharacters(in: .whitespacesAndNewlines).last else {
        return false
    }
    return Set("。！？；;.!?").contains(last)
}

func isRecitationWhitespace(_ character: Character) -> Bool {
    character.unicodeScalars.allSatisfy { scalar in
        CharacterSet.whitespacesAndNewlines.contains(scalar)
    }
}

func isRecitationPunctuation(_ character: Character) -> Bool {
    character.unicodeScalars.allSatisfy { scalar in
        CharacterSet.punctuationCharacters.contains(scalar)
            || CharacterSet.symbols.contains(scalar)
    }
}

func formatSeconds(_ value: TimeInterval) -> String {
    if abs(value.rounded() - value) < 0.001 {
        return String(Int(value.rounded()))
    }
    return String(format: "%.2f", value)
}
