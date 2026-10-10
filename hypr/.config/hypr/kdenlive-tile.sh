#!/bin/bash
# Keep Kdenlive's MAIN window tiled while its welcome screen floats.
#
# Both windows map with the same class AND the same title, "Kdenlive":
# the welcome / quick-setup card is a translucent QML window that has to
# float (tiled, it is a small card in a big see-through hole), but when you
# pick New/Open from it the main window ALSO maps titled "Kdenlive" — so
# the `float-kdenlive-splash` windowrule in hyprland.conf floats it too, and
# it came up as a 1280x800 popup instead of joining the tiling layout.
# Nothing Hyprland can match at map time tells them apart (verified: no
# modal flag on the splash, same pid/class/initial title).
#
# What DOES differ is what happens next: the main window renames itself to
# "Untitled / HD 1080p 25 fps — Kdenlive" (or the project name) a moment
# after mapping; the splash keeps "Kdenlive" until it closes. So the rule
# floats both — which gives the splash its own correct size — and this
# script tiles a window the first time its title moves off "Kdenlive".
#
# Only windows whose INITIAL title is "Kdenlive" are touched, so dialogs
# (Render, Settings — mapped with their own titles, floated by Hyprland as
# dialogs) are left alone, and only the first rename counts, so a main
# window you float by hand (SUPER+V) is not snapped back on every save.
#
# exec-once from hyprland.conf.

set -u

declare -A seen=()

sock="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
socat -U - "UNIX-CONNECT:$sock" | while IFS= read -r line; do
    case "$line" in
        windowtitlev2\>\>*)
            rest="${line#windowtitlev2>>}"
            addr="0x${rest%%,*}"; title="${rest#*,}"
            case "$title" in *Kdenlive*) ;; *) continue ;; esac
            [ "$title" = "Kdenlive" ] && continue
            [ -n "${seen[$addr]:-}" ] && continue
            seen[$addr]=1
            hyprctl clients -j | jq -e --arg a "$addr" 'any(.[]; .address == $a
                and .class == "org.kde.kdenlive" and .initialTitle == "Kdenlive"
                and .floating)' >/dev/null \
                && hyprctl dispatch settiled "address:$addr" >/dev/null ;;
        closewindow\>\>*)
            unset "seen[0x${line#closewindow>>}]" ;;
    esac
done
