#!/bin/bash
# Show / hide / toggle the bottom bar.
#
#   bottom-bar.sh start | stop | toggle
#
# The bottom bar is part of the Quickshell shell (~/.config/quickshell/
# BottomBar.qml) since 2026-10-09 — it used to be a second waybar instance
# (bottom-bar.sh.pre-quickshell). "stop" only hides it; the shell keeps
# running. The dock no longer needs restarting afterwards: it re-centres
# itself when the bar's exclusive zone comes or goes. A trailing --no-dock
# (old callers) is accepted and ignored.

QS="$HOME/.local/bin/qs"

case "${1:-toggle}" in
    start)  verb=open ;;
    stop)   verb=close ;;
    toggle) verb=toggle ;;
    *)      echo "usage: $0 start|stop|toggle" >&2; exit 1 ;;
esac

exec "$QS" ipc call bottombar "$verb"
