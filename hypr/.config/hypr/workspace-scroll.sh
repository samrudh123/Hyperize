#!/bin/bash
# SUPER+Scroll — cycle the occupied workspaces PLUS one empty one, then wrap.
#
#   workspace-scroll.sh next | prev
#
# With windows on 1, 2 and 5:   next  1 → 2 → 5 → 6 (empty) → 1 → …
#                               prev  in exactly the reverse order
#
# `workspace e+1` only visits occupied workspaces, so there was no way to
# scroll onto a fresh one. The one empty stop is always (highest occupied + 1),
# so new windows go to the right of everything. Workspace 1 is always a stop.
# Sitting on some other empty workspace (e.g. jumped to 8 with SUPER+8) counts
# as being at that number.

set -u

cur=$(hyprctl activeworkspace -j | jq '.id')
mapfile -t occ < <(hyprctl workspaces -j | jq '.[] | select(.id > 0 and .windows > 0) | .id' | sort -n)

# Workspace 1 is always a stop, even when empty — the wrap lands there.
if [ ${#occ[@]} -eq 0 ]; then
    stops=(1)
else
    mapfile -t stops < <(printf '%s\n' 1 "${occ[@]}" $(( occ[-1] + 1 )) | sort -nu)
fi

target=""
case "${1:-}" in
    next)
        for s in "${stops[@]}"; do (( s > cur )) && { target=$s; break; }; done
        [ -n "$target" ] || target=${stops[0]}           # past the end → wrap
        ;;
    prev)
        for (( i=${#stops[@]}-1; i>=0; i-- )); do
            (( stops[i] < cur )) && { target=${stops[i]}; break; }
        done
        [ -n "$target" ] || target=${stops[-1]}          # before the start → wrap
        ;;
    *) echo "usage: workspace-scroll.sh next|prev" >&2; exit 2 ;;
esac

[ "$target" = "$cur" ] || hyprctl dispatch workspace "$target" >/dev/null
