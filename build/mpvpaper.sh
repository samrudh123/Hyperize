#!/usr/bin/env bash
# mpvpaper — animated (video/GIF) wallpapers; set-wallpaper.sh calls
# ~/.local/bin/mpvpaper by absolute path.
source "$(dirname "$0")/common.sh"
checkout https://github.com/GhostNaN/mpvpaper.git mpvpaper "${MPVPAPER_REF:-master}"
meson setup build --prefix="$PREFIX" --buildtype=release --wipe >/dev/null 2>&1 \
    || meson setup build --prefix="$PREFIX" --buildtype=release
ninja -C build
install -m755 build/mpvpaper build/mpvpaper-holder "$PREFIX/bin/"
