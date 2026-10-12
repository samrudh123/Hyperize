#!/bin/bash
# Pick files in yazi and print their paths, one per line (nothing if
# cancelled). Used by phone.py send and tailscale-bar.py send.
#
#   pick-files.sh [START_DIR]
#
# Space marks several files; Enter on a file (or with a selection) chooses.
# Its own ghostty instance (--gtk-single-instance=false), so this waits for
# yazi to close instead of handing the window to a running ghostty.
out="$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/pick-files.XXXXXX")"
trap 'rm -f "$out"' EXIT
ghostty --gtk-single-instance=false --class=com.samrudh.yazi --title="Pick files to send" \
    -e "$HOME/.config/hypr/yazi-launch.sh" --chooser-file="$out" "${1:-$HOME}" >/dev/null 2>&1
cat "$out"
