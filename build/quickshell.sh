#!/usr/bin/env bash
# Quickshell — the bars, dock and pickers (~/.config/quickshell).
# Uses private Qt API: rebuild after every Qt update or it crashes.
source "$(dirname "$0")/common.sh"
checkout https://git.outfoxxed.me/quickshell/quickshell.git quickshell "${QUICKSHELL_REF:-v0.3.2}"
cmake -GNinja -B build -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_INSTALL_PREFIX="$PREFIX" -DCRASH_HANDLER=OFF
cmake --build build
cmake --install build
ln -sf quickshell "$PREFIX/bin/qs"
echo "quickshell -> $PREFIX/bin/qs"
