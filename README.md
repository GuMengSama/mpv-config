# mpv-config

[中文](README.zh.md)

[mpv](https://mpv.io) configuration for macOS (Apple Silicon), with an install
script.

## Contents

- `mpv/`: `mpv.conf`, `input.conf`, `script-opts/`, `bilibili_sponsorblock.lua`, and `whisper_subs.lua`
- `sources.txt`: pinned third-party scripts, fonts and shaders, downloaded by `install.sh`
- `sources-whisper.txt`: pinned Whisper models, downloaded by the optional `whisper` step
- `Brewfile`: mpv, yt-dlp, ffmpeg, python, node, [mpv-wrapper](https://github.com/GuMengSama/mpv-wrapper)
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
`script-opts/whisper_subs.conf`. It is optional: the `whisper` step installs
whisper.cpp and downloads the models (~550 MB).

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
| `ff2mpv` | Builds ff2mpv-rust into `~/.local/bin`, symlinks `~/.config/ff2mpv-rust.json`, and installs the Chrome native messaging manifest. Signs the binary with a local certificate (see below). Installs Rust via rustup if absent |
| `pot` | Builds [bgutil-ytdlp-pot-provider](https://github.com/Brainicism/bgutil-ytdlp-pot-provider) in `~/bgutil-ytdlp-pot-provider` and installs its yt-dlp plugin. YouTube refuses many streams without the PO tokens it generates |
| `whisper` | Optional. Installs whisper.cpp and downloads `sources-whisper.txt` entries into `mpv/` for `whisper_subs.lua`. Skip it if you don't need generated subtitles |

Existing ff2mpv files are not overwritten. Then install the
[ff2mpv extension](https://chromewebstore.google.com/detail/ff2mpv/ephjcajbkgplkjmelpglennepbpmdpjg)
and restart Chrome.

### Full Disk Access

`mpv.conf` has yt-dlp read Chrome's cookies, which YouTube requires and which
unlock login-only qualities elsewhere. When Chrome starts mpv, macOS allows this
only if `~/.local/bin/ff2mpv-rust` has Full Disk Access.

The first `ff2mpv` step creates a certificate named "ff2mpv-rust local signing"
in the login keychain, asks for your password to trust it for code signing, and
opens System Settings. Add `~/.local/bin/ff2mpv-rust` there (Cmd+Shift+G types a
path). Later builds are signed with the same certificate, so the access stays.

After `link`, moving the repository breaks the symlink; run `./install.sh link`
again.

## Troubleshooting

- No window opens from ff2mpv: check that `ff2mpv-rust` is enabled under Full
  Disk Access. If it is, remove it and add it again.
- YouTube asks to sign in: sign in to YouTube in Chrome. If it persists, run
  `brew upgrade yt-dlp`.
- To see why a video fails, run
  `mpv --msg-level=ytdl_hook=v '<url>'` in a terminal.

## Updating

Edits to `~/.config/mpv` are edits to this repository. To update a third-party
component, change its commit or URL and SHA-256 in `sources.txt` and run
`./install.sh fetch`.

## License

[MIT](LICENSE). Downloaded components keep their own licenses.
