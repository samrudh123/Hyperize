#!/usr/bin/env python3
"""Is the KDE Connect link to the phone usable right now?

    kdec_link.py            print the last probe (JSON)

kdec-netwatch.py pings the phone's Tailscale address (KDE Connect's
customDevices) every couple of seconds and writes the verdict to STATE.
Measured 2026-10-26, phone on mobile data, laptop on Wi-Fi: 0.9-2.4 s
round trips with 27-50 % loss, then minutes of nothing at all — while
KDE Connect still said "reachable". Over such a link KDE Connect's copy of
the phone's players is frozen (the bar was 80 s behind on position, a pause
sent through it never arrived), but Spotify's Web API, which goes through
Spotify's servers, stays current. So while the link is bad:

  * spotify-remote.py's bridge doesn't step aside for KDE Connect's copy of
    the phone's Spotify (it shows the Web API's view, and now-playing.py
    hides the copy as superseded), doesn't send commands through it, and
    doesn't take its "Spotify is closed" or its pushes as the truth;
  * resume ("Last played") goes through Spotify Connect, not KDE Connect.

healthy() is True when nothing is known (no watcher running, old file): the
old behaviour, trust KDE Connect.
"""

import json
import os
import sys
import time

STATE = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "kdec-link.json")
STALE = 20          # s: an older verdict means the watcher isn't running


def state():
    try:
        with open(STATE) as f:
            d = json.load(f)
    except (OSError, ValueError):
        return None
    return d if time.time() - d.get("at", 0) < STALE else None


def healthy():
    d = state()
    return True if d is None else bool(d.get("ok", True))


def write(d):
    tmp = STATE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(d, f)
    os.replace(tmp, STATE)


if __name__ == "__main__":
    print(json.dumps(state()))
    sys.exit(0 if healthy() else 1)
