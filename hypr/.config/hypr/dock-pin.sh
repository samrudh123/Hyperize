#!/bin/bash
# Pin/unpin an app in the SIDEBAR (nwg-dock) given a .desktop ID.
#
#   dock-pin.sh status <id>   -> prints "pinned" or "unpinned"
#   dock-pin.sh add    <id>   -> add to ~/.cache/nwg-dock-pinned
#   dock-pin.sh remove <id>   -> remove from it
#
# Called by the right-click menu in the patched nwg-drawer. The awkward part is
# that the drawer knows a .desktop ID while the dock's pinned list holds bare
# WINDOW CLASSES — get that wrong and the app renders twice, once as a dotless
# pin and once as a running task (this is the Brave bug from the very first
# session). There is no reliable static mapping from a .desktop file to a
# Wayland app_id, so resolve in this order:
#
#   1. a running window whose class matches the .desktop stem  -> use its class
#   2. a running window matching the file's StartupWMClass      -> use its class
#   3. a running window matching X-SnapInstanceName             -> use its class
#   4. a line ALREADY in the pinned list that names this app    -> reuse it
#   5. X-SnapInstanceName itself, if the file has one
#   6. otherwise fall back to the stem
#
# Step 4 exists because the stem is only a GUESS, and for install4j/Java
# launchers it is always a wrong one: the file is literally
# install4j_1nco9fl-JDownloader2.desktop while the dock's line says
# "JDownloader" (and its StartupWMClass is a third string again,
# install4j-org-jdownloader-update-launcher-JDLauncher). Guessing there made the
# drawer offer "Pin to sidebar" for an app already ON the sidebar, and "Unpin"
# then deleted a line that did not exist — so the icon never went away. That was
# the whole bug: one pinned entry out of fourteen, silently un-unpinnable.
#
# Step 4 only ever reuses a line that is ALREADY pinned, and only when exactly
# one matches, so it cannot invent an entry: worst case it declines and falls
# through to the old behaviour.
#
# StartupWMClass is matched only against RUNNING windows on purpose: it is the
# X11 WM_CLASS and often disagrees with the Wayland app_id (brave_brave.desktop
# says "brave-browser"; Hyprland reports "brave"). X-SnapInstanceName is the
# snap's instance name and has matched the real class for every snap here
# (code_code.desktop -> code, brave_brave.desktop -> brave), which is what makes
# step 5 usable while the app is closed. Step 6 is a guess; if it picks wrong,
# pin once from the dock's own right-click menu, which always has the true
# class, and delete the bad line from ~/.cache/nwg-dock-pinned.

set -u

ACTION="${1:-status}"
ID="${2:-}"
PINNED="$HOME/.cache/nwg-dock-pinned"
[ -n "$ID" ] || { echo "usage: dock-pin.sh {status|add|remove} <desktop-id>" >&2; exit 2; }

stem="${ID%.desktop}"

find_desktop() {
    for d in "$HOME/.local/share/applications" /usr/local/share/applications \
             /usr/share/applications /var/lib/snapd/desktop/applications \
             /var/lib/flatpak/exports/share/applications; do
        [ -f "$d/$stem.desktop" ] && { printf '%s\n' "$d/$stem.desktop"; return 0; }
    done
    return 1
}

running_classes() { hyprctl clients -j 2>/dev/null | /usr/bin/python3 -c '
import json,sys
try:
    for c in json.load(sys.stdin):
        if c.get("class"): print(c["class"])
except Exception:
    pass
' | sort -u; }

# Does the pinned list already have a line that names this app? Compared against
# every identifier the .desktop file offers, case-insensitively: the stem, the
# StartupWMClass, the snap instance name, the Name with spaces stripped, and the
# Name's first word (which is what catches "JDownloader" from "JDownloader 2").
existing_pin() {
    local f name namesq first swm snapname line l hit="" n=0
    [ -s "$PINNED" ] || return 1
    f=$(find_desktop) || return 1

    name=$(grep -m1 '^Name=' "$f" | cut -d= -f2-)
    namesq="${name// /}"; namesq="${namesq,,}"
    first="${name%% *}"; first="${first,,}"
    swm=$(grep -m1 '^StartupWMClass=' "$f" | cut -d= -f2-)
    snapname=$(grep -m1 '^X-SnapInstanceName=' "$f" | cut -d= -f2-)

    while IFS= read -r line; do
        [ -n "$line" ] || continue
        l="${line,,}"
        if [ "$l" = "${stem,,}" ] \
           || { [ -n "$swm" ]      && [ "$l" = "${swm,,}" ]; } \
           || { [ -n "$snapname" ] && [ "$l" = "${snapname,,}" ]; } \
           || { [ -n "$namesq" ]   && [ "$l" = "$namesq" ]; } \
           || { [ -n "$first" ]    && [ "$l" = "$first" ]; }; then
            hit="$line"; n=$((n+1))
        fi
    done < "$PINNED"

    # Exactly one, or decline: an ambiguous match would unpin the wrong icon.
    [ "$n" -eq 1 ] || return 1
    printf '%s\n' "$hit"
}

resolve_class() {
    local classes wm
    classes=$(running_classes)

    while IFS= read -r c; do
        [ -n "$c" ] || continue
        [ "${c,,}" = "${stem,,}" ] && { printf '%s\n' "$c"; return; }
    done <<< "$classes"

    local snap=""
    if f=$(find_desktop); then
        for key in StartupWMClass X-SnapInstanceName; do
            wm=$(grep -m1 "^$key=" "$f" | cut -d= -f2-)
            [ -n "${wm:-}" ] || continue
            [ "$key" = X-SnapInstanceName ] && snap="$wm"
            while IFS= read -r c; do
                [ -n "$c" ] || continue
                [ "${c,,}" = "${wm,,}" ] && { printf '%s\n' "$c"; return; }
            done <<< "$classes"
        done
    fi

    # Not running. An entry already on the sidebar is better evidence than any
    # guess below it, so ask that first.
    local pinned_as
    if pinned_as=$(existing_pin); then printf '%s\n' "$pinned_as"; return; fi

    # A snap's instance name is the best available guess.
    [ -n "$snap" ] && { printf '%s\n' "$snap"; return; }

    printf '%s\n' "$stem"
}

CLASS=$(resolve_class)
touch "$PINNED"

case "$ACTION" in
status)
    grep -qxF "$CLASS" "$PINNED" && echo pinned || echo unpinned
    ;;
add)
    grep -qxF "$CLASS" "$PINNED" || printf '%s\n' "$CLASS" >> "$PINNED"
    echo "pinned $CLASS"
    ;;
remove)
    tmp=$(mktemp)
    grep -vxF "$CLASS" "$PINNED" > "$tmp" && mv "$tmp" "$PINNED"
    echo "unpinned $CLASS"
    ;;
*)
    echo "unknown action: $ACTION" >&2; exit 2 ;;
esac
