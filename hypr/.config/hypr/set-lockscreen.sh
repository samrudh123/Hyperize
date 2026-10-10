#!/bin/bash
# Set the LOCK SCREEN wallpaper. Independent of the desktop wallpaper —
# ~/.config/hypr/set-wallpaper.sh handles that one and does not touch this.
#
#   set-lockscreen.sh                  pick one from a fuzzel name-only menu
#                                      (SUPER+SHIFT+W runs wallpaper-grid.py
#                                       --lock instead — thumbnails; this stays
#                                       as the fallback)
#   set-lockscreen.sh /path/to/img     set that image
#   set-lockscreen.sh --screenshot     blur whatever is on screen at lock time
#   set-lockscreen.sh --show           print the current setting
#
# Edits the single `path =` line inside hyprlock.conf's `background` block.
# hyprlock has NO --verify-config, so a hand-edited typo is only discovered when
# the screen actually locks. Going through this script avoids that.

DIR="$HOME/Pictures/wallpapers"
CONF="$HOME/.config/hypr/hyprlock.conf"
TEMPLATE="$HOME/.config/hypr/theme/templates/hyprlock.conf"

current() {
    sed -n '/^background {/,/^}/p' "$CONF" | sed -n 's/^\s*path\s*=\s*//p' | head -1
}

apply() {
    local img="$1"
    if [ "$img" != "screenshot" ] && [ ! -f "$img" ]; then
        notify-send "Lock screen" "Not found: $img" 2>/dev/null
        echo "not found: $img" >&2
        exit 1
    fi
    cp -- "$CONF" "$CONF.bak"
    set_path "$CONF" "$img"
    if [ $? -eq 0 ]; then
        # hyprlock.conf is also an accent template (set-accent.sh renders the
        # live file from theme/templates/ on every accent change). Without
        # this the next accent change — now also any wallpaper pick, via
        # wallpaper-picker.py — put the OLD lock image back.
        [ -f "$TEMPLATE" ] && set_path "$TEMPLATE" "$img"
        notify-send "Lock screen" "Set to ${img##*/}" 2>/dev/null
        echo "lock screen -> $img"
    else
        mv -- "$CONF.bak" "$CONF"
        echo "failed; hyprlock.conf restored" >&2
        exit 1
    fi
}

# set_path FILE IMG — rewrite the `path =` line of FILE's background block.
set_path() {
    python3 - "$1" "$2" <<'EOF'
import re, sys
conf, img = sys.argv[1], sys.argv[2]
s = open(conf).read()
new, n = re.subn(r'(background\s*\{[^}]*?\n\s*path\s*=\s*)[^\n]*',
                 lambda m: m.group(1) + img, s, count=1, flags=re.S)
if n != 1:
    sys.exit("could not find the path line in the background block")
if new.count("{") != new.count("}"):
    sys.exit("refusing to write: braces unbalanced")
open(conf, "w").write(new)
EOF
}

case "$1" in
    --show)       echo "lock screen: $(current)" ;;
    --screenshot) apply screenshot ;;
    "")
        choice=$( { echo "screenshot  (blur the live screen)"
                    find "$DIR" -maxdepth 1 -type f \
                      \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \
                         -o -iname '*.webp' -o -iname '*.bmp' \) -printf '%f\n' | sort
                  } | fuzzel --dmenu --prompt '  lock screen  ')
        case "$choice" in
            "")            exit 0 ;;
            screenshot*)   apply screenshot ;;
            *)             apply "$DIR/$choice" ;;
        esac
        ;;
    *) apply "$1" ;;
esac
