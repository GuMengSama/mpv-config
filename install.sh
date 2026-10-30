#!/bin/bash
# Restores this mpv setup on a Mac. Asks before each step and is safe to re-run.
#
#   ./install.sh            run every step
#   ./install.sh <step>     run one step: brew, fetch, link, ff2mpv
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
MPV_DIR="$HOME/.config/mpv"
FF2MPV_REPO=https://github.com/ryze312/ff2mpv-rust
FF2MPV_COMMIT=14d663e14b5ca5a9106e9da5c171ae8044ef280c # tag 1.1.7
FF2MPV_CONFIG="$HOME/.config/ff2mpv-rust.json"
CHROME_HOSTS="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

ask() {
    local reply
    read -r -p "$1 [y/N] " reply
    [[ $reply == [yY]* ]]
}

# Checks out one commit of a git repo into a new directory
checkout() {
    git init -q "$3"
    git -C "$3" fetch -q --depth 1 "$1" "$2"
    git -C "$3" checkout -q FETCH_HEAD
}

step_brew() {
    if ! command -v brew >/dev/null; then
        echo "Homebrew is not installed. Install it from https://brew.sh, then run this again."
        exit 1
    fi
    brew bundle --file "$REPO/Brewfile"
}

step_fetch() {
    local kind url pin src dest dir
    while read -r kind url pin src dest; do
        [[ -z $kind || $kind == \#* ]] && continue
        dir="$WORK/$(basename "$url")-${pin:0:12}"
        if [[ ! -d $dir ]]; then
            echo "Downloading $url"
            if [[ $kind == git ]]; then
                checkout "$url" "$pin" "$dir"
            else
                curl -fsSL -o "$dir.zip" "$url"
                echo "$pin  $dir.zip" | shasum -a 256 -c --quiet
                unzip -q "$dir.zip" -d "$dir"
            fi
        fi
        rm -rf "${REPO:?}/mpv/$dest"
        mkdir -p "$(dirname "$REPO/mpv/$dest")"
        if [[ -d $dir/$src ]]; then
            rsync -a --exclude '.git*' "$dir/$src/" "$REPO/mpv/$dest/"
        else
            cp "$dir/$src" "$REPO/mpv/$dest"
        fi
    done < "$REPO/sources.txt"
    echo "Third-party scripts, fonts and shaders are in $REPO/mpv"
}

step_link() {
    if [[ -L $MPV_DIR && "$(readlink "$MPV_DIR")" == "$REPO/mpv" ]]; then
        echo "$MPV_DIR already points to $REPO/mpv"
        return
    fi
    if [[ -e $MPV_DIR || -L $MPV_DIR ]]; then
        local backup
        backup="$MPV_DIR.backup-$(date +%Y%m%d-%H%M%S)"
        mv "$MPV_DIR" "$backup"
        echo "Moved the existing $MPV_DIR to $backup"
    fi
    mkdir -p "$(dirname "$MPV_DIR")"
    ln -s "$REPO/mpv" "$MPV_DIR"
    echo "Linked $MPV_DIR to $REPO/mpv"
}

step_ff2mpv() {
    local cargo="$HOME/.cargo/bin/cargo"
    if [[ ! -x $cargo ]]; then
        if ! ask "Rust is needed to build ff2mpv-rust. Install it with rustup (minimal profile)?"; then
            return
        fi
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
    fi

    checkout "$FF2MPV_REPO" "$FF2MPV_COMMIT" "$WORK/ff2mpv-rust"
    "$cargo" build --release --locked --manifest-path "$WORK/ff2mpv-rust/Cargo.toml"
    mkdir -p "$HOME/.local/bin"
    install -m 755 "$WORK/ff2mpv-rust/target/release/ff2mpv-rust" "$HOME/.local/bin/ff2mpv-rust"
    echo "Installed $HOME/.local/bin/ff2mpv-rust"

    if [[ -L $FF2MPV_CONFIG && "$(readlink "$FF2MPV_CONFIG")" == "$REPO/ff2mpv/ff2mpv-rust.json" ]]; then
        echo "$FF2MPV_CONFIG already points to the repo"
    elif [[ -e $FF2MPV_CONFIG ]]; then
        echo "Left the existing $FF2MPV_CONFIG alone; compare it with $REPO/ff2mpv/ff2mpv-rust.json"
    else
        ln -s "$REPO/ff2mpv/ff2mpv-rust.json" "$FF2MPV_CONFIG"
        echo "Linked $FF2MPV_CONFIG to the repo"
    fi

    local manifest="$CHROME_HOSTS/ff2mpv.json"
    mkdir -p "$CHROME_HOSTS"
    "$HOME/.local/bin/ff2mpv-rust" manifest_chromium > "$WORK/ff2mpv.json"
    if [[ ! -e $manifest ]]; then
        cp "$WORK/ff2mpv.json" "$manifest"
        echo "Installed the Chrome manifest; restart Chrome with Cmd+Q to load it"
    elif cmp -s "$WORK/ff2mpv.json" "$manifest"; then
        echo "The Chrome manifest is already installed"
    else
        echo "Left the existing $manifest alone; it differs from:"
        cat "$WORK/ff2mpv.json"
    fi
}

run() {
    local question
    case $1 in
        brew)   question="Install Homebrew packages from the Brewfile?" ;;
        fetch)  question="Download the pinned third-party scripts, fonts and shaders into $REPO/mpv?" ;;
        link)   question="Point $MPV_DIR at $REPO/mpv (an existing one is renamed to a backup)?" ;;
        ff2mpv) question="Build ff2mpv-rust and install its config and Chrome manifest?" ;;
        *)      echo "Unknown step: $1 (use brew, fetch, link or ff2mpv)"; exit 1 ;;
    esac
    # Not "ask && step": set -e is ignored inside a function called from an && list
    if ask "$question"; then
        "step_$1"
    fi
}

if [[ $# -gt 0 ]]; then
    run "$1"
else
    for step in brew fetch link ff2mpv; do run "$step"; done
fi
