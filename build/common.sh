# Shared by the build scripts: where sources go and where things install.
# Override for a dry run, e.g.  PREFIX=/tmp/x SRC=/tmp/src ./build/mpvpaper.sh
set -euo pipefail
PREFIX="${PREFIX:-$HOME/.local}"
SRC="${SRC:-$HOME/.local/src}"
DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATCHES="$DOTFILES/hypr/.config/hypr/patches"
mkdir -p "$PREFIX/bin" "$SRC"

# clone REPO into $SRC/NAME at REF (tag/branch), or update an existing checkout
checkout() {
    local url=$1 name=$2 ref=$3
    if [ -d "$SRC/$name/.git" ]; then
        git -C "$SRC/$name" fetch --tags -q origin
        git -C "$SRC/$name" checkout -q -f "$ref"
        git -C "$SRC/$name" clean -fdq
    else
        git clone -q "$url" "$SRC/$name"
        git -C "$SRC/$name" checkout -q "$ref"
    fi
    cd "$SRC/$name"
}
