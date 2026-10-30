# mpv-config

[中文](README.zh.md)

[mpv](https://mpv.io) configuration for macOS (Apple Silicon), with an install
script.

## Contents

- `mpv/`: `mpv.conf`, `input.conf`, `script-opts/`, `bilibili_sponsorblock.lua`, and `whisper_subs.lua`
- `sources.txt`: pinned third-party scripts, fonts, shaders and Whisper models, downloaded by `install.sh`
- `Brewfile`: mpv, yt-dlp, ffmpeg, python, whisper.cpp, node, [mpv-wrapper](https://github.com/GuMengSama/mpv-wrapper)
- `ff2mpv/ff2mpv-rust.json`: [ff2mpv-rust](https://github.com/ryze312/ff2mpv-rust) config

Third-party components: [uosc](https://github.com/tomasklaen/uosc),
[thumbfast](https://github.com/po5/thumbfast), [memo](https://github.com/po5/memo),
[SmartCopyPaste](https://github.com/Eisa01/mpv-scripts),
[uosc_danmaku](https://github.com/Tony15246/uosc_danmaku),
[mpv_sponsorblock](https://github.com/po5/mpv_sponsorblock),
[Anime4K](https://github.com/bloc97/Anime4K).
`bilibili_sponsorblock.lua` uses data from
[BilibiliSponsorBlock](https://github.com/hanydd/BilibiliSponsorBlock).

`whisper_subs.lua` generates subtitles offline with
[whisper.cpp](https://github.com/ggml-org/whisper.cpp), starting at the playhead
and staying ahead of playback. `Ctrl+g` starts and stops it; options are in
`script-opts/whisper_subs.conf`. The model (~550 MB) is downloaded by `fetch`.

## Install

Requires [Homebrew](https://brew.sh) and the Xcode command line tools
(`xcode-select --install`).

```sh
git clone https://github.com/GuMengSama/mpv-config.git
cd mpv-config
./install.sh            # all steps, each confirmed
./install.sh <step>     # one step
```

| Step | Action |
|---|---|
| `brew` | `brew bundle` |
| `fetch` | Downloads `sources.txt` entries into `mpv/` and verifies them |
| `link` | Symlinks `~/.config/mpv` to `mpv/`. An existing directory is renamed to `~/.config/mpv.backup-<date>` |
| `ff2mpv` | Builds ff2mpv-rust into `~/.local/bin`, symlinks `~/.config/ff2mpv-rust.json`, and installs the Chrome native messaging manifest. Installs Rust via rustup if absent |
| `pot` | Builds [bgutil-ytdlp-pot-provider](https://github.com/Brainicism/bgutil-ytdlp-pot-provider) in `~/bgutil-ytdlp-pot-provider` and installs its yt-dlp plugin. YouTube refuses many streams without the PO tokens it generates |

Existing ff2mpv files are not overwritten. Then install the
[ff2mpv extension](https://chromewebstore.google.com/detail/ff2mpv/ephjcajbkgplkjmelpglennepbpmdpjg)
and restart Chrome.

`mpv.conf` passes Chrome's cookies to yt-dlp. macOS blocks this when Chrome
starts mpv, so give `~/.local/bin/ff2mpv-rust` Full Disk Access (System
Settings → Privacy & Security). Without it, no video opens from ff2mpv. Repeat
after every `ff2mpv` step, as macOS drops the access when the binary changes.

After `link`, moving the repository breaks the symlink; run `./install.sh link`
again.

## Updating

Edits to `~/.config/mpv` are edits to this repository. To update a third-party
component, change its commit or URL and SHA-256 in `sources.txt` and run
`./install.sh fetch`.

## License

[MIT](LICENSE). Downloaded components keep their own licenses.
