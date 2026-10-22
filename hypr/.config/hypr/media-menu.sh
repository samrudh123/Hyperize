#!/bin/bash
# Media dropdown — now a small GTK window so its text can carry the bar's
# colour coding; see media-menu.py. Kept as the entry point because the
# SUPER+M bind and the bottom bar's on-clicks all call this path.
# (The fuzzel version is media-menu.sh.pre-gtk (archived in ~/.dotfiles-backup/pre-backups-2026-10-17.tar.gz).)
exec /usr/bin/python3 "$HOME/.config/hypr/media-menu.py" "$@"
