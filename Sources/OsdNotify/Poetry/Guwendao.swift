import Foundation

let guwendaoBaseURL = URL(string: "https://www.guwendao.net")!
let guwendaoGaowenEntryURL = URL(string: "https://www.guwendao.net/wenyan/gaowen.aspx")!
struct GuwendaoPoemLink {
    let id: String
    let entryTitle: String
    let url: URL
}

struct GuwendaoPoemItem: Codable {
    let id: String
    let title: String
    let entryTitle: String
    let author: String
    let dynasty: String
    let url: String
    let content: String
}

struct GuwendaoPoemCache: Codable {
    let sourceURL: String
    let fetchedAt: Date
    let items: [GuwendaoPoemItem]
}

func parseGuwendaoEntryLinks(_ html: String, baseURL: URL) -> [GuwendaoPoemLink] {
    guard let mainRange = html.range(of: #"<div\s+class=["']main3["'][^>]*>"#, options: .regularExpression),
          let leftRange = html.range(
            of: #"<div\s+class=["']left["'][^>]*>"#,
            options: .regularExpression,
            range: mainRange.upperBound..<html.endIndex
          ),
          let leftHTML = balancedHTMLElement(in: html, openingTagRange: leftRange, tagName: "div") else {
        return []
    }

    let pattern = #"<a\b[^>]*href=["']([^"']*?/shiwenv_([0-9a-fA-F]+)\.aspx)["'][^>]*>(.*?)</a>"#
    let matches = regexMatches(pattern, in: leftHTML, options: [.caseInsensitive, .dotMatchesLineSeparators])
    var links: [GuwendaoPoemLink] = []
    var seenIDs = Set<String>()

    for match in matches {
        guard match.numberOfRanges >= 4,
              let hrefRange = Range(match.range(at: 1), in: leftHTML),
              let idRange = Range(match.range(at: 2), in: leftHTML),
              let titleRange = Range(match.range(at: 3), in: leftHTML) else {
            continue
        }

        let id = String(leftHTML[idRange]).lowercased()
        guard !seenIDs.contains(id) else {
            continue
        }
        let href = String(leftHTML[hrefRange])
        guard let url = URL(string: href, relativeTo: baseURL)?.absoluteURL else {
            continue
        }
        let title = htmlToSingleLineText(String(leftHTML[titleRange]))
        guard !title.isEmpty else {
            continue
        }

        links.append(GuwendaoPoemLink(id: id, entryTitle: title, url: url))
        seenIDs.insert(id)
    }

    return links
}

func parseGuwendaoPoemPage(_ html: String, link: GuwendaoPoemLink) throws -> GuwendaoPoemItem {
    let zhengwenHTML: String
    if let zhengwenRange = html.range(
        of: #"<div\s+id=["']zhengwen\#(NSRegularExpression.escapedPattern(for: link.id))["'][^>]*>"#,
        options: .regularExpression
    ), let extracted = balancedHTMLElement(in: html, openingTagRange: zhengwenRange, tagName: "div") {
        zhengwenHTML = extracted
    } else {
        zhengwenHTML = html
    }

    let title = firstRegexCapture(#"<h1\b[^>]*>(.*?)</h1>"#, in: zhengwenHTML)
        .map(htmlToSingleLineText) ?? link.entryTitle
    let sourceHTML = firstRegexCapture(#"<p\b[^>]*class=["'][^"']*\bsource\b[^"']*["'][^>]*>(.*?)</p>"#, in: zhengwenHTML) ?? ""
    let sourceParts = regexMatches(#"<a\b[^>]*>(.*?)</a>"#, in: sourceHTML, options: [.caseInsensitive, .dotMatchesLineSeparators])
        .compactMap { match -> String? in
            guard let range = Range(match.range(at: 1), in: sourceHTML) else {
                return nil
            }
            let text = htmlToSingleLineText(String(sourceHTML[range]))
                .trimmingCharacters(in: CharacterSet(charactersIn: "[]〔〕"))
            return text.isEmpty ? nil : text
        }
    let author = sourceParts.first ?? ""
    let dynasty = sourceParts.dropFirst().first ?? ""

    guard let contsonRange = html.range(
        of: #"<div\b[^>]*id=["']contson\#(NSRegularExpression.escapedPattern(for: link.id))["'][^>]*>"#,
        options: .regularExpression
    ), let contsonHTML = balancedHTMLElement(in: html, openingTagRange: contsonRange, tagName: "div") else {
        throw CLIError.message("无法从 \(link.url.absoluteString) 提取原文。")
    }

    let content = poemContentText(from: contsonHTML)
    guard !content.isEmpty else {
        throw CLIError.message("从 \(link.url.absoluteString) 提取到的原文为空。")
    }

    return GuwendaoPoemItem(
        id: link.id,
        title: title,
        entryTitle: link.entryTitle,
        author: author,
        dynasty: dynasty,
        url: link.url.absoluteString,
        content: content
    )
}

func poemContentText(from html: String) -> String {
    let paragraphs = regexMatches(#"<p\b[^>]*>(.*?)</p>"#, in: html, options: [.caseInsensitive, .dotMatchesLineSeparators])
        .compactMap { match -> String? in
            guard let range = Range(match.range(at: 1), in: html) else {
                return nil
            }
            let text = htmlToMultilineText(String(html[range]))
            return text.isEmpty ? nil : text
        }

    if !paragraphs.isEmpty {
        return paragraphs.joined(separator: "\n")
    }

    return htmlToMultilineText(html)
}

func bestPoemMatch(for rawQuery: String, in items: [GuwendaoPoemItem]) throws -> GuwendaoPoemItem {
    let query = normalizedPoemTitle(rawQuery)
    guard !query.isEmpty else {
        throw CLIError.message("标题不能为空。")
    }
    guard !items.isEmpty else {
        throw CLIError.message("古文池为空。")
    }

    let scored = items.map { item -> (item: GuwendaoPoemItem, score: Int) in
        let title = normalizedPoemTitle(item.title)
        let entryTitle = normalizedPoemTitle(item.entryTitle)
        let score = max(poemTitleScore(query: query, candidate: title), poemTitleScore(query: query, candidate: entryTitle))
        return (item, score)
    }
    guard let best = scored.max(by: { $0.score < $1.score }), best.score > 0 else {
        let candidates = items.prefix(5).map(\.title).joined(separator: "、")
        throw CLIError.message("没有找到匹配标题 '\(rawQuery)' 的古文。候选示例：\(candidates)")
    }
    return best.item
}

func poemTitleScore(query: String, candidate: String) -> Int {
    guard !query.isEmpty, !candidate.isEmpty else {
        return 0
    }
    if query == candidate {
        return 10_000 + candidate.count
    }
    if candidate.contains(query) {
        return 8_000 + query.count * 10 - abs(candidate.count - query.count)
    }
    if query.contains(candidate) {
        return 7_000 + candidate.count * 10 - abs(candidate.count - query.count)
    }
    let overlap = longestCommonSubsequenceLength(query, candidate)
    return overlap * 100 - abs(candidate.count - query.count)
}

func longestCommonSubsequenceLength(_ lhs: String, _ rhs: String) -> Int {
    let left = Array(lhs)
    let right = Array(rhs)
    guard !left.isEmpty, !right.isEmpty else {
        return 0
    }

    var previous = Array(repeating: 0, count: right.count + 1)
    var current = previous
    for leftIndex in left.indices {
        current[0] = 0
        for rightIndex in right.indices {
            if left[leftIndex] == right[rightIndex] {
                current[rightIndex + 1] = previous[rightIndex] + 1
            } else {
                current[rightIndex + 1] = max(previous[rightIndex + 1], current[rightIndex])
            }
        }
        swap(&previous, &current)
    }
    return previous[right.count]
}

func normalizedPoemTitle(_ title: String) -> String {
    htmlToSingleLineText(title)
        .filter { character in
            !character.unicodeScalars.allSatisfy { scalar in
                CharacterSet.whitespacesAndNewlines.contains(scalar)
                    || CharacterSet.punctuationCharacters.contains(scalar)
                    || CharacterSet.symbols.contains(scalar)
            }
        }
}

func guwendaoPoemCacheDirectoryURL() throws -> URL {
    let baseURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches", isDirectory: true)
    let url = baseURL
        .appendingPathComponent("osd-notify", isDirectory: true)
        .appendingPathComponent("poems", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func guwendaoPoemCacheFileURL() throws -> URL {
    try guwendaoPoemCacheDirectoryURL()
        .appendingPathComponent("guwendao-gaowen.json")
}

func readGuwendaoPoemCache() throws -> GuwendaoPoemCache? {
    let url = try guwendaoPoemCacheFileURL()
    guard FileManager.default.fileExists(atPath: url.path) else {
        return nil
    }
    let data = try Data(contentsOf: url)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return try decoder.decode(GuwendaoPoemCache.self, from: data)
}

func writeGuwendaoPoemCache(_ cache: GuwendaoPoemCache) throws {
    let url = try guwendaoPoemCacheFileURL()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(cache)
    try data.write(to: url, options: .atomic)
}

func loadGuwendaoPoemCache(refresh: Bool) throws -> GuwendaoPoemCache {
    if !refresh {
        do {
            if let cache = try readGuwendaoPoemCache(), !cache.items.isEmpty {
                return cache
            }
        } catch {
            fputs("古文缓存不可读，将重新采集：\(error)\n", stderr)
        }
    }

    let cache = try fetchGuwendaoPoemCache()
    try writeGuwendaoPoemCache(cache)
    print("已缓存 \(cache.items.count) 篇高中文言文：\(try guwendaoPoemCacheFileURL().path)")
    return cache
}

func fetchGuwendaoPoemCache() throws -> GuwendaoPoemCache {
    let entryHTML = try fetchText(from: guwendaoGaowenEntryURL)
    let links = parseGuwendaoEntryLinks(entryHTML, baseURL: guwendaoBaseURL)
    guard !links.isEmpty else {
        throw CLIError.message("没有从古文岛高中文言入口解析到作品链接。")
    }

    var items: [GuwendaoPoemItem] = []
    for (index, link) in links.enumerated() {
        do {
            let html = try fetchText(from: link.url)
            let item = try parseGuwendaoPoemPage(html, link: link)
            items.append(item)
            fputs("采集 \(index + 1)/\(links.count)：\(item.title)\n", stderr)
        } catch {
            fputs("跳过 \(link.entryTitle)：\(error)\n", stderr)
        }
        if index + 1 < links.count {
            Thread.sleep(forTimeInterval: 0.08)
        }
    }

    guard !items.isEmpty else {
        throw CLIError.message("古文岛入口中没有成功采集到可播放原文。")
    }

    return GuwendaoPoemCache(
        sourceURL: guwendaoGaowenEntryURL.absoluteString,
        fetchedAt: Date(),
        items: items
    )
}

func recitePoem(_ options: PoemOptions) throws {
    let cache = try loadGuwendaoPoemCache(refresh: options.refreshCache)
    let item: GuwendaoPoemItem
    if let query = options.query {
        item = try bestPoemMatch(for: query, in: cache.items)
    } else {
        guard let randomItem = cache.items.randomElement() else {
            throw CLIError.message("古文池为空。")
        }
        item = randomItem
    }

    let reciteOptions = recitationOptions(for: item, poemOptions: options)

    if options.dryRun {
        print("选中：\(poemDisplayTitle(item))")
        print("URL：\(item.url)")
    }

    try recitePlainText(reciteOptions)
}

func recitationOptions(for item: GuwendaoPoemItem, poemOptions options: PoemOptions) -> ReciteOptions {
    var reciteOptions = ReciteOptions()
    reciteOptions.inputs = [.text(item.content)]
    reciteOptions.source = options.source ?? poemDisplayTitle(item)
    reciteOptions.interval = options.interval
    reciteOptions.speed = options.speed
    reciteOptions.limit = options.limit
    reciteOptions.clearWhenFinished = options.clearWhenFinished
    reciteOptions.dryRun = options.dryRun
    reciteOptions.displayOptions = options.displayOptions
    if reciteOptions.displayOptions.linkURL == nil {
        reciteOptions.displayOptions.linkURL = item.url
    }
    return reciteOptions
}

func poemDisplayTitle(_ item: GuwendaoPoemItem) -> String {
    if item.author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return item.title
    }
    return "\(item.author)《\(item.title)》"
}
