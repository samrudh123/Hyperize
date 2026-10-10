#!/bin/bash
# UNUSED since 2026-10-09: the dock is Quickshell now (~/.config/quickshell/Dock.qml).
# Kept, with nwg-dock in ~/.local/bin, as the way back (hyprland.conf.pre-quickshell).
# Start the sidebar (nwg-dock-hyprland).
#
# THE SHAPE: a floating, content-sized pill
# The dock used to be `-f -a start -x`: full screen height, icons packed at the
# top, and an exclusive zone that reserved 84px down the whole left edge so
# every tiled window was 84px narrower for good. Now:
#
#   no -f   the surface is only as tall as its icons. With no top/bottom
#           anchor, gtk-layer-shell centres it vertically in the usable area
#           (i.e. below waybar's 40px zone), which is what -a used to fake.
#           -a only means anything with -f, so it is gone too.
#   no -x   no exclusive zone: the dock floats OVER the tiling layout on the
#           `top` layer instead of pushing it aside. `hyprctl monitors` should
#           report `reserved: 0 40 0 0` — left is no longer 84.
#   -l top  -x used to force this layer; state it explicitly now that -x is
#           gone, or nwg-dock defaults to `overlay` and the dock would draw
#           above the app grid, the power menu and notifications.
#
# -mt/-mb went with -f as well: layer-shell margins only apply on edges the
# surface is anchored to, and it is no longer anchored top or bottom.
#
# This script is the single source of truth for the dock's flags —
# dock-toggle.sh and reload.sh call it rather than repeating them.

set -u

DOCK="$HOME/.local/bin/nwg-dock-hyprland"

# -c needs an ABSOLUTE path: nwg-dock splits the string on spaces and execs it
# with no shell, so a leading ~ is never expanded (landmine 14).
# -icondir: Catppuccin Mocha glyph icons instead of the apps' own, made by
# dock-theme-icons.py (local patch, change 5); -ico is the grid button's.
# -indicator 5: the running-app bars (images/task-*-vertical.svg) get a 5px
# strip instead of -i/8 = 3px, where they were hard to see (change 6).
ICONS="$HOME/.local/share/nwg-dock-hyprland/mocha-icons"
DOCK_ARGS=(
    -p left -i 30 -r -ml 6
    -l top
    -c "$HOME/.config/hypr/app-grid.sh"
    -lp end
    -bottom dock-disk-,dock-trash
    -reorder
    -icondir "$ICONS"
    -ico "$ICONS/launcher.svg"
    -indicator 5
)

# Wait for waybar to map before we commit our own surface.
#
# This used to be load-bearing: both surfaces claimed exclusive zones, those
# are resolved in surface-creation order, and when the dock won that race at
# login it came up as `6 6 78 1188` — full height, over the bar — and shoved
# waybar to `92 5 1820 40`. With -x gone that failure mode is gone with it.
#
# It is kept because the dock is now CENTRED in whatever vertical space is
# free: map before the bar and it centres on the full 1200px, then jumps 20px
# down when waybar takes its 40px zone. Cheap wait, no visible settle.
#
# Checking only for the surface is not enough: a killed waybar's layer lingers
# in `hyprctl layers` for a moment after the process is gone, and that ghost
# was enough to let the dock through early. Give up after ~10s and start
# anyway — a missing bar should not cost us the dock entirely.
# --hidden: start the dock already hidden (used at login only — SUPER+A shows
# it). nwg-dock has no start-hidden flag, so launch it, wait for its layer to
# map, then send the hide signal. The wait matters: SIGRTMIN+3 before the
# handler is installed would hit the default action and KILL the dock.
NO_WAIT=0 HIDDEN=0
for arg in "$@"; do
    case "$arg" in
        --no-wait) NO_WAIT=1 ;;
        --hidden)  HIDDEN=1 ;;
    esac
done

if [ "$NO_WAIT" = 0 ]; then
    for _ in $(seq 1 100); do
        # One layer per waybar process: the top bar AND the bottom bar, when
        # it is running (namespace "bottombar", from its "name"). The bottom
        # bar mapping after the dock would make the dock drop its surface
        # (see bottom-bar.sh).
        n=$(pgrep -cx waybar 2>/dev/null)
        if [ "${n:-0}" -gt 0 ] \
           && [ "$(hyprctl layers 2>/dev/null | grep -cE "namespace: (waybar|bottombar)")" -ge "$n" ]; then
            sleep 0.3          # let the zone settle before we commit ours
            break
        fi
        sleep 0.1
    done
fi

# Icons for anything installed since the last start (fast: unchanged files are
# not rewritten).
/usr/bin/python3 "$HOME/.config/hypr/dock-theme-icons.py" >/dev/null 2>&1

if [ "$HIDDEN" = 0 ]; then
    exec "$DOCK" "${DOCK_ARGS[@]}"
fi

"$DOCK" "${DOCK_ARGS[@]}" &
DOCK_PID=$!
for _ in $(seq 1 100); do
    if hyprctl layers 2>/dev/null | grep -q "namespace: nwg-dock"; then
        sleep 0.2          # handler is up by the time the surface maps
        kill -RTMIN+3 "$DOCK_PID" 2>/dev/null
        break
    fi
    sleep 0.05
done
wait "$DOCK_PID"
