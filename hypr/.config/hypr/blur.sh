#!/bin/bash
# Background blur (decoration:blur:enabled) — the frosted glass behind
# translucent windows, bars, popups and the dock.
#
#   blur.sh get            the saved choice: on | off
#   blur.sh set on|off     save it (blur.conf, sourced by hyprland.conf) and
#                          apply it now — Settings › Appearance › Transparency
#   blur.sh toggle         SUPER+ALT+B
#   blur.sh lowbat on|off  battery-saver.py: entering low battery turns blur
#                          off if it's on (not saved); leaving puts the saved
#                          choice back. A `set` in between wins and stays.
#   blur.sh reapply        hyprland.conf `exec` (every config reload): the
#                          reload re-reads blur.conf, so keep it off if
#                          low battery had turned it off
#
# With an animated wallpaper the blur is redone every video frame (~1.3 W
# measured 2026-10-31); over a still wallpaper it is cached and nearly free.

HYPR="$HOME/.config/hypr"
PREF="$HYPR/blur.conf"
MARK="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/blur-lowbat"

pref() { grep -qE '^decoration:blur:enabled *= *(false|0)' "$PREF" 2>/dev/null && echo off || echo on; }
apply() { hyprctl keyword decoration:blur:enabled "$([ "$1" = on ] && echo true || echo false)" >/dev/null; }
live() { hyprctl getoption decoration:blur:enabled -j 2>/dev/null | grep -q '"int": *1' && echo on || echo off; }

save() {
    cat > "$PREF" <<EOF
# blur.sh / Settings › Appearance › Transparency — sourced by hyprland.conf
decoration:blur:enabled = $([ "$1" = on ] && echo true || echo false)
EOF
}

case "$1" in
    get) pref ;;
    set)
        case "$2" in on|off) ;; *) echo "usage: $0 set on|off" >&2; exit 2 ;; esac
        save "$2"; rm -f "$MARK"; apply "$2" ;;
    toggle)
        v=$([ "$(pref)" = on ] && echo off || echo on)
        save "$v"; rm -f "$MARK"; apply "$v" ;;
    lowbat)
        if [ "$2" = on ]; then
            [ "$(live)" = on ] && { apply off; touch "$MARK"; }
        elif [ -e "$MARK" ]; then
            rm -f "$MARK"; apply "$(pref)"
        fi ;;
    reapply) [ -e "$MARK" ] && apply off ;;
    *) echo "usage: $0 get | set on|off | toggle | lowbat on|off | reapply" >&2; exit 2 ;;
esac
exit 0
