#!/bin/bash
# Start the Quickshell shell and bring it back if it CRASHES.
#
#   exec-once in hyprland.conf, reload.sh (restart_bar) and dock-toggle.sh
#   start the shell through this instead of ~/.local/bin/qs directly.
#
# A crash (killed by SIGSEGV / SIGABRT / SIGBUS / SIGFPE — exit 139/134/135/
# 136) restarts it after a second, with a notification. A normal exit, `qs
# kill` or `pkill qs` (SIGTERM) ends this too, so reload.sh's own restart
# never races a second copy. More than 5 crashes in 2 minutes: give up (a
# crash loop) and say so — SUPER+A (dock-toggle.sh) starts it again.
#
# Why: 2026-11-24 the winter theme's falling clumps (QtQuick.Particles)
# segfaulted the shell every so often; the bars and snow vanished until
# SUPER+A. Particles are gone now; this is the safety net for anything else.
QS="$HOME/.local/bin/qs"
crashes=()
while :; do
    "$QS" "$@"
    code=$?
    case $code in
        134|135|136|139) ;;
        *) exit $code ;;
    esac
    now=$(date +%s)
    recent=()
    for t in "${crashes[@]}"; do (( now - t < 120 )) && recent+=("$t"); done
    crashes=("${recent[@]}" "$now")
    if (( ${#crashes[@]} > 5 )); then
        notify-send -a "Shell" -u critical "Quickshell keeps crashing" \
            "Stopped restarting it. SUPER+A starts it again; see: qs log" 2>/dev/null
        exit $code
    fi
    logger -t qs-run "quickshell crashed (exit $code), restarting" 2>/dev/null
    notify-send -a "Shell" "Quickshell crashed — restarted" "exit $code · details: journalctl -t qs-run, qs log" 2>/dev/null
    sleep 1
done
