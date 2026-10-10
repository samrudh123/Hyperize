#!/bin/bash
# Screen brightness via systemd-logind.
#
# Why not brightnessctl? /sys/class/backlight/*/brightness is root:video 0664 and
# this user is NOT in the `video` group, so brightnessctl fails with "You should
# run this program with root privileges" - silently, from waybar and keybinds.
# logind's SetBrightness works for whoever owns the active session, with no group
# membership, no sudo and no re-login. It is what GNOME uses.
#
#   brightness.sh up [step%]     raise   (default 5)
#   brightness.sh down [step%]   lower
#   brightness.sh set <percent>  absolute
#   brightness.sh save           remember the current level
#   brightness.sh restore        return to the saved level
#   brightness.sh get            print current percent

DEV=intel_backlight
SYS=/sys/class/backlight/$DEV
STATE="${XDG_RUNTIME_DIR:-/tmp}/brightness.saved"
MIN_PCT=2          # never black the panel out entirely

max=$(< "$SYS/max_brightness")
cur=$(< "$SYS/brightness")
min=$(( max * MIN_PCT / 100 ))
[ "$min" -lt 1 ] && min=1

session_path() {
    local id="${XDG_SESSION_ID:-}"
    [ -z "$id" ] && id=$(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $1}' | head -1)
    busctl call org.freedesktop.login1 /org/freedesktop/login1 \
        org.freedesktop.login1.Manager GetSession s "$id" 2>/dev/null \
        | awk '{print $2}' | tr -d '"'
}

apply() {
    local v=$1
    [ "$v" -lt "$min" ] && v=$min
    [ "$v" -gt "$max" ] && v=$max
    local p; p=$(session_path)
    [ -n "$p" ] || { echo "no logind session" >&2; exit 1; }
    busctl call org.freedesktop.login1 "$p" org.freedesktop.login1.Session \
        SetBrightness ssu backlight "$DEV" "$v" >/dev/null
}

step=${2:-5}
case "$1" in
    up)      apply $(( cur + max * step / 100 )) ;;
    down)    apply $(( cur - max * step / 100 )) ;;
    set)     apply $(( max * ${2:-50} / 100 )) ;;
    save)    printf '%s\n' "$cur" > "$STATE" ;;
    restore) [ -s "$STATE" ] && apply "$(< "$STATE")" ;;
    get)     echo $(( cur * 100 / max )) ;;
    *)       echo "usage: $0 {up|down|set|save|restore|get} [value]" >&2; exit 2 ;;
esac
