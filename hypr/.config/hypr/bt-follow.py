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
phone (that's why mpris-proxy is masked). So this decides for them, by the
rule multipoint earbuds follow — STICKY (2026-10-28, the
user's rule): the headphones stay with whichever device played last, as
long as it keeps playing; only once it has been silent / paused for QUIET s
do they move — and only if the OTHER device is playing then:

  * RELEASE is OFF since 2026-10-28 (RELEASE = False; the user: "can it
    not just remain as it is?"): when the laptop stops, it keeps the
    headphones exactly as they are — the phone only gets them if the
    headphones switch over by themselves. What it did:
    RELEASE, to the phone: a phone player is Playing (KDE Connect's
    kdeconnect.mpris_*, or spotify-remote.py's Spotify bridge), the laptop
    has played nothing for QUIET s, and a Bluetooth audio device is
    connected here with its audio on -> switch the laptop's AUDIO for it off
    (its PipeWire card profile -> "off"). It STAYS CONNECTED (since
    2026-10-28 — disconnecting meant reconnecting by hand when the reclaim
    failed); the laptop just stops holding its audio channel, so the
    headphones take the phone's. Not while the KDE Connect link is bad
    (kdec_link.py): the phone's state may be stale then.
  * RECLAIM, for the laptop: an app here plays (a PipeWire output stream
    running for SUSTAIN s; notification / event sounds don't count), the
    phone has played nothing for QUIET s (or its state is unknown: the KDE
    Connect link is down), and a device THIS released has its audio off ->
    mute the laptop's speakers,
    switch its audio back on (the profile it had), unmute once its sink is
    the default (made so, if WirePlumber doesn't), unmute (or after MUTE_MAX
    s), so the sound doesn't come out of the speakers meanwhile. While the
    phone plays, laptop sound stays on the speakers.
    (A device released the old way — disconnected — is still reconnected.)
  * Only devices released here are reclaimed: audio you switched off, or a
    device you disconnected, yourself stays that way. One that won't come
    back (off, out of range) is given up after GIVE_UP failed tries.
  * HOLD SINK (2026-10-28, the user's wish): while the phone has the
    headphones, the laptop's output is NOT the speakers — a silent stand-in
    sink named after them ("<headphones> (phone has it)", node
    bt-follow-hold) is the default, so the bar's sound pill still shows the
    headphones and laptop playback just carries on, unheard, until the
    headphones come back (streams follow the default over to them). It goes
    away when they come back, disconnect, or this stops.
  * A headphone connecting (audio on) while the laptop's default is a
    built-in sink becomes the default — once, so picking the speakers by
    hand afterwards sticks.
  * `bt-follow.py off` (or the watcher stopping) switches released audio
    back on, so a headset is never left connected-but-silent.
  * COOLDOWN s between actions, so the two rules can't ping-pong.

Event-driven on the laptop side (`pw-dump -m` wakes it when a PipeWire
node changes), polled every POLL s for the phone and Bluetooth while a
device is released (IDLE_POLL s otherwise; the phone isn't asked then).
Stdlib only.
"""

import json
import os
import queue
import subprocess
import sys
import threading
import time

import kdec_link   # same directory: is the KDE Connect link usable?

POLL = 1.0          # s: phone / Bluetooth re-check when nothing wakes us
IDLE_POLL = 3.0     # s: the same with nothing released (PipeWire events still wake at once)
QUIET = 2.25        # s the side holding the headphones must be silent before they move (was 3.5)
SUSTAIN = 0.8       # s a laptop stream must run before reclaiming
COOLDOWN = 4.0      # s between actions
RELEASE = False     # hand the headphones to the phone when the laptop stops? (no: see above)
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
RELEASED = os.path.join(STATE_DIR, "released.json")
# MAC -> {"profile": the A2DP profile it had, "fails": n}   (audio switched off)
#      | n                                                  (old: disconnected)


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
def pw_objs():
    """one pw-dump, parsed ([] on failure) — the watch loop shares one per
    pass between laptop_streams and hold_id (two were ~half its CPU)"""
    rc, out = run("pw-dump", timeout=5)
    try:
        return json.loads(out) if rc == 0 else []
    except ValueError:
        return []


def laptop_streams(objs=None):
    """Node ids of PipeWire output streams that are playing (running) here."""
    if objs is None:
        objs = pw_objs()
    ids = set()
    for o in objs:
        if o.get("type") != "PipeWire:Interface:Node":
            continue
        info = o.get("info") or {}
        p = info.get("props") or {}
        if p.get("media.class") != "Stream/Output/Audio" or info.get("state") != "running":
            continue
        # a filter's own output (the equalizer, rice-eq.output) runs whenever
        # anything plays through it, notification sounds included: not an app
        if p.get("node.link-group"):
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


def bt_card(mac):
    """-> (device id, active profile name, {profile name: index}) of the
    PipeWire card for that Bluetooth MAC, or (None, "", {})"""
    rc, out = run("pw-dump", timeout=5)
    try:
        objs = json.loads(out) if rc == 0 else []
    except ValueError:
        return None, "", {}
    want = "bluez_card." + mac.replace(":", "_")
    for o in objs:
        info = o.get("info") or {}
        if o.get("type") != "PipeWire:Interface:Device" or (info.get("props") or {}).get("device.name") != want:
            continue
        params = info.get("params") or {}
        profiles = {x.get("name"): x.get("index") for x in params.get("EnumProfile", []) if x.get("name")}
        active = next((x.get("name") for x in params.get("Profile", []) if x.get("name")), "")
        return o["id"], active, profiles
    return None, "", {}


def audio_off(mac):
    """connected here, and its audio switched off (the card's profile)"""
    dev, active, _ = bt_card(mac)
    return dev is not None and active == "off"


def bt_out_names(mac):
    """a headphone's sink node.name: PipeWire writes the MAC with COLONS
    (bluez_output.B8:84:…) — the card has underscores (bluez_card.B8_84_…);
    the underscore form alone never matched, so reclaim never set it default"""
    return ["bluez_output." + mac, "bluez_output." + mac.replace(":", "_")]


def bt_sink_id(prefixes):
    """the PipeWire id of the first sink whose node.name starts with one of prefixes"""
    rc, out = run("pw-dump", timeout=5)
    try:
        objs = json.loads(out) if rc == 0 else []
    except ValueError:
        return None
    for o in objs:
        p = (o.get("info") or {}).get("props") or {}
        if p.get("media.class") == "Audio/Sink" and str(p.get("node.name", "")).startswith(tuple(prefixes)):
            return o["id"]
    return None


HOLD = "bt-follow-hold"


def hold_id(objs=None):
    if objs is None:
        objs = pw_objs()
    return next((o["id"] for o in objs if ((o.get("info") or {}).get("props") or {}).get("node.name") == HOLD), None)


def hold_on(name):
    """the silent stand-in sink, made the default -> its id"""
    hid = hold_id()
    if hid is None:
        desc = f"{name} (phone has it)".replace('"', "'")
        run("pw-cli", "create-node", "adapter",
            "{ factory.name=support.null-audio-sink node.name=" + HOLD
            + f' node.description="{desc}" media.class=Audio/Sink'
            + " audio.position=[ FL FR ] monitor.channel-volumes=true object.linger=true }")
        for _ in range(20):
            hid = hold_id()
            if hid is not None:
                break
            time.sleep(0.1)
    if hid is not None:
        run("wpctl", "set-default", str(hid))
    return hid


def hold_off():
    hid = hold_id()
    if hid is not None:
        run("pw-cli", "destroy", str(hid))


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
def decide(now, phone, link_ok, laptop_since, quiet_since, devs, released, last_action,
           phone_quiet_since=0.0):
    """-> ("release", [MAC…]) | ("reclaim", [MAC…]) | (None, reason)

    laptop_since: when the current laptop playback started (None = silent)
    quiet_since:  when the laptop went silent (None = playing)
    phone_quiet_since: when the phone stopped playing (None = playing)"""
    if now - last_action < COOLDOWN:
        return None, "cooldown"
    # connected here AND holding audio (a released one sits with audio off)
    connected = [m for m, (_, c) in devs.items() if c and not (m in released and isinstance(released[m], dict))]
    if laptop_since is not None and now - laptop_since >= SUSTAIN:
        want = [m for m in released if m in devs
                and (devs[m][1] if isinstance(released[m], dict) else not devs[m][1])]
        phone_idle = not link_ok or (phone_quiet_since is not None and now - phone_quiet_since >= QUIET)
        if want and phone_idle:
            return "reclaim", want
        return None, "laptop playing" + ("" if phone_idle or not want else " — phone still has them")
    if RELEASE and phone and link_ok and connected and quiet_since is not None \
            and now - quiet_since >= QUIET:
        return "release", connected
    return None, "nothing to do"


# ── doing it ────────────────────────────────────────────────────────────────
def release(macs, devs, dry):
    """switch the laptop's audio for them off — they stay connected"""
    names = ", ".join(devs[m][0] for m in macs)
    log(f"release {names} -> phone (phone playing, laptop quiet; staying connected)")
    if dry:
        return
    released = load_released()
    done = []
    for m in macs:
        dev, active, profiles = bt_card(m)
        if dev is None or "off" not in profiles:
            log(f"  {devs[m][0]}: no audio card to switch off — leaving it")
            continue
        if active == "off":
            continue
        run("wpctl", "set-profile", str(dev), str(profiles["off"]))
        released[m] = {"profile": active, "fails": 0}
        done.append(devs[m][0])
    save_released(released)
    if done:
        hold_on(done[0])        # laptop sound: silent, not the speakers
    if done:
        notify(f"{', '.join(done)} → phone (still connected)")


def audio_on(m, entry):
    """switch a released device's audio back on: the profile it had, else
    the best-looking A2DP one. -> True when it took"""
    dev, active, profiles = bt_card(m)
    if dev is None:
        return False
    if active not in ("", "off"):
        return True
    want = entry.get("profile") if isinstance(entry, dict) else ""
    if want not in profiles:
        want = next((n for n in profiles if n.startswith("a2dp-sink")), "") \
            or next((n for n in profiles if n != "off"), "")
    if not want:
        return False
    run("wpctl", "set-profile", str(dev), str(profiles[want]))
    return True


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
            entry = released.get(m, 0)
            if isinstance(entry, dict):                 # connected, audio off
                good = audio_on(m, entry)
            else:                                       # old way: disconnected
                rc, out = run("bluetoothctl", "connect", m, timeout=12)
                good = rc == 0 and "successful" in out.lower()
            if good:
                released.pop(m, None)
                ok = True
            else:
                fails = (entry.get("fails", 0) if isinstance(entry, dict) else entry) + 1
                if fails >= GIVE_UP:
                    log(f"  {devs[m][0]} won't come back — giving up on it")
                    released.pop(m)
                elif isinstance(entry, dict):
                    released[m] = dict(entry, fails=fails)
                else:
                    released[m] = fails
        save_released(released)
        if ok:
            end = time.monotonic() + MUTE_MAX
            want = [n for m in macs for n in bt_out_names(m)]
            while time.monotonic() < end and not default_sink()[1].startswith(tuple(want)):
                nid = bt_sink_id(want)
                if nid:                             # there, but not the default: make it
                    run("wpctl", "set-default", str(nid))
                time.sleep(0.3)
            if not any(isinstance(v, dict) for v in load_released().values()):
                hold_off()                          # its streams moved with the default
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
    phone_quiet_since = time.monotonic()
    tidy = {}
    last_action = 0.0
    releases = []                       # monotonic times, for FLAP_*
    last_reason = ""
    while True:
        now = time.monotonic()
        objs = pw_objs()
        playing_here = bool(laptop_streams(objs))
        if playing_here:
            quiet_since = None
            laptop_since = laptop_since or now
        else:
            laptop_since = None
            quiet_since = quiet_since or now
        released = load_released()
        # decide() only looks at the phone to release (RELEASE) or to wait
        # for it before reclaiming a released device: otherwise don't ask
        # playerctl every pass. Not watched = not known quiet, so once it
        # matters it has to be quiet QUIET s first.
        need_phone = RELEASE or bool(released)
        phone = phone_playing() if need_phone else False
        if not need_phone:
            phone_quiet_since = None
        elif phone:
            phone_quiet_since = None
        else:
            phone_quiet_since = phone_quiet_since or now
        if os.path.exists(OFF):
            last_reason = "off"
        else:
            devs = bt_audio()
            what, arg = decide(now, phone, kdec_link.healthy(), laptop_since,
                               quiet_since, devs, released, last_action, phone_quiet_since)
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
            if not dry:
                if what in ("release", "reclaim"):         # things moved: look again
                    keep_tidy(bt_audio(), load_released(), tidy)
                else:
                    keep_tidy(devs, released, tidy, objs)
        # sleep until PipeWire changes or POLL s (IDLE_POLL with nothing
        # released: then only PipeWire events — streams, a headphone's sink
        # appearing — can lead anywhere); while a laptop stream is
        # waiting out SUSTAIN, come back in time for it
        timeout = POLL if need_phone else IDLE_POLL
        if quiet_since is not None and now - quiet_since < QUIET:
            timeout = min(timeout, QUIET - (now - quiet_since) + 0.05)
        if laptop_since is not None and now - laptop_since < SUSTAIN:
            timeout = SUSTAIN - (now - laptop_since) + 0.05
        try:
            wake.get(timeout=timeout)
            while True:
                wake.get(timeout=0.1)               # a burst: one look
        except queue.Empty:
            pass


def restore_all():
    """switch every device's audio we switched off back on (connected ones)"""
    released = load_released()
    for m, entry in list(released.items()):
        if isinstance(entry, dict) and audio_on(m, entry):
            released.pop(m)
            log(f"  {m}: audio back on")
            sink = None
            for _ in range(25):
                sink = bt_sink_id(bt_out_names(m))
                if sink:
                    break
                time.sleep(0.2)
            if sink:
                run("wpctl", "set-default", str(sink))
    save_released(released)
    hold_off()


def keep_tidy(devs, released, state, objs=None):
    """the hold sink exists exactly while a released device is connected
    (audio off); a headphone that just came on becomes the default once.
    objs: a fresh pw-dump to reuse"""
    held = [m for m, e in released.items() if isinstance(e, dict) and m in devs and devs[m][1]]
    have = hold_id(objs) is not None
    if held and not have:
        hold_on(devs[held[0]][0])
    elif not held and have:
        hold_off()
    # newly connected with audio on -> default (edge-triggered)
    live = {m for m, (_, c) in devs.items() if c and m not in released}
    for m in live - state.get("live", set()):
        sid = bt_sink_id(bt_out_names(m))
        if sid and not default_sink()[1].startswith("bluez_output"):
            run("wpctl", "set-default", str(sid))
            log(f"  {devs[m][0]} connected: made it the output")
    state["live"] = live


def status():
    devs = bt_audio()
    print("switching:", "OFF" if os.path.exists(OFF) else "on")
    print("phone playing:", phone_playing(), "| KDE Connect link ok:", kdec_link.healthy())
    print("laptop streams playing:", sorted(laptop_streams()) or "none")
    print("default sink:", default_sink()[1])
    for m, (name, c) in devs.items():
        state = "not connected here"
        if c:
            state = "connected here, audio " + ("OFF (phone has it)" if audio_off(m) else "on")
        print(f"  {name} ({m}): {state}")
    print("released by bt-follow:", load_released() or "none")


def main():
    arg = sys.argv[1] if len(sys.argv) > 1 else ""
    if arg == "status":
        status()
    elif arg == "off":
        os.makedirs(STATE_DIR, exist_ok=True)
        open(OFF, "w").close()
        restore_all()
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
        import signal
        signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
        try:
            watch(dry=arg == "--dry-run")
        finally:
            if arg != "--dry-run":
                restore_all()               # never leave a headset connected but silent
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
