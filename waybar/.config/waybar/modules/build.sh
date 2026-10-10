#!/bin/bash
# Build the bottom bar's now-playing plugin (nowplaying.c -> nowplaying.so).
# waybar loads it at start: restart the bottom bar after rebuilding
# (~/.config/hypr/bottom-bar.sh stop --no-dock; ~/.config/hypr/bottom-bar.sh start).
set -e
cd "$(dirname "$0")"
gcc -shared -fPIC -O2 -Wall -Wextra -o nowplaying.so.new nowplaying.c \
    $(pkg-config --cflags --libs gtk+-3.0) -lm
mv nowplaying.so.new nowplaying.so      # atomic: never a half-written .so
echo "built $(pwd)/nowplaying.so"
