#!/usr/bin/python3
"""Native messaging host for the Rice Accent Firefox extension.

Sends {"palette": {...}, "accent": "#rrggbb"} — the desktop theme's colours
(~/.config/hypr/theme/palette.json, set-theme.sh) and accent (theme/accent,
set-accent.sh) — once at start and again whenever either file changes.
Firefox starts it when the extension loads and closes stdin on shutdown.
"""
import json
import os
import struct
import sys
import threading
import time

THEME = os.path.expanduser("~/.config/hypr/theme")
FILES = [os.path.join(THEME, "palette.json"), os.path.join(THEME, "accent")]


def send(obj):
    data = json.dumps(obj).encode()
    sys.stdout.buffer.write(struct.pack("@I", len(data)) + data)
    sys.stdout.buffer.flush()


def read_state():
    try:
        with open(FILES[0]) as f:
            palette = json.load(f)
        with open(FILES[1]) as f:
            accent = "#" + f.read().strip().lstrip("#").lower()
        int(accent[1:], 16)
    except (OSError, ValueError):
        return None
    if len(accent) != 7 or "base" not in palette:
        return None
    return {"palette": palette, "accent": accent}


def stamp():
    out = []
    for p in FILES:
        try:
            st = os.stat(p)
            out.append((st.st_mtime_ns, st.st_size, st.st_ino))
        except OSError:
            out.append(None)
    return out


def watch_stdin():
    # Firefox closes our stdin when the extension (or Firefox) goes away
    while sys.stdin.buffer.read(4096):
        pass
    os._exit(0)


def main():
    threading.Thread(target=watch_stdin, daemon=True).start()
    last, sent = None, None
    while True:
        now = stamp()
        if now != last:
            last = now
            # set-theme.sh moves palette.json in, then set-accent.sh writes
            # the accent a moment later; let a burst of writes settle
            time.sleep(0.15)
            last = stamp()
            state = read_state()
            if state and state != sent:
                send(state)
                sent = state
        time.sleep(0.3)


if __name__ == "__main__":
    main()
