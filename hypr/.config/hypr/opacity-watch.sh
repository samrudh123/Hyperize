#!/bin/bash
# Give every new window of an app listed in opacity-defaults.conf that app's
# "opNN" opacity tag (Ghostty 100 — it does its own background-opacity, see
# ~/.config/ghostty/config — yazi 96, and whatever the opacity OSD's "Make
# default" button has added). Everything else keeps the global 92 % from
# hyprland.conf.
#
# A tag, not a windowrule (`match:class = ghostty` → `opacity = 1.0
# override`). That rule fought the opNN tag rules from opacity.sh: Hyprland
# re-evaluates window rules on every TITLE change, and with two opacity rules
# matching it alternated between them — so a Ghostty window you had scrolled to
# 80% flickered 80% ↔ 100% whenever its title changed (Claude Code's spinner
# changes it several times a second). `match:tag = negative:...` did not
# exclude it either. A tag added by dispatch is static, so with the rule gone
# there is only ever ONE opacity rule matching a window and nothing to flicker.
#
# The defaults file is re-read for every new window, so a new "Make default"
# applies to the next window straight away. exec-once from hyprland.conf; also
# tags any untagged window already open.

set -u

DEFAULTS="$HOME/.config/hypr/opacity-defaults.conf"

pct_for() {   # $1 = class -> its percent, or nothing
    awk -F'=' -v c="$1" '
        /^[[:space:]]*#/ { next }
        { k = $1; gsub(/[[:space:]]/, "", k); if (k == c) { v = $2; gsub(/[[:space:]]/, "", v) } }
        END { if (v ~ /^[0-9]+$/) print v }' "$DEFAULTS" 2>/dev/null
}

tag_if_untagged() {   # $1 = address with 0x, $2 = class
    local pct
    pct=$(pct_for "$2")
    [ -n "$pct" ] || return 0
    hyprctl clients -j | jq -e --arg a "$1" \
        'any(.[]; .address == $a and (.tags | any(test("^op[0-9]+$"))))' >/dev/null \
        || hyprctl dispatch tagwindow "+op$pct" "address:$1" >/dev/null
}

hyprctl clients -j | jq -r '.[] | "\(.address)\t\(.class)"' |
    while IFS=$'\t' read -r a c; do tag_if_untagged "$a" "$c"; done

# openwindow>>ADDRESS,WORKSPACE,CLASS,TITLE
sock="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
socat -U - "UNIX-CONNECT:$sock" | while IFS= read -r line; do
    case "$line" in
        openwindow\>\>*)
            rest="${line#openwindow>>}"
            addr="0x${rest%%,*}"; rest="${rest#*,}"
            rest="${rest#*,}"; class="${rest%%,*}"
            tag_if_untagged "$addr" "$class" ;;
    esac
done
