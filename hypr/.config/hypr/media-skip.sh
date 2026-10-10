#!/bin/bash
# Bottom bar ⏮ / ⏭ — act on the player the bar SHOWS.
#
#   media-skip.sh next | prev  [player]
#
# The bar's two pills (now-playing.py --scope local / remote) each have their
# own ⏮ ⏭, which pass their own player; without one, the shown player.
#
# Was `playerctl previous || spotify-remote.py prev` on the bar. Two bugs in
# that: plain playerctl acts on playerctld's front player, which is not always
# the one shown (see now-playing.py shown_player); and when the shown player
# refused — YouTube Morphe has no "previous" outside a playlist
# (CanGoPrevious false) — the fallback skipped SPOTIFY on the phone instead.
#
# Now: if the player supports it, skip; if it can't go back, ⏮ restarts the
# current video/track instead (absolute SetPosition 0 — KDE Connect ignores
# relative seeks, see media-seek.sh); with no player shown, nothing.

set -u
case "${1:-}" in
    next) method=next; can=CanGoNext ;;
    prev) method=previous; can=CanGoPrevious ;;
    *) echo "usage: media-skip.sh next|prev [player]" >&2; exit 2 ;;
esac

player=${2:-$(/usr/bin/python3 "$HOME/.config/hypr/now-playing.py" current)}
# Nothing showing: do nothing. (Was: skip Spotify on whatever device via the
# Web API — with the phone off that only produced "Spotify lost the device".)
[ -n "$player" ] || exit 0

ok=$(busctl --user get-property "org.mpris.MediaPlayer2.$player" /org/mpris/MediaPlayer2 \
        org.mpris.MediaPlayer2.Player "$can" 2>/dev/null)
if [ "$ok" = "b true" ]; then
    exec playerctl -p "$player" "$method"
elif [ "$method" = previous ]; then
    case "$player" in
        kdeconnect.mpris_*)   # KDE Connect reports the CURRENT phone player's position for all
            /usr/bin/python3 "$HOME/.config/hypr/now-playing.py" focus "$player" ;;
    esac
    exec playerctl -p "$player" position 0
fi
