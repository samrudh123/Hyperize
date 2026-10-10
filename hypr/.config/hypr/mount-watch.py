#!/usr/bin/python3
"""Re-generate the dock's place entries whenever a volume is mounted or removed.

THE BUG THIS FIXES
`dock-places.sh` runs once, from exec-once, at login. It can only see volumes
that are mounted *at that moment*. The Windows partition here is BitLocker, so
it is locked at login and only mounts after you unlock it in Files — i.e.
always after the script has already run. Nothing re-ran it, so the disk icon
could effectively never appear on its own.

Watching /proc/self/mounts is event-driven, not polling: the kernel marks it
POLLPRI when the mount table changes, so poll() blocks at zero cost until
something actually mounts or unmounts.

After regenerating, nothing else is needed — the patched dock watches
~/.cache/nwg-dock-pinned with fsnotify and rebuilds itself, so the icon appears
without a restart.

Set HYPR_MOUNT_DEBUG=1 to trace.
"""

import os
import select
import subprocess
import sys
import time

HOME = os.path.expanduser("~")
PLACES = os.path.join(HOME, ".config/hypr/dock-places.sh")
ICONS = os.path.join(HOME, ".config/hypr/dock-icons.sh")

# Only these prefixes produce dock entries; ignore the constant churn of
# /proc, /sys, snap loopbacks and so on.
WATCHED_PREFIXES = (
    f"/run/media/{os.environ.get('USER', 'user')}/",
    f"/media/{os.environ.get('USER', 'user')}/",
    "/mnt/",
)

DEBOUNCE = 1.0   # mounting settles over a few table rewrites
DEBUG = os.environ.get("HYPR_MOUNT_DEBUG") == "1"


def log(*a):
    if DEBUG:
        print("[mount-watch]", *a, file=sys.stderr, flush=True)


def user_mounts():
    """The set of mount points that would become dock entries."""
    out = subprocess.run(["findmnt", "-rno", "TARGET"],
                         capture_output=True, text=True).stdout.split("\n")
    return {m for m in out if m.startswith(WATCHED_PREFIXES)}


def regenerate():
    for script in (PLACES, ICONS):
        try:
            r = subprocess.run(["bash", script], capture_output=True, text=True,
                               timeout=30)
            log(os.path.basename(script), "->", r.stdout.strip() or r.returncode)
        except (OSError, subprocess.SubprocessError) as e:
            log("failed:", script, e)


def main():
    known = user_mounts()
    log("watching; current:", known or "none")

    with open("/proc/self/mounts") as fh:
        poller = select.poll()
        # POLLPRI is how the kernel signals a change to the mount table.
        poller.register(fh, select.POLLPRI | select.POLLERR)
        while True:
            poller.poll()
            fh.seek(0)
            fh.read()          # must re-read, or poll() returns immediately forever

            time.sleep(DEBOUNCE)
            now = user_mounts()
            if now == known:
                continue
            log("changed:", known, "->", now)
            known = now
            regenerate()


if __name__ == "__main__":
    main()
