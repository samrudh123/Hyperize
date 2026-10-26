#!/usr/bin/env python3
"""Shuffle / repeat — the bottom bar's ⇄ and ⟲ buttons (NowPlaying.qml).

    media_modes.py shuffle <player>    toggle
    media_modes.py repeat <player>     off -> playlist -> track -> off
    media_modes.py get <player>        "<shuffle> <loop>" (debugging)

As a module (now-playing.py): state(inst, spotify, key, playing) -> (shuffle, loop), with
shuffle "1" / "0" and loop "None" / "Playlist" / "Track" (MPRIS LoopStatus
words), "" for what the player can't do — the bar hides that button.

Two sources:
  * the player's own MPRIS Shuffle / LoopStatus (the Spotify app, YouTube
    Music desktop, mpv with mpv-mpris, …). Read with one GetAll per render;
    a change made in the app wakes now-playing.py through its playerctl
    follower, which prints {{shuffle}} {{loop}} for exactly that.
  * Spotify whose MPRIS has neither — KDE Connect's copy of the phone's
    Spotify (KDE Connect relays no Shuffle / LoopStatus, and its mprisremote
    interface has none either) and spotify-remote.py's bridge: the Spotify
    Web API. GET /me/player has shuffle_state / repeat_state ("off" /
    "context" / "track"); PUT /me/player/shuffle|repeat sets them (Premium,
    which the user has). The PHONE is the truth, so:
      - shown: read in now-playing.py's background thread every
        TTL_PLAYING / TTL_PAUSED s and at once on a new song / play / pause
        (`key`), into CACHE, shared by both bar pills; now-playing.py wakes
        for it even while paused (web_shown). One kept-alive HTTPS
        connection (Api) — a GET /me/player is still ~0.7 s, Spotify's own
        time. A change made on the phone shows in ~2-3 s.
      - Spotify reporting no player (asleep on the phone: /me/player 204),
        no login, or no good read for STALE s: UNKNOWN, and the buttons hide
        — never a stale guess the phone doesn't match.
      - a click (now-playing.py stdin from the bar, or this CLI) steps from
        a read no older than FRESH s — the bar's own polling keeps one that
        fresh while it plays; otherwise it GETs first — shows the new state
        AT ONCE and PUTs it. Spotify takes 0.6-2.4 s to answer a PUT and
        0.7-1.6 s a GET (measured, its own time), so waiting for them was
        what made a click take 4-5 s. The PUT sets an ABSOLUTE state, so
        phone and bar end up the same either way; a refused PUT puts the
        old state back (and notifies). The API trails its own PUT (1.8-4 s),
        so for HOLD s after it reads still saying the old value are ignored;
        after that the API wins again.
Everything else (Firefox, phone YouTube) has neither: both buttons hide.
"""

import contextlib
import fcntl
import http.client
import importlib.util
import json
import os
import signal
import subprocess
import sys
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "spotify-modes.json")
TTL_PLAYING = 1.5              # s between Web API reads while a Spotify pill plays
TTL_PAUSED = 4.0               # ...a paused one
STALE = 30.0                   # API unreachable this long: the state is unknown
HOLD = 5.0                     # s after an accepted PUT that stale reads are ignored (API lag measured up to ~4 s)
FRESH = 3.0                    # a click may step from a read this recent
BACKOFF = 30.0                 # s without reads after HTTP 429 (rate limited)
LOCK = CACHE + ".lock"
LOOPS = ["None", "Playlist", "Track"]                  # the ⟲ cycle
TO_API = {"None": "off", "Playlist": "context", "Track": "track"}
FROM_API = {v: k for k, v in TO_API.items()}

on_change = None               # now-playing.py: called when a Web API read changed something
web_shown = False              # the last state() came from the Web API: keep re-reading it
_fetching = threading.Lock()


def run(*cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    return r.stdout.rstrip("\n") if r.returncode == 0 else ""


def mpris(inst):
    """-> (shuffle, loop) from the player's own MPRIS properties."""
    out = run("busctl", "--user", "--json=short", "call", "org.mpris.MediaPlayer2." + inst,
              "/org/mpris/MediaPlayer2", "org.freedesktop.DBus.Properties", "GetAll", "s",
              "org.mpris.MediaPlayer2.Player")
    try:
        props = json.loads(out)["data"][0]
    except (ValueError, KeyError, IndexError):
        return "", ""
    shuffle = (props.get("Shuffle") or {}).get("data")
    loop = (props.get("LoopStatus") or {}).get("data")
    return ("" if shuffle is None else "1" if shuffle else "0",
            loop if loop in LOOPS else "")


# ── Spotify Web API ──────────────────────────────────────────────────────────
def _spotify():
    """spotify-remote.py as a module (the name has a dash) — for api()."""
    spec = importlib.util.spec_from_file_location("spotify_remote",
                                                  os.path.join(HERE, "spotify-remote.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class Api:
    """The Web API over ONE kept-alive HTTPS connection. spotify-remote.py's
    api() opens a new one per call — ~0.35 s of TCP + TLS each time (measured
    here), which made a click (GET + PUT) take seconds. A request on
    a connection the server has since closed is retried once on a new one
    (PUTs here set an absolute state, so repeating one is harmless); a 401
    goes through spotify-remote's api(), which refreshes the token."""

    def __init__(self):
        self.sr = _spotify()
        self.ApiError = self.sr.ApiError
        self.conn = None

    def logged_in(self):
        return bool(self.sr.load_token())

    def __call__(self, method, path):
        token = self.sr.access_token()
        if not token:
            raise self.ApiError(401, "not logged in")
        headers = {"Authorization": "Bearer " + token}
        for attempt in (1, 2):
            if self.conn is None:
                self.conn = http.client.HTTPSConnection("api.spotify.com", timeout=8)
            try:
                self.conn.request(method, "/v1" + path, headers=headers,
                                  body=None if method == "GET" else b"")
                r = self.conn.getresponse()
                body = r.read()
                break
            except (http.client.HTTPException, OSError):
                self.conn.close()
                self.conn = None
                if attempt == 2:
                    raise OSError("Spotify Web API unreachable")
        if r.status == 401:
            return self.sr.api(method, path)
        if r.status >= 400:
            raise self.ApiError(r.status, body.decode(errors="replace"))
        if method != "GET" or not body.strip():
            return None
        try:
            return json.loads(body)
        except ValueError:
            raise self.ApiError(r.status, "unparseable body")


_local = threading.local()


def client():
    """This thread's Api — a connection can't carry two requests at once (the
    bar's background reads and a click run in different threads)."""
    if getattr(_local, "api", None) is None:
        _local.api = Api()
    return _local.api


def load():
    try:
        with open(CACHE) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def save(d):
    tmp = CACHE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(d, f)
    os.replace(tmp, CACHE)


@contextlib.contextmanager
def locked():
    """One reader / writer of the API state at a time: a background read that
    started before a click's PUT must not store the old value after it."""
    with open(LOCK, "a") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        yield


def read_api(api):
    """-> {"shuffle": bool, "loop": "None"|"Playlist"|"Track"} now, or None
    when Spotify reports no player. Raises on network / HTTP errors."""
    p = api("GET", "/me/player")
    if not p or "repeat_state" not in p:
        return None
    return {"shuffle": bool(p.get("shuffle_state")),
            "loop": FROM_API.get(p["repeat_state"], "None")}


def _fetch(key):
    asked = time.time()                     # TTLs run from the ask, as the bar ticks
    got, err = None, None
    try:                                    # not under LOCK: a click mustn't wait for it
        api = client()
        got = read_api(api) if api.logged_in() else None
    except Exception as e:                              # noqa: BLE001 — offline, 429, …
        err = e
    with locked():
        old = load()
        new = dict(old, at=asked, key=key)
        now = time.time()
        if err is None:
            got = got or {"shuffle": None, "loop": None}
            held = {k: old.get(k) for k in ("shuffle", "loop")}
            if now < old.get("hold_until", 0) and got != held:
                pass                        # read before / trailing our own PUT
            else:
                new.update(got)
                new.pop("hold_until", None)
            new["ok_at"] = now
        else:
            if getattr(err, "status", 0) == 429:
                new["at"] = now + BACKOFF - TTL_PAUSED
            if now - new.get("ok_at", 0) > STALE:       # a blip keeps the last read
                new.update(shuffle=None, loop=None)
        save(new)
    if (old.get("shuffle"), old.get("loop")) != (new.get("shuffle"), new.get("loop")) \
            and on_change:
        on_change()


def _fetch_bg(key):
    if not _fetching.acquire(blocking=False):
        return
    def go():
        try:
            _fetch(key)
        finally:
            _fetching.release()
    threading.Thread(target=go, daemon=True).start()


def as_fields(d):
    if d.get("shuffle") is None:
        return "", ""                                   # unknown: hide the buttons
    return "1" if d["shuffle"] else "0", d.get("loop") or "None"


def web(key, playing):
    """-> (shuffle, loop) as last read from the Web API; reads again in the
    background when that is older than the TTL or was for another `key`
    (song and play state)."""
    d = load()
    ttl = TTL_PLAYING if playing else TTL_PAUSED
    if time.time() - d.get("at", 0) > ttl or d.get("key") != key:
        _fetch_bg(key)
    return as_fields(d)


def state(inst, spotify=False, key="", playing=False):
    global web_shown
    shuffle, loop = mpris(inst)
    web_shown = spotify and not shuffle and not loop
    if web_shown:
        return web(key, playing)
    return shuffle, loop


# ── CLI: the buttons ─────────────────────────────────────────────────────────
def nudge_bars():
    """Redraw now (now-playing.py's SIGUSR1) — while paused nothing else would."""
    out = run("pgrep", "-f", r"^/usr/bin/python3 .*/now-playing\.py( --cffi)?( --scope [a-z]+)?$")
    for pid in out.split():
        try:
            os.kill(int(pid), signal.SIGUSR1)
        except (ValueError, OSError):
            pass


def is_spotify(inst):
    if inst.split(".")[0] == "spotify":
        return True
    ident = run("busctl", "--user", "--json=short", "get-property",
                "org.mpris.MediaPlayer2." + inst, "/org/mpris/MediaPlayer2",
                "org.mpris.MediaPlayer2", "Identity")
    try:
        return json.loads(ident)["data"].lower().startswith("spotify")
    except (ValueError, KeyError):
        return False


def change(what, inst):
    shuffle, loop = mpris(inst)
    if shuffle or loop:                                 # the player does it itself
        if what == "shuffle" and shuffle:
            run("playerctl", "-p", inst, "shuffle", "Off" if shuffle == "1" else "On")
        elif what == "repeat" and loop:
            run("playerctl", "-p", inst, "loop", LOOPS[(LOOPS.index(loop) + 1) % 3])
        return
    if not is_spotify(inst):
        return
    with locked():
        _change_web(what)
    nudge_bars()


def change_bg(what, inst):
    """now-playing.py's stdin command: change() on its warm connection, in a
    thread; on_change() redraws when done."""
    def go():
        try:
            if mpris(inst) != ("", ""):
                change(what, inst)
            else:
                with locked():
                    _change_web(what)
                if on_change:
                    on_change()
        except Exception as exc:                        # noqa: BLE001 — never kill the bar
            print(f"media_modes: {what}: {exc!r}", file=sys.stderr)
    threading.Thread(target=go, daemon=True).start()


def _change_web(what):
    api = client()
    sr = api.sr
    try:
        d = load()
        now = time.time()
        if d.get("shuffle") is not None and (now < d.get("hold_until", 0)
                                             or now - d.get("ok_at", 0) < FRESH):
            cur = {"shuffle": d["shuffle"], "loop": d["loop"]}
        else:
            cur = read_api(api)                         # too old to step from: ask
        if cur is None:
            save(dict(d, shuffle=None, loop=None, at=time.time()))
            sr.notify("Spotify", "Spotify isn't reporting the phone right now — "
                      "start playing there, then try again")
            return
        want = dict(cur)
        if what == "shuffle":
            want["shuffle"] = not cur["shuffle"]
            path = f"/me/player/shuffle?state={'true' if want['shuffle'] else 'false'}"
        else:
            want["loop"] = LOOPS[(LOOPS.index(cur["loop"]) + 1) % 3]
            path = f"/me/player/repeat?state={TO_API[want['loop']]}"
        save(dict(load(), **want, hold_until=time.time() + 30))   # show it now…
        if on_change:
            on_change()
        try:
            api("PUT", path)                            # …the phone follows in ~1 s
        except BaseException:
            save(dict(load(), **cur, hold_until=0))     # refused: back to what it was
            raise
        now = time.time()
        save(dict(load(), **want, at=now, hold_until=now + HOLD))
    except api.ApiError as e:
        if e.status == 403 and "PREMIUM" in e.body.upper():
            sr.notify("Spotify", "Controlling other devices needs Spotify Premium")
        elif e.status == 404:
            sr.notify("Spotify", "Spotify lost the device — open Spotify on it once")
        else:
            sr.notify("Spotify", f"Couldn't change {what}: HTTP {e.status}")
    except OSError:                                     # URLError, timeouts
        sr.notify("Spotify", "Offline — couldn't reach Spotify")


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] in ("shuffle", "repeat"):
        change(sys.argv[1], sys.argv[2])
    elif len(sys.argv) == 3 and sys.argv[1] == "get":
        inst = sys.argv[2]
        spotify = is_spotify(inst)
        if spotify and mpris(inst) == ("", ""):
            _fetch("")                      # here and now: a CLI can't wait for a thread
            print(*as_fields(load()))
        else:
            print(*state(inst, spotify))
    else:
        sys.exit("usage: media_modes.py shuffle|repeat|get <player>")
