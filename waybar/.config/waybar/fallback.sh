#!/bin/sh
# Emergency bars for when Quickshell is broken (e.g. after a Qt update, until
# build/quickshell.sh has rebuilt it): the old waybar top + bottom bars.
#
#   ~/.config/waybar/fallback.sh          start both
#   pkill -x waybar                       stop them again
#
# bottom.jsonc loads the now-playing plugin by bare name ("nowplaying.so") so
# no home path is written into the config; dlopen finds it here:
export LD_LIBRARY_PATH="$HOME/.config/waybar/modules${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
waybar >/dev/null 2>&1 &
waybar -c "$HOME/.config/waybar/bottom.jsonc" -s "$HOME/.config/waybar/bottom.css" >/dev/null 2>&1 &
