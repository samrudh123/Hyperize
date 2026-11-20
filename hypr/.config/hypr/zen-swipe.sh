#!/bin/bash
# 3-finger swipe down / up (no modifier; hyprland.conf maps them to up / down)
# → one tiling workspace up / down Zen's
# tab list: sends the browser Alt+PgUp / Alt+PgDn, which
# ~/.config/zen-rice/tiles.uc.js handles without wrapping — up from the top
# workspace opens a new tab at the top, down from the bottom does nothing.
# Does nothing when Zen isn't the focused window.
#
#   zen-swipe.sh up | down

set -u
read -r cls addr < <(hyprctl activewindow -j | jq -r '"\(.class // "") \(.address // "")"')
[ "$cls" = zen ] && [ -n "$addr" ] || exit 0
case "${1:-}" in
    up)   key=Page_Up ;;
    down) key=Page_Down ;;
    *) echo "usage: zen-swipe.sh up|down" >&2; exit 2 ;;
esac
hyprctl dispatch sendshortcut "ALT, $key, address:$addr" >/dev/null
