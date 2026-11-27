#!/bin/bash
# Launch Zoom in the rice's colour mode. Used by the Zoom.desktop override in
# ~/.local/share/applications (so the dock, nwg-drawer and zoommtg:// links all
# come through here), and with --mode-only by set-theme.sh's apply_mode.
#
#   zoom.sh [args…]     set the mode, then start /usr/bin/zoom with the args
#   zoom.sh --mode-only [light|dark]
#                       set the mode in zoomus.conf and stop (no launch);
#                       without light|dark it is read from palette.json
#
# Zoom has no "follow the system" on Linux: its `useSystemTheme` key never
# turns it dark (tested with the xdgdesktopportal Qt theme while the portal
# reported prefer-dark). Its own Appearance setting is the key
# com.zoom.client.theme.mode in ~/.config/zoomus.conf — 1 = light, 2 = dark
# (tested). Zoom reads it only at start and writes its in-memory copy back on
# exit, so it is (re)written just before every launch, never while it runs.
#
# QT_QPA_PLATFORMTHEME: the session's "kde" plugin isn't in Zoom's bundled Qt
# (/opt/zoom/Qt/plugins/platformthemes has gtk3 + xdgdesktopportal only), so Qt
# fell back to no theme at all. xdgdesktopportal sends its file dialogs through
# the portal — yazi (termfilechooser) like every other app — instead of Qt's
# stock light-grey file dialog.

set -u
CONF="$HOME/.config/zoomus.conf"
PALETTE="$HOME/.config/hypr/theme/palette.json"
KEY="com.zoom.client.theme.mode"

set_mode() {
    local mode=${1:-} val
    [ -n "$mode" ] || mode=$(sed -n 's/.*"mode": *"\([a-z]*\)".*/\1/p' "$PALETTE" 2>/dev/null | head -1)
    [ "$mode" = light ] && val=1 || val=2
    # Zoom running: it would overwrite the file on exit anyway
    pgrep -f '^/opt/zoom/zoom( |$)' >/dev/null && return 0
    [ -f "$CONF" ] || printf '[General]\n' > "$CONF"
    if grep -q "^$KEY=" "$CONF"; then
        sed -i "s/^$KEY=.*/$KEY=$val/" "$CONF"
    elif grep -q '^\[General\]' "$CONF"; then
        sed -i "/^\[General\]/a $KEY=$val" "$CONF"
    else
        printf '[General]\n%s=%s\n' "$KEY" "$val" >> "$CONF"
    fi
}

if [ "${1:-}" = --mode-only ]; then set_mode "${2:-}"; exit 0; fi
set_mode

export QT_QPA_PLATFORMTHEME=xdgdesktopportal
exec /usr/bin/zoom "$@"
