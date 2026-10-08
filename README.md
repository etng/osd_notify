# osd-notify

`osd-notify` 是一个 macOS 屏幕提示命令行工具。它会在所有显示器上显示清晰的浮层，适合在自动化、长任务或需要暂停手动操作时提醒使用者。

## 系统要求

- macOS 13 或更高版本
- Apple Silicon 或 Intel Mac

## 安装

推荐使用 Homebrew 安装，直接下载公开 Release，无需 GitHub 登录：

```bash
brew install etng/taps/osd-notify
```

Homebrew 会随 `brew update` 获取新 Formula；检查并安装更新：

```bash
brew update
brew outdated osd-notify
brew upgrade osd-notify
```

也可以直接下载最新版通用二进制：

```bash
curl -fL -o osd-notify-macos-universal \
  https://github.com/etng/osd_notify/releases/latest/download/osd-notify-macos-universal
chmod +x osd-notify-macos-universal
sudo install osd-notify-macos-universal /usr/local/bin/osd-notify
sudo xattr -dr com.apple.quarantine /usr/local/bin/osd-notify
```

Release 同时提供压缩包和 `SHA256SUMS` 校验文件。

二进制使用 ad-hoc 签名，未做 Apple 公证。Homebrew 安装后会自动移除本程序的 quarantine 标记；该步骤也可以通过 `brew postinstall etng/taps/osd-notify` 重新执行。

### 从源码一键打包、安装并运行

在仓库根目录执行（需要已安装 Xcode Command Line Tools，包含 Swift）：

```bash
make
```

该命令依次完成 Release 构建、生成当前 Mac 架构的压缩包和 SHA-256 校验文件、安装到 `~/.local/bin/osd-notify`，然后显示一次“任务完成”提示，60 秒后自动消失。打包产物位于 `dist/`；这是当前架构的二进制，不是 Release 中的通用二进制。

自定义提示文字：

```bash
make MESSAGE='打包安装完成'
```

日常直接输入 `osd-notify` 时，请确保 `~/.local/bin` 已加入 `PATH`，否则可使用 `~/.local/bin/osd-notify` 调用。

## 快速开始

查看当前版本和检查最新 Release：

```bash
osd-notify --version
osd-notify check-update
```

更新检查需要已安装并登录的 [GitHub CLI](https://cli.github.com/)，工具不会保存访问令牌；Homebrew 安装和 Release 下载无需登录。

显示默认提醒：

```bash
osd-notify show
```

显示自定义提醒：

```bash
osd-notify show "Chrome 正在由自动化控制，请暂时不要操作" \
  --source codex \
  --ttl 600 \
  --level busy
```

任务结束后清除同一来源的提醒：

```bash
osd-notify clear --source codex
```

## 常用功能

### 提醒样式

```bash
osd-notify show "任务完成" --level done --ttl 60
osd-notify show "请注意当前操作" --level warn
osd-notify show "落木千山天远大，澄江一道月分明。" \
  --source '黄庭坚《登快阁》' \
  --style lyric
```

可用等级为 `info`、`warn`、`busy` 和 `done`；可用位置为 `top`、`center` 和 `bottom`；可用样式为 `soft`、`glass` 和 `lyric`。

### 链接

```bash
osd-notify show "查看任务结果" --url https://example.com/result
```

浮层右下角会出现链接图标，点击后使用默认浏览器打开。

### 定时字幕

```bash
osd-notify play song.lrc
osd-notify play subtitle.srt --speed 2
osd-notify play movie.mkv
```

支持 LRC、SRT，以及视频容器中的常见文本字幕。视频字幕需要系统中可用的 `ffprobe` 和 `ffmpeg`。

### 普通文本背诵

```bash
osd-notify recite article.txt --source '兰亭序' --interval 8
osd-notify recite --text '永和九年，岁在癸丑，暮春之初。'
```

工具会自动断句，并按固定间隔用歌词样式显示。

### 在线诗文

```bash
osd-notify poem random
osd-notify poem 劝学
osd-notify poetry random
```

`poem` 使用本地缓存的古文池，`poetry` 从在线诗词服务获取内容；首次使用或刷新内容时需要联网。

## `show` 参数

- `--source name`：设置提醒来源；同一来源的新提醒会替换旧提醒。
- `--ttl seconds`：设置自动消失时间，单位为秒。
- `--level info|warn|busy|done`：设置提醒等级。
- `--position top|center|bottom`：设置默认显示位置。
- `--style soft|glass|lyric`：设置视觉样式。
- `--url https://...`：绑定可点击链接。
- `--font name`：设置字体。
- `--font-size points`：设置正文大小。
- `--title-size points`：设置标题大小。
- `--opacity 0...1`：设置背景透明度，也支持 `42%` 形式。
- `--window-opacity 0...1`：设置整个浮层透明度。
- `--click-through`：让鼠标操作穿过浮层。
- `--blocks-clicks`：让浮层接收鼠标操作，以便拖动、关闭或打开链接。

不认识的 `--xxx` 参数会直接报错，不会混入提醒正文。当正文需要以 `--` 开头时，使用单独的 `--` 结束参数解析：

```bash
osd-notify show --source example -- "-- 这是一条正文"
```

## 清理提醒

```bash
osd-notify clear --source codex
osd-notify clear --all
```

默认只清理当前来源。`--all` 会清理所有来源，请只在确实需要时使用。

## 交互

- 同一来源的新提醒会替换旧提醒，不同来源可以同时显示。
- 浮层会在多个显示器上同步出现。
- 可交互浮层支持拖动，并会记住同一来源的位置。
- 双击标题行可显示关闭按钮。
- 使用 `--click-through` 后，拖动、手动关闭和链接点击不可用。

## 状态与日志

```bash
osd-notify status
osd-notify logs
```

`status` 会检查守护进程数量和本地服务状态。`logs` 会显示最近的结构化诊断事件；为了方便完整追溯，每次调用的命令行参数都会原样记录在仅当前用户可读写的本机轮转日志中。请不要直接在命令行参数里传入密码或访问令牌。

查看完整帮助：

```bash
osd-notify --help
```
