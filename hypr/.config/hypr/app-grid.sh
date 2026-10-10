#!/bin/bash
# The GNOME-style app grid — SUPER+D, and the launcher button in the top
# bar's left corner (TopBar.qml; it used to sit at the foot of the dock).
#
# nwg-drawer 0.7.5, built from source into ~/.local/bin because it is not
# packaged for Ubuntu. Absolute path on purpose: neither keybind children nor
# exec-once children get ~/.local/bin on PATH.
#
# Flags kept here rather than inline so the keybind and the top bar's launcher
# button cannot drift apart.
#
#   -c 7        columns
#   -is 56      icon size
#   -fm/-term   what the file search and terminal apps open with
#   -wm hyprland  launch apps via `hyprctl dispatch exec`, so they become
#                 children of Hyprland (session-18.scope) rather than of the
#                 drawer — they then survive the drawer closing.
#   -ovl        overlay layer, so it covers the top bar and the sidebar
#
# Escape closes it. Right-click an app to pin/unpin it in the drawer's own
# favourites row (that is ~/.cache/nwg-pin-cache — NOT the sidebar's
# ~/.cache/nwg-dock-pinned; the sidebar has its own right-click menu).
#
# Cold start measured at ~0.6s / 79MB, so it is not kept resident (-r).

# ── Category filters ───────────────────────────────────────────────────────
# Without this the grid shows only "All".
#
# nwg-drawer's dataDir() walks XDG_DATA_DIRS looking for the FIRST
# <dir>/nwg-drawer/desktop-directories; if none matches it returns "" and
# setUpCategories() then builds relative paths that never resolve, so the
# category list ends up empty. The session's XDG_DATA_DIRS is only
# /usr/local/share/:/usr/share/:/var/lib/snapd/desktop, and it does NOT
# consult XDG_DATA_HOME for this — so a plain ~/.local/share install is
# invisible to it. Upstream's answer is to copy the .directory files into
# /usr/local/share/nwg-drawer, which needs root on every new machine.
#
# Instead we point it at a user-owned dir. It MUST be a dedicated directory,
# not ~/.local/share itself: getAppDirs() appends ~/.local/share/applications
# unconditionally and then every XDG_DATA_DIRS entry + /applications, and it
# de-duplicates ONLY the flatpak paths — so adding ~/.local/share here would
# list that dir twice and double every app in the grid.
# nwg-data deliberately has no applications/ subdir, so pathExists() drops it.
export XDG_DATA_DIRS="$HOME/.local/share/nwg-data:${XDG_DATA_DIRS:-/usr/local/share/:/usr/share/}"

exec "$HOME/.local/bin/nwg-drawer" \
    -c 7 -is 56 \
    -fm nautilus \
    -term ghostty \
    -wm hyprland \
    -ovl
