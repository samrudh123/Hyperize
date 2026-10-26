#!/bin/bash
# Seek the bar's current player — scroll on custom/now-playing.
#
#   media-seek.sh 5+ | 5-  [player]
#
# The bar's two pills (now-playing.py --scope local / remote) pass their own
# player; without one, the player the bar shows (`now-playing.py current`).
# Each player gets its own running total / leader below.
#
# Why not just `playerctl position 5+` like the mpris module: that is the MPRIS
# Seek(offset) call, and KDE Connect's bridge to the phone silently ignores it
# (verified: Seek +10s left the position where it was). SetPosition(absolute)
# DOES reach the phone, so for kdeconnect players this reads the position and
# sets current ± N. Same for Firefox (see below). Others keep the plain relative seek.
#
# A fast wheel spin starts one copy per notch. They used to queue on a lock
# and each do the whole job — find the shown player, select it in KDE Connect,
# read, seek, then sleep 0.4 s — so four notches took 2.4 s (measured) before
# the last one landed. Now every copy just adds its step to a running total;
# the first one ("leader") waits COLLECT s for the rest of the spin, then
# seeks ONCE by the sum, and repeats while more notches keep arriving.
# No sleep after the seek: KDE Connect records the new position locally the
# moment it sends it, and the Spotify bridge does the same (optimistically).

set -u

arg="${1:-}"
[[ "$arg" =~ ^([0-9]+)([+-])$ ]] || { echo "usage: media-seek.sh N+|N- [player]" >&2; exit 2; }
delta=${BASH_REMATCH[1]}; [ "${BASH_REMATCH[2]}" = - ] && delta=$(( -delta ))

want="${2:-}"
RT="${XDG_RUNTIME_DIR:-/tmp}"
key=$(printf '%s' "${want:-shown}" | tr -c 'A-Za-z0-9._-' _)
ACC="$RT/media-seek.$key.acc"
COLLECT=0.12

add() {   # atomically add $1 to the running total; print the total taken if $2 = take
    (
        flock 7
        local cur; cur=$(cat "$ACC" 2>/dev/null); cur=${cur:-0}
        if [ "${2:-}" = take ]; then echo "$(( cur + $1 ))"; echo 0 > "$ACC"
        else echo "$(( cur + $1 ))" > "$ACC"; fi
    ) 7>"$ACC.lock"
}

add "$delta"
exec 9>"$RT/media-seek.$key.leader"
flock -n 9 || exit 0            # a leader is collecting; our step is in the total

player=${want:-$(/usr/bin/python3 "$HOME/.config/hypr/now-playing.py" current)}   # else the one the bar shows
if [ -z "$player" ]; then add 0 take >/dev/null; exit 0; fi
case "$player" in
    kdeconnect.mpris_*)
        # KDE Connect reports the position of its CURRENT phone player for
        # all of them — select this one first (see kdec_focus in now-playing.py).
        /usr/bin/python3 "$HOME/.config/hypr/now-playing.py" focus "$player" ;;
esac

while :; do
    sleep "$COLLECT"
    total=$(add 0 take)
    [ "$total" = 0 ] && break
    case "$player" in
        # Firefox (and Zen, same engine) too: it turns a relative Seek into the page's "seek forward /
        # back", and YouTube jumps a fixed 5 s whatever the offset (a 4-notch
        # spin = 5 s, measured). Its absolute SetPosition is exact.
        kdeconnect.*|firefox.*|zen.*)
            cur=$(playerctl -p "$player" position 2>/dev/null) || break
            new=$(awk -v c="$cur" -v d="$total" 'BEGIN { n = c + d; if (n < 0) n = 0; printf "%.3f", n }')
            playerctl -p "$player" position "$new" ;;
        *)
            if [ "$total" -lt 0 ]; then playerctl -p "$player" position "$(( -total ))-"
            else playerctl -p "$player" position "${total}+"; fi ;;
    esac
done

# Tell the bar to redraw now: while paused nothing else would (KDE Connect
# emits no Seeked for a seek sent through it). SIGUSR1 = now-playing.py's
# "redraw" (nudge_bars there).
pkill -USR1 -f '^/usr/bin/python3 .*/now-playing\.py( --cffi)?( --scope [a-z]+)?$'

# A notch that arrived between our last look and releasing the lock would be
# stranded (its copy saw us as leader and left): pick it up.
flock -u 9
[ "$(cat "$ACC" 2>/dev/null || echo 0)" != 0 ] && exec "$0" 0+ "$want"
exit 0
