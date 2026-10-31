#!/bin/bash
# Restores this mpv setup on a Mac. Asks before each step and is safe to re-run.
#
#   ./install.sh            run every step
#   ./install.sh <step>     run one step: brew, fetch, link, ff2mpv, pot, whisper
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
MPV_DIR="$HOME/.config/mpv"
FF2MPV_REPO=https://github.com/ryze312/ff2mpv-rust
FF2MPV_COMMIT=14d663e14b5ca5a9106e9da5c171ae8044ef280c # tag 1.1.7
FF2MPV_CONFIG="$HOME/.config/ff2mpv-rust.json"
CHROME_HOSTS="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
SIGN_NAME="ff2mpv-rust local signing"
POT_REPO=https://github.com/Brainicism/bgutil-ytdlp-pot-provider
POT_VERSION=2.0.2
POT_COMMIT=26475e9d3665b972c4aeb83b4dbaafcf64b88438 # tag 2.0.2
POT_ZIP_SHA256=a26b980bf6d8e8400d8f21445daa4d8381bf6183d20f0be309391f86b31e27ef
POT_DIR="$HOME/bgutil-ytdlp-pot-provider"
YTDLP_PLUGINS="$HOME/.config/yt-dlp/plugins"

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

# Downloads the entries of a sources file into mpv/ and verifies them
fetch_sources() {
    local kind url pin src dest dir
    while read -r kind url pin src dest; do
        [[ -z $kind || $kind == \#* ]] && continue
        if [[ $kind == file && -f $REPO/mpv/$dest ]] &&
            echo "$pin  $REPO/mpv/$dest" | shasum -a 256 -c --quiet 2>/dev/null; then
            continue
        fi
        dir="$WORK/$(basename "$url")-${pin:0:12}"
        if [[ ! -d $dir ]]; then
            echo "Downloading $url"
            if [[ $kind == git ]]; then
                checkout "$url" "$pin" "$dir"
            elif [[ $kind == file ]]; then
                mkdir "$dir"
                curl -fsSL -o "$dir/$src" "$url"
                echo "$pin  $dir/$src" | shasum -a 256 -c --quiet
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
        if [[ -f $REPO/patches/$dest.patch ]]; then
            patch -s "$REPO/mpv/$dest" < "$REPO/patches/$dest.patch"
            echo "Applied patches/$dest.patch"
        fi
    done < "$1"
}

step_fetch() {
    fetch_sources "$REPO/sources.txt"
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

# Creates a self-signed code signing certificate in the login keychain, made on
# this Mac and never shared, and trusts it for code signing only
make_signing_identity() {
    if ! security find-certificate -c "$SIGN_NAME" >/dev/null 2>&1; then
        echo "Creating the code signing certificate \"$SIGN_NAME\""
        cat > "$WORK/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $SIGN_NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF
        /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$WORK/cert.cnf" \
            -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null
        /usr/bin/openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
            -out "$WORK/id.p12" -passout pass:ff2mpv
        security import "$WORK/id.p12" -P ff2mpv -T /usr/bin/codesign >/dev/null
        rm -f "$WORK/key.pem" "$WORK/id.p12"
    fi
    security find-certificate -c "$SIGN_NAME" -p > "$WORK/cert.pem"
    echo "macOS asks for your password to trust \"$SIGN_NAME\" for code signing"
    security add-trusted-cert -p codeSign "$WORK/cert.pem"
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

    # mpv.conf has yt-dlp read Chrome's cookies, which macOS only allows a
    # process started by Chrome if ff2mpv-rust has Full Disk Access. macOS ties
    # that access to the signature, so sign with a fixed certificate: an
    # unsigned build loses the access on every rebuild
    local new_identity=false
    if ! security find-identity -v -p codesigning | grep -qF "\"$SIGN_NAME\""; then
        make_signing_identity
        new_identity=true
    fi
    codesign -f -s "$SIGN_NAME" -i ff2mpv-rust "$HOME/.local/bin/ff2mpv-rust"
    echo "Signed it with \"$SIGN_NAME\""
    if $new_identity; then
        echo "Add $HOME/.local/bin/ff2mpv-rust to Full Disk Access (Cmd+Shift+G in the"
        echo "file picker types a path), replacing any existing ff2mpv-rust entry."
        echo "Without it, no video opens from ff2mpv. It is needed only once."
        open "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles"
    fi

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

# YouTube refuses many streams without a PO token. This builds the generator
# that yt-dlp's bgutil plugin runs on demand, and installs the plugin
step_pot() {
    if [[ -d $POT_DIR && "$(git -C "$POT_DIR" rev-parse HEAD 2>/dev/null)" != "$POT_COMMIT" ]]; then
        echo "Left the existing $POT_DIR alone; it is not at tag $POT_VERSION"
        return
    fi
    if [[ ! -d $POT_DIR ]]; then
        checkout "$POT_REPO" "$POT_COMMIT" "$POT_DIR"
    fi
    (cd "$POT_DIR/server" && npm ci --no-audit --no-fund && npx tsc)
    echo "Built the PO token generator in $POT_DIR"

    curl -fsSL -o "$WORK/pot.zip" "$POT_REPO/releases/download/$POT_VERSION/bgutil-ytdlp-pot-provider.zip"
    echo "$POT_ZIP_SHA256  $WORK/pot.zip" | shasum -a 256 -c --quiet
    mkdir -p "$YTDLP_PLUGINS"
    cp "$WORK/pot.zip" "$YTDLP_PLUGINS/bgutil-ytdlp-pot-provider.zip"
    echo "Installed the yt-dlp plugin in $YTDLP_PLUGINS"
}

# Optional: whisper.cpp and its models (~550 MB) for whisper_subs.lua
step_whisper() {
    if ! command -v brew >/dev/null; then
        echo "Homebrew is not installed. Install it from https://brew.sh, then run this again."
        exit 1
    fi
    brew install whisper.cpp
    fetch_sources "$REPO/sources-whisper.txt"
    echo "Whisper models are in $REPO/mpv/models; Ctrl+g in mpv generates subtitles"
}

run() {
    local question
    case $1 in
        brew)   question="Install Homebrew packages from the Brewfile?" ;;
        fetch)  question="Download the pinned third-party scripts, fonts, shaders and models into $REPO/mpv?" ;;
        link)   question="Point $MPV_DIR at $REPO/mpv (an existing one is renamed to a backup)?" ;;
        ff2mpv) question="Build ff2mpv-rust and install its config and Chrome manifest?" ;;
        pot)    question="Build the YouTube PO token provider in $POT_DIR and install its yt-dlp plugin?" ;;
        whisper) question="Optional: install whisper.cpp and download its models (~550 MB) for offline subtitles?" ;;
        *)      echo "Unknown step: $1 (use brew, fetch, link, ff2mpv, pot or whisper)"; exit 1 ;;
    esac
    # Not "ask && step": set -e is ignored inside a function called from an && list
    if ask "$question"; then
        "step_$1"
    fi
}

if [[ $# -gt 0 ]]; then
    run "$1"
else
    for step in brew fetch link ff2mpv pot whisper; do run "$step"; done
fi
