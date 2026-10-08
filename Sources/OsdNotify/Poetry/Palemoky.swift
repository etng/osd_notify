import Foundation

let palemokyPoetryBaseURL = URL(string: "https://poetry.palemoky.com")!

struct PalemokyRandomPoemResponse: Decodable {
    let ok: Bool
    let status: Int
    let url: String
    let data: PalemokyRandomPoemPayload

    var poem: PalemokyPoem {
        data.data
    }
}

struct PalemokyRandomPoemPayload: Decodable {
    let data: PalemokyPoem
    let lang: String
}

struct PalemokyDirectPoemResponse: Decodable {
    let data: PalemokyPoem
    let lang: String
}

struct PalemokyPoem: Decodable {
    let id: Int
    let title: String
    let content: [String]
    let author: PalemokyPoemNamedValue
    let dynasty: PalemokyPoemNamedValue
    let type: PalemokyPoemNamedValue
}

struct PalemokyPoemNamedValue: Decodable {
    let id: Int
    let name: String
}

func palemokyRandomPoemURL(lang: String) throws -> URL {
    var components = URLComponents(url: palemokyPoetryBaseURL.appendingPathComponent("/api/poems/random"), resolvingAgainstBaseURL: false)
    components?.queryItems = [
        URLQueryItem(name: "lang", value: lang)
    ]
    guard let url = components?.url else {
        throw CLIError.message("无法构造 Palemoky 随机诗词 API URL。")
    }
    return url
}

func decodePalemokyRandomPoemResponse(_ data: Data) throws -> PalemokyRandomPoemResponse {
    let body = String(decoding: data.prefix(512), as: UTF8.self)
    guard body.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") else {
        if body.localizedCaseInsensitiveContains("Just a moment")
            || body.localizedCaseInsensitiveContains("Cloudflare")
            || body.localizedCaseInsensitiveContains("challenge") {
            throw CLIError.message("Palemoky API 返回 Cloudflare challenge，不是 JSON。请稍后重试，或先在浏览器访问 poetry.palemoky.com 完成验证。")
        }
        throw CLIError.message("Palemoky API 返回的不是 JSON。")
    }

    let response: PalemokyRandomPoemResponse
    let decoder = JSONDecoder()
    do {
        response = try decoder.decode(PalemokyRandomPoemResponse.self, from: data)
    } catch {
        do {
            let direct = try decoder.decode(PalemokyDirectPoemResponse.self, from: data)
            response = PalemokyRandomPoemResponse(
                ok: true,
                status: 200,
                url: "",
                data: PalemokyRandomPoemPayload(data: direct.data, lang: direct.lang)
            )
        } catch {
            throw CLIError.message("Palemoky API 返回 JSON 结构不符合预期：\(palemokyResponsePreview(body))")
        }
    }
    guard response.ok, response.status == 200 else {
        throw CLIError.message("Palemoky API 返回失败状态：ok=\(response.ok), status=\(response.status)。")
    }
    guard !response.poem.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          !response.poem.content.isEmpty else {
        throw CLIError.message("Palemoky API 返回的诗词内容为空。")
    }
    return response
}

func palemokyResponsePreview(_ body: String) -> String {
    let collapsed = body
        .replacingOccurrences(of: "\r", with: " ")
        .replacingOccurrences(of: "\n", with: " ")
        .replacingOccurrences(of: "\t", with: " ")
        .split(separator: " ")
        .joined(separator: " ")
    if collapsed.count <= 160 {
        return collapsed
    }
    let index = collapsed.index(collapsed.startIndex, offsetBy: 160)
    return "\(collapsed[..<index])..."
}

func fetchPalemokyRandomPoem(lang: String) throws -> PalemokyRandomPoemResponse {
    let url = try palemokyRandomPoemURL(lang: lang)
    let result = try fetchHTTPData(from: url, accept: "application/json")
    guard result.statusCode == 200 else {
        if result.statusCode == 403,
           let body = String(data: result.data, encoding: .utf8),
           body.localizedCaseInsensitiveContains("challenge") {
            throw CLIError.message("Palemoky API 当前返回 403 Cloudflare challenge，CLI 无法直接取得 JSON。")
        }
        throw CLIError.message("Palemoky API HTTP \(result.statusCode)。")
    }
    let response = try decodePalemokyRandomPoemResponse(result.data)
    guard response.url.isEmpty else {
        return response
    }
    return PalemokyRandomPoemResponse(
        ok: response.ok,
        status: response.status,
        url: url.absoluteString,
        data: response.data
    )
}

func timedTextLines(for poem: PalemokyPoem, interval: TimeInterval, limit: Int?) -> [TimedTextLine] {
    var content = poem.content
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    if let limit {
        content = Array(content.prefix(limit))
    }
    return content.enumerated().map { index, line in
        let start = TimeInterval(index) * interval
        return TimedTextLine(start: start, end: start + interval, text: line)
    }
}

func recitePoetry(_ options: PoetryOptions) throws {
    let response = try fetchPalemokyRandomPoem(lang: options.lang)
    let poem = response.poem
    let lines = timedTextLines(for: poem, interval: options.interval, limit: options.limit)
    guard !lines.isEmpty else {
        throw CLIError.message("Palemoky API 返回的诗词没有可播放行。")
    }

    if options.dryRun {
        print("选中：\(poem.title)")
        print("作者：\(poem.author.name)  朝代：\(poem.dynasty.name)  体裁：\(poem.type.name)")
        print("URL：\(response.url)")
        print("按 content 数组得到 \(lines.count) 行，interval=\(formatSeconds(options.interval)) 秒，title='\(poem.title)'：")
        for line in lines {
            print("[\(formatTimedTextTimestamp(line.start))] \(line.text)")
        }
        return
    }

    var displayOptions = options.displayOptions
    if displayOptions.linkURL == nil {
        displayOptions.linkURL = response.url
    }

    var playbackOptions = PlayOptions()
    playbackOptions.speed = options.speed
    playbackOptions.clearWhenFinished = options.clearWhenFinished
    playbackOptions.displayOptions = displayOptions

    let source = options.source ?? poem.title
    let track = SubtitlePlaybackTrack(
        source: source,
        title: poem.title,
        stackIndex: nil,
        lines: lines
    )

    print("正在用 lyric 样式按 \(formatSeconds(options.interval)) 秒间隔背诵 \(lines.count) 行：\(poem.title)。")
    try playSubtitleTracks([track], baseOptions: playbackOptions, stackGroup: nil)
}
