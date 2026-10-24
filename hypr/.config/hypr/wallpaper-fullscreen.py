#!/usr/bin/python3
"""Pause the animated wallpaper only while the CURRENT workspace is fullscreen
— and only when that fullscreen window is fully opaque. Fullscreen windows
follow the transparency settings (opacity-rules.conf's third value,
decoration:fullscreen_opacity), so a see-through one keeps the wallpaper
moving behind it.

mpvpaper's own `-a full` pauses whenever ANY window is fullscreen: the window
list it gets from the compositor (wlr-foreign-toplevel) carries no workspace,
so a fullscreen YouTube on workspace 3 froze the wallpaper on every other
workspace too. And `-p` alone never fires here: Hyprland keeps sending frame
callbacks to the background layer even under a fullscreen window (measured:
same CPU either way).

So this watches Hyprland's event socket and asks Hyprland directly whether the
active workspace has a fullscreen window, then pauses / resumes mpv over its
IPC socket (set-wallpaper.sh starts mpvpaper with input-ipc-server=MPV_SOCK).
mpvpaper records an outside pause as a *user* pause and never overrides it,
and the bottom-bar pause button uses SIGSTOP, so the three do not fight.

Still wallpapers (swaybg) have no socket; the send just fails quietly.
"""

import fcntl
import json
import os
import select
import socket
import sys
import time

# Events after which "is the active workspace fullscreen?" may have changed.
TRIGGERS = {
    "workspace", "workspacev2", "focusedmon", "focusedmonv2", "fullscreen",
    "openwindow", "closewindow", "movewindow", "movewindowv2",
    "activewindowv2", "changefloatingmode", "configreloaded",
}
DEBOUNCE = 0.08
# Re-assert the state now and then, so a wallpaper restarted while fullscreen
# (new mpv, default unpaused) gets paused within a few seconds — and so an
# opacity change on a fullscreen window (a tag; Hyprland sends no event) lands.
RESYNC = 3.0

DEBUG = os.environ.get("WALLPAPER_FS_DEBUG") == "1"
RUN = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
MPV_SOCK = f"{RUN}/mpvpaper.sock"


def log(*a):
    if DEBUG:
        print("[wallpaper-fullscreen]", *a, file=sys.stderr, flush=True)


def _base():
    sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    if not sig:
        sys.exit("HYPRLAND_INSTANCE_SIGNATURE not set — not running under Hyprland")
    return f"{RUN}/hypr/{sig}"


BASE = _base()


def request(text):
    """One command on Hyprland's control socket (no hyprctl, so no PATH needs)."""
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


def active_is_fullscreen():
    """True while the active workspace's fullscreen window hides the wallpaper
    completely, i.e. is fullscreen AND renders at opacity 1."""
    ws = json.loads(request("j/activeworkspace"))
    if not ws.get("hasfullscreen"):
        return False
    win = next((c for c in json.loads(request("j/clients"))
                if c.get("fullscreen") and c.get("workspace", {}).get("id") == ws.get("id")), None)
    if win is None:
        return True
    if win["fullscreen"] != 2:      # maximised: the wallpaper still shows around the bars
        return False
    w = f"address:{win['address']}"
    alpha = json.loads(request(f"j/getprop {w} opacity_fullscreen")).get("opacity_fullscreen", 1)
    if not json.loads(request(f"j/getprop {w} opacity_fullscreen_override")).get("opacity_fullscreen_override"):
        alpha *= json.loads(request("j/getoption decoration:fullscreen_opacity")).get("float", 1)
    return alpha >= 0.999


def set_pause(paused):
    msg = json.dumps({"command": ["set_property", "pause", paused]}) + "\n"
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.settimeout(0.5)
            s.connect(MPV_SOCK)
            s.sendall(msg.encode())
    except OSError as e:          # no animated wallpaper right now, or restarting
        log("mpv not reachable:", e)


def sync(last):
    try:
        fs = active_is_fullscreen()
    except (OSError, ValueError) as e:
        log("query failed:", e)
        return last
    if fs != last:
        log("fullscreen on active workspace:", fs)
    set_pause(fs)
    return fs


def main():
    # one instance: a second exec (a reload, a manual start) would double the
    # pause/resume traffic
    lock = open(f"{RUN}/wallpaper-fullscreen.lock", "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        print("wallpaper-fullscreen: already running", file=sys.stderr)
        return 1
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.connect(f"{BASE}/.socket2.sock")
    log("listening")

    state = sync(None)
    buf = b""
    pending = None
    next_resync = time.monotonic() + RESYNC
    while True:
        deadline = next_resync if pending is None else min(pending, next_resync)
        ready, _, _ = select.select([sock], [], [], max(0, deadline - time.monotonic()))

        if ready:
            data = sock.recv(8192)
            if not data:
                log("socket closed — Hyprland exited")
                return
            buf += data
            *lines, buf = buf.split(b"\n")
            for line in lines:
                if line.split(b">>", 1)[0].decode(errors="replace") in TRIGGERS:
                    pending = time.monotonic() + DEBOUNCE

        now = time.monotonic()
        if (pending is not None and now >= pending) or now >= next_resync:
            pending = None
            next_resync = now + RESYNC
            state = sync(state)


if __name__ == "__main__":
    sys.exit(main())
