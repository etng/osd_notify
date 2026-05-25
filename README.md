# osd-notify

`osd-notify` 是一个用 Swift 写的 macOS 屏幕提示工具，用来在 Codex、Chrome 自动化、Computer Use、Playwright/CDP 等操作可能打断用户时，在所有显示器上显示醒目的 OSD 提示。

它现在采用本地守护进程模型：普通 `show` 命令只负责把请求发给后台守护进程，然后立即退出；窗口生命周期、淡入淡出、同来源替换、拖动位置记忆都由守护进程管理。


## 快速使用

```bash
osd-notify show
```

默认会显示：

```text
请暂停手动操作，Codex 正在控制 Chrome
```

自动化结束后应显式清除：

```bash
osd-notify clear --source codex
```

如果没有传 `--source`，会按环境变量或父进程名推断来源。

## 默认行为

- 消息：`请暂停手动操作，Codex 正在控制 Chrome`
- 进程模型：`show` 自动启动或连接本地守护进程，发完请求后立即退出
- TTL：`3600` 秒，仅作为兜底；自动化实际结束时应主动 `clear`
- 位置：`bottom`
- 样式：`glass`
- 字体：`PingFang SC`
- 主消息字号：`36pt`
- 背景透明度：`42%`
- 鼠标行为：默认可拖动；`--click-through` 可改为鼠标穿透
- 显示器行为：所有已连接显示器同时显示
- 宽度：按文本测量，最多为屏幕可见宽度的 `80%`
- 标题：显式来源 / 环境来源优先；否则读取直接父进程 PID 的 macOS 应用名；仍无法识别时使用等级标题
- 动效：显示时淡入；同来源替换、`clear`、TTL 到期时淡出
- 位置记忆：可拖动 OSD 被移动后，同来源下次优先使用该屏幕上的相对位置

## 常用命令

```bash
osd-notify show "请暂停手动操作，Codex 正在控制 Chrome" --source codex
osd-notify show "Chrome 正在被自动化控制" --source codex --ttl 600
osd-notify show "落木千山天远大，澄江一道月分明。" --source '黄庭坚《登快阁》' --style lyric
osd-notify play ./song.lrc
osd-notify play ./subtitle.srt --speed 20 --limit 8
osd-notify recite ./lantingxu.txt --source '兰亭序' --interval 8
osd-notify clear --source codex
osd-notify clear --all
```

`clear` 默认只清除当前来源。只有显式使用 `--all` 时才会清除所有来源的 OSD。

## 参数

- `--ttl seconds`：显示时长，单位秒。
- `--source name`：调用来源身份。同一个来源的新 `show` 会替换旧 OSD；不同来源可以并存。
- `--level info|warn|busy|done`：等级预设，影响标题和状态色。
- `--position top|center|bottom`：默认布局位置；如果同来源已有拖动位置记忆，则优先使用记忆位置。
- `--style soft|glass|lyric`：视觉样式。`lyrics` 也可作为 `lyric` 的别名。
- `--font name`：字体，例如 `"PingFang SC"`。
- `--font-size points`：主消息字号。
- `--title-size points`：标题字号。
- `--opacity 0...1`：背景透明度，也支持百分比，例如 `0.42` 或 `42%`。
- `--window-opacity 0...1`：整个 OSD 窗口透明度，包含文字。
- `--click-through`：鼠标事件穿透到下方窗口。
- `--blocks-clicks`：OSD 接收鼠标事件；`glass` 和 `lyric` 默认如此，因此可以拖动。

## 定时文本播放

`play` 子命令会读取带时间戳的 LRC / SRT 文件，并按照文件里的时间依次显示每一行；也可以读取 MKV / MP4 等视频容器里的文本字幕流：

```bash
osd-notify play file.lrc
osd-notify play file.srt
osd-notify play zh.srt en.srt
osd-notify play movie.mkv
```

默认行为：

- 来源：使用输入文件的 basename，也就是去掉目录后的文件名，例如 `song.lrc`。
- 样式：强制使用 `lyric`，保证复杂背景上的可读性。
- LRC：按每个 `[mm:ss.xx]` / `[hh:mm:ss.xx]` 时间戳显示后续文本；支持多个时间戳共用同一句。
- SRT：按 `start --> end` 显示对应字幕块；多行字幕会保留换行。
- 多个 LRC/SRT 文件：按命令顺序从上到下垂直错开显示。
- 起播时间：播放会从所选字幕中最早的第一条时间戳开始，不等待片头空白；多字幕之间仍按原始时间差同步。
- 视频容器：先用 `ffprobe` 探测字幕流，只把 SRT / ASS / SSA / WebVTT / mov_text 等文本字幕交给 `ffmpeg` 抽取成 SRT。
- 边抽边播：视频字幕首次播放时，抽取线程会持续读取 `ffmpeg` stdout、写入缓存并增量解析；播放器调度器消费已解析 cue，不等待整部片字幕抽完。
- 缓存：视频字幕默认缓存到 `~/Library/Caches/osd-notify/subtitles/`，同一个视频、同一个 stream 下次优先直接读取缓存。
- 多字幕流：交互终端里会先列出编号；直接输入 `1,3` 或 `1 3` 回车即可，选择顺序表示从上到下；空回车才尝试打开 `gum` TUI。
- 图形字幕：PGS / DVD / DVB 这类图片字幕会列出但跳过，当前不会做 OCR。
- 结束：默认播放完最后一行后自动 `clear` 当前来源。

常用参数：

- `--source name`：覆盖默认文件名来源。
- `--speed rate`：按倍率加速播放，适合测试。例如 `--speed 20` 表示 20 倍速。
- `--limit count`：只播放前 N 行，适合 smoke test。
- `--list-subtitles`：只列出视频容器里的字幕流，不播放。
- `--stream index`：脚本或非交互场景指定 ffprobe stream index，可重复；顺序表示从上到下。普通使用直接 `osd-notify play movie.mkv` 后按编号选择即可。
- `--no-cache`：视频字幕本次不读写缓存。
- `--refresh-cache`：忽略旧缓存并重新抽取。
- `--warm-cache`：只抽取并写缓存，不显示 OSD；不能和 `--limit` 一起使用。
- `--no-clear`：播放结束后不自动清理最后一条 OSD。
- `--position`、`--font`、`--font-size`、`--title-size`、`--opacity`、`--window-opacity`、`--click-through`、`--blocks-clicks`：含义与 `show` 一致。

## 古诗词 / 古文背诵

`recite` 子命令用于普通纯文本，不需要提前写 LRC/SRT 时间戳。它会先按中文/英文逗号、句号、问号、叹号和分号初拆，再全局选择断点，让字幕句长度尽量接近、通常落在 7-20 字之间，最后按固定间隔生成字幕式 OSD：

```bash
osd-notify recite article.txt --source '兰亭序' --interval 8
osd-notify recite --text '永和九年，岁在癸丑，暮春之初。' --source '兰亭序' --interval 5
```

默认规则：

- 分隔符：`，`、`,`、`。`、`！`、`？`、`；`、`;`、`.`、`!`、`?`；句末分隔符会保留在当前句里。
- 顿号 `、` 默认不拆；它通常只是词组内停顿，拆开会破坏背诵节奏。
- 均衡断句：逗号是候选断点，句号、问号、叹号和分号是强断点；算法会尽量让每条字幕长度接近，并避免跨过强断点硬凑长度。
- 间隔：默认每 `6` 秒显示下一句；`--interval seconds` 可调整。
- 样式：默认使用 `lyric`，与 `play` 的字幕播放保持一致。
- 来源：单文件输入默认用文件名；也可以用 `--source '兰亭序'` 覆盖标题。
- 输入：支持直接文本、已有文本文件、`--file path` 和 `--stdin`。
- 预览：`--dry-run` 只打印拆句结果和时间线，不显示 OSD。
- 清理：默认播放结束后自动清理；`--no-clear` 会保留最后一句。

常用参数：

- `--interval seconds`：每句起播间隔。
- `--delimiters chars`：自定义切分字符。例如 `--delimiters '，。！？'` 会取消默认分号拆分；`--delimiters '，。！？；、'` 会额外按顿号拆分。
- `--min-chars count`：均衡断句下限，默认 `7`。
- `--max-chars count`：均衡断句软上限，默认 `20`。
- `--speed rate`：按倍率加速，适合测试。
- `--limit count`：只播放前 N 句，适合 smoke test。
- `--dry-run`：只预览拆句结果。
- `--position`、`--font`、`--font-size`、`--title-size`、`--opacity`、`--window-opacity`、`--click-through`、`--blocks-clicks`：含义与 `show` 一致。

## 样式

- `glass`：默认样式。使用 macOS 毛玻璃材质和较深的半透明隔离层，兼顾系统感和可读性。
- `soft`：低存在感的柔和马卡龙样式，默认鼠标穿透。
- `lyric`：桌面歌词式高可读样式。参考 LyricsX 和字幕样式实践，使用深色半透明底板、暖白文字、黑色阴影和细描边，适合复杂背景或深色窗口上阅读。

## 来源和堆叠

来源（`source`）是 OSD 的隔离单位：

- 同一个来源再次 `show`：旧 OSD 淡出，新 OSD 淡入。
- 不同来源同时显示：不会互相覆盖。
- 多个来源使用同一个 `--position`：后显示的 OSD 会按已有高度错开。
- `clear --source name`：只清该来源。
- `clear --all`：显式全清。

来源也会用于标题显示。比如：

- `--source codex` 显示标题 `Codex`
- `--source '黄庭坚《登快阁》'` 显示标题 `黄庭坚《登快阁》`

如果没有显式来源，工具会先看 `OSD_NOTIFY_SOURCE`、`CODEX_OSD_SOURCE`，再读取直接父进程名，并尝试通过 `NSRunningApplication(processIdentifier:)` 获取 macOS 应用显示名。

