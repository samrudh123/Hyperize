#!/bin/bash
# Set the desktop wallpaper and remember the choice across logins.
# Still images go to swaybg; videos/GIFs (animated wallpapers) go to mpvpaper.
#
#   set-wallpaper.sh                  pick one from a menu
#   set-wallpaper.sh /path/to/file    set that image or video
#   set-wallpaper.sh --restore        re-apply the saved one (used at login)
#   set-wallpaper.sh --preview FILE [KIND]
#                                     play the transition to FILE on screen and
#                                     fade back — nothing is changed (picker `t`)
#
# The saved path lives in ~/.config/hypr/wallpaper so hyprland.conf does not
# need editing every time you change it.
#
# TRANSITIONS. A change is animated by the Quickshell shell
# (~/.config/quickshell/WallpaperTransition.qml): it covers the screen's
# wallpaper with the old one, animates to the new one while the backend is
# swapped underneath, and fades away. The kind is in
# ~/.config/hypr/wallpaper-transition (circle, cursor, iris, fade, wipe, wave,
# slide, zoom, dissolve, pixelate, diamond, random, none) — the picker's `t`
# sets it. No shell running, or `none`: the old instant switch.

DIR="$HOME/Pictures/wallpapers"
STATE="$HOME/.config/hypr/wallpaper"
MODE="fill"          # fill = cover the screen, cropping overflow
TRANSITION_FILE="$HOME/.config/hypr/wallpaper-transition"
QS="$HOME/.local/bin/qs"
FRAMES="$HOME/.cache/wallpaper-thumbs/first-frame"     # a video's first frame
RUN="${XDG_RUNTIME_DIR:-/tmp}"
# The first-run / broken-state wallpaper: this one if it is there, else any
# still image on the shelf, else Ubuntu's own (a fresh install has no shelf yet).
FALLBACK="$DIR/catppuccin-mocha-glow.png"
if [ ! -f "$FALLBACK" ]; then
    FALLBACK=$(find "$DIR" /usr/share/backgrounds -maxdepth 1 -type f \
                   \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
                   2>/dev/null | head -1)
fi

# mpvpaper is built from source into ~/.local/bin, which is not on the PATH
# exec-once children get — so call it by absolute path.
MPVPAPER="$HOME/.local/bin/mpvpaper"
# -p        pause while the wallpaper is fully covered (saves battery)
# (no -a full: it pauses while ANY window is fullscreen, even one on another
#  workspace — the window list mpvpaper gets has no workspace info — so a
#  fullscreen YouTube on workspace 3 froze the wallpaper on every workspace.
#  -p alone already pauses when the wallpaper is not actually being drawn.)
# panscan=1 crops to cover the screen, the video equivalent of swaybg's `fill`
# input-ipc-server: wallpaper-fullscreen.py pauses through this socket while
# the CURRENT workspace has a fullscreen window (what -a full got wrong).
MPV_SOCK="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/mpvpaper.sock"
MPV_OPTS="no-audio loop hwdec=auto-safe panscan=1.0 input-ipc-server=$MPV_SOCK"

is_video() {
    case "${1,,}" in
        *.mp4|*.webm|*.mkv|*.mov|*.gif) return 0 ;;
        *) return 1 ;;
    esac
}

# Set the global array `cmd` to the command that shows $1 as wallpaper.
# Small GIFs are pixel art (most of the animated shelf is 480–1280 px wide):
# blown up 2–4× with mpv's default smooth scaler they go blurry, so those get
# nearest-neighbour scaling and stay crisp. Big GIFs keep the smooth scaler.
wallpaper_cmd() {
    if is_video "$1"; then
        local opts="$MPV_OPTS" w
        if [[ "${1,,}" == *.gif ]]; then
            w=$(ffprobe -v error -select_streams v:0 -show_entries stream=width -of csv=p=0 "$1" 2>/dev/null)
            [[ "$w" =~ ^[0-9]+$ ]] && (( w < 1400 )) && opts+=" scale=nearest"
        fi
        cmd=("$MPVPAPER" -p -o "$opts" '*' "$1")
    else
        cmd=(swaybg -i "$1" -m "$MODE")
    fi
}

# A still that looks like $1 does on screen right now / will at its start:
#   a still image  -> itself
#   the RUNNING video (from the saved state) -> mpv's current frame, over its
#                     IPC socket (falls back to the first frame if mpvpaper is
#                     paused with SIGSTOP and does not answer)
#   any other video -> its first frame (mpvpaper starts there), cached
first_frame() {
    local key out
    key=$(printf '%s' "$1" | md5sum | cut -c1-16)-$(stat -c %Y "$1" 2>/dev/null)
    out="$FRAMES/$key.png"
    if [ ! -s "$out" ]; then
        mkdir -p "$FRAMES"
        ffmpeg -v error -y -i "$1" -frames:v 1 "$out" </dev/null 2>/dev/null || return 1
    fi
    printf '%s\n' "$out"
}
current_frame() {
    local out="$RUN/wallpaper-from-$$.png"
    find "$RUN" -maxdepth 1 -name 'wallpaper-from-*.png' -mmin +2 -delete 2>/dev/null
    printf '{"command":["screenshot-to-file","%s","video"]}\n' "$out" |
        timeout 0.5 socat - "UNIX-CONNECT:$MPV_SOCK" >/dev/null 2>&1
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        [ -s "$out" ] && { sleep 0.05; printf '%s\n' "$out"; return 0; }
        sleep 0.03
    done
    return 1
}
still_of() {   # $1 = path, $2 = "running" if it is the wallpaper on screen now
    if ! is_video "$1"; then printf '%s\n' "$1"
    elif [ "${2:-}" = running ] && pgrep -x mpvpaper >/dev/null && current_frame; then :
    else first_frame "$1"
    fi
}

# Start the animation (returns at once; the shell waits for both images).
# 0 = a transition is running and wants `ready` once the backend has switched.
start_transition() {   # $1 = new wallpaper, $2 = kind (default: the saved one)
    local kind="${2:-}" old from to cx cy w h
    [ -n "$kind" ] || kind=$(tr -d '[:space:]' < "$TRANSITION_FILE" 2>/dev/null)
    [ -n "$kind" ] || kind=circle
    [ "$kind" = none ] && return 1
    [ -x "$QS" ] || return 1
    [ -s "$STATE" ] && IFS= read -r old < "$STATE"
    [ -n "$old" ] && [ -f "$old" ] && [ "$old" != "$1" ] || return 1
    from=$(still_of "$old" running) || return 1
    to=$(still_of "$1") || return 1
    # the cursor, as a fraction of the screen ("cursor" grows from it)
    read -r cx cy < <(hyprctl cursorpos 2>/dev/null | tr -d ',')
    read -r w h < <(hyprctl monitors -j 2>/dev/null | jq -r '.[0] | "\(.width / .scale) \(.height / .scale)"')
    local ox oy
    ox=$(awk -v c="${cx:-0}" -v w="${w:-1}" 'BEGIN { printf "%.4f", c / w }')
    oy=$(awk -v c="${cy:-0}" -v h="${h:-1}" 'BEGIN { printf "%.4f", c / h }')
    "$QS" ipc call wallpaper transition "$from" "$to" "$kind" "$ox" "$oy" >/dev/null 2>&1
}

apply() {
    local img="$1"
    [ -f "$img" ] || { notify-send "Wallpaper" "Not found: $img" 2>/dev/null; exit 1; }
    if is_video "$img" && [ ! -x "$MPVPAPER" ]; then
        notify-send "Wallpaper" "mpvpaper not installed: $MPVPAPER" 2>/dev/null; exit 1
    fi
    # Neither swaybg nor mpvpaper is driven over IPC here: replace the running
    # instance. Start the new one BEFORE killing the old so there is no black
    # flash. Kill both kinds, so switching image <-> video leaves no leftover
    # layer underneath.
    local animating=0
    start_transition "$img" && animating=1
    wallpaper_cmd "$img"
    "${cmd[@]}" >/dev/null 2>&1 &
    local new=$!
    disown "$new" 2>/dev/null
    sleep 0.6        # mpvpaper needs a moment longer than swaybg to show a frame
    for pid in $(pgrep -x swaybg) $(pgrep -x mpvpaper) $(pgrep -x mpvpaper-holder); do
        # CONT too: wallpaper-control.sh pauses mpvpaper with SIGSTOP, and a
        # stopped process does not act on SIGTERM until it is continued.
        [ "$pid" != "$new" ] && kill "$pid" 2>/dev/null && kill -CONT "$pid" 2>/dev/null
    done
    printf '%s\n' "$img" > "$STATE"
    # the new wallpaper is up under the animation: it may now fade away
    [ "$animating" = 1 ] && "$QS" ipc call wallpaper ready >/dev/null 2>&1

}

case "$1" in
    --preview)
        # Same animation, but the backend is never touched: `ready` straight
        # away, so the overlay fades back to the real wallpaper once it ends.
        [ -f "${2:-}" ] || exit 1
        start_transition "$2" "${3:-}" && "$QS" ipc call wallpaper ready >/dev/null 2>&1
        ;;
    --restore)
        img="$FALLBACK"
        [ -s "$STATE" ] && IFS= read -r saved < "$STATE" && [ -f "$saved" ] && img="$saved"
        is_video "$img" && [ ! -x "$MPVPAPER" ] && img="$FALLBACK"
        wallpaper_cmd "$img"
        exec "${cmd[@]}"
        ;;
    "")
        # menu: show file names, handles spaces in filenames correctly
        choice=$(find "$DIR" -maxdepth 1 -type f \
                    \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \
                       -o -iname '*.webp' -o -iname '*.bmp' \
                       -o -iname '*.mp4' -o -iname '*.webm' -o -iname '*.mkv' \
                       -o -iname '*.mov' -o -iname '*.gif' \) -printf '%f\n' \
                 | sort | fuzzel --dmenu --prompt '  wallpaper  ')
        [ -n "$choice" ] && apply "$DIR/$choice"
        ;;
    *)
        apply "$1"
        ;;
esac
