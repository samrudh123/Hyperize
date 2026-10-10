#!/bin/bash
# Toggle the sidebar dock — SUPER+A.
#
# The dock is part of the Quickshell shell (~/.config/quickshell/Dock.qml)
# since 2026-10-09; this used to signal nwg-dock-hyprland (see
# dock-toggle.sh.pre-quickshell). Now it is an IPC call. If quickshell is not
# running (crashed, or killed) it is started and the dock shown.
#
# Absolute path: keybind children do not get ~/.local/bin on PATH.

set -u

QS="$HOME/.local/bin/qs"

"$QS" ipc call dock toggle >/dev/null 2>&1 && exit 0

# Through hyprctl so it lands in the session scope (landmine 12), then wait
# for its IPC socket before showing the dock ("Not ready" exits non-zero).
hyprctl dispatch exec "$QS" >/dev/null
for _ in $(seq 1 50); do
    "$QS" ipc call dock open >/dev/null 2>&1 && exit 0
    sleep 0.1
done
echo "dock-toggle: quickshell did not come up — see: $QS log" >&2
exit 1
