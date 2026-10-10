#!/bin/bash
# Run after a fresh Hyprland login to confirm the session came up correctly.
#
# The dock no longer takes an exclusive zone, so the old race check (was it
# `6 6 78 1188` instead of `6 46 78 1148`?) is gone. What is worth checking now
# is that it kept its NEW shape: a content-sized pill, centred vertically, with
# the left edge of the screen unreserved so windows run under it.
#
# Its height tracks the number of pins — disks come and go with mounts — so
# nothing here hardcodes it. Only the fixed facts are asserted.
# The shell is Quickshell since 2026-10-09: qs-bar / qs-bottombar / qs-dock.
# The dock starts hidden — show it (SUPER+A) before running this.
echo "--- layer geometry (qs-bar 0 0 <screen width> 40|42, dock x=6 w=54, centred, < full height) ---"
hyprctl layers | grep -E "namespace: (qs-bar|qs-bottombar|qs-dock)" | sed 's/.*xywh/  xywh/'
echo "--- reserved area (left MUST be 0: the dock floats over the tiling) ---"
hyprctl monitors | grep reserved | sed 's/^\s*/  /'
echo "--- one of each daemon ---"
# swaybg OR mpvpaper, depending on whether the wallpaper is a still or a video
for p in qs swaybg mpvpaper mako hypridle; do
    printf "  %-18s %s\n" "$p" "$(pgrep -x "$p" | tr '\n' ' ')"
done
for n in mount-watch.py workspace-stack.py; do
    printf "  %-18s %s\n" "${n%.py}" "$(ps -eo pid,comm,args | grep -F "$n" | awk '$2=="python3"{print $1}' | tr '\n' ' ')"
done
echo "--- stale surfaces (must be 0) ---"
hyprctl layers | grep -c "pid: -1"
echo "--- verdict ---"
read -r dx dy dw dh <<<"$(hyprctl layers | grep "namespace: qs-dock" | sed -E 's/.*xywh: ([0-9]+) ([0-9]+) ([0-9]+) ([0-9]+).*/\1 \2 \3 \4/')"
w=$(hyprctl layers | grep "namespace: qs-bar," | sed -E 's/.*xywh: ([0-9]+ [0-9]+ [0-9]+ [0-9]+).*/\1/')
# reserved: <left> <top> <right> <bottom>
read -r rl rt _ rb <<<"$(hyprctl monitors | grep -m1 reserved | sed -E 's/.*reserved: //')"
mh=$(hyprctl monitors -j | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["height"])')
# the bar spans the (logical) screen width: 40 px tall classic, 42 islands
mw=$(hyprctl monitors -j | python3 -c 'import json,sys; m=json.load(sys.stdin)[0]; print(round(m["width"]/m["scale"]))')

ok=1
case "$w" in "0 0 $mw 40"|"0 0 $mw 42") ;; *) echo "  BAR: qs-bar='$w' (expected '0 0 $mw 40' or 42)"; ok=0 ;; esac
[ "${rl:-x}" = "0" ]          || { echo "  ZONE: left reserved=$rl — the dock took an exclusive zone (Dock.qml exclusionMode?)"; ok=0; }
[ "${dx:-x}" = "6" ] && [ "${dw:-x}" = "54" ] \
                              || { echo "  SHAPE: dock x=$dx w=$dw (expected 6 / 54)"; ok=0; }
if [ -n "${dh:-}" ] && [ "$dh" -ge "$((mh - rt - ${rb:-0}))" ]; then
    echo "  SHAPE: dock is $dh tall — full height (Dock.qml anchors top/bottom?)"; ok=0
fi
# centred in the usable strip (rt..mh-rb; rb is the trial bottom bar), ±4px for rounding
if [ -n "${dy:-}" ] && [ -n "${dh:-}" ]; then
    want=$(( rt + (mh - rt - ${rb:-0} - dh) / 2 ))
    [ "${dy#-}" -ge "$((want - 4))" ] && [ "$dy" -le "$((want + 4))" ] \
        || { echo "  CENTRE: dock y=$dy (expected ~$want for a ${dh}px dock)"; ok=0; }
fi
[ "$ok" = 1 ] && echo "  OK — bar flush, sidebar centred and floating"
