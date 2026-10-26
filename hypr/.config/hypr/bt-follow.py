#!/usr/bin/env python3
"""Bluetooth headphones follow whichever device is playing: laptop or phone.

    bt-follow.py              the watcher (exec-once in hyprland.conf)
    bt-follow.py --dry-run    the watcher, only logging what it would do
    bt-follow.py status       what it sees right now
    bt-follow.py off | on     stop / resume switching (kept across restarts)

Log: ~/.local/state/bt-follow/log.

Multipoint headphones stay connected to the laptop AND the
phone, but play only one of them — whichever had them last — and don't
hand over by themselves: the phone could play Spotify while the headphones
sat silently on an idle laptop. Worse, when the phone paused they moved to
the laptop and sent it AVRCP "Play", which mpris-proxy passed back to the
phone (that's why mpris-proxy is masked). So this decides for them:

  * RELEASE, to the phone: a phone player is Playing (KDE Connect's
    kdeconnect.mpris_*, or spotify-remote.py's Spotify bridge), the laptop
    has played nothing for QUIET s, and a Bluetooth audio device is
    connected here -> disconnect it from the laptop; the headphones then
    take the phone's audio. Not while the KDE Connect link is bad
    (kdec_link.py): the phone's state may be stale then.
  * RECLAIM, for the laptop: an app here plays (a PipeWire output stream
    running for SUSTAIN s; notification / event sounds don't count) and a
    device THIS released is not connected -> mute the laptop's speakers,
    connect it, unmute once its sink is the default (or after MUTE_MAX s),
    so the sound doesn't come out of the speakers meanwhile. The laptop
    playing later than the phone wins: that's someone at the laptop.
  * Only devices released here are reconnected: one you disconnected
    yourself stays disconnected. A device that won't connect (off, out of
    range) is given up after GIVE_UP failed tries.
  * COOLDOWN s between actions, so the two rules can't ping-pong.

Event-driven on the laptop side (`pw-dump -m` wakes it when a PipeWire
node changes), polled every POLL s for the phone and Bluetooth. Stdlib only.
"""

import json
import os
import queue
import subprocess
import sys
import threading
import time

import kdec_link   # same directory: is the KDE Connect link usable?

POLL = 2.0          # s: phone / Bluetooth re-check when nothing wakes us
QUIET = 5.0         # s the laptop must have been silent before releasing
SUSTAIN = 0.8       # s a laptop stream must run before reclaiming
COOLDOWN = 10.0     # s between actions
MUTE_MAX = 10.0     # s the speakers stay muted waiting for the headphones
GIVE_UP = 2         # failed reconnects before forgetting a released device
FLAP_COUNT = 3      # this many releases within FLAP_WINDOW s (the headphones
FLAP_WINDOW = 120   # keep coming back by themselves) ->
FLAP_PAUSE = 600    # leave them alone this long
A2DP_SINK = "0000110b-0000-1000-8000-00805f9b34fb"
SKIP_ROLES = {"notification", "event", "alert", "accessibility"}
SKIP_APPS = ("speech-dispatcher",)

STATE_DIR = os.path.join(os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")),
                         "bt-follow")
LOG = os.path.join(STATE_DIR, "log")
OFF = os.path.join(STATE_DIR, "off")
RELEASED = os.path.join(STATE_DIR, "released.json")   # MAC -> failed reconnects


def run(*cmd, timeout=15):
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return r.returncode, r.stdout
    except (OSError, subprocess.TimeoutExpired):
        return 1, ""


def log(msg):
    os.makedirs(STATE_DIR, exist_ok=True)
    if os.path.exists(LOG) and os.path.getsize(LOG) > 100_000:
        os.replace(LOG, LOG + ".old")
    with open(LOG, "a") as f:
        f.write(f"{time.strftime('%F %T')}  {msg}\n")


def notify(body):
    run("notify-send", "-a", "Bluetooth", "-t", "3000", "-h", "string:x-canonical-private-synchronous:bt-follow",
        "Headphones", body)


# ── what's going on ──────────────────────────────────────────────────────────
def laptop_streams():
    """Node ids of PipeWire output streams that are playing (running) here."""
    rc, out = run("pw-dump", timeout=5)
    try:
        objs = json.loads(out) if rc == 0 else []
    except ValueError:
        return set()
    ids = set()
    for o in objs:
        if o.get("type") != "PipeWire:Interface:Node":
            continue
        info = o.get("info") or {}
        p = info.get("props") or {}
        if p.get("media.class") != "Stream/Output/Audio" or info.get("state") != "running":
            continue
        if (p.get("media.role") or "").lower() in SKIP_ROLES:
            continue
        app = (p.get("application.name") or p.get("node.name") or "").lower()
        if app.startswith(SKIP_APPS):
            continue
        ids.add(o["id"])
    return ids


def phone_playing():
    rc, out = run("playerctl", "-a", "metadata", "--format", "{{playerInstance}}\t{{status}}", timeout=5)
    return any(line.startswith("kdeconnect.") and line.endswith("\tPlaying")
               for line in out.splitlines())


def bt_audio():
    """{MAC: (name, connected)} for paired Bluetooth devices that take audio."""
    rc, out = run("busctl", "--system", "--json=short", "call", "org.bluez", "/",
                  "org.freedesktop.DBus.ObjectManager", "GetManagedObjects", timeout=5)
    try:
        objs = json.loads(out)["data"][0]
    except (ValueError, KeyError, IndexError):
        return {}
    devs = {}
    for ifaces in objs.values():
        d = ifaces.get("org.bluez.Device1")
        if not d:
            continue
        val = lambda k, dflt=None: (d.get(k) or {}).get("data", dflt)
        if val("Paired") and A2DP_SINK in (val("UUIDs") or []):
            devs[val("Address")] = (val("Alias") or val("Name") or val("Address"), bool(val("Connected")))
    return devs


def default_sink():
    rc, out = run("wpctl", "inspect", "@DEFAULT_AUDIO_SINK@", timeout=5)
    sid = out.split(",", 1)[0].split()[-1] if out.startswith("id ") else ""
    name = next((l.split("=", 1)[1].strip().strip('"') for l in out.splitlines()
                 if "node.name" in l), "")
    return sid, name


def load_released():
    try:
        with open(RELEASED) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def save_released(d):
    os.makedirs(STATE_DIR, exist_ok=True)
    with open(RELEASED, "w") as f:
        json.dump(d, f)


# ── decisions (pure, so they can be tested) ─────────────────────────────────
def decide(now, phone, link_ok, laptop_since, quiet_since, devs, released, last_action):
    """-> ("release", [MAC…]) | ("reclaim", [MAC…]) | (None, reason)

    laptop_since: when the current laptop playback started (None = silent)
    quiet_since:  when the laptop went silent (None = playing)"""
    if now - last_action < COOLDOWN:
        return None, "cooldown"
    connected = [m for m, (_, c) in devs.items() if c]
    if laptop_since is not None and now - laptop_since >= SUSTAIN:
        want = [m for m in released if m in devs and not devs[m][1]]
        if want:
            return "reclaim", want
        return None, "laptop playing"
    if phone and link_ok and connected and quiet_since is not None \
            and now - quiet_since >= QUIET:
        return "release", connected
    return None, "nothing to do"


# ── doing it ────────────────────────────────────────────────────────────────
def release(macs, devs, dry):
    names = ", ".join(devs[m][0] for m in macs)
    log(f"release {names} -> phone (phone playing, laptop quiet)")
    if dry:
        return
    released = load_released()
    for m in macs:
        rc, _ = run("bluetoothctl", "disconnect", m)
        released[m] = 0
    save_released(released)
    notify(f"{names} → phone")


def reclaim(macs, devs, dry):
    names = ", ".join(devs[m][0] for m in macs)
    log(f"reclaim {names} -> laptop (laptop playing)")
    if dry:
        return
    sid, sink = default_sink()
    muted = False
    if sid and not sink.startswith("bluez_output"):
        rc, vol = run("wpctl", "get-volume", sid)
        if "MUTED" not in vol:
            run("wpctl", "set-mute", sid, "1")
            muted = True
    released = load_released()
    ok = False
    try:
        for m in macs:
            rc, out = run("bluetoothctl", "connect", m, timeout=12)
            if rc == 0 and "successful" in out.lower():
                released.pop(m, None)
                ok = True
            else:
                released[m] = released.get(m, 0) + 1
                if released[m] >= GIVE_UP:
                    log(f"  {devs[m][0]} won't connect — giving up on it")
                    released.pop(m)
        save_released(released)
        if ok:
            end = time.monotonic() + MUTE_MAX
            while time.monotonic() < end and not default_sink()[1].startswith("bluez_output"):
                time.sleep(0.25)
            notify(f"{names} → laptop")
    finally:
        if muted:
            run("wpctl", "set-mute", sid, "0")


def watch(dry=False):
    log(f"started{' (dry run)' if dry else ''}")
    wake = queue.Queue()

    def pw_monitor():
        """A NODE appearing / changing / going wakes the loop. Not any change:
        every pw-dump / wpctl run is a client coming and going, and waking on
        those (our own pw-dump included) looped at ~14 Hz, 10 % CPU."""
        while True:
            nodes, buf, first = set(), [], True
            with subprocess.Popen(["pw-dump", "-m", "-N"], stdout=subprocess.PIPE,
                                  stderr=subprocess.DEVNULL, text=True) as p:
                for line in p.stdout:
                    buf.append(line)
                    if not line.startswith("]"):    # one update batch per JSON array
                        continue
                    try:
                        batch = json.loads("".join(buf))
                    except ValueError:
                        batch = []
                    buf = []
                    hit = False
                    for o in batch:
                        if o.get("type") == "PipeWire:Interface:Node":
                            nodes.add(o.get("id"))
                            hit = True
                        elif o.get("info") is None and o.get("id") in nodes:
                            nodes.discard(o.get("id"))      # removed
                            hit = True
                    if hit and not first:
                        wake.put(1)
                    first = False
            time.sleep(2)
    threading.Thread(target=pw_monitor, daemon=True).start()

    laptop_since = None
    quiet_since = time.monotonic()
    last_action = 0.0
    releases = []                       # monotonic times, for FLAP_*
    last_reason = ""
    while True:
        now = time.monotonic()
        playing_here = bool(laptop_streams())
        if playing_here:
            quiet_since = None
            laptop_since = laptop_since or now
        else:
            laptop_since = None
            quiet_since = quiet_since or now
        if os.path.exists(OFF):
            last_reason = "off"
        else:
            devs = bt_audio()
            what, arg = decide(now, phone_playing(), kdec_link.healthy(), laptop_since,
                               quiet_since, devs, load_released(), last_action)
            if what == "release":
                release(arg, devs, dry)
                last_action = time.monotonic()
                releases = [t for t in releases if last_action - t < FLAP_WINDOW] + [last_action]
                if len(releases) >= FLAP_COUNT:
                    log(f"released {len(releases)}x in {FLAP_WINDOW} s — they keep coming "
                        f"back; pausing {FLAP_PAUSE // 60} min")
                    last_action += FLAP_PAUSE - COOLDOWN
                    releases = []
            elif what == "reclaim":
                reclaim(arg, devs, dry)
                last_action = time.monotonic()
            elif dry and arg != last_reason:
                log(f"  ({arg})")
                last_reason = arg
        # sleep until PipeWire changes or POLL s; while a laptop stream is
        # waiting out SUSTAIN, come back in time for it
        timeout = POLL
        if laptop_since is not None and now - laptop_since < SUSTAIN:
            timeout = SUSTAIN - (now - laptop_since) + 0.05
        try:
            wake.get(timeout=timeout)
            while True:
                wake.get(timeout=0.1)               # a burst: one look
        except queue.Empty:
            pass


def status():
    devs = bt_audio()
    print("switching:", "OFF" if os.path.exists(OFF) else "on")
    print("phone playing:", phone_playing(), "| KDE Connect link ok:", kdec_link.healthy())
    print("laptop streams playing:", sorted(laptop_streams()) or "none")
    print("default sink:", default_sink()[1])
    for m, (name, c) in devs.items():
        print(f"  {name} ({m}): {'connected here' if c else 'not connected here'}")
    print("released by bt-follow:", load_released() or "none")


def main():
    arg = sys.argv[1] if len(sys.argv) > 1 else ""
    if arg == "status":
        status()
    elif arg == "off":
        os.makedirs(STATE_DIR, exist_ok=True)
        open(OFF, "w").close()
        log("switched off")
        print("headphone switching off")
    elif arg == "on":
        if os.path.exists(OFF):
            os.remove(OFF)
        log("switched on")
        print("headphone switching on")
    elif arg in ("", "--dry-run"):
        import fcntl
        lock = open(os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "bt-follow.lock"), "w")
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            sys.exit("bt-follow: already running")
        watch(dry=arg == "--dry-run")
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
