#!/usr/bin/env bash
# yazi + ya — the official static release build, into ~/.local/bin.
source "$(dirname "$0")/common.sh"
ver="${YAZI_VERSION:-latest}"
url="https://github.com/sxyazi/yazi/releases/$([ "$ver" = latest ] && echo latest/download || echo "download/$ver")/yazi-x86_64-unknown-linux-gnu.zip"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
curl -fsSL -o "$tmp/yazi.zip" "$url"
unzip -q "$tmp/yazi.zip" -d "$tmp"
install -m755 "$tmp"/yazi-x86_64-unknown-linux-gnu/{yazi,ya} "$PREFIX/bin/"
"$PREFIX/bin/ya" pkg install >/dev/null 2>&1 || true     # plugins pinned in yazi/package.toml
"$PREFIX/bin/yazi" --version | head -1
