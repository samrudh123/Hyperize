#!/bin/sh
# Escape dismisses the task reminders on screen (tasks.py's notifications,
# app name "Tasks"; the red ones never expire on their own). Bound with
# bindn in hyprland.conf, so Escape still reaches the focused window as
# usual; with no reminder up this does nothing. Other apps' notifications
# are left alone. Dismissed ones stay in the notification centre's history.
makoctl list 2>/dev/null | awk '
    /^Notification [0-9]+:/ { id = $2; sub(":", "", id) }
    /^  App name: Tasks$/   { print id }' |
while read -r id; do
    makoctl dismiss -n "$id"
done
