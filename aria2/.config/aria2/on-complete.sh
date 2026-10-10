#!/bin/bash
# aria2 on-download-complete hook: $1 = GID, $2 = number of files, $3 = path.
# Notification with "Open" / "Show in folder" buttons (mako supports actions).
# Detached so aria2 is never kept waiting on a notification.
path="$3"
[ -n "$path" ] || exit 0
case "$path" in */.aria2/*|*.torrent|*.meta4|*.metalink) exit 0 ;; esac   # metadata, not a real download
(
    act=$(notify-send -a Downloads -i emblem-downloads \
        --action=open=Open --action=folder="Show in folder" \
        "Download complete" "$(basename -- "$path")")
    case "$act" in
        open)   xdg-open "$path" ;;
        folder) if command -v nautilus >/dev/null; then nautilus --select "$path"
                else xdg-open "$(dirname -- "$path")"; fi ;;
    esac
) >/dev/null 2>&1 </dev/null &
disown
