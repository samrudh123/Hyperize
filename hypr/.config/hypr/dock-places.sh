#!/bin/bash
# Put Trash and the mounted disks in the dock, the way the Ubuntu/GNOME dock does.
#
# nwg-dock has no concept of volumes or trash — it only draws pinned entries and
# running windows. So each "place" is a generated .desktop file that gets pinned
# like any other app. Two consequences worth knowing:
#
#   * Pins in ~/.cache/nwg-dock-pinned are matched against window CLASSES, but a
#     pin that matches no running window is drawn as a plain icon that launches
#     its .desktop Exec — which is exactly what a place needs.
#   * The dock re-reads that file at runtime (on its next Hyprland event), so a
#     disk mounted later only needs this script re-run — no dock restart. What
#     is missing is a watcher: nothing re-runs it automatically on mount.
#
# NoDisplay=true keeps these out of fuzzel's app list; nwg-dock reads the file
# regardless (same trick as the code.desktop snap alias).

set -u

APPS="$HOME/.local/share/applications"
PINNED="$HOME/.cache/nwg-dock-pinned"
FM=nautilus                       # GNOME Files: handles trash:/// and mount paths
mkdir -p "$APPS" "$(dirname "$PINNED")"

write_entry() {   # name, icon, exec, file
    cat > "$APPS/$4" <<EOF
[Desktop Entry]
Type=Application
Name=$1
Icon=$2
Exec=$3
Terminal=false
NoDisplay=true
Categories=System;
EOF
}

# ── Trash ──────────────────────────────────────────────────────────────────
# user-trash-full only while something is in it; regenerated on every run.
trash_icon=user-trash
[ -n "$(ls -A "$HOME/.local/share/Trash/files" 2>/dev/null)" ] && trash_icon=user-trash-full
write_entry "Trash" "$trash_icon" "$FM trash:///" "dock-trash.desktop"

# ── Disks ──────────────────────────────────────────────────────────────────
rm -f "$APPS"/dock-disk-*.desktop
places=()
while IFS= read -r mp; do
    [ -d "$mp" ] || continue
    label=$(basename "$mp")
    slug=$(printf '%s' "$label" | tr -c '[:alnum:]' '-' | sed 's/-\+/-/g; s/^-//; s/-$//')
    [ -n "$slug" ] || continue

    # Removable media gets the USB-stick icon; fixed partitions the platter one.
    icon=drive-harddisk
    src=$(findmnt -no SOURCE --target "$mp" 2>/dev/null)
    if [ -n "$src" ] && [ "$(lsblk -no HOTPLUG "$src" 2>/dev/null | head -1 | tr -d ' ')" = "1" ]; then
        icon=drive-removable-media
    fi

    write_entry "$label" "$icon" "$FM $(printf '%q' "$mp")" "dock-disk-$slug.desktop"
    places+=("dock-disk-$slug")
done < <(findmnt -rno TARGET | grep -E "^(/run/media/$USER|/media/$USER|/mnt)/" | sort -u)

places+=("dock-trash")

# ── Rewrite the pinned list ────────────────────────────────────────────────
# Keep whatever the user has pinned (they can pin/unpin from the dock's context
# menu), drop any stale places, then append the current ones at the end.
tmp=$(mktemp)
if [ -f "$PINNED" ]; then
    grep -vE '^(dock-disk-|dock-trash$)' "$PINNED" > "$tmp"
fi
printf '%s\n' "${places[@]}" >> "$tmp"
# Mocha icons for any new place (a disk) BEFORE the pin appears — the dock
# redraws as soon as the pinned file changes (dock-theme-icons.py).
mapfile -t ids < "$tmp"
/usr/bin/python3 "$HOME/.config/hypr/dock-theme-icons.py" "${ids[@]}" >/dev/null 2>&1
mv "$tmp" "$PINNED"

printf 'dock-places: %d disk(s) + Trash\n' "$(( ${#places[@]} - 1 ))"
