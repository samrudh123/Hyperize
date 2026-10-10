#!/bin/bash
# mako left-click (on-button-left in ./config). mako sets $id.
#
# mako's stock left-click is invoke-default-action, which does NOTHING for a
# notification whose only actions are named buttons — blueman's "Confirm /
# Deny" Bluetooth pairing prompt, KDE Connect's "Accept / Reject" — so the
# click just looked dead. Here: if it has named actions, pick one in fuzzel;
# otherwise behave as before (default action, then dismiss).

set -u
id="${id:-}"
[ -n "$id" ] || exit 0

# `makoctl list` (1.10, text): "Notification <id>: …", then "  Actions:" and
# "    key: label" lines under it.
named=$(makoctl list | awk -v id="$id" '
    /^Notification [0-9]+:/ { cur = ($2 == id ":") ; inact = 0; next }
    cur && /^  Actions:/      { inact = 1; next }
    cur && inact && /^    /   { sub(/^ +/, ""); split($0, a, ":"); if (a[1] != "default") n++ }
    END { print n + 0 }')

if [ "$named" -gt 0 ]; then
    exec makoctl menu -n "$id" fuzzel --dmenu --prompt "action  " --lines "$((named + 1))"
fi
makoctl invoke -n "$id" default 2>/dev/null
makoctl dismiss -n "$id"
