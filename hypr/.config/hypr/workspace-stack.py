#!/usr/bin/python3
"""
Stack/compact workspaces — mobile-home-screen behaviour.

Workspaces hold no gaps. The moment a workspace empties, everything above it
slides down one, so the occupied workspaces are always 1..N with nothing
missing in between. Close the last window on 2 and what was on 3 becomes 2,
what was 4 becomes 3, and the top workspace disappears.

Why a daemon: Hyprland has no native compaction. It destroys empty workspaces
but never renumbers the survivors, so you end up with holes (1, 3, 7). This
listens on Hyprland's event socket and renumbers by moving windows.

Run with --once to compact a single time and exit (handy for a keybind or for
testing); with no arguments it runs as the daemon.

Set HYPR_STACK_DEBUG=1 to log every decision to stderr.


RESERVE_ACTIVE (below) is the one knob worth knowing about.

  True  (default) the workspace you are standing on never gets compacted away,
        even while it is empty. Switch to an empty workspace to launch
        something and it stays yours; the gap closes once you leave it.
  False strict compaction. Standing on an empty workspace means the next
        occupied one is pulled down on top of you, which makes "go to an
        empty workspace and open an app" impossible.

Either way the behaviour you asked for holds: an empty workspace you are NOT
looking at is always closed up.
"""

import json
import os
import select
import socket
import sys
import time

RESERVE_ACTIVE = True

# Events that can change which workspaces are occupied. Anything else (mouse
# focus, window titles, layer surfaces) is ignored so we are not recomputing
# on every pointer move.
TRIGGERS = {
    "openwindow",
    "closewindow",
    "movewindow",
    "movewindowv2",
    "workspace",
    "workspacev2",
    "createworkspace",
    "createworkspacev2",
    "destroyworkspace",
    "destroyworkspacev2",
    "moveworkspace",
    "moveworkspacev2",
    "pin",
}

# Coalesce bursts. Closing a window emits closewindow + destroyworkspace +
# workspace in quick succession; without this we would compact three times.
DEBOUNCE = 0.06

DEBUG = os.environ.get("HYPR_STACK_DEBUG") == "1"


def log(*a):
    if DEBUG:
        print("[workspace-stack]", *a, file=sys.stderr, flush=True)


def _base():
    sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    if not sig:
        sys.exit("HYPRLAND_INSTANCE_SIGNATURE not set — not running under Hyprland")
    run = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
    return f"{run}/hypr/{sig}"


BASE = _base()


def request(text):
    """Send one command on Hyprland's control socket and return the reply.

    Talking to the socket directly rather than shelling out to hyprctl keeps
    this off PATH entirely — exec-once children do not get ~/.local/bin, and
    a compaction can issue a dozen commands at once.
    """
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.connect(f"{BASE}/.socket.sock")
        s.sendall(text.encode())
        chunks = []
        while True:
            chunk = s.recv(65536)
            if not chunk:
                break
            chunks.append(chunk)
    return b"".join(chunks).decode(errors="replace")


def query(what):
    return json.loads(request("j/" + what))


def plan():
    """Work out the renumbering. Returns (moves, target_workspace) or None."""

    # Multi-monitor is deliberately out of scope: workspace ids are global but
    # each belongs to a monitor, so compacting would drag windows across
    # screens. This laptop is single-display; bail rather than surprise.
    monitors = query("monitors")
    if len(monitors) != 1:
        log("skipping — %d monitors" % len(monitors))
        return None

    # Normal workspaces only. Special workspaces (the SUPER+S scratchpad) use
    # negative ids and must never be renumbered.
    clients = [
        c
        for c in query("clients")
        if c["workspace"]["id"] >= 1 and not c.get("pinned")
    ]

    counts = {}
    for c in clients:
        counts[c["workspace"]["id"]] = counts.get(c["workspace"]["id"], 0) + 1

    active = query("activeworkspace")["id"]

    occupied = set(counts)
    if RESERVE_ACTIVE and active >= 1:
        occupied.add(active)

    # The whole algorithm: occupied workspaces, in order, become 1..N.
    mapping = {old: new for new, old in enumerate(sorted(occupied), start=1)}

    moves = [
        (c["address"], mapping[c["workspace"]["id"]])
        for c in clients
        if mapping[c["workspace"]["id"]] != c["workspace"]["id"]
    ]
    if not moves:
        return None

    return moves, mapping.get(active)


def compact():
    p = plan()
    if p is None:
        return False
    moves, target = p

    # movetoworkspacesilent leaves focus alone, so the windows shuffle without
    # the view jumping around; we choose where to land ourselves, afterwards.
    cmds = [f"dispatch movetoworkspacesilent {ws},address:{addr}" for addr, ws in moves]

    # Follow the windows down. Without this, closing the last window on 2 while
    # sitting on 3 leaves you staring at an empty workspace whose contents just
    # moved one place left.
    if target is not None:
        cmds.append(f"dispatch workspace {target}")

    log("compacting:", cmds)
    reply = request("[[BATCH]]" + " ; ".join(cmds))
    if "ok" not in reply:
        log("unexpected reply:", reply.strip()[:200])
    return True


def main():
    if "--once" in sys.argv[1:]:
        compact()
        return

    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.connect(f"{BASE}/.socket2.sock")
    log("listening")

    # Compact once at startup so a reload of this script tidies up whatever
    # state the session is already in.
    compact()

    buf = b""
    pending = None
    while True:
        timeout = None if pending is None else max(0, pending - time.monotonic())
        ready, _, _ = select.select([sock], [], [], timeout)

        if ready:
            data = sock.recv(8192)
            if not data:
                log("socket closed — Hyprland exited")
                return
            buf += data
            *lines, buf = buf.split(b"\n")
            for line in lines:
                name = line.split(b">>", 1)[0].decode(errors="replace")
                if name in TRIGGERS:
                    pending = time.monotonic() + DEBOUNCE

        if pending is not None and time.monotonic() >= pending:
            pending = None
            try:
                compact()
            except (OSError, ValueError) as e:
                # A window can vanish between the query and the dispatch; that
                # is normal, and the next event will put things right.
                log("compact failed:", e)


if __name__ == "__main__":
    main()
