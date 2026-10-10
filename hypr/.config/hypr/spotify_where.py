#!/usr/bin/env python3
"""Where is Spotify actually playing — this laptop, or another device?

    spotify_where.py hidden <player>...   print the players to hide (one per line)
    spotify_where.py where  <player>...   print laptop | elsewhere | none

Spotify mirrors itself. The laptop app, opened while the phone plays, does not
take over playback (Spotify Connect keeps the phone until you pick another
device) — it just shows the phone's song as its own MPRIS player. And the
phone's Spotify, relayed by KDE Connect, shows the laptop's song while the
laptop plays. Either way the bottom bar had the same song in both pills.

So one copy is hidden, and the pill follows the SOUND: the laptop app is the
real player only while it puts audio out here (a running PipeWire stream from
the spotify binary). Otherwise it is a mirror, and the phone's copy (KDE
Connect, or spotify-remote.py's Web API bridge) is the one shown.

A copy is only a mirror if it shows the SAME song. One account streams to
one device at a time, but a paused laptop app can sit on one song while the
phone plays another (or plays offline) — both are real then, and both show.

While paused there is no sound to go by, so the last answer is kept in
$XDG_RUNTIME_DIR/spotify-where.json; with none, the laptop app counts as a
mirror if a phone copy exists (opening the app never moves playback).

Used by now-playing.py, media-menu.py and spotify-remote.py (import — they
live in the same directory) and media-prefer-playing.sh (the CLI).
"""

import json
import os
import subprocess
import sys
import time

STATE = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "spotify-where.json")
BRIDGE = "kdeconnect.spotifyremote"
# Playing with no audio for this long before the laptop counts as a mirror:
# covers the gap between pressing play and the stream starting, and a track
# change. A move TO the laptop (audio appears) is taken at once.
NOAUDIO_GRACE = 2.5


def _run(*cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    return r.stdout.rstrip("\n") if r.returncode == 0 else ""


def is_laptop(inst):
    return inst.split(".")[0] == "spotify"


def is_remote_copy(inst):
    """KDE Connect's copy of the phone's Spotify, or the Web API bridge."""
    if inst == BRIDGE:
        return True
    if not inst.startswith("kdeconnect.mpris_"):
        return False
    out = _run("busctl", "--user", "--json=short", "get-property",
               "org.mpris.MediaPlayer2." + inst, "/org/mpris/MediaPlayer2",
               "org.mpris.MediaPlayer2", "Identity")
    try:
        return json.loads(out)["data"].lower().startswith("spotify")
    except (ValueError, KeyError):
        return False


def audio_here():
    """Is the Spotify app putting sound out on this laptop right now?"""
    try:
        nodes = json.loads(_run("pw-dump") or "[]")
    except ValueError:
        return False
    for n in nodes:
        info = n.get("info") or {}
        props = info.get("props") or {}
        if not str(props.get("media.class", "")).startswith("Stream/Output/Audio"):
            continue
        who = f'{props.get("application.process.binary", "")} {props.get("application.name", "")}'
        if "spotify" in who.lower() and info.get("state") == "running":
            return True
    return False


def _load():
    try:
        with open(STATE) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def _save(st):
    if st == _load():
        return
    tmp = f"{STATE}.{os.getpid()}"
    with open(tmp, "w") as f:
        json.dump(st, f)
    os.replace(tmp, STATE)


def where(players):
    """-> "laptop" | "elsewhere" | None (no Spotify app on this laptop)."""
    laptop = next((p for p in players if is_laptop(p)), None)
    if laptop is None:
        try:
            os.remove(STATE)             # a fresh app starts with no history
        except OSError:
            pass
        return None
    st = _load()
    if _run("playerctl", "-p", laptop, "status") == "Playing":
        if audio_here():
            _save({"where": "laptop"})
            return "laptop"
        if st.get("where") == "laptop":
            since = st.get("noaudio_since") or time.time()
            if time.time() - since < NOAUDIO_GRACE:
                _save({"where": "laptop", "noaudio_since": since})
                return "laptop"
        _save({"where": "elsewhere"})
        return "elsewhere"
    if st.get("where") in ("laptop", "elsewhere"):
        return st["where"]
    return "elsewhere" if any(is_remote_copy(p) for p in players) else "laptop"


def _title(inst):
    return _run("playerctl", "-p", inst, "metadata", "xesam:title")


def hidden(players):
    """The Spotify players that only mirror the real one (same song)."""
    w = where(players)
    if w is None:
        return set()
    laptop = [p for p in players if is_laptop(p)]
    remote = [p for p in players if is_remote_copy(p)]
    if not remote:
        # Nothing else shows the phone's Spotify (KDE Connect can't see it and
        # the bridge isn't up yet): keep the laptop app rather than show nothing.
        return set()
    song = _title(laptop[0])
    same = {p for p in remote if song and _title(p) == song}
    if w == "laptop":
        return same
    return set(laptop) if same else set()


if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in ("hidden", "where"):
        sys.exit("usage: spotify_where.py hidden|where <player>...")
    ps = sys.argv[2:]
    if sys.argv[1] == "hidden":
        for p in sorted(hidden(ps)):
            print(p)
    else:
        print(where(ps) or "none")
