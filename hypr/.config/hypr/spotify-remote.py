#!/usr/bin/env python3
"""Spotify's Web API, for what KDE Connect can't do — nothing is polled.

    spotify-remote.py record        the recorder (exec-once from hyprland.conf):
                                    remembers the last Spotify song, over D-Bus
    spotify-remote.py resume        play that song again where it last played
                                    (the players deck's / media menu's Resume)
    spotify-remote.py status        JSON for the bar's Spotify pill — only ever
                                    a "log in" prompt
    spotify-remote.py watch [SEC]   `status` every SEC s (3), a line per change (bar pill)
    spotify-remote.py login         one-time browser login
    spotify-remote.py api-stats [H] the request log of the last H hours (24), summed up

The phone's Spotify reaches the bar through KDE Connect (kdeconnect.mpris_*).
KDE Connect can't report or change shuffle / repeat, and can't start Spotify
on the phone, so those two go through the Web API — on demand only:

  * ⇄ ⟲ (media_modes.py): read when the phone's song or play state changes,
    and on a click. Only while KDE Connect shows the phone's Spotify.
  * Resume (`resume`): a request or two per click.

Until 2026-11-09 a bridge (`mpris`) also republished Spotify on ANY device as
an MPRIS player by asking the Web API every 3 s. It was rate limited for
hours, twice (~2,400 requests an hour, mostly "nothing playing"), and showed
little KDE Connect doesn't, so it is gone; `record` keeps its one other job.

Every request is logged (log_request) and a 429 stops all of them for as long
as Spotify says (Retry-After, check_backoff).

Login is Authorization Code + PKCE: no client secret, just the client ID of the
developer app (redirect URI http://127.0.0.1:8888/callback — Spotify rejects
"localhost"). Tokens live in ~/.local/state/spotify-remote/token.json (0600);
the refresh token rotates on every refresh, so it is re-saved each time — and
refreshed under a lock, since two refreshes racing would burn it.

Standard library + PyGObject (Gio) for the recorder.
"""

import base64
import fcntl
import hashlib
import html
import json
import os
import secrets
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

import kdec_link       # same directory: is the KDE Connect link to the phone usable?
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
# Set when the refresh token is dead (access_token); `status` then shows "log in".
LOGIN_FLAG = os.path.join(RUNTIME, "spotify-remote.login")
# The last Spotify song and where it played — for media-menu.py's "Last
# played" row (written by the recorder, see recorder()).
LAST_PLAYED = os.path.join(STATE_DIR, "last-played.json")
# Set by `resume` (the row was clicked): media-menu.py hides the row until
# Spotify has played and stopped again (the recorder clears it once it sees
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


# ── rate limit (HTTP 429), shared by every Web API user ────────────────────
# Spotify answers 429 with Retry-After — once measured at 36979 s (~10 h,
# "QUOTA_EXCEEDED") after the bar had polled shuffle / repeat every 1.5 s
# all day. Asking again before then gets nothing but more 429s, so every
# caller (this file's api(), media_modes.Api, the bridge, clicks) checks one
# file first: until the time in it, requests fail at once, without the network.
# In STATE_DIR, not $XDG_RUNTIME_DIR: a ban outlasts a reboot (2026-11-08: the
# runtime copy vanished with a reboot mid-ban, and the first request after
# login was refused again).
BACKOFF_FILE = os.path.join(STATE_DIR, "api-backoff")


def backoff_left():
    """-> seconds until the Web API may be asked again (0 = now)."""
    try:
        with open(BACKOFF_FILE) as f:
            return max(0.0, float(f.read().strip() or 0) - time.time())
    except (OSError, ValueError):
        return 0.0


def note_429(retry_after):
    """A 429 came back: no requests for Retry-After seconds (60 if missing)."""
    try:
        wait = float(retry_after) if retry_after else 60.0
    except ValueError:
        wait = 60.0
    try:
        tmp = BACKOFF_FILE + ".tmp"
        with open(tmp, "w") as f:
            f.write(str(time.time() + max(1.0, wait)))
        os.replace(tmp, BACKOFF_FILE)
    except OSError:
        pass


def check_backoff():
    left = backoff_left()
    if left > 0:
        raise ApiError(429, f"rate limited by Spotify, {int(left)} s left")


# ── request log (2026-11-08: how many requests really go out?) ─────────────
# Every request that reaches Spotify — Web API and token refreshes, from any
# process — is one line in API_LOG:
#     2026-11-08T05:30:01.234  now-playing:remote  GET /me/player  200  142ms
# (status "ERR" = no answer: offline / timeout). Requests stopped by the
# backoff above never leave, so they aren't logged. Kept under ~2 MB (one
# old copy, .1). `spotify-remote.py api-stats [HOURS]` sums it up.
API_LOG = os.path.join(STATE_DIR, "api.log")
API_LOG_MAX = 2_000_000


def _caller():
    name = os.path.basename(sys.argv[0]).removesuffix(".py") if sys.argv else "?"
    if name == "now-playing" and "--scope" in sys.argv:
        i = sys.argv.index("--scope")
        return f"now-playing:{sys.argv[i + 1]}" if i + 1 < len(sys.argv) else name
    if name == "spotify-remote" and len(sys.argv) > 1:
        return "recorder" if sys.argv[1] in ("record", "mpris") else f"spotify-remote:{sys.argv[1]}"
    return name


def log_request(method, path, status, started):
    ms = int((time.monotonic() - started) * 1000)
    now = time.time()
    stamp = time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(now)) + f".{int(now % 1 * 1000):03d}"
    line = f"{stamp}  {_caller()}  {method} {path.split('?')[0]}  {status}  {ms}ms\n"
    try:
        os.makedirs(STATE_DIR, mode=0o700, exist_ok=True)
        if os.path.exists(API_LOG) and os.path.getsize(API_LOG) > API_LOG_MAX:
            os.replace(API_LOG, API_LOG + ".1")
        fd = os.open(API_LOG, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
        try:
            os.write(fd, line.encode())             # one write: lines from several processes don't mix
        finally:
            os.close(fd)
    except OSError:
        pass


def api_stats(hours=24.0):
    """Print what API_LOG says about the last HOURS: totals per caller and
    per hour, the busiest 30 s window (Spotify counts over a rolling 30 s),
    and every 429."""
    import collections
    import datetime
    since = time.time() - hours * 3600
    rows = []
    for path in (API_LOG + ".1", API_LOG):
        try:
            with open(path) as f:
                for ln in f:
                    parts = ln.split()
                    if len(parts) < 6:
                        continue
                    try:
                        t = datetime.datetime.strptime(parts[0], "%Y-%m-%dT%H:%M:%S.%f").timestamp()
                    except ValueError:
                        continue
                    if t >= since:
                        rows.append((t, parts[1], parts[2] + " " + parts[3], parts[4]))
        except OSError:
            pass
    rows.sort()
    if not rows:
        print(f"No Spotify requests logged in the last {hours:g} h ({API_LOG}).")
        return
    span = max(rows[-1][0] - rows[0][0], 1)
    print(f"Spotify requests, last {hours:g} h: {len(rows)}"
          f"  (first {time.strftime('%F %T', time.localtime(rows[0][0]))},"
          f" avg {len(rows) / span * 60:.1f}/min over the logged span)")
    print("\nBy caller:")
    for who, n in collections.Counter(r[1] for r in rows).most_common():
        print(f"  {n:6d}  {who}")
    print("\nBy request:")
    for what, n in collections.Counter(r[2] for r in rows).most_common(8):
        print(f"  {n:6d}  {what}")
    print("\nPer hour:")
    for h, n in sorted(collections.Counter(time.strftime("%F %H:00", time.localtime(r[0])) for r in rows).items()):
        print(f"  {h}  {n:5d}")
    best, j = (0, 0.0), 0
    for i in range(len(rows)):
        while rows[i][0] - rows[j][0] > 30:
            j += 1
        if i - j + 1 > best[0]:
            best = (i - j + 1, rows[j][0])
    print(f"\nBusiest 30 s: {best[0]} requests, from {time.strftime('%F %T', time.localtime(best[1]))}")
    limited = [r for r in rows if r[3] == "429"]
    print(f"429 (too many requests): {len(limited)}"
          + (f", first {time.strftime('%F %T', time.localtime(limited[0][0]))}" if limited else ""))
    left = backoff_left()
    if left > 0:
        print(f"Backoff now: {int(left)} s left (until {time.strftime('%T', time.localtime(time.time() + left))})")


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
    started = time.monotonic()
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            log_request("POST", "/api/token", r.status, started)
            return save_token(json.load(r))
    except urllib.error.HTTPError as e:
        log_request("POST", "/api/token", e.code, started)
        raise ApiError(e.code, e.read().decode(errors="replace"))
    except (urllib.error.URLError, TimeoutError, OSError):
        log_request("POST", "/api/token", "ERR", started)
        raise


def access_token():
    tok = load_token()
    if not tok or not tok.get("refresh_token"):
        return None
    if time.time() >= tok.get("expires_at", 0):
        # The bar's ⇄ ⟲ reads and a click can both get here; the refresh token
        # rotates, so the loser of an unlocked race would kill the login.
        os.makedirs(STATE_DIR, mode=0o700, exist_ok=True)
        with open(TOKEN_FILE + ".lock", "w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            tok = load_token()                # someone may have just refreshed
            if time.time() >= tok.get("expires_at", 0):
                try:
                    tok = token_request({"grant_type": "refresh_token",
                                         "refresh_token": tok["refresh_token"]})
                except ApiError as e:
                    if e.status in (400, 401):    # refresh token dead: the pill asks to log in
                        open(LOGIN_FLAG, "w").close()
                    raise
                try:
                    os.remove(LOGIN_FLAG)
                except OSError:
                    pass
    return tok["access_token"]


def api(method, path, retry=True, body=None):
    check_backoff()
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
    started = time.monotonic()
    try:
        with urllib.request.urlopen(req, timeout=8) as r:
            log_request(method, path, r.status, started)
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
        log_request(method, path, e.code, started)
        if e.code == 429:
            note_429(e.headers.get("Retry-After"))
        if e.code == 401 and retry:          # revoked early — force a refresh once
            tok = load_token()
            tok["expires_at"] = 0
            save_token(tok)
            return api(method, path, retry=False, body=body)
        raise ApiError(e.code, e.read().decode(errors="replace"))
    except (urllib.error.URLError, TimeoutError, OSError):
        log_request(method, path, "ERR", started)
        raise


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


# ── helpers ────────────────────────────────────────────────────────────────
def busctl_identity(instance):
    r = subprocess.run(["busctl", "--user", "--json=short", "get-property",
                        "org.mpris.MediaPlayer2." + instance, "/org/mpris/MediaPlayer2",
                        "org.mpris.MediaPlayer2", "Identity"],
                       capture_output=True, text=True)
    try:
        return json.loads(r.stdout)["data"]
    except (ValueError, KeyError):
        return ""


def notify(summary, body=""):
    subprocess.run(["notify-send", "-a", "Spotify", "-t", "2500", summary, body],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


# ── the recorder: remembers the last Spotify song (for `resume`) ────────────
# Replaced the Web API bridge on 2026-11-09. The bridge asked Spotify what was
# playing every 3 s (two requests when nothing was: ~2,400 an hour), got the
# app rate-limited for hours twice, and only added what KDE Connect already
# shows. This reads the same players over D-Bus instead: no Web API at all.
RECORDER_LOCK = os.path.join(RUNTIME, "spotify-remote.record.lock")
RECORD_EVERY = 2          # s
MPRIS_PATH = "/org/mpris/MediaPlayer2"
ROOT_IFACE = "org.mpris.MediaPlayer2"
PLAYER_IFACE = "org.mpris.MediaPlayer2.Player"


def recorder():
    lock = os.open(RECORDER_LOCK, os.O_RDWR | os.O_CREAT, 0o600)
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        print("spotify-remote: recorder already running", file=sys.stderr)
        return 1
    # exec-once drops stderr; keep complaints somewhere readable.
    os.makedirs(STATE_DIR, mode=0o700, exist_ok=True)
    log = os.path.join(STATE_DIR, "recorder.log")
    if os.path.exists(log) and os.path.getsize(log) > 200_000:
        os.replace(log, log + ".old")
    sys.stderr = open(log, "a", buffering=1)
    print(f"{time.strftime('%F %T')} recorder started", file=sys.stderr)

    import gi
    gi.require_version("Gio", "2.0")
    gi.require_version("GLibUnix", "2.0")
    from gi.repository import Gio, GLib, GLibUnix
    conn = Gio.bus_get_sync(Gio.BusType.SESSION, None)

    def get(name, iface, prop):
        return conn.call_sync(name, MPRIS_PATH, "org.freedesktop.DBus.Properties", "Get",
                              GLib.Variant("(ss)", (iface, prop)), None,
                              Gio.DBusCallFlags.NONE, 500, None).unpack()[0]

    def record_last():
        """Every RECORD_EVERY s: remember the last Spotify song and WHERE it
        played (last-played.json, for the "Resume" button / media-menu.py's
        "Last played" row and `resume`). Sources: this laptop's Spotify app
        and KDE Connect's copy of the phone's.

        Spotify mirrors itself — the laptop app shows the phone's song and
        the other way round — so only the copy where the SOUND comes out
        counts (spotify_where.py). A laptop mirror still lends its track
        URI, which the phone's copy doesn't carry."""
        try:
            found = []                     # (playing, kind, device, title, artists, uri)
            mirror = {}                    # laptop app mirroring elsewhere: title -> uri
            names = conn.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus",
                                   "org.freedesktop.DBus", "ListNames", None, None,
                                   Gio.DBusCallFlags.NONE, 500, None).unpack()[0]
            insts = [n[len("org.mpris.MediaPlayer2."):] for n in names
                     if n.startswith("org.mpris.MediaPlayer2.")]
            mirrors = spotify_where.hidden(insts)
            for inst in insts:
                n = "org.mpris.MediaPlayer2." + inst
                if inst.split(".")[0] == "spotify":
                    kind, device = "laptop", "this laptop"
                elif inst.startswith("kdeconnect.mpris_"):
                    ident = get(n, ROOT_IFACE, "Identity")
                    if not ident.lower().startswith("spotify") or inst in mirrors:
                        continue                   # not Spotify / the phone mirroring the laptop
                    kind, device = "phone", ident.partition(" - ")[2]
                else:
                    continue
                md = get(n, PLAYER_IFACE, "Metadata")
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
                found.append((get(n, PLAYER_IFACE, "PlaybackStatus") == "Playing",
                              kind, device, title, list(md.get("xesam:artist") or []), uri))
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

    GLib.timeout_add(RECORD_EVERY * 1000, record_last)
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
    # Not over a bad link (kdec_link.py) — the play would never arrive.
    p = kdec_spotify_player() if kdec_link.healthy() else None
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
    elif cmd == "watch":                     # the bar: `status` on a timer, in one process
        import barwatch
        barwatch.run(status, float(sys.argv[2]) if len(sys.argv) > 2 else 3)
    elif cmd in ("record", "mpris"):         # (mpris: the old bridge's name, from an old exec-once)
        sys.exit(recorder())
    elif cmd == "login":
        sys.exit(login())
    elif cmd == "api-stats":                 # the request log, summed up (see log_request)
        api_stats(float(sys.argv[2]) if len(sys.argv) > 2 else 24.0)
    elif cmd == "click":                     # the old waybar module's on-click
        sys.exit(login() if not load_token() else 0)
    elif cmd == "resume":                    # media-menu.py's "Last played" row
        sys.exit(resume())
    else:
        print(__doc__, file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
