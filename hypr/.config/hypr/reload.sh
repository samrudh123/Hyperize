#!/bin/bash
# Apply config changes without logging out.
#
#   reload.sh            hyprland.conf only  (keybinds, rules, env, monitors)
#   reload.sh bar        restart the shell (Quickshell: both bars + the dock)
#   reload.sh dock       show / hide the sidebar  [--hidden | --shown]
#   reload.sh mako       notification daemon
#   reload.sh idle       hypridle
#   reload.sh all        everything above
#
# Since 2026-10-09 the bars and the dock are ONE Quickshell process
# (~/.config/quickshell), so the old waybar-then-dock ordering dance
# (landmine 11, reload.sh.pre-quickshell (archived in ~/.dotfiles-backup/pre-backups-2026-10-17.tar.gz)) is gone. Quickshell also hot-reloads
# by itself whenever a file under ~/.config/quickshell is saved; `bar` is only
# for a real restart (after rebuilding quickshell, or if it wedged).
#
# Everything is (re)started with `hyprctl dispatch exec` on purpose: a process
# launched straight from a terminal inside the VS Code snap inherits the snap's
# cgroup and dies when VS Code does. Hyprland forks it into the session scope
# instead, exactly as exec-once would. (Landmine 12.)

set -u

QS="$HOME/.local/bin/qs"

say() { printf '  %s\n' "$*"; }

# Is the dock on screen? A shown dock has a "qs-dock" layer.
dock_shown() { hyprctl layers 2>/dev/null | grep -qE "namespace: qs-dock, pid: [0-9]"; }

reload_hypr() {
    if ! Hyprland --verify-config -c "$HOME/.config/hypr/hyprland.conf" 2>&1 | grep -q "config ok"; then
        echo "hyprland.conf has errors — NOT reloading. Run:" >&2
        echo "  Hyprland --verify-config -c ~/.config/hypr/hyprland.conf" >&2
        return 1
    fi
    hyprctl reload >/dev/null && say "hyprland.conf reloaded"
    say "note: 'env =' lines only affect processes started AFTER this point"
}

restart_dock() {
    case "${DOCK_STATE:-}" in
        --shown)  "$QS" ipc call dock open ;;
        --hidden) "$QS" ipc call dock close ;;
        *)        "$QS" ipc call dock toggle ;;
    esac >/dev/null 2>&1 || { say "quickshell is not running — try: reload.sh bar"; return 1; }
    say "sidebar $(dock_shown && echo shown || echo hidden)"
}

restart_bar() {
    # The dock comes back the way it was (it always starts hidden).
    local shown=0
    dock_shown && shown=1
    "$QS" kill >/dev/null 2>&1
    sleep 1
    # Through hyprctl, so it lives in the session scope (landmine 12).
    hyprctl dispatch exec "$QS" >/dev/null
    for _ in $(seq 1 40); do
        "$QS" ipc show >/dev/null 2>&1 && hyprctl layers 2>/dev/null | grep -q "namespace: qs-bar," && break
        sleep 0.25
    done
    [ "$shown" = 1 ] && "$QS" ipc call dock open >/dev/null 2>&1

    local geo
    geo=$(hyprctl layers 2>/dev/null | grep "namespace: qs-bar," | grep -o "xywh: [0-9 ]*")
    say "shell restarted   ${geo:-(no qs-bar layer!)}"
    local mw
    mw=$(hyprctl monitors -j 2>/dev/null | python3 -c 'import json,sys; m=json.load(sys.stdin)[0]; print(round(m["width"]/m["scale"]))' 2>/dev/null)
    case "$geo" in
        "xywh: 0 0 $mw "*)    say "geometry ok — bar reaches both edges" ;;
        "")                   say "WARNING: the bar did not come back — see: qs log" ;;
        *)                    say "WARNING: unexpected bar geometry" ;;
    esac
}

case "${1:-hypr}" in
    hypr|conf|"") reload_hypr ;;
    bar|waybar)   restart_bar ;;
    dock|sidebar) DOCK_STATE=${2:-} restart_dock ;;
    mako|notif)   makoctl reload && say "mako reloaded" ;;
    idle|hypridle)
        pkill -x hypridle 2>/dev/null; sleep 0.5
        hyprctl dispatch exec hypridle >/dev/null; say "hypridle restarted" ;;
    all)
        reload_hypr
        makoctl reload 2>/dev/null && say "mako reloaded"
        pkill -x hypridle 2>/dev/null; sleep 0.3
        hyprctl dispatch exec hypridle >/dev/null; say "hypridle restarted"
        restart_bar ;;
    *)
        sed -n '3,9p' "$0" | sed 's/^# \?//' >&2; exit 2 ;;
esac
