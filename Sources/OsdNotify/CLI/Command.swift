import Foundation
import Darwin

enum Command {
    case version
    case checkUpdate
    case status
    case logs
    case show(Options)
    case clear(ClearOptions)
    case play(PlayOptions)
    case recite(ReciteOptions)
    case poem(PoemOptions)
    case poetry(PoetryOptions)
    case daemon
}

enum CLIError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case .message(let text):
            return text
        }
    }
}

func printUsage() {
    let usage = """
    用法:
      osd-notify --version
      osd-notify check-update
      osd-notify status
      osd-notify logs
      osd-notify show [message] [--source name] [--url https://...] [--ttl seconds] [--level info|warn|busy|done] [--position top|center|bottom] [--style soft|glass|lyric] [--font name] [--font-size points] [--title-size points] [--opacity 0...1] [--window-opacity 0...1] [--click-through|--blocks-clicks]
      osd-notify play file.lrc|file.srt|video.mkv [...] [--source name] [--url https://...] [--speed rate] [--limit count] [--stream index ...] [--list-subtitles] [--no-cache|--refresh-cache|--warm-cache] [--position top|center|bottom] [--font name] [--font-size points] [--title-size points] [--opacity 0...1] [--window-opacity 0...1] [--click-through|--blocks-clicks]
      osd-notify recite [text|file.txt ...] [--file path] [--text text] [--stdin] [--source name] [--url https://...] [--interval seconds] [--delimiters chars] [--min-chars count] [--max-chars count] [--speed rate] [--limit count] [--dry-run] [--no-clear] [--position top|center|bottom] [--font name] [--font-size points] [--title-size points] [--opacity 0...1] [--window-opacity 0...1] [--click-through|--blocks-clicks]
      osd-notify poem [random|title] [--refresh] [--source name] [--url https://...] [--interval seconds] [--speed rate] [--limit count] [--dry-run] [--no-clear] [--position top|center|bottom] [--font name] [--font-size points] [--title-size points] [--opacity 0...1] [--window-opacity 0...1] [--click-through|--blocks-clicks]
      osd-notify poetry [random] [--lang zh-Hans] [--source name] [--url https://...] [--interval seconds] [--speed rate] [--limit count] [--dry-run] [--no-clear] [--position top|center|bottom] [--font name] [--font-size points] [--title-size points] [--opacity 0...1] [--window-opacity 0...1] [--click-through|--blocks-clicks]
      osd-notify clear [--source name] [--all]

    示例:
      osd-notify show
      osd-notify show --source codex
      osd-notify show "参考链接" --url https://example.com
      osd-notify show "Glass test" --style glass
      osd-notify show "Lyric test" --style lyric
      osd-notify show "Automation finished" --ttl 3 --level done
      osd-notify play ./song.lrc
      osd-notify play ./subtitle.srt --speed 20 --limit 8
      osd-notify play ./zh.srt ./en.srt
      osd-notify play ./movie.mkv
      osd-notify play ./movie.mkv --list-subtitles
      osd-notify play ./movie.mkv --stream 8 --stream 9
      osd-notify play ./movie.mkv --warm-cache --stream 8 --stream 9
      osd-notify recite ./lantingxu.txt --source 兰亭序 --interval 8
      osd-notify recite --text "永和九年，岁在癸丑，暮春之初。" --source 兰亭序 --interval 5
      osd-notify recite ./lantingxu.txt --source 兰亭序 --dry-run
      osd-notify poem random
      osd-notify poem 劝学 --interval 15
      osd-notify poem 劝学 --refresh --dry-run --limit 5
      osd-notify poetry random --dry-run
      osd-notify clear
      osd-notify clear --source codex
      osd-notify clear --all

    说明:
      show 未提供正文时显示使用引导，默认 info 等级、60 秒后消失。
      默认样式: glass、bottom、PingFang SC、36pt 主文字、42% 背景透明度、3600 秒 TTL。
      OSD 会同时显示在所有已连接显示器上。
      传入 --url 后，OSD 右下角会显示链接图标，点击会用默认浏览器打开该地址。
      不同来源可以同时显示；相同位置已有 OSD 时会自动错开堆叠。
      clear 默认只清理当前来源；只有 --all 会清理所有来源。
      标题优先使用显式 source / 环境 source；否则读取直接父进程 PID 对应的 macOS 应用名。
      play 默认用输入文件 basename 作为 source，并始终用 lyric 样式按时间戳播放。多个 LRC/SRT 文件会按命令顺序从上到下堆叠显示。
      视频文件会先用 ffprobe 探测文本字幕流；多字幕流时会列出编号，直接输入 1,3 或 1 3 回车即可；空回车才尝试打开 gum TUI。视频字幕默认边抽边播，并缓存到 ~/Library/Caches/osd-notify/subtitles/。
      recite 读取普通文本，默认按中文/英文逗号、句号、问号、叹号和分号初拆，再均衡组合成 7-20 字左右的字幕句；--delimiters 可自定义切分字符。
      poem 首次运行会从古文岛高中文言入口采集原文并缓存到 ~/Library/Caches/osd-notify/poems/；默认随机，传标题时做近似匹配；默认每 15 秒显示一句；会自动把原文来源 URL 放到链接图标。
      poetry 会从 Palemoky 在线 API 随机取诗词，标题作为 OSD 标题，content 数组每个元素作为一行；如果 API 返回 Cloudflare challenge，会明确报错。
      glass 默认可拖动；soft 默认鼠标穿透。
    """
    print(usage)
}

func parseCommand() throws -> Command {
    var args = Array(CommandLine.arguments.dropFirst())

    if args.isEmpty {
        var options = try parseOptions([])
        options.source = "osd-notify"
        options.sourceWasProvidedByCaller = true
        options.messageSize = 24
        return .show(options)
    }

    if args.first == "version" || args.first == "--version" || args.first == "-V" {
        guard args.count == 1 else {
            throw CLIError.message("version 不接受其它参数。")
        }
        return .version
    }

    if args.first == "check-update" || args.first == "update-check" {
        guard args.count == 1 else {
            throw CLIError.message("check-update 不接受其它参数。")
        }
        return .checkUpdate
    }

    if args.first == "status" {
        guard args.count == 1 else {
            throw CLIError.message("status 不接受其它参数。")
        }
        return .status
    }

    if args.first == "logs" {
        guard args.count == 1 else {
            throw CLIError.message("logs 不接受其它参数。")
        }
        return .logs
    }

    if args.first == "help" || args.first == "--help" || args.first == "-h" {
        printUsage()
        exit(0)
    }

    if args.first == "--daemon" {
        return .daemon
    }

    if args.first == "clear" {
        args.removeFirst()
        return .clear(try parseClearOptions(args))
    }

    if args.first == "play" {
        args.removeFirst()
        return .play(try parsePlayOptions(args))
    }

    if args.first == "recite" {
        args.removeFirst()
        return .recite(try parseReciteOptions(args))
    }

    if args.first == "poem" {
        args.removeFirst()
        return .poem(try parsePoemOptions(args))
    }

    if args.first == "poetry" {
        args.removeFirst()
        return .poetry(try parsePoetryOptions(args))
    }

    if args.first == "show" {
        args.removeFirst()
    }

    return .show(try parseOptions(args))
}
