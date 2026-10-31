#!/bin/bash
# Restores this mpv setup on a Mac. Asks which features to install, then
# installs them. Safe to re-run, also to add or remove features.
#
#   ./install.sh            choose features, then install
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
CHOICES="$REPO/.install-features"

# Optional features. mpv, yt-dlp, ffmpeg, uosc, thumbnails and the config are
# always installed. sources.txt names the feature each download belongs to
FEATURES=(ff2mpv youtube danmaku sponsorblock anime4k whisper)
NAMES=("Browser button" "YouTube support" "Bilibili danmaku" "SponsorBlock" "Anime4K shaders" "Whisper subtitles")
DETAILS=(
    "open videos from Chrome in mpv (ff2mpv, built with Rust)"
    "PO token provider YouTube needs for most streams (node)"
    "bullet comments on Bilibili videos (uosc_danmaku)"
    "skip sponsored segments on YouTube and Bilibili (python)"
    "anime upscaling, Ctrl+1-6"
    "offline subtitles with whisper.cpp, Ctrl+g (~550 MB)"
)
DEFAULTS=(1 1 1 1 0 0)
CHOSEN=("${DEFAULTS[@]}")

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

# Whether a feature is on this Mac, for installs made before choices were saved
installed() {
    case $1 in
        ff2mpv) [[ -x $HOME/.local/bin/ff2mpv-rust ]] ;;
        youtube) [[ -d $POT_DIR ]] ;;
        danmaku) [[ -d $REPO/mpv/scripts/uosc_danmaku ]] ;;
        sponsorblock) [[ -f $REPO/mpv/scripts/sponsorblock.lua ]] ;;
        anime4k) [[ -d $REPO/mpv/shaders ]] ;;
        whisper) [[ -d $REPO/mpv/models ]] ;;
    esac
}

# Starts from the last saved choices. Without them, an existing install keeps
# what it has, so nothing is removed; a fresh clone gets the defaults
load_choices() {
    local i
    if [[ -f $CHOICES ]]; then
        for i in "${!FEATURES[@]}"; do
            if grep -qx "${FEATURES[i]}" "$CHOICES"; then CHOSEN[i]=1; else CHOSEN[i]=0; fi
        done
    elif [[ -d $REPO/mpv/scripts/uosc ]]; then
        for i in "${!FEATURES[@]}"; do
            if installed "${FEATURES[i]}"; then CHOSEN[i]=1; else CHOSEN[i]=0; fi
        done
    fi
}

save_choices() {
    local i
    : > "$CHOICES"
    for i in "${!FEATURES[@]}"; do
        if [[ ${CHOSEN[i]} == 1 ]]; then echo "${FEATURES[i]}" >> "$CHOICES"; fi
    done
}

choose() {
    local i
    for i in "${!FEATURES[@]}"; do
        if [[ ${FEATURES[i]} == "$1" ]]; then CHOSEN[i]=1; fi
    done
}

chosen() {
    [[ $1 == core ]] && return 0
    local i
    for i in "${!FEATURES[@]}"; do
        [[ ${FEATURES[i]} == "$1" ]] && { [[ ${CHOSEN[i]} == 1 ]]; return; }
    done
    return 1
}

choose_features() {
    local i n reply mark
    while true; do
        echo
        echo "Choose what to install (mpv, uosc, thumbnails and the config are always installed):"
        for i in "${!FEATURES[@]}"; do
            mark=" "
            if [[ ${CHOSEN[i]} == 1 ]]; then mark=x; fi
            printf "  %d) [%s] %s: %s\n" $((i + 1)) "$mark" "${NAMES[i]}" "${DETAILS[i]}"
        done
        read -r -p "Numbers to toggle (e.g. 3 5), Enter to continue: " reply
        [[ -z $reply ]] && break
        for n in $reply; do
            if [[ $n =~ ^[0-9]+$ ]] && ((n >= 1 && n <= ${#FEATURES[@]})); then
                CHOSEN[n - 1]=$((1 - CHOSEN[n - 1]))
            else
                echo "Ignored $n"
            fi
        done
    done

    local on="" off=""
    for i in "${!FEATURES[@]}"; do
        if [[ ${CHOSEN[i]} == 1 ]]; then on+="${on:+, }${NAMES[i]}"; else off+="${off:+, }${NAMES[i]}"; fi
    done
    echo
    echo "Install:     mpv, uosc, thumbnails, config${on:+, $on}"
    if [[ -n $off ]]; then
        echo "Leave out:   $off"
        echo "             (their files in mpv/ are removed; Homebrew packages, ff2mpv and"
        echo "             the PO token provider stay installed if you had them)"
    fi
    if [[ -e $MPV_DIR || -L $MPV_DIR ]] && [[ "$(readlink "$MPV_DIR" || true)" != "$REPO/mpv" ]]; then
        echo "Your existing $MPV_DIR is renamed to a backup and replaced by a link to $REPO/mpv"
    fi
    ask "Continue?"
}

need_brew() {
    if ! command -v brew >/dev/null; then
        echo "Homebrew is not installed. Install it from https://brew.sh, then run this again."
        exit 1
    fi
}

step_brew() {
    need_brew
    brew bundle --file "$REPO/Brewfile"
    local packages=()
    if chosen youtube; then packages+=(node); fi
    if chosen sponsorblock; then packages+=(python); fi
    if chosen whisper; then packages+=(whisper.cpp); fi
    if [[ ${#packages[@]} -gt 0 ]]; then brew install "${packages[@]}"; fi
}

# Downloads the sources.txt entries of the chosen features into mpv/ and
# verifies them, and removes those of features that are not chosen
fetch_sources() {
    local feature kind url pin src dest dir
    while read -r feature kind url pin src dest; do
        [[ -z $feature || $feature == \#* ]] && continue
        if [[ -z $dest || ( $feature != core && " ${FEATURES[*]} " != *" $feature "* ) ]]; then
            echo "Bad line in sources.txt: $feature $kind $url"
            exit 1
        fi
        if ! chosen "$feature"; then
            if [[ -e $REPO/mpv/$dest ]]; then
                rm -rf "${REPO:?}/mpv/$dest"
                echo "Removed mpv/$dest"
            fi
            continue
        fi
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
    done < "$REPO/sources.txt"
}

# mpv loads every script in scripts/, so features that live in this repo are
# turned off here instead. mpv.conf includes this file
write_features_conf() {
    local conf="$REPO/mpv/features.conf" controls
    {
        echo "# Written by install.sh from your feature choices; edits are overwritten."
        echo "# Run ./install.sh fetch after changing controls in script-opts/uosc.conf"
    } > "$conf"
    if ! chosen danmaku; then
        # uosc would show a placeholder for the danmaku button and toggle
        controls=$(sed -n 's/^controls=//p' "$REPO/mpv/script-opts/uosc.conf" |
            sed 's/button:danmaku,//; s/cycle:[^,]*@uosc_danmaku:[^,]*,//')
        echo "script-opts-append=uosc-controls=$controls" >> "$conf"
    fi
    if ! chosen sponsorblock; then
        echo "script-opts-append=bilibili_sponsorblock-enabled=no" >> "$conf"
    fi
}

step_fetch() {
    fetch_sources
    write_features_conf
    echo "Third-party scripts, fonts, shaders and models of your features are in $REPO/mpv"
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

# Adds whisper.cpp and its models (~550 MB) to an existing install
step_whisper() {
    need_brew
    choose whisper
    save_choices
    brew install whisper.cpp
    step_fetch
    echo "Ctrl+g in mpv generates subtitles"
}

load_choices
if [[ $# -gt 0 ]]; then
    case $1 in
        brew | fetch | link | ff2mpv | pot | whisper) "step_$1" ;;
        *) echo "Unknown step: $1 (use brew, fetch, link, ff2mpv, pot or whisper)"; exit 1 ;;
    esac
    exit
fi

need_brew
if ! choose_features; then
    echo "Nothing was changed"
    exit
fi
save_choices
step_brew
step_fetch
step_link
if chosen ff2mpv; then step_ff2mpv; fi
if chosen youtube; then step_pot; fi
echo
echo "Done. Run ./install.sh again to add or remove features."
