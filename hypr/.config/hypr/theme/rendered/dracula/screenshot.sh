#!/bin/bash
# Screenshots — SUPER+SHIFT+S (region), Print (screen), SHIFT+Print (window).
#
# Every mode does the same: capture a timestamped PNG, put it on the
# clipboard, then ask with a popup (screenshot-save.py) whether to keep it as
# a file and in which folder — Save… opens the folder picker (yazi), Discard
# deletes it. Until then it is only a temp copy in $XDG_RUNTIME_DIR. (It used
# to land in ~/Pictures/Screenshots unconditionally.)
# The old binds were a bare `grim - | wl-copy`, which worked fine but wrote no
# file and showed nothing, so it was indistinguishable from a dead keybind.
#
# Everything used here lives in /usr/bin. Do not reach for anything in
# ~/.local/bin: keybind children inherit Hyprland's PATH, which omits it.

set -u

DIR="${XDG_RUNTIME_DIR:-/tmp}/screenshots"      # temp until the popup says where
FILE="$DIR/$(date +%Y-%m-%d_%H-%M-%S).png"
MODE="${1:-region}"

notify() { notify-send -a Screenshot "$@"; }

mkdir -p "$DIR" || { notify -u critical "Screenshot failed" "cannot create $DIR"; exit 1; }

case "$MODE" in
region)
    # Catppuccin Mocha selection box: mauve border on a dimmed ground.
    # slurp exits non-zero when cancelled with Escape — that is a normal
    # outcome, not an error, so leave without writing or notifying.
    GEOM=$(slurp -d -b 282a36aa -c @@ACCENT@@ff -s 00000000 -w 2) || exit 0
    [ -n "$GEOM" ] || exit 0
    grim -g "$GEOM" "$FILE" || { notify -u critical "Screenshot failed" "grim could not capture the region"; exit 1; }
    LABEL="Region captured"
    ;;
screen)
    grim "$FILE" || { notify -u critical "Screenshot failed" "grim could not capture the screen"; exit 1; }
    LABEL="Screen captured"
    ;;
window)
    # hyprctl clients/activewindow report the window box; grim wants "X,Y WxH".
    GEOM=$(hyprctl activewindow -j | /usr/bin/python3 -c '
import json, sys
w = json.load(sys.stdin)
if not w or not w.get("address"):
    sys.exit(1)
(x, y), (cx, cy) = w["at"], w["size"]
print(f"{x},{y} {cx}x{cy}")
') || { notify -u critical "Screenshot failed" "no active window"; exit 1; }
    grim -g "$GEOM" "$FILE" || { notify -u critical "Screenshot failed" "grim could not capture the window"; exit 1; }
    LABEL="Window captured"
    ;;
*)
    notify -u critical "Screenshot failed" "unknown mode: $MODE"
    exit 1
    ;;
esac

# Redirect from the file rather than piping grim straight into wl-copy, so the
# saved copy is what actually reached the clipboard.
wl-copy --type image/png < "$FILE"

# grim returns 0 while producing an all-black frame when stale layer surfaces
# are around (see landmine 10 in the notes) — say so rather than silently
# handing over a black rectangle.
if /usr/bin/python3 - "$FILE" <<'EOF'
import sys
from PIL import Image
sys.exit(0 if all(hi == 0 for _, hi in Image.open(sys.argv[1]).convert("RGB").getextrema()) else 1)
EOF
then
    notify -u critical "Screenshot is all black" "Stale layer surfaces? Check: hyprctl layers | grep 'pid: -1'"
    exit 1
fi

# Save it somewhere, or not. The clipboard copy is already done, so whatever
# the answer, the keybind has done its job.
exec /usr/bin/python3 "$HOME/.config/hypr/screenshot-save.py" "$FILE" "$LABEL"
