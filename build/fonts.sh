#!/usr/bin/env bash
# JetBrainsMono Nerd Font — every bar glyph and the terminal use it.
source "$(dirname "$0")/common.sh"
dir="$HOME/.local/share/fonts"
ls "$dir"/JetBrainsMonoNerdFont-Regular.ttf >/dev/null 2>&1 && { echo "font already installed"; exit 0; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
curl -fsSL -o "$tmp/f.zip" https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip
mkdir -p "$dir"
unzip -q -o "$tmp/f.zip" 'JetBrainsMonoNerdFont-Regular.ttf' 'JetBrainsMonoNerdFont-Bold.ttf' \
    'JetBrainsMonoNerdFont-Italic.ttf' 'JetBrainsMonoNerdFont-BoldItalic.ttf' -d "$dir"
fc-cache -f "$dir"
