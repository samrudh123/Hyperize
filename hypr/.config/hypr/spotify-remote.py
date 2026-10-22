#!/usr/bin/env python3
"""Spotify playing on ANOTHER device (phone, speaker, …) — as an MPRIS player.

    spotify-remote.py mpris         the bridge (exec-once from hyprland.conf)
    spotify-remote.py status        JSON for waybar's custom/spotify-remote —
                                    only ever a "log in" prompt now
    spotify-remote.py login         one-time browser login
    spotify-remote.py toggle        play / pause
    spotify-remote.py click         log in if needed, else toggle (bar on-click)
    spotify-remote.py next | prev   skip

Playerctl only sees players running on this laptop, and the Spotify app only
reports remote playback while it is open. This asks the Web API instead
(GET /v1/me/player), so nothing has to run here.

THE BRIDGE
`mpris` polls the Web API and republishes what it finds as an ordinary MPRIS
player, org.mpris.MediaPlayer2.kdeconnect.spotifyremote (Identity
"Spotify - <device>"; the prefix keeps KDE Connect from echoing it back to the phone).
So it is just another player to everything else: custom/now-playing draws it
with its progress line, scroll seeks it (media-seek.sh -> Seek -> PUT
/me/player/seek), right-click / SUPER+M list it in media-menu.py, and
playerctl / media keys / prev / next all work on it. It used to be a separate
waybar module of its own, which had none of that.

The name is only owned while there is remote playback to show AND nobody else
shows it already: the Spotify app running here, or the phone's own Spotify
session relayed by KDE Connect (kdeconnect.mpris_*, Identity "Spotify - …").
KDE Connect is the better source when it works — it reads the phone's media
session, so it keeps working in the case the API cannot: Spotify backgrounded
on Android and resumed from earbuds after a long pause drops off Spotify
Connect entirely (/me/player 204, /me/player/devices empty) while still
playing. For that case the bridge falls back to /me/player/currently-playing,
then to the last track seen for as long as it can still be playing.

Position is interpolated between polls; play/pause and seeks are applied
locally at once and the next few polls are not allowed to undo them while
Spotify catches up. Wheel seeks are coalesced into one API call.
Controlling another device needs Premium (403 PREMIUM_REQUIRED otherwise).

Login is Authorization Code + PKCE: no client secret, just the client ID of the
developer app (redirect URI http://127.0.0.1:8888/callback — Spotify rejects
"localhost"). Tokens live in ~/.local/state/spotify-remote/token.json (0600);
the refresh token rotates on every refresh, so it is re-saved each time — and
refreshed under a lock, since two refreshes racing would burn it.

Standard library + PyGObject (Gio) for the bridge.
"""

import base64
import fcntl
import hashlib
import html
import json
import os
import queue
import secrets
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

import spotify_where   # same directory: is the laptop app real or a mirror?

# The developer app's client ID — per user, kept out of the (public) dotfiles
# repo: ~/.config/hypr/spotify-client-id (one line), or $SPOTIFY_CLIENT_ID.
def _client_id():
    try:
        with open(os.path.expanduser("~/.config/hypr/spotify-client-id")) as f:
            return f.read().strip()
    except OSError:
        return os.environ.get("SPOTIFY_CLIENT_ID", "")


CLIENT_ID = _client_id()
REDIRECT = "http://127.0.0.1:8888/callback"
SCOPES = "user-read-playback-state user-modify-playback-state"

STATE_DIR = os.path.join(os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")),
                         "spotify-remote")
TOKEN_FILE = os.path.join(STATE_DIR, "token.json")
RUNTIME = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
# Set by the bridge when the refresh token is dead; `status` then shows "log in".
LOGIN_FLAG = os.path.join(RUNTIME, "spotify-remote.login")
BRIDGE_LOCK = os.path.join(RUNTIME, "spotify-remote.mpris.lock")
# The last Spotify song and where it played — for media-menu.py's "Last
# played" row (written by the bridge, see record_last()).
LAST_PLAYED = os.path.join(STATE_DIR, "last-played.json")
# Set by `resume` (the row was clicked): media-menu.py hides the row until
# Spotify has played and stopped again (the bridge clears it once it sees
# Spotify), or RESUME_GIVEUP s have passed with nothing starting.
RESUME_MARK = os.path.join(RUNTIME, "spotify-resume.pending")
RESUME_GIVEUP = 150   # > resume()'s own waiting (≈ 2 min worst case)

I_SPOTIFY = "\U000F04C7"   # md-spotify

HIDDEN = {"text": "", "class": "hidden", "tooltip": ""}


class ApiError(Exception):
    def __init__(self, status, body):
        super().__init__(f"{status}: {body}")
        self.status = status
        self.body = body


# ── tokens ─────────────────────────────────────────────────────────────────
def load_token():
    try:
        with open(TOKEN_FILE) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def save_token(tok):
    os.makedirs(STATE_DIR, mode=0o700, exist_ok=True)
    tok["expires_at"] = time.time() + tok.get("expires_in", 3600) - 60
    old = load_token() or {}
    tok.setdefault("refresh_token", old.get("refresh_token"))
    fd = os.open(TOKEN_FILE + ".tmp", os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(tok, f)
    os.replace(TOKEN_FILE + ".tmp", TOKEN_FILE)
    return tok


def token_request(fields):
    data = urllib.parse.urlencode({"client_id": CLIENT_ID, **fields}).encode()
    req = urllib.request.Request("https://accounts.spotify.com/api/token", data=data,
                                 headers={"Content-Type": "application/x-www-form-urlencoded"})
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return save_token(json.load(r))
    except urllib.error.HTTPError as e:
        raise ApiError(e.code, e.read().decode(errors="replace"))


def access_token():
    tok = load_token()
    if not tok or not tok.get("refresh_token"):
        return None
    if time.time() >= tok.get("expires_at", 0):
        # The bridge and a bar click can both get here; the refresh token
        # rotates, so the loser of an unlocked race would kill the login.
        os.makedirs(STATE_DIR, mode=0o700, exist_ok=True)
        with open(TOKEN_FILE + ".lock", "w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            tok = load_token()                # someone may have just refreshed
            if time.time() >= tok.get("expires_at", 0):
                tok = token_request({"grant_type": "refresh_token",
                                     "refresh_token": tok["refresh_token"]})
    return tok["access_token"]


def api(method, path, retry=True, body=None):
    token = access_token()
    if not token:
        raise ApiError(401, "not logged in")
    headers = {"Authorization": "Bearer " + token}
    data = b"" if method in ("PUT", "POST") else None
    if body is not None:
        data = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request("https://api.spotify.com/v1" + path, method=method,
                                 headers=headers, data=data)
    try:
        with urllib.request.urlopen(req, timeout=8) as r:
            body = r.read()
            if method != "GET" or not body.strip():
                # Commands (play/pause/next/seek) answer 2xx with a body that is
                # not always JSON — seek's isn't. Nothing in it is needed, and
                # parsing it turned every successful scroll into a "Couldn't
                # seek: HTTP 200" notification.
                return None
            try:
                return json.loads(body)
            except ValueError:   # seen now and then: a GET 200 whose body isn't JSON
                raise ApiError(r.status, "unparseable body: " + body[:80].decode(errors="replace"))
    except urllib.error.HTTPError as e:
        if e.code == 401 and retry:          # revoked early — force a refresh once
            tok = load_token()
            tok["expires_at"] = 0
            save_token(tok)
            return api(method, path, retry=False, body=body)
        raise ApiError(e.code, e.read().decode(errors="replace"))


# ── login ──────────────────────────────────────────────────────────────────
def login():
    verifier = secrets.token_urlsafe(64)
    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()
    state = secrets.token_urlsafe(16)
    url = "https://accounts.spotify.com/authorize?" + urllib.parse.urlencode({
        "client_id": CLIENT_ID, "response_type": "code", "redirect_uri": REDIRECT,
        "scope": SCOPES, "state": state,
        "code_challenge_method": "S256", "code_challenge": challenge,
    })
    result = {}

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            if urllib.parse.urlparse(self.path).path != "/callback":
                self.send_response(404)
                self.end_headers()
                return
            ok = q.get("state", [""])[0] == state and "code" in q
            if ok:
                result["code"] = q["code"][0]
            else:
                result["error"] = q.get("error", ["state mismatch"])[0]
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            msg = "Logged in — you can close this tab." if ok else "Login failed: " + html.escape(result["error"])
            self.wfile.write(f"<html><body style='font-family:sans-serif'><h2>{msg}</h2></body></html>".encode())

        def log_message(self, *a):
            pass

    server = HTTPServer(("127.0.0.1", 8888), Handler)
    deadline = time.time() + 300
    subprocess.Popen(["xdg-open", url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    print("Opened the Spotify login in your browser. If it didn't open, visit:\n" + url, flush=True)
    while not result and time.time() < deadline:     # skips favicon & co.
        server.timeout = max(1, deadline - time.time())
        server.handle_request()
    server.server_close()

    if "code" not in result:
        notify("Spotify login failed", result.get("error", "timed out"))
        print("Login failed:", result.get("error", "timed out"), file=sys.stderr)
        return 1
    token_request({"grant_type": "authorization_code", "code": result["code"],
                   "redirect_uri": REDIRECT, "code_verifier": verifier})
    try:
        os.remove(LOGIN_FLAG)
    except OSError:
        pass
    notify("Spotify", "Logged in — remote playback will show in the bar")
    print("Logged in.")
    return 0


# ── status: the bar module is just the login prompt now ────────────────────
def status():
    if not load_token():
        out = {"text": f"{I_SPOTIFY}  log in", "class": "login",
               "tooltip": "Spotify on other devices — click to log in"}
    elif os.path.exists(LOGIN_FLAG):
        out = {"text": f"{I_SPOTIFY}  log in", "class": "login",
               "tooltip": "Spotify login expired — click to log in again"}
    else:
        out = HIDDEN               # playback itself shows in custom/now-playing
    print(json.dumps(out, ensure_ascii=False))


# ── what is playing remotely ───────────────────────────────────────────────
SEEN_FILE = os.path.join(STATE_DIR, "last-seen.json")
LOG_FILE = os.path.join(STATE_DIR, "events.log")


def load_seen():
    try:
        with open(SEEN_FILE) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def save_seen(d):
    os.makedirs(STATE_DIR, mode=0o700, exist_ok=True)
    with open(SEEN_FILE + ".tmp", "w") as f:
        json.dump(d, f)
    os.replace(SEEN_FILE + ".tmp", SEEN_FILE)


def remember(p):
    seen = load_seen() or {}
    seen.update({"item": p["item"], "is_playing": p.get("is_playing", False),
                 "progress_ms": p.get("progress_ms") or 0, "at": time.time()})
    device = (p.get("device") or {}).get("name")
    if device:
        seen["device"] = device
    save_seen(seen)


def still_playing_guess():
    """Last track seen playing, if by its own length it should still be going.
    Spotify gives no end signal for a backgrounded phone, so this is the best
    available; a track change shows up as soon as the API reports again."""
    seen = load_seen()
    if not seen or not seen.get("is_playing") or not seen.get("item"):
        return None
    elapsed_ms = (time.time() - seen["at"]) * 1000
    length = seen["item"].get("duration_ms", 0)
    remaining = length - seen["progress_ms"] - elapsed_ms
    if remaining < -15000:            # a little slack for the next track to register
        return None
    return {"item": seen["item"], "is_playing": True,
            "progress_ms": min(length, seen["progress_ms"] + elapsed_ms)}


def log_source(source):
    """Append to events.log only when where the data comes from changes —
    shows whether the phone really drops off the API when backgrounded."""
    flag = os.path.join(RUNTIME, "spotify-remote.source")
    try:
        with open(flag) as f:
            last = f.read()
    except OSError:
        last = ""
    if last == source:
        return
    with open(flag, "w") as f:
        f.write(source)
    try:
        os.makedirs(STATE_DIR, mode=0o700, exist_ok=True)
        if os.path.exists(LOG_FILE) and os.path.getsize(LOG_FILE) > 200_000:
            os.replace(LOG_FILE, LOG_FILE + ".old")
        with open(LOG_FILE, "a") as f:
            f.write(f"{time.strftime('%F %T')}  {last or '-'} -> {source}\n")
    except OSError:
        pass


def busctl_identity(instance):
    r = subprocess.run(["busctl", "--user", "--json=short", "get-property",
                        "org.mpris.MediaPlayer2." + instance, "/org/mpris/MediaPlayer2",
                        "org.mpris.MediaPlayer2", "Identity"],
                       capture_output=True, text=True)
    try:
        return json.loads(r.stdout)["data"]
    except (ValueError, KeyError):
        return ""


def shown_elsewhere():
    """True when another player already shows this Spotify session, so the
    bridge stays hidden and makes no Web API calls at all:

      * the Spotify app running HERE — unless it is only a mirror of
        playback elsewhere (spotify_where.py: no sound out here), in which
        case the bridge may show that playback in the phone pill, or
      * the phone's Spotify seen by KDE Connect (its player list has Spotify).

    KDE Connect runs over Tailscale and hears from the phone directly:
    play/pause/next/seek round-trip in well under a second, and closed apps
    are caught by kdec-netwatch.py's list refresh. The Web API trails the
    phone by seconds and its commands fail when Android has the app asleep
    (HTTP 502 notifications). So the bridge is only the fallback for when
    KDE Connect can't see the phone's Spotify — not connected, or Spotify
    playing on a speaker / PC.

    (Earlier the bridge superseded KDE Connect's copy, because over
    Bluetooth that copy froze; superseded() in now-playing.py still applies
    if both ever show.)
    """
    r = subprocess.run(["playerctl", "-l"], capture_output=True, text=True)
    if spotify_where.where(r.stdout.split()) == "laptop":
        return True
    return phone_has_spotify() is True


def phone_has_spotify():
    """What KDE Connect says about the phone: True / False whether its current
    player list has Spotify, None when no phone is connected (nothing known).

    The list is kept fresh by kdec-netwatch.py, which re-requests it every
    few seconds while a phone player plays: the phone reports a player's
    changes at once but never that it has closed."""
    r = subprocess.run(["busctl", "--user", "--json=short", "call", "org.kde.kdeconnect",
                        "/modules/kdeconnect", "org.kde.kdeconnect.daemon", "devices", "bb",
                        "true", "true"], capture_output=True, text=True)
    try:
        devices = json.loads(r.stdout)["data"][0]
    except (ValueError, KeyError, IndexError):
        return None
    known = None
    for dev in devices:
        r = subprocess.run(["busctl", "--user", "--json=short", "get-property",
                            "org.kde.kdeconnect", f"/modules/kdeconnect/devices/{dev}/mprisremote",
                            "org.kde.kdeconnect.device.mprisremote", "playerList"],
                           capture_output=True, text=True)
        try:
            names = json.loads(r.stdout)["data"]
        except (ValueError, KeyError):
            continue
        if any(n.lower().startswith("spotify") for n in names):
            return True
        known = False
    return known


def fetch():
    """-> (kind, playback). kind: login | covered | error | none | ok."""
    if not load_token():
        return "login", None
    if shown_elsewhere():
        return "covered", None
    try:
        p = api("GET", "/me/player")
    except (ApiError, urllib.error.URLError, TimeoutError, OSError) as e:
        if isinstance(e, ApiError) and e.status in (400, 401):   # refresh token dead
            return "login", None
        return "error", None                  # offline / 429 / 5xx: keep what we had

    # The phone stops reporting a "player" (204 from /me/player) once Android
    # backgrounds the Spotify app, even though music keeps playing.
    source = "player"
    if not p or not p.get("item"):
        try:
            p = api("GET", "/me/player/currently-playing")
        except (ApiError, urllib.error.URLError, TimeoutError, OSError):
            p = None
        source = "currently-playing"
    # Spotify closed on the phone: its servers keep reporting the session for
    # a while (and the "remembered" guess below would run on to the end of the
    # track). If the phone is connected over KDE Connect and has no Spotify
    # player any more, believe the phone. Only for the phone itself — Spotify
    # on a speaker or a PC is not in the phone's player list either way.
    on_phone = (not p or not (p.get("device") or {}).get("type")
                or p["device"]["type"].lower() == "smartphone")
    gone = on_phone and phone_has_spotify() is False
    if gone:
        p = None
    elif not p or not p.get("item"):
        p = still_playing_guess()
        source = "remembered"
    log_source("closed on phone" if gone else source if p else "none")
    if not p:
        return "none", None
    if source != "remembered":
        remember(p)
    if not (p.get("device") or {}).get("name"):
        p["device"] = {"name": (load_seen() or {}).get("device", "")}
    return "ok", p


# ── controls ───────────────────────────────────────────────────────────────
def notify(summary, body=""):
    subprocess.run(["notify-send", "-a", "Spotify", "-t", "2500", summary, body],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def control(cmd, arg=None):
    """True if Spotify accepted it."""
    try:
        if cmd == "toggle":
            p = api("GET", "/me/player")
            if not p:
                return False
            api("PUT", "/me/player/pause" if p.get("is_playing") else "/me/player/play")
        elif cmd == "play":
            api("PUT", "/me/player/play")
        elif cmd == "pause":
            api("PUT", "/me/player/pause")
        elif cmd == "next":
            api("POST", "/me/player/next")
        elif cmd == "prev":
            api("POST", "/me/player/previous")
        elif cmd == "seek":
            api("PUT", f"/me/player/seek?position_ms={int(arg)}")
        return True
    except ApiError as e:
        if e.status == 403 and "PREMIUM" in e.body.upper():
            notify("Spotify", "Controlling other devices needs Spotify Premium")
        elif e.status == 404:
            notify("Spotify", "Spotify lost the device — open Spotify on it once")
        elif e.status != 401:
            notify("Spotify", f"Couldn't {cmd}: HTTP {e.status}")
    except (urllib.error.URLError, TimeoutError, OSError):
        notify("Spotify", "Offline — couldn't reach Spotify")
    return False


# ── the MPRIS bridge ───────────────────────────────────────────────────────
# Under "kdeconnect." on purpose: kdeconnectd's mpriscontrol plugin offers
# every OTHER local player to the phone as a laptop player to control, and
# skips its own org.mpris.MediaPlayer2.kdeconnect.* ones. Named plain
# "spotifyremote", the phone's own Spotify came back to the phone as a
# "laptop" player — a loop, and a stray Play there resumed Spotify on the
# phone over the YouTube clip that was playing.
BUS_NAME = "org.mpris.MediaPlayer2.kdeconnect.spotifyremote"
MPRIS_PATH = "/org/mpris/MediaPlayer2"
ROOT_IFACE = "org.mpris.MediaPlayer2"
PLAYER_IFACE = "org.mpris.MediaPlayer2.Player"
POLL = 3.0          # seconds between Web API polls (what the old module used)
FAST_POLL = 1.0     # ...for FAST_FOR seconds after anything changed
FAST_FOR = 10.0
NUDGE_DELAY = 0.3   # a burst of MPRIS signals -> one early poll
DEBUG = bool(os.environ.get("SPOTIFY_REMOTE_DEBUG"))   # log every poll to bridge.log
HOLD = 3.0          # after a local play/pause/seek, polls can't override it for this long
TRACK_HOLD = 8.0    # ...and a new song the phone announced, while the API still has the old one
SEEK_DEBOUNCE = 0.35
STALE_AFTER = 60    # API unreachable this long: stop claiming anything is playing

MPRIS_XML = """
<node>
  <interface name="org.mpris.MediaPlayer2">
    <method name="Raise"/>
    <method name="Quit"/>
    <property name="CanQuit" type="b" access="read"/>
    <property name="CanRaise" type="b" access="read"/>
    <property name="HasTrackList" type="b" access="read"/>
    <property name="Identity" type="s" access="read"/>
    <property name="DesktopEntry" type="s" access="read"/>
    <property name="SupportedUriSchemes" type="as" access="read"/>
    <property name="SupportedMimeTypes" type="as" access="read"/>
  </interface>
  <interface name="org.mpris.MediaPlayer2.Player">
    <method name="Next"/>
    <method name="Previous"/>
    <method name="Pause"/>
    <method name="PlayPause"/>
    <method name="Stop"/>
    <method name="Play"/>
    <method name="Seek"><arg direction="in" name="Offset" type="x"/></method>
    <method name="SetPosition">
      <arg direction="in" name="TrackId" type="o"/>
      <arg direction="in" name="Position" type="x"/>
    </method>
    <method name="OpenUri"><arg direction="in" name="Uri" type="s"/></method>
    <signal name="Seeked"><arg name="Position" type="x"/></signal>
    <property name="PlaybackStatus" type="s" access="read"/>
    <property name="Rate" type="d" access="read"/>
    <property name="Metadata" type="a{sv}" access="read"/>
    <property name="Volume" type="d" access="read"/>
    <property name="Position" type="x" access="read"/>
    <property name="MinimumRate" type="d" access="read"/>
    <property name="MaximumRate" type="d" access="read"/>
    <property name="CanGoNext" type="b" access="read"/>
    <property name="CanGoPrevious" type="b" access="read"/>
    <property name="CanPlay" type="b" access="read"/>
    <property name="CanPause" type="b" access="read"/>
    <property name="CanSeek" type="b" access="read"/>
    <property name="CanControl" type="b" access="read"/>
  </interface>
</node>
"""


def bridge():
    lock = os.open(BRIDGE_LOCK, os.O_RDWR | os.O_CREAT, 0o600)
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        print("spotify-remote: bridge already running", file=sys.stderr)
        return 1

    # exec-once drops stderr; keep the worker's complaints somewhere readable.
    os.makedirs(STATE_DIR, mode=0o700, exist_ok=True)
    log = os.path.join(STATE_DIR, "bridge.log")
    if os.path.exists(log) and os.path.getsize(log) > 200_000:
        os.replace(log, log + ".old")
    sys.stderr = open(log, "a", buffering=1)
    print(f"{time.strftime('%F %T')} bridge started", file=sys.stderr)

    import gi
    gi.require_version("Gio", "2.0")
    gi.require_version("GLibUnix", "2.0")
    from gi.repository import Gio, GLib, GLibUnix

    class Bridge:
        def __init__(self):
            self.conn = Gio.bus_get_sync(Gio.BusType.SESSION, None)
            for iface in Gio.DBusNodeInfo.new_for_xml(MPRIS_XML).interfaces:
                self.conn.register_object_with_closures2(MPRIS_PATH, iface, self.on_call,
                                                         self.on_get, None)
            self.owner = 0                       # bus name id while shown
            self.track = None                    # dict, see set_playback()
            self.device = ""
            self.playing = False
            self.pos_us, self.pos_at = 0, time.monotonic()
            self.hold_until = 0.0
            self.seek_timer = 0
            self.last_ok = time.monotonic()
            self.q = queue.Queue()               # commands for the worker
            self.fast_until = 0.0                # poll every FAST_POLL until then
            self.device_type = ""
            self.nudge_timer = 0
            # Any OTHER player changing track / state / position — above all
            # KDE Connect's copy of the phone's Spotify, which the phone
            # pushes the instant something happens — means "ask Spotify now"
            # instead of up to POLL s later, then poll fast for a while (the
            # Web API itself trails the phone by a second or two).
            self.conn.signal_subscribe(None, "org.freedesktop.DBus.Properties",
                                       "PropertiesChanged", MPRIS_PATH, PLAYER_IFACE,
                                       Gio.DBusSignalFlags.NONE, self.on_other_player)
            self.conn.signal_subscribe(None, PLAYER_IFACE, "Seeked", MPRIS_PATH, None,
                                       Gio.DBusSignalFlags.NONE, self.on_other_player)
            threading.Thread(target=self.worker, daemon=True).start()
            GLib.timeout_add(1000, self.reconcile)
            GLib.timeout_add(2000, self.record_last)

        # ── position ──
        def position(self):
            pos = self.pos_us
            if self.playing:
                pos += int((time.monotonic() - self.pos_at) * 1_000_000)
            length = (self.track or {}).get("length", 0)
            return max(0, min(pos, length) if length else pos)

        def set_position(self, us):
            self.pos_us, self.pos_at = int(us), time.monotonic()

        # ── D-Bus properties ──
        def metadata(self):
            t = self.track or {}
            md = {"mpris:trackid": GLib.Variant("o", t.get("trackid", "/org/mpris/MediaPlayer2/TrackList/NoTrack"))}
            if t:
                md["mpris:length"] = GLib.Variant("x", t["length"])
                md["xesam:title"] = GLib.Variant("s", t["title"])
                md["xesam:artist"] = GLib.Variant("as", t["artists"])
                md["xesam:album"] = GLib.Variant("s", t["album"])
                if t["art"]:
                    md["mpris:artUrl"] = GLib.Variant("s", t["art"])
                if t["url"]:
                    md["xesam:url"] = GLib.Variant("s", t["url"])
            return md

        def props(self, iface):
            if iface == ROOT_IFACE:
                ident = f"Spotify - {self.device}" if self.device else "Spotify"
                return {"CanQuit": GLib.Variant("b", False), "CanRaise": GLib.Variant("b", False),
                        "HasTrackList": GLib.Variant("b", False),
                        "Identity": GLib.Variant("s", ident),
                        "DesktopEntry": GLib.Variant("s", "spotify"),
                        "SupportedUriSchemes": GLib.Variant("as", []),
                        "SupportedMimeTypes": GLib.Variant("as", [])}
            has = self.track is not None
            return {"PlaybackStatus": GLib.Variant("s", "Playing" if self.playing else
                                                   ("Paused" if has else "Stopped")),
                    "Rate": GLib.Variant("d", 1.0), "MinimumRate": GLib.Variant("d", 1.0),
                    "MaximumRate": GLib.Variant("d", 1.0), "Volume": GLib.Variant("d", 1.0),
                    "Metadata": GLib.Variant("a{sv}", self.metadata()),
                    "Position": GLib.Variant("x", self.position()),
                    "CanGoNext": GLib.Variant("b", has), "CanGoPrevious": GLib.Variant("b", has),
                    "CanPlay": GLib.Variant("b", has), "CanPause": GLib.Variant("b", has),
                    "CanSeek": GLib.Variant("b", has and self.track["length"] > 0),
                    "CanControl": GLib.Variant("b", True)}

        def on_get(self, _conn, _sender, _path, iface, prop):
            return self.props(iface).get(prop)

        def emit_changed(self, before):
            for iface in (ROOT_IFACE, PLAYER_IFACE):
                now = self.props(iface)
                now.pop("Position", None)        # never signalled (MPRIS spec)
                changed = {k: v for k, v in now.items() if before.get((iface, k)) != v}
                if changed:
                    self.conn.emit_signal(None, MPRIS_PATH, "org.freedesktop.DBus.Properties",
                                          "PropertiesChanged",
                                          GLib.Variant("(sa{sv}as)", (iface, changed, [])))

        def snapshot(self):
            return {(i, k): v for i in (ROOT_IFACE, PLAYER_IFACE)
                    for k, v in self.props(i).items() if k != "Position"}

        def seeked(self):
            self.conn.emit_signal(None, MPRIS_PATH, PLAYER_IFACE, "Seeked",
                                  GLib.Variant("(x)", (self.position(),)))

        # ── D-Bus methods (main thread; never block it — the worker talks HTTP) ──
        def on_call(self, _conn, _sender, _path, iface, method, params, invocation):
            before = self.snapshot()
            if iface == PLAYER_IFACE and self.track:
                kspot = self.kdec_spotify()
                if method in ("PlayPause", "Play", "Pause", "Stop"):
                    want = {"PlayPause": not self.playing, "Play": True}.get(method, False)
                    if want != self.playing:
                        self.set_position(self.position())   # freeze / restart the clock
                        self.playing = want
                        self.hold_until = time.monotonic() + HOLD
                        if kspot:
                            self.kdec_send(kspot, "Play" if want else "Pause")
                        else:
                            self.q.put(("play" if want else "pause", None))
                elif method in ("Next", "Previous"):
                    if kspot:
                        self.kdec_send(kspot, method)
                    else:
                        self.q.put(("next" if method == "Next" else "prev", None))
                elif method in ("Seek", "SetPosition"):
                    if method == "Seek":
                        target = self.position() + params.unpack()[0]
                    else:
                        trackid, target = params.unpack()
                        if trackid != self.track["trackid"]:
                            target = None
                    if target is not None and self.track["length"] > 0:
                        self.set_position(max(0, min(target, self.track["length"] - 1_000_000)))
                        self.hold_until = time.monotonic() + HOLD
                        self.seeked()
                        # A wheel spin is many Seeks: send only where it ends up.
                        if self.seek_timer:
                            GLib.source_remove(self.seek_timer)
                        self.seek_timer = GLib.timeout_add(int(SEEK_DEBOUNCE * 1000), self.send_seek)
            invocation.return_value(None)
            self.emit_changed(before)

        def send_seek(self):
            self.seek_timer = 0
            self.hold_until = time.monotonic() + HOLD
            self.q.put(("seek", self.position() // 1000))
            return False

        # ── worker thread: all HTTP, one request at a time ──
        def worker(self):
            # Anything unexpected (a garbled API body, a full disk…) must not
            # end this loop: once it did, the thread died silently, the last
            # state stayed published forever, and the bridge never stepped
            # aside for KDE Connect's own Spotify player — a duplicate stuck
            # at "Playing", past the end of its track.
            next_poll = 0.0
            while True:
                try:
                    try:
                        cmd, arg = self.q.get(timeout=max(0.0, next_poll - time.monotonic()))
                    except queue.Empty:
                        fast = time.monotonic() < self.fast_until
                        if DEBUG:
                            print(f"{time.strftime('%T')} poll{' (fast)' if fast else ''}",
                                  file=sys.stderr)
                        next_poll = time.monotonic() + (FAST_POLL if fast else POLL)
                        kind, p = fetch()
                        GLib.idle_add(self.apply, kind, p, time.monotonic())
                        continue
                    if cmd == "poll":                       # nudged: poll right away
                        if DEBUG:
                            print(f"{time.strftime('%T')} nudged", file=sys.stderr)
                        next_poll = 0.0
                        continue
                    self.fast_until = time.monotonic() + FAST_FOR
                    if not control(cmd, arg):
                        GLib.idle_add(self.drop_hold)
                    # see the result soon (a skip changes the track)
                    next_poll = min(next_poll, time.monotonic() + 0.8)
                except Exception as exc:                    # noqa: BLE001
                    print(f"spotify-remote: worker: {exc!r}", file=sys.stderr, flush=True)
                    time.sleep(POLL)

        # ── KDE Connect fast path ──
        # When the phone's Spotify is also on KDE Connect (kdeconnect.mpris_*,
        # Identity "Spotify - <phone>"), that copy hears from the phone in a
        # fraction of a second, while Spotify's servers trail the phone by
        # 1-5 s (measured: next/previous took 4-5 s to show through the Web
        # API alone, a pause sent via KDE Connect 2.7 s). So: commands go to
        # the phone through that copy, and its pushes (title, play state) are
        # taken over at once; the Web API is left to supply what KDE Connect
        # gets wrong — the position (see kdec_focus in now-playing.py), the
        # track id, the album art URL — and to confirm.
        def kdec_spotify(self, sender=None):
            """Bus name of KDE Connect's Spotify copy (or the one owned by
            `sender`), or None."""
            try:
                names = self.conn.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus",
                                            "org.freedesktop.DBus", "ListNames", None, None,
                                            Gio.DBusCallFlags.NONE, 500, None).unpack()[0]
                for n in names:
                    if not n.startswith("org.mpris.MediaPlayer2.kdeconnect.mpris_"):
                        continue
                    if sender:
                        owner = self.conn.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus",
                                                    "org.freedesktop.DBus", "GetNameOwner",
                                                    GLib.Variant("(s)", (n,)), None,
                                                    Gio.DBusCallFlags.NONE, 500, None).unpack()[0]
                        if owner != sender:
                            continue
                    ident = self.conn.call_sync(n, MPRIS_PATH, "org.freedesktop.DBus.Properties",
                                                "Get", GLib.Variant("(ss)", (ROOT_IFACE, "Identity")),
                                                None, Gio.DBusCallFlags.NONE, 500, None).unpack()[0]
                    if ident.lower().startswith("spotify"):
                        return n
            except GLib.Error:
                pass
            return None

        def kdec_get(self, name, iface, prop):
            return self.conn.call_sync(name, MPRIS_PATH, "org.freedesktop.DBus.Properties", "Get",
                                       GLib.Variant("(ss)", (iface, prop)), None,
                                       Gio.DBusCallFlags.NONE, 500, None).unpack()[0]

        def kdec_current_is_spotify(self):
            """KDE Connect reports every phone player's Position as that of
            its CURRENT phone player (see kdec_focus in now-playing.py, which
            selects Spotify while the bar shows this bridge). Only then is the
            copy's position Spotify's."""
            try:
                devs = self.conn.call_sync("org.kde.kdeconnect", "/modules/kdeconnect",
                                           "org.kde.kdeconnect.daemon", "devices",
                                           GLib.Variant("(bb)", (True, True)), None,
                                           Gio.DBusCallFlags.NONE, 500, None).unpack()[0]
                for dev in devs:
                    cur = self.conn.call_sync("org.kde.kdeconnect",
                                              f"/modules/kdeconnect/devices/{dev}/mprisremote",
                                              "org.freedesktop.DBus.Properties", "Get",
                                              GLib.Variant("(ss)", ("org.kde.kdeconnect.device.mprisremote",
                                                                    "player")),
                                              None, Gio.DBusCallFlags.NONE, 500, None).unpack()[0]
                    if cur.lower().startswith("spotify"):
                        return True
            except GLib.Error:
                pass
            return False

        def kdec_state(self):
            """{status, title, md, pos (µs or None)} of KDE Connect's Spotify
            copy, or None when there is none."""
            name = self.kdec_spotify()
            if not name:
                return None
            try:
                md = self.kdec_get(name, PLAYER_IFACE, "Metadata")
                st = {"status": self.kdec_get(name, PLAYER_IFACE, "PlaybackStatus"),
                      "title": md.get("xesam:title", ""), "md": md, "pos": None}
                if self.kdec_current_is_spotify():
                    st["pos"] = int(self.kdec_get(name, PLAYER_IFACE, "Position"))
                return st
            except GLib.Error:
                return None

        def kdec_send(self, name, method):
            self.fast_until = time.monotonic() + FAST_FOR      # then confirm via the API
            self.conn.call(name, MPRIS_PATH, PLAYER_IFACE, method, None, None,
                           Gio.DBusCallFlags.NONE, 2000, None, None)

        def adopt(self, changed):
            """Take the phone's push (via KDE Connect) as the truth for now.
            Also runs while the bridge is hidden, so that it comes up with the
            phone's song rather than the API's older one."""
            before = self.snapshot()
            md = changed.get("Metadata") or {}
            title = md.get("xesam:title")
            if title and (not self.track or title != self.track["title"]):
                self.track = {"trackid": "/org/mpris/MediaPlayer2/TrackList/NoTrack",
                              "title": title,
                              "artists": list(md.get("xesam:artist") or []),
                              "album": md.get("xesam:album", ""), "art": "", "url": "",
                              "length": int(md.get("mpris:length") or 0),
                              "provisional": True}           # until the API names it too
                self.set_position(0)
                self.hold_until = time.monotonic() + TRACK_HOLD
            if "PlaybackStatus" in changed and self.track:
                want = changed["PlaybackStatus"] == "Playing"
                if want != self.playing:
                    self.set_position(self.position())
                    self.playing = want
                    self.hold_until = time.monotonic() + HOLD
            self.emit_changed(before)

        def on_other_player(self, _conn, sender, _path, _iface, signal, params):
            if sender == self.conn.get_unique_name():
                return
            if signal == "PropertiesChanged":
                changed = params.unpack()[1]
                if not {"PlaybackStatus", "Metadata"} & set(changed):
                    return
                if self.kdec_spotify(sender):
                    self.adopt(changed)
            elif signal == "Seeked" and self.track and self.owner and self.kdec_spotify(sender) \
                    and self.kdec_current_is_spotify():
                # seeked on the phone: KDE Connect knows in ~0.5 s, the Web API
                # 4-5 s later (measured) — take KDE Connect's position now
                new = params.unpack()[0]
                if abs(new - self.position()) < 1_500_000:
                    return          # the phone confirming a seek we already show
                before = self.snapshot()
                self.set_position(new)
                self.hold_until = time.monotonic() + HOLD
                self.seeked()
                self.emit_changed(before)

        def record_last(self):
            """Every 2 s: remember the last Spotify song and WHERE it played
            (last-played.json, for media-menu.py's "Last played" row and
            `resume`). Sources: this laptop's Spotify app, KDE Connect's copy of
            the phone's, or this bridge (Spotify Connect, any device).

            Spotify mirrors itself — the laptop app shows the phone's song and
            the other way round — so only the copy where the SOUND comes out
            counts (spotify_where.py). A laptop mirror still lends its track
            URI, which the phone's copy doesn't carry."""
            try:
                found = []                     # (playing, kind, device, title, artist, uri)
                mirror = {}                    # laptop app mirroring elsewhere: title -> uri
                names = self.conn.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus",
                                            "org.freedesktop.DBus", "ListNames", None, None,
                                            Gio.DBusCallFlags.NONE, 500, None).unpack()[0]
                insts = [n[len("org.mpris.MediaPlayer2."):] for n in names
                         if n.startswith("org.mpris.MediaPlayer2.")]
                mirrors = spotify_where.hidden(insts)
                for n in names:
                    inst = n[len("org.mpris.MediaPlayer2."):] if n.startswith("org.mpris.MediaPlayer2.") else ""
                    if inst.split(".")[0] == "spotify":
                        kind, device = "laptop", "this laptop"
                    elif inst.startswith("kdeconnect.mpris_"):
                        ident = self.kdec_get(n, ROOT_IFACE, "Identity")
                        if not ident.lower().startswith("spotify"):
                            continue
                        if inst in mirrors:            # the phone mirroring the laptop
                            continue
                        kind, device = "phone", (self.device or ident.partition(" - ")[2])
                    else:
                        continue
                    md = self.kdec_get(n, PLAYER_IFACE, "Metadata")
                    title = md.get("xesam:title", "")
                    if not title:
                        continue
                    uri = ""
                    url = md.get("xesam:url", "")
                    if "open.spotify.com/track/" in url:
                        uri = "spotify:track:" + url.rsplit("/", 1)[-1].split("?")[0]
                    if kind == "laptop" and inst in mirrors:
                        mirror[title] = uri
                        continue
                    found.append((self.kdec_get(n, PLAYER_IFACE, "PlaybackStatus") == "Playing",
                                  kind, device, title, list(md.get("xesam:artist") or []), uri))
                if self.owner and self.track:          # this bridge (Spotify Connect)
                    kind = "phone" if (self.device_type or "smartphone") == "smartphone" else "other"
                    tid = self.track.get("trackid", "").rsplit("/", 1)[-1]
                    found.append((self.playing, kind, self.device, self.track["title"],
                                  self.track["artists"],
                                  f"spotify:track:{tid}" if tid and tid != "NoTrack" else ""))
                if found:
                    found.sort(key=lambda f: not f[0])  # a playing one wins
                    playing, kind, device, title, artists, uri = found[0]
                    last = load_last() or {}
                    rec = {"kind": kind, "device": device, "title": title, "artists": artists,
                           "uri": uri or mirror.get(title)
                           or (last.get("uri") if last.get("title") == title else ""),
                           "at": time.time()}
                    if {k: v for k, v in rec.items() if k != "at"} != \
                            {k: v for k, v in last.items() if k != "at"} or time.time() - last.get("at", 0) > 30:
                        os.makedirs(STATE_DIR, mode=0o700, exist_ok=True)
                        with open(LAST_PLAYED + ".tmp", "w") as f:
                            json.dump(rec, f)
                        os.replace(LAST_PLAYED + ".tmp", LAST_PLAYED)
                # resume mark: Spotify is back -> done; nothing after a while -> give up
                if os.path.exists(RESUME_MARK):
                    try:
                        age = time.time() - os.path.getmtime(RESUME_MARK)
                    except OSError:
                        age = 0
                    if found or age > RESUME_GIVEUP:
                        os.remove(RESUME_MARK)
            except Exception as exc:                    # noqa: BLE001 — never kill the loop
                print(f"spotify-remote: record_last: {exc!r}", file=sys.stderr, flush=True)
            return True

        def reconcile(self):
            """Once a second, while shown: line up with KDE Connect's copy —
            play state, and position when it is trustworthy. Catches what no
            signal announces: KDE Connect only emits Seeked when the phone's
            position differs from what it had locally, so a seek sent through
            it never produces one (measured: such seeks took 4.6-4.8 s to show,
            waiting on the Web API)."""
            if self.owner and self.track and time.monotonic() >= self.hold_until:
                ks = self.kdec_state()
                if ks and ks["title"] == self.track["title"]:
                    before, moved = self.snapshot(), False
                    if (ks["status"] == "Playing") != self.playing:
                        self.set_position(self.position())
                        self.playing = ks["status"] == "Playing"
                    if ks["pos"] is not None and abs(ks["pos"] - self.position()) > 1_500_000:
                        self.set_position(ks["pos"])
                        moved = True
                    self.emit_changed(before)
                    if moved:
                        self.seeked()
            return True
            self.fast_until = time.monotonic() + FAST_FOR
            if not self.nudge_timer:
                self.nudge_timer = GLib.timeout_add(int(NUDGE_DELAY * 1000), self.nudge)

        def nudge(self):
            self.nudge_timer = 0
            self.q.put(("poll", None))
            return False

        def drop_hold(self):
            self.hold_until = 0.0
            return False

        # ── poll results (main thread) ──
        def apply(self, kind, p, fetched_at):
            try:
                self._apply(kind, p, fetched_at)
            except Exception as exc:                        # noqa: BLE001
                print(f"spotify-remote: apply: {exc!r}", file=sys.stderr, flush=True)
            return False

        def _apply(self, kind, p, fetched_at):
            if kind == "login":
                open(LOGIN_FLAG, "w").close()
            elif os.path.exists(LOGIN_FLAG) and kind != "error":
                os.remove(LOGIN_FLAG)
            if kind == "error":                  # keep showing what we had — for a while
                if self.owner and time.monotonic() - self.last_ok > STALE_AFTER:
                    self.track = None
                    self.show(False)
                return
            self.last_ok = time.monotonic()
            if kind != "ok":
                self.track = None
                self.show(False)
                return

            before = self.snapshot()
            item = p["item"]
            if item.get("type") == "episode":
                artists = [(item.get("show") or {}).get("name", "")]
                album = (item.get("show") or {}).get("name", "")
                images = item.get("images") or (item.get("show") or {}).get("images") or []
            else:
                artists = [a["name"] for a in item.get("artists", [])]
                album = (item.get("album") or {}).get("name", "")
                images = (item.get("album") or {}).get("images") or []
            tid = "".join(c for c in (item.get("id") or "") if c.isalnum())
            track = {"trackid": f"/com/spotify/track/{tid}" if tid else
                     "/org/mpris/MediaPlayer2/TrackList/NoTrack",
                     "title": item.get("name", ""), "artists": [a for a in artists if a],
                     "album": album, "art": images[0]["url"] if images else "",
                     "url": (item.get("external_urls") or {}).get("spotify", ""),
                     "length": int(item.get("duration_ms") or 0) * 1000}
            was_playing, jumped = self.playing, False
            confirmed = False
            if self.track and self.track.get("provisional"):
                if track["title"] != self.track["title"]:
                    if time.monotonic() < self.hold_until:
                        self.show(True)          # the servers haven't caught up yet
                        return
                else:
                    confirmed = True             # same song: take the full details
            new_track = not confirmed and (not self.track or self.track["trackid"] != track["trackid"])
            before_track = self.track
            self.track = track
            self.device = (p.get("device") or {}).get("name") or self.device
            self.device_type = ((p.get("device") or {}).get("type") or self.device_type or "").lower()

            server_pos = int(p.get("progress_ms") or 0) * 1000
            server_pos += int((time.monotonic() - fetched_at) * 1_000_000) if p.get("is_playing") else 0
            # KDE Connect's copy of the phone's Spotify hears from the phone
            # directly; the API trails it by seconds. Same song: its play state
            # wins, and its position too when it can be trusted. Different song:
            # the API is behind — keep (or start) the phone's song.
            ks = self.kdec_state()
            if ks and ks["title"] and ks["title"] != track["title"]:
                self.track = before_track
                if not (self.track and self.track["title"] == ks["title"]):
                    self.adopt({"Metadata": ks["md"]})
                self.adopt({"PlaybackStatus": ks["status"]})
                self.show(True)
                return
            if ks:
                p["is_playing"] = ks["status"] == "Playing"
                if ks["pos"] is not None:
                    server_pos = ks["pos"]
            if confirmed:                        # the API's position for the new song
                self.set_position(server_pos)
            if new_track or time.monotonic() >= self.hold_until:
                jumped = abs(server_pos - self.position()) > 3_000_000
                self.playing = bool(p.get("is_playing"))
                self.set_position(server_pos)
                if jumped and not new_track:
                    self.seeked()                # seeked on the phone itself
            if new_track or jumped or was_playing != self.playing:
                self.fast_until = time.monotonic() + FAST_FOR
            self.emit_changed(before)
            self.show(True)

        def show(self, on):
            if on and not self.owner:
                self.owner = Gio.bus_own_name_on_connection(
                    self.conn, BUS_NAME, Gio.BusNameOwnerFlags.NONE, None, None)
            elif not on and self.owner:
                Gio.bus_unown_name(self.owner)
                self.owner = 0

    try:                                         # the old module's flag, now unused
        os.remove(os.path.join(RUNTIME, "spotify-remote.active"))
    except OSError:
        pass
    Bridge()
    loop = GLib.MainLoop()
    GLibUnix.signal_add(GLib.PRIORITY_DEFAULT, 15, loop.quit)    # SIGTERM
    GLibUnix.signal_add(GLib.PRIORITY_DEFAULT, 2, loop.quit)     # SIGINT
    loop.run()
    return 0


# ── "Last played" → play again where it last played ─────────────────────────
def load_last():
    try:
        with open(LAST_PLAYED) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def players():
    return subprocess.run(["playerctl", "-l"], capture_output=True, text=True).stdout.split()


def wait_for(check, timeout, step=0.5):
    end = time.time() + timeout
    while time.time() < end:
        v = check()
        if v:
            return v
        time.sleep(step)
    return None


def api_device(want_type=None, want_name=None):
    try:
        devs = (api("GET", "/me/player/devices") or {}).get("devices") or []
    except (ApiError, urllib.error.URLError, TimeoutError, OSError):
        return None
    for d in devs:
        if want_name and d.get("name") == want_name:
            return d
    for d in devs:
        if want_type and (d.get("type") or "").lower() == want_type:
            return d
    return None


def transfer_and_play(dev):
    """Move Spotify's remembered playback (the last song, where it stopped)
    to `dev` and start it. Without a context of its own a freshly opened app
    would otherwise just sit there."""
    try:
        api("PUT", "/me/player", body={"device_ids": [dev["id"]], "play": True})
    except ApiError:
        api("PUT", f"/me/player/play?device_id={dev['id']}")


def resume_laptop():
    if not any(p.split(".")[0] == "spotify" for p in players()):
        subprocess.Popen(["hyprctl", "dispatch", "exec", "/usr/bin/spotify"],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    sp = wait_for(lambda: next((p for p in players() if p.split(".")[0] == "spotify"), None), 30)
    if not sp:
        return False
    # the app restores its last song a moment after its player appears
    wait_for(lambda: subprocess.run(["playerctl", "-p", sp, "metadata", "title"],
                                    capture_output=True, text=True).stdout.strip(), 10)
    subprocess.run(["playerctl", "-p", sp, "play"])
    if wait_for(lambda: subprocess.run(["playerctl", "-p", sp, "status"], capture_output=True,
                                       text=True).stdout.strip() == "Playing", 5):
        return True
    dev = api_device(want_type="computer")       # app up but idle: via Spotify Connect
    if dev:
        transfer_and_play(dev)
        return True
    return False


def kdec_spotify_player():
    """KDE Connect's copy of the phone's Spotify (exists once the app runs)."""
    return next((p for p in players() if p.startswith("kdeconnect.mpris_")
                 and busctl_identity(p).lower().startswith("spotify")), None)


RESUME_SETTLE = 4      # s to let a freshly started Spotify finish starting up
RESUME_PING = "spotify-resume"   # KDE Connect ping text the phone's MacroDroid macro reacts to
RESUME_LINK_AFTER = 10           # s without Spotify before the tap-to-open link goes too


def resume_phone(last):
    # Spotify still has a session on the phone (KDE Connect shows it): just play.
    p = kdec_spotify_player()
    if p:
        subprocess.run(["playerctl", "-p", p, "play"])
        return True

    # One try through Spotify Connect, for an app that is alive in the
    # background (listed AND reachable). Asleep/closed it answers 404 / 502
    # (measured) and nothing happens on the phone.
    dev = api_device(want_type="smartphone", want_name=last.get("device"))
    if dev:
        try:
            transfer_and_play(dev)
            return True
        except ApiError:
            pass

    # Start the app. First a KDE Connect ping "spotify-resume": a MacroDroid
    # macro on the phone opens Spotify and presses play when it sees that
    # notification (Android won't let KDE Connect itself open an app from the
    # background — a shared link only becomes a tap-to-open notification).
    # If Spotify isn't up after RESUME_LINK_AFTER s (no macro / it didn't
    # run), send the link as well: one tap on that pop-up opens Spotify.
    url = "https://open.spotify.com/"
    if (last.get("uri") or "").startswith("spotify:track:"):
        url += "track/" + last["uri"].split(":")[-1]
    pinged, shared = set(), set()
    started = time.time()

    def nudge_phones():
        """Ping (and later share to) every phone KDE Connect can reach that
        hasn't had it yet — a phone that comes back mid-wait (restarting)
        still gets them."""
        late = time.time() - started >= RESUME_LINK_AFTER
        for d in subprocess.run(["kdeconnect-cli", "-a", "--id-only"], capture_output=True,
                                text=True).stdout.split():
            if d not in pinged:
                pinged.add(d)
                subprocess.run(["kdeconnect-cli", "-d", d, "--ping-msg", RESUME_PING],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if late and d not in shared:
                shared.add(d)
                subprocess.run(["kdeconnect-cli", "-d", d, "--share", url],
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def app_up():
        nudge_phones()
        return kdec_spotify_player()

    # Then wait for Spotify to actually be RUNNING there — its player showing
    # up in KDE Connect — and send ONE play. Hammering it with Spotify Connect
    # "play here" requests every 2 s while it was still starting (the old way)
    # left the app holding a song it could not play, until force-stopped.
    p = wait_for(app_up, 20, 1)
    if not p:
        notify("Spotify", f"Open Spotify on {last.get('device') or 'your phone'} — "
                          "the last song will start")
        p = wait_for(app_up, 90, 1)
    if not p:
        return False
    time.sleep(RESUME_SETTLE)
    p = kdec_spotify_player() or p
    subprocess.run(["playerctl", "-p", p, "play"])      # the app restored its last song
    if wait_for(lambda: subprocess.run(["playerctl", "-p", p, "status"], capture_output=True,
                                       text=True).stdout.strip() == "Playing", 6):
        return True
    # Up but idle (no song loaded): one Spotify Connect request, not a loop.
    dev = api_device(want_type="smartphone", want_name=last.get("device"))
    if dev:
        try:
            transfer_and_play(dev)
            return True
        except ApiError:
            pass
    return False


def resume():
    """media-menu.py's "Last played" row: play the last Spotify song on the
    device it last played on — this laptop's app, or the phone."""
    last = load_last()
    if not last:
        notify("Spotify", "Nothing played yet to resume")
        return 1
    with open(RESUME_MARK, "w") as f:
        f.write(str(time.time()))
    where = "this laptop" if last.get("kind") == "laptop" else (last.get("device") or "your phone")
    try:
        ok = resume_laptop() if last.get("kind") == "laptop" else resume_phone(last)
    except (ApiError, urllib.error.URLError, TimeoutError, OSError) as e:
        print(f"{time.strftime('%F %T')} resume: {e!r}", file=sys.stderr)
        ok = False
    if not ok:
        try:
            os.remove(RESUME_MARK)               # let the row come back
        except OSError:
            pass
        notify("Spotify", f"Couldn't start Spotify on {where}")
        return 1
    return 0


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
    if cmd == "status":
        status()
    elif cmd == "mpris":
        sys.exit(bridge())
    elif cmd == "login":
        sys.exit(login())
    elif cmd == "click":                     # the bar's on-click
        sys.exit(login() if not load_token() else (control("toggle") and 0))
    elif cmd in ("toggle", "next", "prev"):
        control(cmd)
    elif cmd == "resume":                    # media-menu.py's "Last played" row
        sys.exit(resume())
    else:
        print(__doc__, file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
