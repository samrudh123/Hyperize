#!/usr/bin/env bash
# nwg-drawer (the SUPER+D app grid) and nwg-dock-hyprland (the old dock, only
# needed to go back from Quickshell), with the local patches from
# hypr/patches (see patches/README.md — the builds silently lose behaviour
# without them). gotk4 cgo is slow: ~15 min each.
source "$(dirname "$0")/common.sh"

checkout https://github.com/nwg-piotr/nwg-drawer.git nwg-drawer "${NWG_DRAWER_REF:-v0.7.5}"
patch -p1 < "$PATCHES/nwg-drawer-0.7.5-context-menu.patch"
gofmt -w tools.go uicomponents.go
go build -o nwg-drawer .
install -m755 nwg-drawer "$PREFIX/bin/"
# category filters: app-grid.sh points XDG_DATA_DIRS at ~/.local/share/nwg-data
# (in the repo, nwg package); refresh it from the checkout if it is missing
[ -d "$HOME/.local/share/nwg-data/nwg-drawer/desktop-directories" ] || {
    mkdir -p "$HOME/.local/share/nwg-data/nwg-drawer"
    cp -r desktop-directories "$HOME/.local/share/nwg-data/nwg-drawer/"
}

if [ "${WITH_NWG_DOCK:-0}" = 1 ]; then
    checkout https://github.com/nwg-piotr/nwg-dock-hyprland.git nwg-dock-hyprland "${NWG_DOCK_REF:-v0.4.11}"
    patch -p1 < "$PATCHES/nwg-dock-hyprland-0.4.11-local.patch"
    GOFLAGS=-mod=mod go get github.com/fsnotify/fsnotify@v1.9.0
    gofmt -w main.go tools.go
    go build -o nwg-dock-hyprland .
    install -m755 nwg-dock-hyprland "$PREFIX/bin/"
fi
