#!/bin/sh
# Open a folder straight in yazi's grid view (grid-view.py), in a new yazi
# terminal; leaving the grid (q / Esc / Alt+G) drops into the normal yazi list
# there. Used by the top bar's "Open recordings folder" and the "Recording
# saved" notification's "Show in folder".
#
#   grid-open.sh DIR|FILE      (a FILE opens its folder with it selected)
#
# Absolute paths: Hyprland exec / keybind children have no ~/.local/bin on PATH.
target="${1:-$HOME}"
[ -e "$target" ] || mkdir -p "$target"
exec ghostty --gtk-single-instance=false --class=com.samrudh.yazi \
    -e /usr/bin/python3 "$HOME/.config/yazi/grid-view.py" --yazi "$target"
