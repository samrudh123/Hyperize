#!/usr/bin/python3
"""Reconnect KDE Connect as soon as the network under Tailscale changes.

    exec-once from hyprland.conf. Logs what it does to
    ~/.local/state/kdec-netwatch.log.

KDE Connect reaches the phone over Tailscale (customDevices in
~/.config/kdeconnect/config = the phone's 100.x address). When the phone
moves between Wi-Fi and mobile data (or the laptop changes networks),
Tailscale finds a new path within seconds (seen in its log: relayed via
DERP, then direct, 6 s) — but KDE Connect's TCP link lags behind:
whatever it sent while the path was down is retried on TCP's growing
back-off, and a link that really died is only noticed by keepalive after
~2 h, so it ends up waiting for the PHONE to redial, which Android does
late. Measured: `kdeconnect-cli --refresh` (the laptop announcing itself to
its custom devices) brings the phone back on a fresh link in about 1 s.

So this watches the path and refreshes when it changes:

  * every POLL s: this laptop's default route (it changed networks) and
    whether Tailscale sees the phone online — cheap, local only;
  * every PROBE s: `tailscale ping -c 1` to the phone — one tiny packet —
    for the path actually in use ("via 152.57.92.161:35935" or via a DERP
    relay). The phone changing networks shows up here. Tailscale's own
    CurAddr can't be used: it goes blank whenever the link sits idle.

On a change it waits SETTLE s for Tailscale to finish switching (relay ->
direct), probes again, and refreshes once (at most every COOLDOWN s). Also,
while the phone is online in Tailscale but KDE Connect can't reach it, it
refreshes every RETRY s (phone rebooted, KDE Connect restarted on either
side). And while a phone player is Playing it asks the phone for its player
list every LIST_REFRESH s, because the phone never reports a CLOSED player
by itself (see refresh_player_lists), and re-asks the selected player for
its position, because a seek made ON the phone isn't pushed either (see
resync_position). Stdlib only.

LINK QUALITY (kdec_link.py): a thread pings the phone every LINK_EVERY s
and publishes ok / bad. KDE Connect keeps saying "reachable" over a link
that loses half its packets with 1-2 s round trips (phone on mobile data,
measured) — its view of the phone's players freezes, so spotify-remote.py
switches to Spotify's Web API while the link is bad. When the link comes
back after a real outage: a fresh connection (--refresh) and fresh player
lists / positions at once, instead of waiting for the next timer.
"""

import collections
import configparser
import fcntl
import os
import re
import subprocess
import sys
import threading
import time

import kdec_link   # same directory: the verdict this writes

POLL = 3
LIST_REFRESH = 5    # s between "send me your player list" while a phone player plays
LIST_REFRESH_IDLE = 15   # ...while phone players exist but none plays (a paused app can be closed too)
PROBE = 15
LINK_EVERY = 2      # s between link-quality pings (one ICMP packet over Tailscale)
LINK_WINDOW = 5     # judge on the last this-many pings
LINK_BAD_LOST = 2   # ...this many lost -> bad
LINK_SLOW_MS = 800  # ...or this many slow ones (LINK_BAD_SLOW) -> bad
LINK_BAD_SLOW = 3
LINK_GOOD_MS = 500  # bad -> ok again after LINK_GOOD_RUN pings in a row under this
LINK_GOOD_RUN = 3
SETTLE = 4
COOLDOWN = 15
RETRY = 20
KDEC_CONFIG = os.path.expanduser("~/.config/kdeconnect/config")
STATE = os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state"))
LOG = os.path.join(STATE, "kdec-netwatch.log")


def log(msg):
    try:
        if os.path.exists(LOG) and os.path.getsize(LOG) > 100_000:
            os.replace(LOG, LOG + ".old")
        with open(LOG, "a") as f:
            f.write(f"{time.strftime('%F %T')}  {msg}\n")
    except OSError:
        pass


def run(*cmd, timeout=10):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout).stdout
    except (OSError, subprocess.TimeoutExpired):
        return ""


def custom_devices():
    cp = configparser.ConfigParser(interpolation=None)
    try:
        cp.read(KDEC_CONFIG)
        raw = cp.get("General", "customDevices", fallback="")
    except configparser.Error:
        return []
    return sorted(a.strip() for a in raw.split(",") if a.strip())


def local_route():
    """This laptop's own way out: (device, source IP) of the default route."""
    w = run("ip", "route", "get", "1.1.1.1").split()
    pick = lambda k: w[w.index(k) + 1] if k in w[:-1] else ""
    return pick("dev"), pick("src")


def online(addr):
    """Tailscale's view: is the peer with this 100.x address online?"""
    for line in run("tailscale", "status").splitlines():
        f = line.split()
        if f and f[0] == addr:
            return "offline" not in line
    return False


def path(addr):
    """The path a disco ping takes right now: "152.57.92.161:35935",
    "DERP(blr)", or "" when there is no answer."""
    out = run("tailscale", "ping", "-c", "1", "--timeout", "3s", addr, timeout=6)
    m = re.search(r"\bvia (\S+)", out)
    return m.group(1) if m else ""


def refresh_player_lists(force=False):
    """Ask every connected phone for its current player list: every
    LIST_REFRESH s while one of its players claims to be Playing (the phone
    is busy then anyway), every LIST_REFRESH_IDLE s while its players are
    only paused, never when it has none. KDE Connect on Android pushes a
    player's CHANGES at once, but not that a player has GONE: closing Spotify
    left it "Playing" on the laptop until something asked (measured: it
    vanished the moment requestPlayerList was sent)."""
    phone = [p for p in run("playerctl", "-l").split() if p.startswith("kdeconnect.")]
    if not phone:
        return False
    playing = any(run("playerctl", "-p", p, "status").strip() == "Playing" for p in phone)
    if not playing and not force and \
            time.monotonic() - refresh_player_lists.idle_at < LIST_REFRESH_IDLE:
        return playing
    if not playing:
        refresh_player_lists.idle_at = time.monotonic()
    for dev in run("kdeconnect-cli", "-a", "--id-only").split():
        run("busctl", "--user", "call", "org.kde.kdeconnect",
            f"/modules/kdeconnect/devices/{dev}/mprisremote",
            "org.kde.kdeconnect.device.mprisremote", "requestPlayerList")
        resync_position(dev)
    return playing


def resync_position(dev):
    """Ask the phone again for the position of KDE Connect's selected player
    (the one now-playing.py shows, see its kdec_focus). Between updates the
    laptop extrapolates the position from the last one it got, and a seek
    made on the phone sends none: AnimeKai's "skip intro" in phone Firefox
    left the bar 88 s behind for the rest of the episode (measured; a fresh
    request fixed it at once). The only request for one player's status that
    the plugin offers is a CHANGE of its `player` property, so step to ""
    (the phone answers nothing for it) and back."""
    path = f"/modules/kdeconnect/devices/{dev}/mprisremote"
    iface = "org.kde.kdeconnect.device.mprisremote"
    m = re.search(r'"(.+)"', run("busctl", "--user", "get-property", "org.kde.kdeconnect",
                                 path, iface, "player"))
    if not m:
        return
    for name in ("", m.group(1)):
        run("busctl", "--user", "set-property", "org.kde.kdeconnect", path, iface,
            "player", "s", name)


refresh_player_lists.idle_at = 0.0


def ping_ms(addr):
    """One ICMP round trip in ms, or None when lost (2 s)."""
    m = re.search(r"time=([\d.]+) ms", run("ping", "-n", "-c", "1", "-W", "2", addr, timeout=4))
    return float(m.group(1)) if m else None


def link_watch():
    """Thread: ping the phone, publish ok / bad (kdec_link.py), and on a
    recovery bring KDE Connect up to date at once."""
    window = collections.deque(maxlen=LINK_WINDOW)
    ok, bad_since = True, 0.0
    while True:
        addrs = custom_devices()
        if not addrs:
            time.sleep(LINK_EVERY * 5)
            continue
        t = time.monotonic()
        rtt = ping_ms(addrs[0])
        window.append(rtt)
        lost = sum(r is None for r in window)
        slow = sum(r is not None and r > LINK_SLOW_MS for r in window)
        recent = list(window)[-LINK_GOOD_RUN:]
        if ok and (lost >= LINK_BAD_LOST or slow >= LINK_BAD_SLOW):
            ok, bad_since = False, time.monotonic()
            log(f"link BAD ({lost} lost, {slow} slow of last {len(window)}) "
                "-> Spotify via Web API")
        elif not ok and len(recent) == LINK_GOOD_RUN and \
                all(r is not None and r < LINK_GOOD_MS for r in recent):
            ok = True
            outage = time.monotonic() - bad_since
            log(f"link ok again after {outage:.0f} s")
            if outage > 10:
                refresh("link recovered")           # a fresh TCP link, not the backed-off one
            refresh_player_lists(force=True)
        kdec_link.write({"ok": ok, "rtt_ms": rtt, "lost": lost, "slow": slow,
                         "of": len(window), "at": time.time()})
        time.sleep(max(0.0, LINK_EVERY - (time.monotonic() - t)))


def reachable():
    return bool(run("kdeconnect-cli", "-a", "--id-only").strip())


def refresh(why):
    run("kdeconnect-cli", "--refresh")
    time.sleep(1.5)
    log(f"refresh ({why}) -> {'reachable' if reachable() else 'not reachable yet'}")


def main():
    lock = open(os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "kdec-netwatch.lock"), "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        print("kdec-netwatch: already running", file=sys.stderr)
        return 1
    log("started")
    threading.Thread(target=link_watch, daemon=True).start()

    route = local_route()
    paths = {}                      # addr -> last path seen
    last_probe = last_refresh = last_retry = last_list = 0.0
    while True:
        addrs = custom_devices()
        now = time.monotonic()
        changed = []

        r = local_route()
        if r != route:
            changed.append(f"laptop network {route[1] or '-'} -> {r[1] or '-'}")
            route = r

        up = {a: online(a) for a in addrs}
        if now - last_probe >= PROBE:
            last_probe = now
            for a in addrs:
                if not up[a]:
                    continue
                p = path(a)
                if p and a in paths and p != paths[a]:
                    changed.append(f"{a} path {paths[a]} -> {p}")
                if p:
                    paths[a] = p

        if changed and now - last_refresh >= COOLDOWN:
            time.sleep(SETTLE)                      # let Tailscale settle (relay -> direct)
            for a in addrs:
                p = path(a) if up.get(a) else ""
                if p:
                    paths[a] = p
            refresh("; ".join(changed))
            last_refresh = last_retry = time.monotonic()
        elif any(up.values()) and now - last_retry >= RETRY and not reachable():
            refresh("phone online in Tailscale, KDE Connect not connected")
            last_retry = time.monotonic()

        if time.monotonic() - last_list >= LIST_REFRESH:
            last_list = time.monotonic()
            refresh_player_lists()

        time.sleep(POLL)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(0)
