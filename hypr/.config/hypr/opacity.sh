#!/bin/bash
# Transparency of the window UNDER THE MOUSE — SUPER+SHIFT+Scroll.
#
#   opacity.sh up | down    step that window's opacity by STEP
#                           (scroll up = more solid)
#   opacity.sh reset        put that window back to its app's default
#   opacity.sh set-default <class> <percent>
#                           make <percent> the default for every window of
#                           that app (the OSD's "Make default" button)
#
# Every app starts at the global default from hyprland.conf's decoration block
# (active 0.92 / inactive 0.88) — except the apps listed in
# opacity-defaults.conf (Ghostty 100, yazi 96, …), which opacity-watch.sh tags
# with their own value as each window opens. Scrolling tags
# the window "opNN" and a rule in opacity-rules.conf (sourced last) gives every
# tag its opacity, with `override` so it REPLACES the global value instead of
# multiplying with it. Reset just removes the tag. Per window, per session.
#
# Why tags and not `dispatch setprop`: setprop values are wiped whenever
# Hyprland re-evaluates window rules — on every title change — so a browser
# switching tab or Spotify changing song snapped back to the default.
#
# Whole-window opacity fades text along with the background, hence the MIN
# floor. Fullscreen windows stay opaque (fullscreen_opacity is 1.0).
#
# SUPER+SHIFT, not SHIFT alone: SHIFT+Scroll is horizontal scrolling in
# browsers / VS Code / file managers and a global bind would steal it.

set -u

# Percent. The rules in opacity-rules.conf exist for exactly MIN..MAX by STEP.
DEFAULT=92              # keep in step with decoration:active_opacity
DEFAULTS="$HOME/.config/hypr/opacity-defaults.conf"
MIN=70
MAX=100
STEP=4                  # even, so every value lands on a rule

# A fast wheel spin starts several copies at once; without this they all read
# the same tag and the steps collapse into one.
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/opacity.lock"
flock 9

# The app's own default (opacity-defaults.conf), else the global one.
app_default() {   # $1 = class
    local v
    v=$(awk -F'=' -v c="$1" '
        /^[[:space:]]*#/ { next }
        { k = $1; gsub(/[[:space:]]/, "", k); if (k == c) { v = $2; gsub(/[[:space:]]/, "", v) } }
        END { print v }' "$DEFAULTS" 2>/dev/null)
    [[ "$v" =~ ^[0-9]+$ ]] && echo "$v" || echo "$DEFAULT"
}

# set-default: rewrite that app's line (none at all when it equals the global
# default), then move every open window of the app that was still sitting at
# its OLD default to the new one. Windows scrolled to something else keep it.
if [ "${1:-}" = set-default ]; then
    class="${2:?class}" pct="${3:?percent}"
    [[ "$pct" =~ ^[0-9]+$ ]] || exit 2
    old=$(app_default "$class")
    tmp=$(mktemp)
    awk -F'=' -v c="$class" '
        /^[[:space:]]*#/ || NF < 2 { print; next }
        { k = $1; gsub(/[[:space:]]/, "", k); if (k != c) print }' "$DEFAULTS" > "$tmp" 2>/dev/null
    [ "$pct" != "$DEFAULT" ] && printf '%s = %s\n' "$class" "$pct" >> "$tmp"
    mv "$tmp" "$DEFAULTS"

    oldtag=""; [ "$old" != "$DEFAULT" ] && oldtag="op$old"
    newtag=""; [ "$pct" != "$DEFAULT" ] && newtag="op$pct"
    batch=""
    while IFS=$'\t' read -r a t; do
        [ "$t" = "$oldtag" ] || continue
        [ -n "$t" ] && batch="$batch dispatch tagwindow -$t address:$a ;"
        [ -n "$newtag" ] && batch="$batch dispatch tagwindow +$newtag address:$a ;"
    done < <(hyprctl clients -j | jq -r --arg c "$class" '
        .[] | select(.class == $c)
        | "\(.address)\t\(.tags | map(select(test("^op[0-9]+$"))) | first // "")"')
    [ -n "$batch" ] && hyprctl --batch "$batch" >/dev/null
    exit 0
fi

# ── which window is under the cursor ───────────────────────────────────────
# Hit-test the cursor against windows on the workspaces actually on screen
# (each monitor's active + special). Floating windows sit above tiled ones;
# among overlapping candidates the most recently focused wins (lowest
# focusHistoryID), which is the one drawn on top.
read -r cx cy < <(hyprctl cursorpos | tr -d ',')
visible=$(hyprctl monitors -j | jq -c '[.[] | .activeWorkspace.id, .specialWorkspace.id] | map(select(. != 0))')
win=$(hyprctl clients -j | jq -r --argjson x "$cx" --argjson y "$cy" --argjson ws "$visible" '
    [ .[] | select(.mapped and (.hidden | not) and (.workspace.id as $w | $ws | index($w)))
          | select($x >= .at[0] and $x < .at[0] + .size[0]
               and $y >= .at[1] and $y < .at[1] + .size[1]) ]
    | sort_by((if .floating or .pinned then 0 else 1 end), .focusHistoryID)
    | first // empty
    | "\(.address)\t\(.class)\t\(.tags | map(select(test("^op[0-9]+$"))) | first // "")"')
[ -n "$win" ] || exit 0                 # cursor is over the bar / wallpaper
IFS=$'\t' read -r addr class tag <<<"$win"
w="address:$addr"

def=$(app_default "$class")
cur=${tag#op}; [ -n "$cur" ] || cur=$def

case "${1:-}" in
    up)    new=$((cur + STEP)) ;;
    down)  new=$((cur - STEP)) ;;
    reset) new=$def ;;
    *)     echo "usage: opacity.sh up|down|reset" >&2; exit 2 ;;
esac
(( new < MIN )) && new=$MIN
(( new > MAX )) && new=$MAX

batch=""
[ -n "$tag" ] && batch="dispatch tagwindow -$tag $w ;"
# Reset to the global default = no tag at all. Anything else — including an
# app's own default from opacity-defaults.conf — is a tag (those apps have no
# windowrule of their own; opacity-watch.sh tags them as they open).
[ "${1:-}" = reset ] && [ "$new" = "$DEFAULT" ] || batch="$batch dispatch tagwindow +op$new $w"
[ -n "$batch" ] && hyprctl --batch "$batch" >/dev/null

# The OSD: Quickshell's (OpacityOsd.qml) — bar, the app's default marked on
# it, and a "Make default" button. If the shell is not running, fall back to
# one mako notification that updates in place (replace-id kept in a file).
# Category "osd" lets that through mako's do-not-disturb mode (mako/config).
pct=$new
if ! "$HOME/.local/bin/qs" ipc call osd opacity "$class" "$pct" "$def" "$DEFAULT" >/dev/null 2>&1; then
    idf="${XDG_RUNTIME_DIR:-/tmp}/opacity-notify-id"
    id=$(cat "$idf" 2>/dev/null)
    notify-send -a "Opacity" -c osd -t 1200 -p ${id:+-r "$id"} -h "int:value:$pct" \
        "${class##*.}  $pct%" > "$idf" 2>/dev/null
fi
