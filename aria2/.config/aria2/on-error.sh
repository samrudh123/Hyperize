#!/bin/bash
# aria2 on-download-error hook: $1 = GID, $2 = number of files, $3 = path (may be empty).
name=$(basename -- "${3:-download $1}")
(
    act=$(notify-send -a Downloads -u critical -i dialog-error \
        --action=status="Open downloads menu" \
        "Download failed" "$name")
    [ "$act" = status ] && "$HOME/.local/bin/dl-popup" status
) >/dev/null 2>&1 </dev/null &
disown
