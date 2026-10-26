#!/usr/bin/python3
"""Media dropdown — SUPER+M, the chevron next to the player in the bottom
bar, and right-click on the player. Run again while open = close (toggle).

Top section: every MPRIS player that exists right now (Spotify, Firefox /
Brave / Chromium tabs, mpv, the phone's apps via KDE Connect, …) with its play
state and what it is playing. Picking one toggles play/pause on THAT player —
the bar's own module only ever controls one. Exception: a Firefox YouTube
tab ("YouTube · tab", one row per tab, from the mpris-position extension)
switches Firefox to that tab instead, and the bar then shows it. "Pause everything" appears while
anything is playing. Bottom section: launchers for Spotify / YouTube (a
Firefox tab) / YouTube Music (the Pear Desktop app).

COLOUR CODING, AS IN THE BAR
Spotify green · YouTube apps (the phone's YouTube / Morphe) red ·
Firefox peach (that includes YouTube tabs) · YouTube Music
pink · anything else blue · nothing-to-show grey. The phone's players are
classified by their MPRIS Identity ("YouTube Morphe - My Phone"), the
same rule as now-playing.py, because their bus name is only
kdeconnect.mpris_<id>.

WHY GTK AND NOT fuzzel ANY MORE
This used to be `fuzzel --dmenu`. fuzzel draws every row's text in one colour
(no markup), so the colour coding could only ever be carried by row icons.
A small GTK window can colour the text itself. It keeps fuzzel's feel: type to
filter, ↑/↓ + Enter, click a row, Escape (or clicking elsewhere) closes, and
it sits bottom-left above the bar (windowrule `media-menu` in hyprland.conf).

Deliberately a normal toplevel window, like network-panel.py and tasks.py:
layer surfaces on this setup have cost real time. app_id from set_prgname().
"""

import fcntl
import json
import os
import signal
import subprocess
import sys

import spotify_where   # same directory: which Spotify copy is only a mirror

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")       # pin BEFORE importing — see network-panel.py
gi.require_version("GdkPixbuf", "2.0")

from gi.repository import GLib  # noqa: E402

GLib.set_prgname("media-menu")         # app_id; must precede the Gtk/Gdk import

from gi.repository import Gdk, GdkPixbuf, Gtk, Pango  # noqa: E402

ICONS = os.path.expanduser("~/.config/hypr/icons/media")
FOCUS = os.path.expanduser("~/.config/hypr/focus-or-launch.sh")
BROWSER = os.path.expanduser("~/.local/opt/zen/zen")   # the default browser (Zen)
LOCK = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "media-menu.lock")

# Catppuccin Mocha, as waybar/bottom.css.
BASE, MANTLE, SURFACE0 = "#1e1e2e", "#181825", "#313244"
TEXT, SUBTEXT, OVERLAY = "#cdd6f4", "#a6adc8", "#6c7086"
# "youtube" is a dimmed red rather than Mocha's own (#f38ba8), which sits too
# close to the YouTube Music pink to tell apart at a glance.
COLOURS = {"spotify": "#a6e3a1", "youtube": "#bf616a", "firefox": "#fab387", "zen": "#cba6f7",
           "ytmusic": "#f5c2e7", "other": "#89b4fa", "muted": OVERLAY}
# "other" (any player without a colour of its own, and "Last played") is the
# accent, like the bar's player pill. The menu is a fresh process on every
# open, so reading it once here follows SUPER+ALT+C. Its icons are drawn in
# Mocha blue and recoloured when loaded (row_icon).
ICON_BLUE = "#89b4fa"


def _accent():
    try:
        with open(os.path.expanduser("~/.config/hypr/theme/accent")) as f:
            hex_ = f.read().strip()
        int(hex_, 16)
        return "#" + hex_ if len(hex_) == 6 else None
    except (OSError, ValueError):
        return None


COLOURS["other"] = _accent() or COLOURS["other"]

I_MENU = "\U000F0CB8"                  # md-playlist_music


# ── single instance: a second launch closes the first ─────────────────────

def _rice_subst(css):
    """Desktop THEMES (SUPER+SHIFT+T): this CSS is written in Catppuccin Mocha;
    recolour it into the current theme (rice-theme.py palette substitution)."""
    try:
        import importlib.util
        import os as _os
        spec = importlib.util.spec_from_file_location(
            "rice_theme", _os.path.expanduser("~/.config/hypr/rice-theme.py"))
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return mod.subst(css, mod.current())
    except Exception:              # noqa: BLE001 — fall back to Mocha
        return css

def toggle_or_claim():
    """Hold an flock for our lifetime. If someone else holds it, a panel is
    open: close it and report True so this launch just exits. A lock rather
    than `pgrep -f`, which matches any shell that merely mentions the name
    (see the landmine in dock-toggle.sh)."""
    fd = os.open(LOCK, os.O_RDWR | os.O_CREAT, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        pid = os.pread(fd, 32, 0).decode().strip()
        if pid.isdigit():
            try:
                os.kill(int(pid), signal.SIGTERM)
            except ProcessLookupError:
                pass
        return True
    os.ftruncate(fd, 0)
    os.pwrite(fd, str(os.getpid()).encode(), 0)
    toggle_or_claim.fd = fd            # keep it open (and locked) until exit
    return False


# ── players ────────────────────────────────────────────────────────────────
def run(*cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    # rstrip("\n"), not strip(): Python counts the \x1f field separator as
    # whitespace, so strip() ate a trailing EMPTY field (no URL, no artist)
    # and the row was dropped as malformed.
    return r.stdout.rstrip("\n") if r.returncode == 0 else ""


def identity(instance):
    out = run("busctl", "--user", "--json=short", "get-property",
              "org.mpris.MediaPlayer2." + instance, "/org/mpris/MediaPlayer2",
              "org.mpris.MediaPlayer2", "Identity")
    try:
        return json.loads(out)["data"]
    except (ValueError, KeyError):
        return ""


# spotify-remote.py's Web API bridge. Its bus name sits under "kdeconnect." so
# kdeconnectd doesn't echo it back to the phone — check for it BEFORE the
# generic kdeconnect (= phone) rules.
BRIDGE = "kdeconnect.spotifyremote"


def superseded(inst, players):
    """KDE Connect's copy of the phone's Spotify, while spotify-remote.py's
    bridge (BRIDGE, from the Web API) is up: the bridge is always
    current, the copy can be frozen (KDE Connect over Bluetooth only reports
    on connect). Same rule in media-menu.py and media-prefer-playing.sh."""
    return (inst.startswith("kdeconnect.") and inst != BRIDGE and BRIDGE in players
            and identity(inst).lower().startswith("spotify"))


def classify_phone(ident):
    app = ident.lower()
    if app.startswith("spotify"):
        return "spotify"
    if "youtube music" in app or "yt music" in app:
        return "ytmusic"
    if "youtube" in app:
        return "youtube"
    return "other"


def describe(instance, url):
    """-> (display name, colour key). Same mapping as the bar's player
    (now-playing.py; colours in waybar/bottom.css)."""
    p = instance.split(".")[0]
    if instance == BRIDGE:                  # Web API bridge, spotify-remote.py
        device = identity(instance).partition(" - ")[2]
        return f"Spotify · {device or 'Remote'}", "spotify"
    if p == "kdeconnect":
        ident = identity(instance)          # "Spotify - My Phone"
        return f"{ident.partition(' - ')[0] or 'Phone'} · Phone", classify_phone(ident)
    if p.lower().startswith("youtubemusic") or p.startswith("youtube-music"):
        return "YouTube Music", "ytmusic"
    if p == "firefox" and gecko(instance) == "zen":
        p = "zen"
    colour = {"spotify": "spotify", "firefox": "firefox", "zen": "zen"}.get(p, "other")
    # YouTube tabs are named as such when the browser exposes the URL
    # (Chromium-based ones do; Firefox usually not).
    if "music.youtube.com" in url:
        return "YouTube Music", colour
    if "youtube.com" in url or "youtu.be" in url:
        return "YouTube", colour
    names = {"spotify": "Spotify", "firefox": "Firefox", "zen": "Zen", "brave": "Brave",
             "chromium": "Chromium"}
    return names.get(p, p[:1].upper() + p[1:]), colour


SPOTIFY_REMOTE = os.path.expanduser("~/.config/hypr/spotify-remote.py")
LAST_PLAYED = os.path.expanduser("~/.local/state/spotify-remote/last-played.json")
RESUME_MARK = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "spotify-resume.pending")


def is_spotify(inst):
    name = inst.split(".")[0]
    return (name == "spotify" or inst == BRIDGE
            or (name == "kdeconnect" and identity(inst).lower().startswith("spotify")))


def last_played_row(players):
    """Blue "Last played" row — only while there is no Spotify player at all
    (laptop app, phone via KDE Connect, or the Web API bridge). Clicking runs
    `spotify-remote.py resume`, which plays it on the device it last played
    on; the row then stays away (RESUME_MARK) until Spotify has played and
    stopped again — the bridge clears the mark when it sees Spotify, or after
    150 s if nothing started. Recorded by the bridge (record_last)."""
    if any(is_spotify(p) for p in players) or os.path.exists(RESUME_MARK):
        return None
    try:
        with open(LAST_PLAYED) as f:
            last = json.load(f)
    except (OSError, ValueError):
        return None
    if not last.get("title"):
        return None
    where = {"laptop": "Laptop", "phone": "Phone"}.get(last.get("kind"), last.get("device") or "Spotify")
    detail = last["title"]
    if last.get("artists"):
        detail += " · " + ", ".join(last["artists"])
    if len(detail) > 52:
        detail = detail[:51] + "…"
    return (f"Last played · {where}", detail, "other", "open",
            ["/usr/bin/python3", SPOTIFY_REMOTE, "resume"])


# Firefox tabs: one player per YouTube tab, "firefox.tab_<id>", from the
# mpris-position extension's native host (~/.local/share/firefox-mpris-position/
# host.py), which also names the tab you're on (the one the bar shows).
# Zen Browser runs the same extension: "zen.tab_<id>", zen-tabs.current.
GECKO = ("firefox", "zen")
RT_DIR = os.environ.get("XDG_RUNTIME_DIR", "/tmp")


def gecko(inst):
    """"firefox" / "zen" for that browser's players, else None. Zen's OWN
    player is named firefox.instance_* too (Gecko hard-codes it); only its
    Identity ("Mozilla zen") tells them apart."""
    b = inst.split(".")[0]
    if b == "firefox" and inst.startswith("firefox.instance"):
        return "zen" if "zen" in identity(inst).lower() else "firefox"
    return b if b in GECKO else None


def hidden_firefox(inst, url, players):
    """Firefox's (or Zen's) own player while per-tab players exist and it is
    one of those YouTube tabs (it publishes only one, for the tab it last
    started) — the tab rows already cover it. Same rule in now-playing.py."""
    b = gecko(inst)
    return (b is not None and ".instance" in inst and "youtube.com" in url
            and any(p.startswith(f"{b}.tab_") for p in players))


def entries():
    """[(name, detail, colour, state, action argv)] — state picks the icon."""
    rows, any_playing = [], False
    players = run("playerctl", "-l").splitlines()
    current = set()                         # each browser's "this tab"
    for b in GECKO:
        try:
            with open(os.path.join(RT_DIR, f"{b}-tabs.current")) as f:
                current.add(f.read().strip())
        except OSError:
            pass
    # Spotify's mirror copy (the laptop app showing the phone's song, or the
    # other way round) — the bar shows only the real one, so does the menu.
    mirrors = spotify_where.hidden(players)
    for inst in players:
        if superseded(inst, players) or inst in mirrors:
            continue
        meta = run("playerctl", "-p", inst, "metadata", "--format",
                   "{{status}}\x1f{{title}}\x1f{{artist}}\x1f{{xesam:url}}").split("\x1f")
        if len(meta) != 4 or not meta[0]:
            continue
        status, title, artist, url = meta
        if hidden_firefox(inst, url, players):
            continue
        state = {"Playing": "playing", "Paused": "paused"}.get(status, "stopped")
        any_playing |= state == "playing"
        name, colour = describe(inst, url)
        now = title or "—"
        if artist:
            now += f" · {artist}"
        if len(now) > 52:
            now = now[:51] + "…"
        action = ["playerctl", "-p", inst, "play-pause"]
        if gecko(inst) and ".tab_" in inst:
            # A Firefox / Zen tab: picking it switches the browser to that
            # tab (MPRIS Raise -> host.py), which makes it the one the bar shows.
            name += " · this tab" if inst in current else " · tab"
            action = ["busctl", "--user", "call", "org.mpris.MediaPlayer2." + inst,
                      "/org/mpris/MediaPlayer2", "org.mpris.MediaPlayer2", "Raise"]
        rows.append((name, now, colour, state, action))
    if not rows:
        rows.append(("Nothing playing", "", "muted", "stopped", None))
    last = last_played_row(players)
    if last:
        rows.append(last)
    if any_playing:
        rows.append(("Pause everything", "", "muted", "paused", ["playerctl", "-a", "pause"]))
    rows += [
        ("Open Spotify", "", "spotify", "open", [FOCUS, "spotify", "/usr/bin/spotify"]),
        ("Open YouTube", "", "zen", "open",          # a Zen tab: Zen's mauve
         ["hyprctl", "dispatch", "exec", f"{BROWSER} --new-tab https://www.youtube.com"]),
        ("Open YouTube Music", "", "ytmusic", "open",
         [FOCUS, "youtube-music", "/usr/bin/youtube-music"]),
    ]
    return rows


# ── window ─────────────────────────────────────────────────────────────────
CSS = f"""
window {{ background: {BASE}; color: {TEXT};
          font-family: "JetBrainsMono Nerd Font"; font-size: 12pt; }}
entry {{ background: transparent; color: {TEXT}; border: none; box-shadow: none;
         padding: 10px 14px 8px 14px; caret-color: {TEXT}; }}
.prompt {{ color: {SUBTEXT}; padding-left: 16px; }}
list, row {{ background: transparent; }}
row {{ padding: 4px 12px; border-radius: 8px; }}
row:selected, row:hover {{ background: {SURFACE0}; }}
list {{ padding: 2px 6px 8px 6px; }}
"""


class MediaMenu(Gtk.Window):
    def __init__(self):
        super().__init__(title="Media")
        self.set_default_size(620, -1)
        self.set_resizable(False)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.add(box)

        top = Gtk.Box()
        prompt = Gtk.Label(label=f"{I_MENU}  media")
        prompt.get_style_context().add_class("prompt")
        top.pack_start(prompt, False, False, 0)
        self.entry = Gtk.Entry()
        self.entry.connect("changed", lambda *_: self.listbox.invalidate_filter()
                           or self.select_first())
        self.entry.connect("activate", lambda *_: self.activate(self.listbox.get_selected_row()))
        top.pack_start(self.entry, True, True, 0)
        box.pack_start(top, False, False, 0)

        self.listbox = Gtk.ListBox()
        self.listbox.set_activate_on_single_click(True)
        self.listbox.set_filter_func(self.filter)
        self.listbox.connect("row-activated", lambda _lb, row: self.activate(row))
        box.pack_start(self.listbox, False, False, 0)

        for name, detail, colour, state, action in entries():
            self.listbox.add(self.make_row(name, detail, colour, state, action))

        self.connect("key-press-event", self.on_key)
        self.connect("focus-out-event", self.on_focus_out)
        self.connect("destroy", Gtk.main_quit)
        self.select_first()

    @staticmethod
    def row_icon(colour, state):
        path = f"{ICONS}/{colour}-{state}.svg"
        if colour != "other" or COLOURS["other"] == ICON_BLUE:
            return GdkPixbuf.Pixbuf.new_from_file_at_size(path, 20, 20)
        with open(path) as f:
            svg = f.read().replace(ICON_BLUE, COLOURS["other"])
        loader = GdkPixbuf.PixbufLoader.new_with_type("svg")
        loader.set_size(20, 20)
        loader.write(svg.encode())
        loader.close()
        return loader.get_pixbuf()

    @staticmethod
    def make_row(name, detail, colour, state, action):
        row = Gtk.ListBoxRow()
        row.action = action
        row.search = f"{name} {detail}".lower()
        h = Gtk.Box(spacing=12)
        icon = Gtk.Image.new_from_pixbuf(MediaMenu.row_icon(colour, state))
        h.pack_start(icon, False, False, 0)
        c = COLOURS[colour]
        markup = f"<span foreground='{c}' weight='bold'>{GLib.markup_escape_text(name)}</span>"
        if detail:
            style = "italic" if state == "paused" else "normal"
            markup += (f"<span foreground='{c}' alpha='70%'>  —  </span>"
                       f"<span foreground='{c}' style='{style}'>"
                       f"{GLib.markup_escape_text(detail)}</span>")
        label = Gtk.Label(xalign=0)
        label.set_markup(markup)
        label.set_ellipsize(Pango.EllipsizeMode.END)
        h.pack_start(label, True, True, 0)
        row.add(h)
        return row

    def filter(self, row):
        words = self.entry.get_text().lower().split()
        return all(w in row.search for w in words)

    def visible_rows(self):
        return [r for r in self.listbox.get_children() if r.get_child_visible()]

    def select_first(self):
        rows = self.visible_rows()
        self.listbox.select_row(rows[0] if rows else None)

    def move(self, step):
        rows = self.visible_rows()
        if not rows:
            return
        cur = self.listbox.get_selected_row()
        i = rows.index(cur) if cur in rows else -1
        self.listbox.select_row(rows[(i + step) % len(rows)])

    def activate(self, row):
        if row is None:
            return
        if row.action:
            subprocess.Popen(row.action, stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL, start_new_session=True)
        Gtk.main_quit()

    def on_key(self, _w, event):
        k = event.keyval
        if k == Gdk.KEY_Escape:
            Gtk.main_quit()
        elif k in (Gdk.KEY_Down, Gdk.KEY_Tab) or (
                k == Gdk.KEY_n and event.state & Gdk.ModifierType.CONTROL_MASK):
            self.move(1)
        elif k in (Gdk.KEY_Up, Gdk.KEY_ISO_Left_Tab) or (
                k == Gdk.KEY_p and event.state & Gdk.ModifierType.CONTROL_MASK):
            self.move(-1)
        else:
            return False                # typing goes to the filter entry
        return True

    def on_focus_out(self, *_):
        # A popup: clicking anywhere else dismisses it, as fuzzel's did.
        Gtk.main_quit()
        return False


def main():
    if toggle_or_claim():
        return
    provider = Gtk.CssProvider()
    provider.load_from_data(_rice_subst(CSS).encode())
    Gtk.StyleContext.add_provider_for_screen(
        Gdk.Screen.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
    win = MediaMenu()
    win.show_all()
    win.entry.grab_focus()
    # SIGTERM = closed by a second launch (toggle_or_claim); quit cleanly.
    GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, Gtk.main_quit)
    Gtk.main()


if __name__ == "__main__":
    sys.exit(main())
