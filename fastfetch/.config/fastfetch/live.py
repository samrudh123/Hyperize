#!/usr/bin/env python3
"""Keeps the zsh greeting live: writes a newline to stdout whenever something
the greeting shows may have changed, and zsh (fortunefetch in ~/.zshrc,
`zle -F` on this pipe) re-runs fastfetch and redraws it if the output differs.

Watches only what config.jsonc's modules show:
  brightness   inotify on /sys/class/backlight/*/brightness (logind writes it)
  battery      kernel uevents for power_supply (charge, AC plugged/unplugged)
  display      kernel uevents for drm (monitor plugged)
  sound        `pw-dump -m` (volume, mute, default output)
  wifi / ip    `ip monitor address link`
  media        `playerctl -F` (track, play/pause)
  the rest     every minute, on the minute (uptime, memory, date, …)

Only real changes count: brightness / battery / AC are compared with what
sysfs said last time (the battery sends uevents that change nothing), and of
pw-dump's stream only the output sinks, audio devices and the default-sink
metadata (other programs' pw-dump runs come and go as clients every few s).
Bursts (a held brightness key) are folded into one line per ~0.15 s. Exits as
soon as zsh closes the pipe (first command run), or if zsh is gone.
"""
import ctypes
import json
import os
import select
import signal
import socket
import subprocess
import sys
import time

CONFIG = os.path.expanduser("~/.config/fastfetch/config.jsonc")
QUIET, MAX_WAIT = 0.06, 0.15   # fire after 60 ms of quiet, or 150 ms into a burst

libc = ctypes.CDLL("libc.so.6", use_errno=True)


def die_with_me():
    libc.prctl(1, signal.SIGTERM)    # PR_SET_PDEATHSIG


def read(path):
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return ""


def sysfs_state():
    """What the brightness / battery / AC lines show, straight from sysfs."""
    out = []
    for base, files in (("/sys/class/backlight", ("brightness",)),
                        ("/sys/class/power_supply", ("capacity", "status", "online"))):
        try:
            names = sorted(os.listdir(base))
        except OSError:
            continue
        for n in names:
            out += [read(os.path.join(base, n, f)) for f in files]
    return out


class PwDump:
    """Splits `pw-dump -m` output into its JSON arrays; says whether one
    touched an output sink, an audio device or the default-sink metadata."""
    WANT = ("PipeWire:Interface:Device", "PipeWire:Interface:Metadata")

    def __init__(self):
        self.buf, self.types, self.primed = "", {}, False
        self.dec = json.JSONDecoder()

    def feed(self, text):
        self.buf += text
        hit = False
        while True:
            b = self.buf.lstrip()
            if not b:
                self.buf = ""
                break
            try:
                objs, end = self.dec.raw_decode(b)
            except ValueError:
                self.buf = b
                break                        # incomplete: wait for more
            self.buf = b[end:]
            for o in objs if isinstance(objs, list) else []:
                oid, t, info = o.get("id"), o.get("type"), o.get("info")
                if t:
                    props = (info or {}).get("props") or {}
                    if t.endswith("Node") and props.get("media.class") != "Audio/Sink":
                        t = "other"
                    self.types[oid] = t
                else:
                    t = self.types.pop(oid, "other")   # removed
                if t in self.WANT or t.endswith("Node"):
                    hit = True
            if not self.primed:              # the first array is the full dump
                self.primed, hit = True, False
        return hit


def modules():
    try:
        with open(CONFIG) as f:
            mods = json.load(f).get("modules", [])
        return {m["type"] if isinstance(m, dict) else m for m in mods}
    except (OSError, ValueError, KeyError, TypeError):
        return {"brightness", "battery", "sound", "wifi", "localip", "uptime"}


def main():
    shell = os.getppid()
    on = modules()
    poll = select.poll()
    poll.register(1, 0)              # POLLERR / POLLHUP: zsh closed the pipe
    sources = {}                     # fd -> (kind, object)
    children = []

    def add(fd, kind, obj=None):
        sources[fd] = (kind, obj)
        poll.register(fd, select.POLLIN)

    if "brightness" in on:
        ino = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
        if ino >= 0:
            base = "/sys/class/backlight"
            for d in os.listdir(base) if os.path.isdir(base) else []:
                libc.inotify_add_watch(ino, os.path.join(base, d, "brightness").encode(), 0x2)  # IN_MODIFY
            add(ino, "inotify")

    subsystems = set()
    if on & {"battery", "poweradapter"}:
        subsystems.add(b"power_supply")
    if "brightness" in on:
        subsystems.add(b"backlight")
    if on & {"display", "monitor"}:
        subsystems.add(b"drm")
    if subsystems:
        try:
            ue = socket.socket(socket.AF_NETLINK, socket.SOCK_DGRAM | socket.SOCK_NONBLOCK, 15)
            ue.bind((0, 1))          # kernel uevents
            add(ue.fileno(), "uevent", (ue, subsystems))
        except OSError:
            pass

    cmds = []
    if "sound" in on:
        cmds.append(("pw", ["pw-dump", "-m", "-N"]))
    if on & {"wifi", "localip"}:
        cmds.append(("cmd", ["ip", "monitor", "address", "link"]))
    if "media" in on:
        cmds.append(("cmd", ["playerctl", "-a", "-F", "metadata", "--format", "{{status}}{{title}}"]))
    for kind, argv in cmds:
        try:
            p = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                 stderr=subprocess.DEVNULL, preexec_fn=die_with_me)
        except OSError:
            continue
        children.append(p)
        os.set_blocking(p.stdout.fileno(), False)
        add(p.stdout.fileno(), kind, p)

    sysfs = sysfs_state()
    pw = PwDump()
    tick = bool(on & {"uptime", "datetime", "memory", "swap", "processes", "loadavg",
                      "battery", "wifi", "disk", "cpuusage"})
    first = last = None

    def cleanup(*_):
        for p in children:
            p.terminate()
        sys.exit(0)

    signal.signal(signal.SIGTERM, cleanup)
    signal.signal(signal.SIGHUP, cleanup)
    signal.signal(signal.SIGINT, signal.SIG_IGN)   # Ctrl+C at the prompt is zsh's

    while True:
        now = time.monotonic()
        waits = [5.0]                                # also: is zsh still there?
        if first is not None:
            waits.append(max(0.0, min(last + QUIET, first + MAX_WAIT) - now))
        if tick:
            waits.append(60 - time.time() % 60 + 0.05)
        events = poll.poll(min(waits) * 1000)
        now = time.monotonic()
        changed = False
        for fd, ev in events:
            if fd == 1:
                cleanup()
            kind, obj = sources.get(fd, (None, None))
            if ev & (select.POLLHUP | select.POLLERR) and not ev & select.POLLIN:
                poll.unregister(fd)
                sources.pop(fd, None)
                continue
            try:
                if kind == "uevent":
                    sock, subs = obj
                    while True:
                        try:
                            msg = sock.recv(8192)
                        except BlockingIOError:
                            break
                        if any(b"SUBSYSTEM=" + x + b"\0" in msg + b"\0" for x in subs):
                            if b"SUBSYSTEM=drm\0" in msg + b"\0":
                                changed = True
                            elif sysfs_state() != sysfs:
                                sysfs, changed = sysfs_state(), True
                else:
                    data = os.read(fd, 1 << 16)
                    while data:              # drain (pw-dump says a lot)
                        try:
                            more = os.read(fd, 1 << 16)
                        except BlockingIOError:
                            break
                        if not more:
                            break
                        data += more
                    if not data:             # child died: stop watching it
                        poll.unregister(fd)
                        sources.pop(fd, None)
                    elif kind == "pw":
                        changed |= pw.feed(data.decode("utf-8", "replace"))
                    elif kind == "inotify":
                        if sysfs_state() != sysfs:
                            sysfs, changed = sysfs_state(), True
                    else:
                        changed = True
            except BlockingIOError:
                pass
        if changed:
            if first is None:
                first = now
            last = now
        due = first is not None and (now - last >= QUIET or now - first >= MAX_WAIT)
        if tick and time.time() % 60 < 0.5 and not events:
            due = True
        if due:
            first = last = None
            try:
                os.write(1, b"\n")
            except OSError:
                cleanup()
        if os.getppid() != shell:
            cleanup()


if __name__ == "__main__":
    main()
