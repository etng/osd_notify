import Foundation

func balancedHTMLElement(in html: String, openingTagRange: Range<String.Index>, tagName: String) -> String? {
    let openPattern = "<\(tagName)\\b"
    let closePattern = "</\(tagName)>"
    var depth = 1
    var searchStart = openingTagRange.upperBound

    while searchStart < html.endIndex {
        let nextOpen = html.range(of: openPattern, options: [.regularExpression, .caseInsensitive], range: searchStart..<html.endIndex)
        let nextClose = html.range(of: closePattern, options: [.caseInsensitive], range: searchStart..<html.endIndex)

        guard let close = nextClose else {
            return nil
        }
        if let open = nextOpen, open.lowerBound < close.lowerBound {
            depth += 1
            searchStart = open.upperBound
            continue
        }

        depth -= 1
        searchStart = close.upperBound
        if depth == 0 {
            return String(html[openingTagRange.lowerBound..<close.upperBound])
        }
    }

    return nil
}

func firstRegexCapture(_ pattern: String, in text: String) -> String? {
    guard let match = regexMatches(pattern, in: text, options: [.caseInsensitive, .dotMatchesLineSeparators]).first,
          match.numberOfRanges >= 2,
          let range = Range(match.range(at: 1), in: text) else {
        return nil
    }
    return String(text[range])
}

func regexMatches(
    _ pattern: String,
    in text: String,
    options: NSRegularExpression.Options = []
) -> [NSTextCheckingResult] {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
        return []
    }
    return regex.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text))
}

func htmlToSingleLineText(_ html: String) -> String {
    htmlToMultilineText(html)
        .split(whereSeparator: \.isNewline)
        .map(String.init)
        .joined(separator: " ")
        .replacingOccurrences(of: #"[ \t\u{00a0}\u{3000}]+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

func htmlToMultilineText(_ html: String) -> String {
    var text = normalizedLineEndings(html)
    text = text.replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression)
    text = text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
    text = decodeHTMLEntities(text)
    let lines = text
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map { line in
            String(line)
                .replacingOccurrences(of: #"[ \t\u{00a0}\u{3000}]+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .filter { !$0.isEmpty }
    return lines.joined(separator: "\n")
}

func decodeHTMLEntities(_ value: String) -> String {
    var text = value
        .replacingOccurrences(of: "&nbsp;", with: " ")
        .replacingOccurrences(of: "&amp;", with: "&")
        .replacingOccurrences(of: "&lt;", with: "<")
        .replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&quot;", with: "\"")
        .replacingOccurrences(of: "&#39;", with: "'")
        .replacingOccurrences(of: "&apos;", with: "'")

    let pattern = #"&#(x?[0-9a-fA-F]+);"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
        return text
    }
    let matches = regex.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)).reversed()
    for match in matches {
        guard match.numberOfRanges >= 2,
              let fullRange = Range(match.range(at: 0), in: text),
              let numberRange = Range(match.range(at: 1), in: text) else {
            continue
        }
        let rawNumber = String(text[numberRange])
        let scalarValue: UInt32?
        if rawNumber.lowercased().hasPrefix("x") {
            scalarValue = UInt32(rawNumber.dropFirst(), radix: 16)
        } else {
            scalarValue = UInt32(rawNumber, radix: 10)
        }
        if let scalarValue, let scalar = UnicodeScalar(scalarValue) {
            text.replaceSubrange(fullRange, with: String(Character(scalar)))
        }
    }
    return text
}
