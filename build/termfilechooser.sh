#!/usr/bin/env bash
# xdg-desktop-portal-termfilechooser — file open/save dialogs as yazi
# (~/.config/xdg-desktop-portal* in the repo route FileChooser to it).
# Installs into ~/.local: xdg-desktop-portal reads ~/.local/share/
# xdg-desktop-portal/portals and the session bus ~/.local/share/dbus-1/services.
source "$(dirname "$0")/common.sh"
checkout https://github.com/hunkyburrito/xdg-desktop-portal-termfilechooser.git \
    xdg-desktop-portal-termfilechooser "${TFC_REF:-v1.4.3}"
# inih: the system one (libinih-dev) if present, else a static copy from WrapDB
opts=()
if ! pkg-config --exists inih; then
    mkdir -p subprojects
    [ -f subprojects/inih.wrap ] || meson wrap install inih
    opts=(--force-fallback-for=inih -Dinih:default_library=static)
fi
meson setup build --prefix="$PREFIX" --buildtype=release "${opts[@]}" --wipe 2>/dev/null \
    || meson setup build --prefix="$PREFIX" --buildtype=release "${opts[@]}"
# only the portal itself: inih's own unit tests trip the parent's -Werror
ninja -C build xdg-desktop-portal-termfilechooser
meson install -C build --no-rebuild --skip-subprojects
