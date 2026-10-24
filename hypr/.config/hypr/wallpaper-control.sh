#!/bin/bash
# Bottom-bar wallpaper widget: show the current wallpaper and pause/resume an
# animated one.
#
#   wallpaper-control.sh status   JSON for waybar (polled by custom/wallpaper)
#   wallpaper-control.sh toggle   pause / resume the animated wallpaper
#
# Pausing uses SIGSTOP / SIGCONT on mpvpaper rather than mpv's own pause:
# mpvpaper's -p auto-pause sends "pause no" whenever the desktop becomes visible
# again, which would silently undo a manual pause. A stopped process keeps its
# last frame on screen, uses no CPU, and resumes exactly where it was.
# set-wallpaper.sh sends SIGCONT along with SIGTERM so a paused instance can
# still be replaced.

STATE="$HOME/.config/hypr/wallpaper"

# Polled every 2 s by the bar, so bash builtins only: pgrep is the one
# process started (head/basename/ps/cut were ~8 forks a poll).
pid=$(pgrep -x mpvpaper)
pid=${pid%%$'\n'*}
name=""
[ -s "$STATE" ] && { IFS= read -r name < "$STATE"; name=${name##*/}; }
name="${name%.*}"

# /proc/PID/stat: "pid (comm) S ..." — S is T while SIGSTOPped
paused() {
    local st
    [ -n "$pid" ] && IFS= read -r st 2>/dev/null < "/proc/$pid/stat" || return 1
    st=${st##*) }
    [ "${st%% *}" = T ]
}

case "$1" in
    toggle)
        [ -n "$pid" ] || exit 0
        if paused; then kill -CONT "$pid"; else kill -STOP "$pid"; fi
        ;;
    status|*)
        if [ -z "$pid" ]; then
            icon="󰸉"; class="static"; tip="Still wallpaper: $name"
        elif paused; then
            icon="󰐊"; class="paused"; tip="Animated wallpaper paused: $name\nClick to resume"
        else
            icon="󰏤"; class="playing"; tip="Animated wallpaper playing: $name\nClick to pause (saves battery)"
        fi
        tip="$tip\nRight-click to pick a wallpaper"
        printf '{"text":"%s  %s","class":"%s","tooltip":"%s"}\n' "$icon" "$name" "$class" "$tip"
        ;;
esac
