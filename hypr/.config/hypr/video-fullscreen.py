#!/usr/bin/python3
"""A VIDEO in fullscreen gets a fully opaque window; plain fullscreen doesn't.

Fullscreen windows keep their transparency (opacity-rules.conf's third value,
decoration:fullscreen_opacity). Only while a video itself is fullscreen — the
player's fullscreen button — is its window tagged "vidfs", and hyprland.conf's
`video-fullscreen-opaque` rule makes a fullscreen vidfs window opaque. F11 and
SUPER+F never tag, so they stay see-through. Hyprland can't tell the two
apart (both are the same fullscreen request); the app has to say which.

    video-fullscreen.py ytm         exec-once: YouTube Music (th-ch). Its MPRIS
                                    Fullscreen property is the player's own
                                    fullscreen button (ytmusic-player-bar
                                    [player-fullscreened]), not F11.
    (native messaging host)         Firefox / Brave: the "Video fullscreen"
                                    extension (~/.config/video-fullscreen) sends
                                    {"fullscreen": true|false} per change.
    video-fullscreen.py tag PID     tag PID's fullscreen window by hand (testing)
    video-fullscreen.py untag PID

Once a window is tagged, a detached follower watches Hyprland's events and
drops the tag the moment that window leaves fullscreen or closes, so a missed
"false" can never leave a stale tag that makes the next F11 opaque.
"""

import json
import os
import socket
import struct
import sys
import time

TAG = "vidfs"
RUN = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
YTM_BUS = "org.mpris.MediaPlayer2.YoutubeMusic"


def _base():
    sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    if not sig:                         # a browser started outside Hyprland's env
        socks = sorted((d for d in os.listdir(f"{RUN}/hypr") if os.path.exists(f"{RUN}/hypr/{d}/.socket.sock")),
                       key=lambda d: os.path.getmtime(f"{RUN}/hypr/{d}"))
        if not socks:
            sys.exit("no Hyprland instance")
        sig = socks[-1]
    return f"{RUN}/hypr/{sig}"


BASE = _base()


def request(text):
    """One command on Hyprland's control socket (no hyprctl, so no PATH needs)."""
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.connect(f"{BASE}/.socket.sock")
        s.sendall(text.encode())
        chunks = []
        while chunk := s.recv(65536):
            chunks.append(chunk)
    return b"".join(chunks).decode(errors="replace")


DEBUG_FLAG = f"{RUN}/video-fullscreen.debug"     # touch it to log to video-fullscreen.log


def dlog(*a):
    if os.path.exists(DEBUG_FLAG):
        with open(f"{RUN}/video-fullscreen.log", "a") as f:
            f.write(f"{time.strftime('%T')}.{int(time.time() * 1000) % 1000:03d} [{os.getpid()}] "
                    + " ".join(map(str, a)) + "\n")


def clients():
    return json.loads(request("j/clients"))


def ancestors(pid):
    """pid and its parents — the browser that started this native host owns
    the window, whichever helper process sits in between."""
    out = []
    while pid > 1:
        out.append(pid)
        try:
            with open(f"/proc/{pid}/stat") as f:
                pid = int(f.read().rsplit(")", 1)[1].split()[1])
        except (OSError, ValueError, IndexError):
            break
    return out


def fullscreen_window(pids, wait=2.0):
    """Address of the (most recently focused) fullscreen window owned by one of
    `pids`. The fullscreen request races the page's event, so wait a little."""
    end = time.monotonic() + wait
    while True:
        wins = [c for c in clients() if c.get("pid") in pids and c.get("fullscreen") == 2]
        if wins:
            return min(wins, key=lambda c: c.get("focusHistoryID", 99))["address"]
        if time.monotonic() >= end:
            return None
        time.sleep(0.1)


def untag(pids):
    batch = [f"dispatch tagwindow -{TAG} address:{c['address']}"
             for c in clients() if c.get("pid") in pids and TAG in c.get("tags", [])]
    if batch:
        request("[[BATCH]]" + ";".join(batch))
    return bool(batch)


def follow(addr):
    """Detached: drop the tag once `addr` is no longer fullscreen (or gone)."""
    if pid := os.fork():
        os.waitpid(pid, 0)              # the middle child exits at once
        return
    os.setsid()
    if os.fork():
        os._exit(0)
    devnull = os.open(os.devnull, os.O_RDWR)
    for fd in (0, 1, 2):
        os.dup2(devnull, fd)
    try:
        ev = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        ev.connect(f"{BASE}/.socket2.sock")
        ev.settimeout(5)                # re-check now and then regardless
        while True:
            try:
                ev.recv(65536) or os._exit(0)
            except socket.timeout:
                pass
            win = next((c for c in clients() if c["address"] == addr), None)
            if win is None or TAG not in win.get("tags", []):
                dlog("follower: window gone or untagged — exit")
                os._exit(0)             # closed, or untagged by a "false"
            if win.get("fullscreen") != 2:
                dlog("follower: left fullscreen", win.get("fullscreen"), win.get("fullscreenClient"), "— untag")
                request(f"dispatch tagwindow -{TAG} address:{addr}")
                os._exit(0)
    finally:
        os._exit(0)


def tag(pids):
    addr = fullscreen_window(pids)
    if not addr:
        return False
    win = next((c for c in clients() if c["address"] == addr), {})
    dlog("tag", addr, win.get("class"), "fs", win.get("fullscreen"), win.get("fullscreenClient"), win.get("tags"))
    if TAG not in win.get("tags", []):
        request(f"dispatch tagwindow +{TAG} address:{addr}")
    follow(addr)
    return True


# ── native messaging host (Firefox / Brave) ─────────────────────────────────

def host():
    raw = sys.stdin.buffer.read(4)
    if len(raw) < 4:
        return
    msg = json.loads(sys.stdin.buffer.read(struct.unpack("@I", raw)[0]))
    pids = ancestors(os.getppid())
    dlog("host", msg, "pids", pids[:4])
    ok = tag(pids) if msg.get("fullscreen") else untag(pids)
    dlog("host done", ok)
    if log := os.environ.get("VIDEO_FS_LOG"):          # for testing
        with open(log, "a") as f:
            f.write(json.dumps({"msg": msg, "argv": sys.argv[1:], "ok": ok}) + "\n")
    data = json.dumps({"ok": ok}).encode()
    sys.stdout.buffer.write(struct.pack("@I", len(data)) + data)
    sys.stdout.buffer.flush()


# ── YouTube Music (th-ch) over MPRIS ────────────────────────────────────────

def ytm():
    from gi.repository import Gio, GLib

    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)

    def owner_pid():
        try:
            return bus.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
                                 "GetConnectionUnixProcessID", GLib.Variant("(s)", (YTM_BUS,)),
                                 None, Gio.DBusCallFlags.NONE, 1000, None).unpack()[0]
        except GLib.Error:
            return None

    def changed(_c, _sender, _path, _iface, _sig, params):
        iface, props, _ = params.unpack()
        if iface != "org.mpris.MediaPlayer2" or "Fullscreen" not in props:
            return
        pid = owner_pid()
        if pid:
            (tag if props["Fullscreen"] else untag)(ancestors(pid))

    bus.signal_subscribe(YTM_BUS, "org.freedesktop.DBus.Properties", "PropertiesChanged",
                         "/org/mpris/MediaPlayer2", None, Gio.DBusSignalFlags.NONE, changed)
    GLib.MainLoop().run()


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "ytm":
        import fcntl
        lock = open(f"{RUN}/video-fullscreen-ytm.lock", "w")
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            sys.exit("video-fullscreen ytm: already running")
        ytm()
    elif cmd in ("tag", "untag") and len(sys.argv) > 2:
        pids = [int(sys.argv[2])]
        print((tag if cmd == "tag" else untag)(pids))
    else:                               # started by a browser: argv = manifest/origin, ext id
        host()


if __name__ == "__main__":
    main()
