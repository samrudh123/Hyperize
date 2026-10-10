#!/bin/bash
# Power menu — the power button at the right end of the top bar.
#
# Uses fuzzel rather than nwg-bar or wlogout on purpose: both of those need a
# package install, while fuzzel is already here and already provides the
# wallpaper / lock-screen / clipboard pickers, so this matches them.
#
# logind + polkit already allow the active session to power off, reboot and
# suspend with no authentication — verified with
#   pkcheck --action-id org.freedesktop.login1.power-off --process $$
# so nothing here needs sudo.
#
# Hibernate is deliberately absent: polkit does not grant it to this session,
# and swap (7.5G) is smaller than RAM (14G), so it could not work reliably
# even if it did.
#
# Anything that loses work — log out, restart, power off — asks a second time
# with Cancel listed first, because this hangs off a single click in the bar.
#
# GLYPHS: written as $'\uXXXX' escapes, never as literal characters. A literal
# glyph did not survive being written into this file and every icon silently
# became an empty string, so the menu rendered as bare text with no icons and
# it looked like a font problem. These escapes are plain ASCII on disk and
# expand at runtime. All codepoints verified present in JetBrainsMonoNerdFont
# with fontTools before use.

set -u

ICON_LOCK=$''      # fa-lock
ICON_SUSPEND=$''   # fa-moon-o
ICON_OUT=$''       # fa-sign-out
ICON_RESTART=$''   # fa-refresh
ICON_OFF=$''       # fa-power-off
ICON_BACK=$''      # fa-chevron-left

menu() { fuzzel --dmenu --lines "$1" --width "$2" --prompt "$3"; }

choice=$(printf '%s\n' \
    "$ICON_LOCK  Lock" \
    "$ICON_SUSPEND  Suspend" \
    "$ICON_OUT  Log out" \
    "$ICON_RESTART  Restart" \
    "$ICON_OFF  Power off" \
    | menu 5 24 "$ICON_OFF  power  ")

[ -n "${choice:-}" ] || exit 0          # Escape, or nothing selected

# Second prompt. Cancel is listed first so Enter on a mis-click is harmless.
confirm() {
    local what="$1" icon="$2" answer
    answer=$(printf '%s\n' "$ICON_BACK  Cancel" "$icon  Yes, $what" \
        | menu 2 26 "$icon  $what?  ")
    [ "${answer:-}" != "${answer#*Yes}" ]
}

case "$choice" in
    *Lock)        exec hyprlock ;;
    *Suspend)     exec systemctl suspend ;;
    *"Log out")   confirm "log out"   "$ICON_OUT"     && exec hyprctl dispatch exit ;;
    *Restart)     confirm "restart"   "$ICON_RESTART" && exec systemctl reboot ;;
    *"Power off") confirm "power off" "$ICON_OFF"     && exec systemctl poweroff ;;
    *) exit 0 ;;
esac
