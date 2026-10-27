#!/usr/bin/env bash
# Fonts for the rice, into ~/.local/share/fonts:
#   Nerd Fonts  AdwaitaMono (the Quickshell shell + apps — Serpantinum's
#               default face), JetBrainsMono, GeistMono, FiraCode,
#               CaskaydiaCove, Hack — the choices in Settings › Appearance ›
#               Font (hypr/set-font.sh)
#   Adwaita Sans  GNOME's proportional twin of AdwaitaMono (adwaita-fonts)
# The .tar.xz release assets (a few MB) rather than the .zip ones (up to 80).
source "$(dirname "$0")/common.sh"
dir="$HOME/.local/share/fonts"
mkdir -p "$dir"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
get() {   # get ARCHIVE FILEPREFIX — Regular / Bold / Italic / BoldItalic, ttf or otf
    ls "$dir/$2-Regular."* >/dev/null 2>&1 && { echo "$2 already installed"; return; }
    mkdir -p "$tmp/$1"
    curl -fsSL -o "$tmp/$1.tar.xz" "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/$1.tar.xz"
    tar -xJf "$tmp/$1.tar.xz" -C "$tmp/$1" --wildcards \
        "$2-Regular.*" "$2-Bold.*" "$2-Italic.*" "$2-BoldItalic.*" 2>/dev/null || true
    cp "$tmp/$1/$2-"* "$dir/"
}
get JetBrainsMono JetBrainsMonoNerdFont
get AdwaitaMono AdwaitaMonoNerdFont
get GeistMono GeistMonoNerdFont
get FiraCode FiraCodeNerdFont
get CascadiaCode CaskaydiaCoveNerdFont
get Hack HackNerdFont
if ! ls "$dir"/AdwaitaSans-Regular.ttf >/dev/null 2>&1; then
    curl -fsSL -o "$tmp/adwaita.tar.xz" https://download.gnome.org/sources/adwaita-fonts/48/adwaita-fonts-48.2.tar.xz
    tar -xJf "$tmp/adwaita.tar.xz" -C "$tmp" --wildcards '*/sans/AdwaitaSans-*.ttf'
    cp "$tmp"/adwaita-fonts-*/sans/AdwaitaSans-*.ttf "$dir/"
fi
fc-cache -f "$dir"
