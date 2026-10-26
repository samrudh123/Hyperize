#!/bin/bash
# Keep a PLAYING player in front of the bottom bar's media controls.
#
# The bar's mpris module, its click (`playerctl play-pause`) and prev/next all
# follow playerctld's "active" player — and playerctld makes a player active on
# ANY property change, or simply by appearing last. With the phone relayed by
# KDE Connect that goes wrong all the time: the phone reports Spotify AND a
# paused YouTube session, the paused one shows up last (or sends an update),
# and the bar shows "Memory reboot ⏸" while Spotify is actually playing — and
# a click toggles the wrong app.
#
# So: whenever player state changes, if the active player isn't playing but
# another one is, rotate playerctld (`playerctld shift`) until a playing one is
# in front. With nothing playing, playerctld's own choice is left alone (the
# last thing you touched — usually what you just paused).
#
# exec-once from hyprland.conf.

set -u

# One instance only: a second exec (a reload, a manual start) doubled every
# follower and every shift.
exec 8>"${XDG_RUNTIME_DIR:-/tmp}/media-prefer-playing.lock"
flock -n 8 || exit 0

status_of() { playerctl -p "$1" status 2>/dev/null; }

# KDE Connect's copy of the phone's Spotify while spotify-remote.py's bridge
# ("kdeconnect.spotifyremote", from the Web API) is up: the copy can be frozen — over
# Bluetooth KDE Connect reports the phone's players only when the link comes
# up — and stuck at "Playing" forever, so it must never be the one in front.
# Same rule as superseded() in now-playing.py / media-menu.py.
superseded() {
    local p=$1; shift
    [[ $p == kdeconnect.* && $p != kdeconnect.spotifyremote ]] || return 1
    printf '%s\n' "$@" | grep -qx kdeconnect.spotifyremote || return 1
    busctl --user get-property "org.mpris.MediaPlayer2.$p" /org/mpris/MediaPlayer2 \
        org.mpris.MediaPlayer2 Identity 2>/dev/null | grep -qi '^s "spotify'
}

# Firefox's (or Zen's) own player while the mpris-position extension's per-tab
# players (firefox.tab_<id> / zen.tab_<id>) cover its YouTube tab — same rule
# as now-playing.py.
ff_covered() {
    local p=$1; shift
    [[ $p == firefox.instance* ]] || return 1
    # Zen's own player is ALSO firefox.instance_* (Gecko hard-codes the name);
    # its Identity is "Mozilla zen" and its tab players are zen.tab_<id>
    local b=firefox
    busctl --user get-property "org.mpris.MediaPlayer2.$p" /org/mpris/MediaPlayer2 \
        org.mpris.MediaPlayer2 Identity 2>/dev/null | grep -qi zen && b=zen
    printf '%s\n' "$@" | grep -q "^$b\.tab_" || return 1
    playerctl -p "$p" metadata xesam:url 2>/dev/null | grep -q 'youtube\.com'
}

# Spotify's mirror copy — the laptop app showing what the phone plays, or the
# phone's app showing the laptop — per spotify_where.py; fix() fills $mirrors.
mirrors=""

# Is this player one we want in front? $1 = player, rest = all players.
good() {
    local p=$1
    [[ $'\n'$mirrors$'\n' == *$'\n'$p$'\n'* ]] && return 1
    superseded "$@" && return 1
    ff_covered "$@" && return 1
    [ "$want" = any ] || [ "$(status_of "$p")" = Playing ]
}

fix() {
    local ps n i p
    mapfile -t ps < <(playerctl -l 2>/dev/null)     # playerctld's activity order
    n=${#ps[@]}
    (( n > 1 )) || return
    mirrors=""
    printf '%s\n' "${ps[@]}" | grep -q '^spotify' &&
        mirrors=$(/usr/bin/python3 "$HOME/.config/hypr/spotify_where.py" hidden "${ps[@]}")
    # Prefer a playing, non-superseded player; with none playing, any
    # non-superseded one (playerctld's own choice otherwise left alone).
    want=playing
    for p in "${ps[@]}"; do good "$p" "${ps[@]}" && break; p=; done
    [ -n "$p" ] || { want=any; for p in "${ps[@]}"; do good "$p" "${ps[@]}" && break; p=; done; }
    [ -n "$p" ] || return
    [ "${ps[0]}" = "$p" ] && return
    for (( i = 1; i < n; i++ )); do
        playerctld shift >/dev/null 2>&1
        [ "$(playerctl -l 2>/dev/null | head -n1)" = "$p" ] && return
    done
}

# On exit, take the playerctl followers along. They live in the pipeline's
# subshells, not as our direct children, so a plain kill of this script left
# them running forever (they had piled up with every restart). The pipeline
# runs in the background with `wait`, because bash only runs a trap once the
# foreground command ends — and this one never does.
kill_tree() { local c; for c in $(pgrep -P "$1"); do kill_tree "$c"; done; kill "$1" 2>/dev/null; }
cleanup() { local c; for c in $(pgrep -P $$); do kill_tree "$c"; done; }
trap cleanup EXIT
trap 'exit 0' TERM INT HUP

fix
# Two triggers: any player's status/track changing, and playerctld switching
# its active player (which can happen with no status change at all).
{
    playerctl -a -F metadata --format '{{playerInstance}} {{status}} {{title}}' 2>/dev/null &
    playerctl -p playerctld -F metadata --format '{{status}} {{title}}' 2>/dev/null
} | while IFS= read -r _; do
    # Drain a burst (shift itself causes a few events) before acting once.
    while IFS= read -r -t 0.3 _; do :; done
    fix
done &
wait
