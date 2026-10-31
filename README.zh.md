# mpv-config

[English](README.md)

适用于 macOS（Apple Silicon）的 [mpv](https://mpv.io) 配置及安装脚本。

## 内容

- `mpv/`：`mpv.conf`、`input.conf`、`script-opts/`、`anime4k.lua`、`bilibili_sponsorblock.lua`、`sprite_thumbnails.lua` 和 `whisper_subs.lua`
- `sources.txt`：固定版本的第三方脚本、字体、着色器和 Whisper 模型，每项标明所属功能，由 `install.sh` 下载
- `patches/`：`fetch` 对下载文件应用的本地修改（thumbfast 将 B 站和 YouTube 视频交给 `sprite_thumbnails.lua`，并转发网站的 HTTP 请求头）
- `Brewfile`：mpv、yt-dlp、ffmpeg、[mpv-wrapper](https://github.com/GuMengSama/mpv-wrapper)
- `ff2mpv/ff2mpv-rust.json`：[ff2mpv-rust](https://github.com/ryze312/ff2mpv-rust) 配置

第三方组件：[uosc](https://github.com/tomasklaen/uosc)、
[thumbfast](https://github.com/po5/thumbfast)、[memo](https://github.com/po5/memo)、
[SmartCopyPaste](https://github.com/Eisa01/mpv-scripts)、
[uosc_danmaku](https://github.com/Tony15246/uosc_danmaku)、
[mpv_sponsorblock](https://github.com/po5/mpv_sponsorblock)、
[Anime4K](https://github.com/bloc97/Anime4K)。
`bilibili_sponsorblock.lua` 的数据来自
[BilibiliSponsorBlock](https://github.com/hanydd/BilibiliSponsorBlock)。
`sprite_thumbnails.lua` 使用 B 站和 YouTube 网页所用的预览图为进度条显示缩略图，即时出现；
本地文件和其他网站仍由 thumbfast 生成。

`whisper_subs.lua` 使用 [whisper.cpp](https://github.com/ggml-org/whisper.cpp)
离线生成字幕，从当前播放位置开始并保持领先于播放进度。`Ctrl+g` 开始或停止；
选项见 `script-opts/whisper_subs.conf`。需要可选的 Whisper 功能（见下文），
它会安装 whisper.cpp 并下载模型（约 550 MB）。

## 安装

需要 [Homebrew](https://brew.sh) 和 Xcode 命令行工具（`xcode-select --install`）。

```sh
git clone https://github.com/GuMengSama/mpv-config.git
cd mpv-config
./install.sh            # 选择功能后安装
./install.sh <步骤>     # 执行单个步骤
```

`install.sh` 先列出可选功能。输入编号切换选择（如 `3 5`），按回车，核对摘要后确认：

```
Choose what to install (mpv, uosc, thumbnails and the config are always installed):
  1) [x] Browser button: open videos from Chrome in mpv (ff2mpv, built with Rust)
  2) [x] YouTube support: PO token provider YouTube needs for most streams (node)
  3) [x] Bilibili danmaku: bullet comments on Bilibili videos (uosc_danmaku)
  4) [x] SponsorBlock: skip sponsored segments on YouTube and Bilibili (python)
  5) [ ] Anime4K shaders: anime upscaling, Ctrl+1-6
  6) [ ] Whisper subtitles: offline subtitles with whisper.cpp, Ctrl+g (~550 MB)
```

选择保存在 `.install-features` 中。再次运行 `./install.sh` 即可增删功能：它从上次的选择开始，
并删除被关闭功能的文件（Homebrew 软件包保留）。本仓库自带的功能（如 uosc 中的弹幕按钮和
`bilibili_sponsorblock.lua`）通过 `install.sh` 写入的 `mpv/features.conf` 关闭。

以下步骤按顺序为所选功能执行，也可单独执行：

| 步骤 | 操作 |
|---|---|
| `brew` | `brew bundle`，并为需要的功能安装 node、python 或 whisper.cpp |
| `fetch` | 下载所选功能在 `sources.txt` 中的条目到 `mpv/`，校验、应用 `patches/`，并写入 `mpv/features.conf` |
| `link` | 将 `~/.config/mpv` 链接到 `mpv/`。已有目录会重命名为 `~/.config/mpv.backup-<日期>` |
| `ff2mpv` | 编译 ff2mpv-rust 到 `~/.local/bin`，链接 `~/.config/ff2mpv-rust.json`，并安装 Chrome native messaging 清单。用本机证书为其签名（见下文）。未安装 Rust 时通过 rustup 安装 |
| `pot` | 在 `~/bgutil-ytdlp-pot-provider` 编译 [bgutil-ytdlp-pot-provider](https://github.com/Brainicism/bgutil-ytdlp-pot-provider) 并安装其 yt-dlp 插件。YouTube 的许多视频流需要它生成的 PO token |
| `whisper` | 为已有安装添加 Whisper 功能：安装 whisper.cpp 并下载模型 |

选择浏览器按钮功能时执行 `ff2mpv`，选择 YouTube 支持时执行 `pot`。
不会覆盖已有的 ff2mpv 文件。完成后安装
[ff2mpv 扩展](https://chromewebstore.google.com/detail/ff2mpv/ephjcajbkgplkjmelpglennepbpmdpjg)
并重启 Chrome。

### 完全磁盘访问权限

`mpv.conf` 让 yt-dlp 读取 Chrome 的 cookies：YouTube 必须登录，其他网站可借此获得需登录的画质。
由 Chrome 启动 mpv 时，只有 `~/.local/bin/ff2mpv-rust` 拥有完全磁盘访问权限，macOS 才允许读取。

首次执行 `ff2mpv` 步骤会在登录钥匙串中创建名为 "ff2mpv-rust local signing" 的证书，
要求输入密码将其设为代码签名可信，并打开系统设置。在其中添加 `~/.local/bin/ff2mpv-rust`
（Cmd+Shift+G 可输入路径）。之后的编译使用同一证书签名，权限保持有效。

执行 `link` 后移动仓库会使链接失效，需重新执行 `./install.sh link`。

## 故障排除

- ff2mpv 打不开窗口：检查完全磁盘访问权限中是否已启用 `ff2mpv-rust`；若已启用，移除后重新添加。
- YouTube 要求登录：在 Chrome 中登录 YouTube。仍有问题时执行 `brew upgrade yt-dlp`。
- 查看视频失败原因：在终端执行 `mpv --msg-level=ytdl_hook=v '<url>'`。

## 更新

修改 `~/.config/mpv` 即修改本仓库。更新第三方组件时，在 `sources.txt` 中修改其 commit 或 URL 及 SHA-256，然后执行 `./install.sh fetch`。`git pull` 之后也要执行，以更新下载、补丁和 `mpv/features.conf`。

## 许可证

[MIT](LICENSE)。下载的组件沿用各自的许可证。
