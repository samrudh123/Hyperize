#!/bin/bash
# Focus an app's window if it is already open, otherwise launch it.
#
#   focus-or-launch.sh CLASS-REGEX COMMAND [ARGS...]
#
# CLASS-REGEX is matched case-insensitively against the window class
# (`hyprctl clients` shows it): Spotify's deb reports "Spotify", Discord's
# "discord". Used by SUPER+SHIFT+M / SUPER+SHIFT+D and by media-menu.sh, so a
# second press jumps to the running app instead of spawning another copy.
#
# Spotify and Discord both minimise to the tray on close, so "running" and
# "has a window" differ: with no window, launching again just re-opens the
# existing instance's window, which is exactly what we want.

set -u
class="$1"; shift

addr=$(hyprctl clients -j | jq -r --arg re "$class" \
    'first(.[] | select(.class | test($re; "i")) | .address) // empty')

if [ -n "$addr" ]; then
    hyprctl dispatch focuswindow "address:$addr" >/dev/null
else
    # Through hyprctl so the app lands in the session scope, not this
    # script's (waybar's) cgroup — same reason as bottom-bar.sh.
    hyprctl dispatch exec "$*" >/dev/null
fi
