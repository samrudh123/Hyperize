#!/bin/bash
# yazi that follows accent / theme changes — yazi reads its theme once at
# startup and has no reload, so it is reopened in place instead.
#
#   yazi-live.sh [yazi args…]     run yazi (SUPER+E, and `y` in zsh)
#   yazi-live.sh --relaunch-all   ask every yazi started this way to reopen
#                                 (set-accent.sh reload_apps, on each change)
#
# Each instance gets its own --client-id and registers it under
# $XDG_RUNTIME_DIR/yazi-live/. --relaunch-all sends it `plugin relaunch`
# (plugins/relaunch.yazi), which writes every tab's folder + hovered entry and
# the active tab to a state file; it is then told to quit, and this loop
# starts yazi again — same folders, same hovered entries, same tabs. Lost: selection,
# scroll offset, the find/filter. If file tasks are running, yazi's own "quit?"
# confirmation shows; answering no just keeps the old colours.
#
# File pickers (xdg-desktop-portal-termfilechooser) and grid-open.sh start
# yazi directly, so they are never relaunched under the user.

set -u
YAZI="$HOME/.local/bin/yazi"
YA="$HOME/.local/bin/ya"
RUN="${XDG_RUNTIME_DIR:-/tmp}/yazi-live"
mkdir -p "$RUN"

if [ "${1:-}" = --relaunch-all ]; then
    for reg in "$RUN"/*.pid; do
        [ -e "$reg" ] || continue
        id=$(basename "$reg" .pid)
        pid=$(cat "$reg" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            (
                rm -f "$RUN/$id.state"
                "$YA" emit-to "$id" plugin relaunch >/dev/null 2>&1
                for _ in $(seq 20); do [ -s "$RUN/$id.state" ] && break; sleep 0.1; done
                # let the plugin task finish first, or yazi asks "unfinished
                # tasks, quit anyway?" about the plugin itself
                [ -s "$RUN/$id.state" ] && sleep 0.4 && "$YA" emit-to "$id" quit >/dev/null 2>&1
            ) &
        else
            rm -f "$reg" "$RUN/$id.state"     # left over from a killed terminal
        fi
    done
    wait
    exit 0
fi

# split flags (--cwd-file=…, kept on every run) from entries (replaced by the
# saved tabs after a relaunch)
flags=() entries=()
for a in "$@"; do
    case "$a" in --*) flags+=("$a") ;; *) entries+=("$a") ;; esac
done

id=$(( 7000000000 + $$ ))           # unique while this wrapper lives
export YAZI_LIVE_STATE="$RUN/$id.state"
echo $$ > "$RUN/$id.pid"
trap 'rm -f "$RUN/$id.pid" "$YAZI_LIVE_STATE"' EXIT

while :; do
    rm -f "$YAZI_LIVE_STATE"
    "$YAZI" --client-id "$id" "${flags[@]}" "${entries[@]}"
    [ -s "$YAZI_LIVE_STATE" ] || break        # a normal quit: done
    # line 1: active tab (1-based); then per tab "folder<TAB>hovered"
    mapfile -t saved < "$YAZI_LIVE_STATE"
    active=${saved[0]}
    entries=() hovered=()
    for line in "${saved[@]:1}"; do
        entries+=("${line%%$'\t'*}")
        hovered+=("${line#*$'\t'}")
    done
    # Folders are passed (a folder entry would be ENTERED, not hovered), so
    # re-hover each tab's entry once yazi is up, then return to the old tab.
    (
        sleep 0.5
        for i in "${!hovered[@]}"; do
            [ -n "${hovered[$i]}" ] || continue
            "$YA" emit-to "$id" tab_switch "$i"
            "$YA" emit-to "$id" reveal "${hovered[$i]}"
        done
        "$YA" emit-to "$id" tab_switch $(( ${active:-1} - 1 ))
    ) >/dev/null 2>&1 &
done
