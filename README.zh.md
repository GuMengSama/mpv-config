# mpv-config

[English](README.md)

适用于 macOS（Apple Silicon）的 [mpv](https://mpv.io) 配置及安装脚本。

## 内容

- `mpv/`：`mpv.conf`、`input.conf`、`script-opts/`、`bilibili_sponsorblock.lua` 和 `whisper_subs.lua`
- `sources.txt`：固定版本的第三方脚本、字体、着色器和 Whisper 模型，由 `install.sh` 下载
- `Brewfile`：mpv、yt-dlp、ffmpeg、python、whisper.cpp、[mpv-wrapper](https://github.com/GuMengSama/mpv-wrapper)
- `ff2mpv/ff2mpv-rust.json`：[ff2mpv-rust](https://github.com/ryze312/ff2mpv-rust) 配置

第三方组件：[uosc](https://github.com/tomasklaen/uosc)、
[thumbfast](https://github.com/po5/thumbfast)、[memo](https://github.com/po5/memo)、
[SmartCopyPaste](https://github.com/Eisa01/mpv-scripts)、
[uosc_danmaku](https://github.com/Tony15246/uosc_danmaku)、
[mpv_sponsorblock](https://github.com/po5/mpv_sponsorblock)、
[Anime4K](https://github.com/bloc97/Anime4K)。
`bilibili_sponsorblock.lua` 的数据来自
[BilibiliSponsorBlock](https://github.com/hanydd/BilibiliSponsorBlock)。

`whisper_subs.lua` 使用 [whisper.cpp](https://github.com/ggml-org/whisper.cpp)
离线生成字幕，从当前播放位置开始并保持领先于播放进度。`Ctrl+g` 开始或停止；
选项见 `script-opts/whisper_subs.conf`。模型（约 550 MB）由 `fetch` 下载。

## 安装

需要 [Homebrew](https://brew.sh) 和 Xcode 命令行工具（`xcode-select --install`）。

```sh
git clone https://github.com/GuMengSama/mpv-config.git
cd mpv-config
./install.sh            # 执行全部步骤，逐步确认
./install.sh <步骤>     # 执行单个步骤
```

| 步骤 | 操作 |
|---|---|
| `brew` | `brew bundle` |
| `fetch` | 下载 `sources.txt` 中的条目到 `mpv/` 并校验 |
| `link` | 将 `~/.config/mpv` 链接到 `mpv/`。已有目录会重命名为 `~/.config/mpv.backup-<日期>` |
| `ff2mpv` | 编译 ff2mpv-rust 到 `~/.local/bin`，链接 `~/.config/ff2mpv-rust.json`，并安装 Chrome native messaging 清单。未安装 Rust 时通过 rustup 安装 |

不会覆盖已有的 ff2mpv 文件。完成后安装
[ff2mpv 扩展](https://chromewebstore.google.com/detail/ff2mpv/ephjcajbkgplkjmelpglennepbpmdpjg)
并重启 Chrome。

执行 `link` 后移动仓库会使链接失效，需重新执行 `./install.sh link`。

## 更新

修改 `~/.config/mpv` 即修改本仓库。更新第三方组件时，在 `sources.txt` 中修改其 commit 或 URL 及 SHA-256，然后执行 `./install.sh fetch`。

## 许可证

[MIT](LICENSE)。下载的组件沿用各自的许可证。
