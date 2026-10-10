#!/usr/bin/python3
"""Wallpaper carousel with colour filters — SUPER+W, and SUPER+SHIFT+W
for the lock screen (--lock).

    wallpaper-picker.py          desktop wallpaper  -> set-wallpaper.sh
    wallpaper-picker.py --lock   lock screen image  -> set-lockscreen.sh

Modelled on ilyamiro's Quickshell picker (r/unixporn "WEEEEEHOOO", 2026-03):
a band of slanted cards across the middle of the screen, the selected one
wide, its neighbours thin slices, and a pill toolbar above it:

    [ Green ]  󰕰  󰐊   ● ● ● ● ● ● ● ●   󰏘  󰍉
     filter   all video  colour filters  accent search

  ← → / h l / wheel   move              Enter / click centre   set it
  Tab / Shift+Tab     next filter        click a side card      move to it
  a  v  1-8           All / Video / colour
  c                   accent follows wallpaper on/off (󰏘)
  t                   transitions strip: ← → pick (saved at once, and played
                      as a preview on the real wallpaper behind the picker),
                      p replays it, Enter / Esc / t close the strip
  /  then type        search names       Esc   clear search, else close

COLOUR FILTERS. Every wallpaper (a video by a frame of it) is sorted into
one bucket — Red Orange Yellow Green Blue Purple Pink, or Mono when too little
of it is saturated — by hue-weighting its saturated pixels. Cached in
~/.cache/wallpaper-thumbs/colours.json by mtime. "All" is sorted by bucket,
so the band runs as a rainbow.

ACCENT. Setting a wallpaper also sets the accent (set-accent.sh) to the
Catppuccin Mocha colour of its bucket — the filter's colour when one is on.
Mono leaves the accent alone. 󰏘 / `c` turns this off (remembered in
~/.config/hypr/wallpaper-accent-sync). The accent picker (SUPER+ALT+C) is
untouched: it can still set any accent afterwards; the next wallpaper pick
sets it again. Note set-accent.sh restarts the bars and re-themes Spotify /
Discord, as it does from the accent picker.

A LAYER SURFACE (overlay, full screen, keyboard-exclusive), unlike
wallpaper-grid.py's toplevel: a band that spans the screen over everything
with a see-through background is what layer-shell is for, and a toplevel
would get Hyprland's borders, rounding and the 0.84 inactive opacity. The two
layer-shell landmines (blur rules on the wrong namespace, a GTK drag freezing
the seat) do not apply: no blur rule targets "wallpaper-picker", no drag.

Setting goes through set-wallpaper.sh (swaybg / mpvpaper, saved state).

TRANSITIONS (desktop only). The change itself is animated by the Quickshell
shell (~/.config/quickshell/WallpaperTransition.qml); which animation is
~/.config/hypr/wallpaper-transition, chosen here with `t` or the 󰤕 button.
A preview is `set-wallpaper.sh --preview <path> <kind>`: the same animation
from the current wallpaper to the selected card, which then fades back — the
wallpaper is not changed.
SUPER+W while open closes it; the other mode's key swaps to that mode.

LOCK MODE (--lock): same carousel and colour filters over ~/Pictures/wallpapers'
images (no videos — hyprlock can't play one; no system backgrounds — the lock
list stays curated, as it was in wallpaper-grid.py), plus a first card "Live
screen": hyprlock's `screenshot`, i.e. blur whatever is on screen when it
locks — previewed with a blurred grab taken as the picker opens. Sets through
set-lockscreen.sh. The accent toggle is separate here and starts OFF
(~/.config/hypr/wallpaper-accent-sync-lock): the accent is global, so by
default only the desktop wallpaper drives it.
"""

import colorsys
import hashlib
import json
import math
import os
import signal
import subprocess
import sys
import threading
import time

import cairo
import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
gi.require_version("Pango", "1.0")
gi.require_version("PangoCairo", "1.0")
from gi.repository import Gdk, GLib, Gtk, GtkLayerShell, Pango, PangoCairo  # noqa: E402

GLib.set_prgname("wallpaper-picker")

HOME = os.path.expanduser("~")
HYPR = os.path.join(HOME, ".config/hypr")
SOURCES = (os.path.join(HOME, "Pictures/wallpapers"), "/usr/share/backgrounds")
SETTER = os.path.join(HYPR, "set-wallpaper.sh")
LOCK_SETTER = os.path.join(HYPR, "set-lockscreen.sh")
LOCK_CONF = os.path.join(HYPR, "hyprlock.conf")
SCREENSHOT = "screenshot"          # hyprlock's word for "blur the live screen"
SET_ACCENT = os.path.join(HYPR, "set-accent.sh")
STATE = os.path.join(HYPR, "wallpaper")
ACCENT_STATE = os.path.join(HYPR, "theme/accent")
SYNC_STATE = os.path.join(HYPR, "wallpaper-accent-sync")
SYNC_STATE_LOCK = os.path.join(HYPR, "wallpaper-accent-sync-lock")
CACHE = os.path.join(HOME, ".cache/wallpaper-thumbs")
CARDS = os.path.join(CACHE, "carousel")
INDEX = os.path.join(CACHE, "colours.json")
LIVE = os.path.join(CARDS, "live-screen.png")      # blurred grab for the lock card
PIDFILE = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "wallpaper-picker.pid")
TRANSITION_FILE = os.path.join(HYPR, "wallpaper-transition")

IMAGE_EXTS = (".png", ".jpg", ".jpeg", ".webp", ".bmp")
VIDEO_EXTS = (".mp4", ".webm", ".mkv", ".mov", ".gif")    # = set-wallpaper.sh is_video

# Catppuccin Mocha
BASE, MANTLE, CRUST = "#1e1e2e", "#181825", "#11111b"
SURFACE0, SURFACE1, OVERLAY0, OVERLAY2 = "#313244", "#45475a", "#6c7086", "#9399b2"
TEXT, SUBTEXT0 = "#cdd6f4", "#a6adc8"

# Filter buckets in band order, each with its Mocha colour — also the accent
# it sets (None: leave the accent alone).
COLOURS = [
    ("Red", "#f38ba8"), ("Orange", "#fab387"), ("Yellow", "#f9e2af"),
    ("Green", "#a6e3a1"), ("Blue", "#89b4fa"), ("Purple", "#cba6f7"),
    ("Pink", "#f5c2e7"), ("Mono", "#9399b2"),
]
SWATCH = dict(COLOURS)
ACCENT_FOR = {name: hexc for name, hexc in COLOURS if name != "Mono"}
ORDER = {name: i for i, (name, _) in enumerate(COLOURS)}
ORDER["Live"] = -1                 # the lock screen's live-screen card goes first
FILTERS = ["All", "Video"] + [name for name, _ in COLOURS]

FONT = "JetBrainsMono Nerd Font"
I_GRID, I_PLAY, I_PALETTE, I_SEARCH = "\U000F0570", "\U000F040A", "\U000F03D8", "\U000F0349"
I_CHECK = "\U000F05E0"
I_TRANSITION = "\U000F0915"       # md-transition

# Wallpaper transitions: (kind, label, glyph). The kinds are
# WallpaperTransition.qml's (plus random / none, handled there and in
# set-wallpaper.sh); keep the two lists in step.
TRANSITIONS = [
    ("circle", "Circle zoom", "\U000F0E96"),     # md-circle_expand
    ("cursor", "From cursor", "\U000F0CFD"),     # md-cursor_default_click
    ("iris", "Iris", "\U000F0104"),              # md-camera_iris
    ("fade", "Fade", "\U000F1853"),              # md-circle_opacity
    ("wipe", "Wipe", "\U000F174A"),              # md-gradient_horizontal
    ("wave", "Wave", "\U000F078D"),              # md-waves
    ("slide", "Slide", "\U000F04E1"),            # md-swap_horizontal
    ("zoom", "Zoom", "\U000F034B"),              # md-magnify_plus
    ("dissolve", "Dissolve", "\U000F0D7C"),      # md-grain
    ("pixelate", "Pixelate", "\U000F013A"),      # md-checkerboard
    ("diamond", "Diamond", "\U000F070C"),        # md-rhombus_outline
    ("random", "Random", "\U000F049F"),          # md-shuffle_variant
    ("none", "Instant", "\U000F0243"),           # md-flash_off
]
TRANSITION_KINDS = [k for k, _, _ in TRANSITIONS]


def current_transition():
    try:
        with open(TRANSITION_FILE) as f:
            k = f.read().strip()
        return k if k in TRANSITION_KINDS else "circle"
    except OSError:
        return "circle"


def rgba(hexc, a=1.0):
    h = hexc.lstrip("#")
    return int(h[0:2], 16) / 255, int(h[2:4], 16) / 255, int(h[4:6], 16) / 255, a


def is_video(path):
    return path.lower().endswith(VIDEO_EXTS)


class Mode:
    """What differs between the desktop and lock-screen pickers."""

    def __init__(self, lock):
        self.lock = lock
        self.name = "lock" if lock else "desktop"
        if lock:
            self.sources, self.exts = SOURCES[:1], IMAGE_EXTS
            self.setter, self.sync_file, self.sync_default = LOCK_SETTER, SYNC_STATE_LOCK, False
            self.filters = ["All"] + [name for name, _ in COLOURS]
        else:
            self.sources, self.exts = SOURCES, IMAGE_EXTS + VIDEO_EXTS
            self.setter, self.sync_file, self.sync_default = SETTER, SYNC_STATE, True
            self.filters = FILTERS

    def current(self):
        return current_lock() if self.lock else current_wallpaper()


def current_lock():
    """The `path =` in hyprlock.conf's background block (= set-lockscreen.sh
    --show)."""
    import re
    try:
        with open(LOCK_CONF) as f:
            block = re.search(r"background\s*\{.*?\}", f.read(), re.S)
    except OSError:
        return ""
    line = block and re.search(r"^\s*path\s*=\s*(.+?)\s*$", block.group(0), re.M)
    return line.group(1) if line else ""


def grab_live():
    """Blurred grab of the screen as it is now: the preview for the lock
    screen's `screenshot` card. Taken before the picker maps."""
    from PIL import Image, ImageFilter
    os.makedirs(CARDS, exist_ok=True)
    tmp = f"{LIVE}.{os.getpid()}.tmp.png"
    if subprocess.run(["grim", "-s", "0.5", tmp], stderr=subprocess.DEVNULL).returncode:
        return False
    im = Image.open(tmp).convert("RGB")
    im.filter(ImageFilter.GaussianBlur(10)).save(tmp)
    os.replace(tmp, LIVE)
    return True


def wallpapers(mode):
    """Every image/video in the mode's sources, personal first; symlinks to
    the same file (Ubuntu's greyscale default -> the Dimmed raccoon) once."""
    seen, out = set(), []
    for d in mode.sources:
        try:
            names = sorted(os.listdir(d), key=str.lower)
        except OSError:
            continue
        for f in names:
            p = os.path.join(d, f)
            if not os.path.isfile(p) or not f.lower().endswith(mode.exts):
                continue
            real = os.path.realpath(p)
            if real in seen:
                continue
            seen.add(real)
            out.append(p)
    return out


def current_wallpaper():
    try:
        with open(STATE) as f:
            return f.read().strip()
    except OSError:
        return ""


def current_accent():
    try:
        with open(ACCENT_STATE) as f:
            return "#" + f.read().strip().lstrip("#").lower()
    except OSError:
        return "#cba6f7"


def accent_sync(mode):
    try:
        with open(mode.sync_file) as f:
            return f.read().strip() == "on"
    except OSError:
        return mode.sync_default


def key_for(path):
    st = os.stat(path)
    return hashlib.sha1(path.encode()).hexdigest()[:16], int(st.st_mtime)


# ── images ─────────────────────────────────────────────────────────────────
def poster(path):
    """A still for a video: a frame 1 s in (0 s for shorter clips), cached."""
    h, mtime = key_for(path)
    out = os.path.join(CARDS, f"poster-{h}-{mtime}.png")
    if os.path.exists(out):
        return out
    os.makedirs(CARDS, exist_ok=True)
    tmp = f"{out}.{os.getpid()}.{threading.get_ident()}.tmp.png"
    for seek in ("1", "0"):
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", seek, "-i", path,
                        "-frames:v", "1", "-vf", "scale=960:-2", tmp],
                       stdin=subprocess.DEVNULL, timeout=20)
        if os.path.exists(tmp):
            os.replace(tmp, out)
            return out
    return None


def open_still(path):
    from PIL import Image
    src = poster(path) if is_video(path) else path
    if not src:
        return None
    im = Image.open(src)
    try:
        im.draft("RGB", (1200, 1200))          # JPEG: decode at reduced size, fast
    except (AttributeError, ValueError):
        pass
    return im.convert("RGB")


def classify(im):
    """-> bucket name. Hue histogram of the saturated pixels, each weighted by
    saturation × value; Mono when under 12 % of the picture is colourful."""
    small = im.copy()
    small.thumbnail((96, 96))
    weights = {name: 0.0 for name, _ in COLOURS}
    total = colourful = 0
    for r, g, b in small.getdata():
        total += 1
        h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
        if s < 0.22 or v < 0.18:
            continue
        colourful += 1
        deg = h * 360
        if deg < 12 or deg >= 345:
            name = "Red"
        elif deg < 40:
            name = "Orange"
        elif deg < 68:
            name = "Yellow"
        elif deg < 165:
            name = "Green"
        elif deg < 255:
            name = "Blue"
        elif deg < 312:            # Ubuntu's aubergine (~305°) is purple, not pink
            name = "Purple"
        else:
            name = "Pink"
        weights[name] += s * v
    if not total or colourful / total < 0.12:
        return "Mono"
    return max(weights, key=weights.get)


def card_image(path, w, h):
    """PNG of the wallpaper cropped to cover w×h (the widest a card gets plus
    its slant), cached per size."""
    from PIL import Image
    k, mtime = key_for(path)
    out = os.path.join(CARDS, f"card-{k}-{mtime}-{w}x{h}.png")
    if os.path.exists(out):
        return out
    im = open_still(path)
    if im is None:
        return None
    scale = max(w / im.width, h / im.height)
    im = im.resize((max(w, round(im.width * scale)), max(h, round(im.height * scale))),
                   Image.LANCZOS)
    left, top = (im.width - w) // 2, (im.height - h) // 2
    os.makedirs(CARDS, exist_ok=True)
    tmp = f"{out}.{os.getpid()}.{threading.get_ident()}.tmp.png"
    im.crop((left, top, left + w, top + h)).save(tmp)
    os.replace(tmp, out)
    return out


def load_index():
    try:
        with open(INDEX) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def save_index(index):
    os.makedirs(CACHE, exist_ok=True)
    with open(INDEX + ".tmp", "w") as f:
        json.dump(index, f)
    os.replace(INDEX + ".tmp", INDEX)


def bucket_of(path, index):
    _, mtime = key_for(path)
    hit = index.get(path)
    if hit and hit.get("mtime") == mtime:
        return hit["bucket"]
    im = open_still(path)
    bucket = classify(im) if im is not None else "Mono"
    index[path] = {"mtime": mtime, "bucket": bucket}
    return bucket


# ── pidfile toggle (same scheme as wallpaper-grid.py) ──────────────────────
def close_running(mode):
    """Close an open picker. True if it was this mode (= the key toggles it
    off); the other mode's picker is closed and this one opens instead."""
    try:
        with open(PIDFILE) as fh:
            pid_s, running = fh.read().split()[:2]
        pid = int(pid_s)
        with open(f"/proc/{pid}/cmdline", "rb") as fh:
            if b"wallpaper-picker" not in fh.read():
                return False
        os.kill(pid, signal.SIGTERM)
        return running == mode.name
    except (OSError, ValueError, IndexError):
        return False


# ── the picker ─────────────────────────────────────────────────────────────
class Picker(Gtk.Window):
    def __init__(self, mode):
        super().__init__()
        self.mode = mode
        GtkLayerShell.init_for_window(self)
        GtkLayerShell.set_namespace(self, "wallpaper-picker")
        GtkLayerShell.set_layer(self, GtkLayerShell.Layer.OVERLAY)
        for edge in (GtkLayerShell.Edge.TOP, GtkLayerShell.Edge.BOTTOM,
                     GtkLayerShell.Edge.LEFT, GtkLayerShell.Edge.RIGHT):
            GtkLayerShell.set_anchor(self, edge, True)
        GtkLayerShell.set_exclusive_zone(self, -1)        # cover the bars too
        GtkLayerShell.set_keyboard_mode(self, GtkLayerShell.KeyboardMode.EXCLUSIVE)
        visual = self.get_screen().get_rgba_visual()
        if visual:
            self.set_visual(visual)
        self.set_app_paintable(True)

        self.area = Gtk.DrawingArea()
        self.area.set_can_focus(True)
        self.area.add_events(Gdk.EventMask.BUTTON_PRESS_MASK | Gdk.EventMask.SCROLL_MASK
                             | Gdk.EventMask.SMOOTH_SCROLL_MASK
                             | Gdk.EventMask.POINTER_MOTION_MASK)
        self.area.connect("draw", self.on_draw)
        self.area.connect("button-press-event", self.on_click)
        self.area.connect("scroll-event", self.on_scroll)
        self.area.connect("motion-notify-event", self.on_motion)
        self.connect("key-press-event", self.on_key)
        self.add(self.area)

        self.all = []                 # [{path, bucket, video, name}]
        self.items = []               # the filtered list on screen
        self.filter = "All"
        self.search = None            # None = not searching, else the query
        self.pos = 0.0                # animated position (index, fractional)
        self.target = 0
        self.fade = 0.0               # opening fade-in, 0..1
        self.surfaces = {}            # path -> cairo.ImageSurface
        self.pending = set()
        self.hover = None             # toolbar item under the pointer
        self.toolbar = []             # [(rect, action)] from the last draw
        self.cards = []               # [(polygon, index)] from the last draw
        self.scroll_acc = 0.0
        self.current = mode.current()
        self.accent = current_accent()
        self.sync = accent_sync(mode)
        self.transition = current_transition()
        self.tstrip = False           # the transitions strip is open
        self.loading = True
        self.geom = None
        self.anim_id = None
        self.queue = []
        self.qlock = threading.Condition()

        threading.Thread(target=self.index_worker, daemon=True).start()
        threading.Thread(target=self.card_worker, daemon=True).start()
        self.animate()

    # ── geometry ──
    def layout(self, W, H):
        ch = round(H * 0.34)
        g = {
            "W": W, "H": H, "ch": ch,
            "slant": round(ch * 0.30),
            "wc": round(ch * 1.55),        # selected card
            "ws": round(ch * 0.30),        # the slices either side
            "gap": 12,
        }
        g["cy"] = round(H / 2 - ch / 2 + 24)
        g["iw"], g["ih"] = g["wc"] + g["slant"], ch
        if self.geom != g:
            self.geom = g
            self.surfaces.clear()
            self.request_cards()
        return g

    # ── workers ──
    def index_worker(self):
        index = load_index()
        out = []
        if self.mode.lock:
            out.append({"path": SCREENSHOT, "bucket": "Live", "video": False,
                        "name": "Live screen"})
        for p in wallpapers(self.mode):
            try:
                bucket = bucket_of(p, index)
            except Exception as e:                       # noqa: BLE001 — one bad file
                print(f"wallpaper-picker: {p}: {e}", file=sys.stderr)
                bucket = "Mono"
            out.append({"path": p, "bucket": bucket, "video": is_video(p),
                        "name": os.path.splitext(os.path.basename(p))[0]})
        try:
            save_index(index)
        except OSError:
            pass
        GLib.idle_add(self.indexed, out)

    def indexed(self, out):
        self.all = sorted(out, key=lambda e: (ORDER.get(e["bucket"], 9),
                                              not e["path"].startswith(SOURCES[0]),
                                              e["name"].lower()))
        self.loading = False
        self.refilter(keep=self.current)
        return False

    def request_cards(self):
        if not self.geom or not self.items:
            return
        # nearest the selection first
        order = sorted(range(len(self.items)), key=lambda i: abs(i - self.target))
        with self.qlock:
            self.queue = [self.items[i]["path"] for i in order
                          if self.items[i]["path"] not in self.surfaces]
            self.qlock.notify()

    def card_worker(self):
        while True:
            with self.qlock:
                while not self.queue or not self.geom:
                    self.qlock.wait()
                path = self.queue.pop(0)
                w, h = self.geom["iw"], self.geom["ih"]
            try:
                png = card_image(LIVE if path == SCREENSHOT else path, w, h) \
                    if path != SCREENSHOT or os.path.exists(LIVE) else None
            except Exception as e:                       # noqa: BLE001
                print(f"wallpaper-picker: {path}: {e}", file=sys.stderr)
                png = None
            if png:
                GLib.idle_add(self.card_ready, path, png, (w, h))

    def card_ready(self, path, png, size):
        if self.geom and size == (self.geom["iw"], self.geom["ih"]):
            try:
                self.surfaces[path] = cairo.ImageSurface.create_from_png(png)
            except (cairo.Error, OSError):
                pass
            self.area.queue_draw()
        return False

    # ── filtering ──
    def refilter(self, keep=None):
        keep = keep or (self.items[self.target]["path"] if self.items else None)
        q = (self.search or "").lower()
        def ok(e):
            if self.filter == "Video" and not e["video"]:
                return False
            if self.filter not in ("All", "Video") and e["bucket"] != self.filter:
                return False
            return not q or q in e["name"].lower()
        self.items = [e for e in self.all if ok(e)]
        idx = next((i for i, e in enumerate(self.items) if e["path"] == keep), 0)
        self.target = idx
        self.pos = float(idx)
        self.request_cards()
        self.area.queue_draw()

    def set_filter(self, name):
        self.filter = name
        self.refilter()

    def cycle_filter(self, step):
        fs = self.mode.filters
        self.set_filter(fs[(fs.index(self.filter) + step) % len(fs)])

    def move(self, step):
        if self.items:
            self.target = max(0, min(len(self.items) - 1, self.target + step))
            self.request_cards()
            self.animate()

    # ── animation ──
    def animate(self):
        if self.anim_id is None:
            self.anim_id = GLib.timeout_add(16, self.tick)

    def tick(self):
        self.pos += (self.target - self.pos) * 0.24
        self.fade = min(1.0, self.fade + 0.12)
        if abs(self.target - self.pos) < 0.002:
            self.pos = float(self.target)
        self.area.queue_draw()
        if self.pos == self.target and self.fade >= 1.0:
            self.anim_id = None
            return False
        return True

    # ── drawing ──
    def text(self, cr, s, x, y, size, colour, bold=False, anchor="center", alpha=1.0):
        layout = PangoCairo.create_layout(cr)
        fd = Pango.FontDescription(f"{FONT} {'Bold ' if bold else ''}{size}")
        layout.set_font_description(fd)
        layout.set_text(s, -1)
        w, h = layout.get_pixel_size()
        if anchor == "center":
            x -= w / 2
        elif anchor == "right":
            x -= w
        cr.set_source_rgba(*rgba(colour, alpha))
        cr.move_to(x, y - h / 2)
        PangoCairo.show_layout(cr, layout)
        return w

    @staticmethod
    def rounded(cr, x, y, w, h, r):
        cr.new_sub_path()
        cr.arc(x + w - r, y + r, r, -math.pi / 2, 0)
        cr.arc(x + w - r, y + h - r, r, 0, math.pi / 2)
        cr.arc(x + r, y + h - r, r, math.pi / 2, math.pi)
        cr.arc(x + r, y + r, r, math.pi, 3 * math.pi / 2)
        cr.close_path()

    def card_width(self, i):
        g = self.geom
        d = min(1.0, abs(i - self.pos))
        return g["ws"] + (g["wc"] - g["ws"]) * (1 - d)

    def on_draw(self, widget, cr):
        alloc = widget.get_allocation()
        g = self.layout(alloc.width, alloc.height)
        a = self.fade
        cr.set_operator(cairo.OPERATOR_SOURCE)
        cr.set_source_rgba(*rgba(CRUST, 0.45 * a))
        cr.paint()
        cr.set_operator(cairo.OPERATOR_OVER)
        self.cards = []
        if self.items:
            self.draw_cards(cr, g, a)
        else:
            msg = "Indexing wallpapers…" if self.loading else (
                f"No wallpapers match “{self.search}”" if self.search
                else f"No {self.filter.lower()} wallpapers")
            self.text(cr, msg, g["W"] / 2, g["cy"] + g["ch"] / 2, 13, SUBTEXT0, alpha=a)
        self.draw_toolbar(cr, g, a)
        if self.items:
            self.draw_caption(cr, g, a)
        return True

    def draw_cards(self, cr, g, a):
        n = len(self.items)
        widths = [self.card_width(i) for i in range(n)]
        lefts, x = [], 0.0
        for w in widths:
            lefts.append(x)
            x += w + g["gap"]
        f = math.floor(self.pos)
        frac = self.pos - f
        c0 = lefts[f] + widths[f] / 2
        c1 = lefts[min(f + 1, n - 1)] + widths[min(f + 1, n - 1)] / 2
        offset = g["W"] / 2 - g["slant"] / 2 - (c0 + (c1 - c0) * frac)
        y, h, s = g["cy"], g["ch"], g["slant"]
        # far cards first, the selected one last (on top of its shadow)
        order = sorted(range(n), key=lambda i: -abs(i - self.pos))
        for i in order:
            left, w = lefts[i] + offset, widths[i]
            if left + w + s < -20 or left > g["W"] + 20:
                continue
            poly = [(left + s, y), (left + w + s, y), (left + w, y + h), (left, y + h)]
            self.cards.append((poly, i))
            d = min(1.0, abs(i - self.pos))
            sel = d < 0.5
            # shadow
            cr.save()
            cr.translate(0, 10)
            self.path(cr, poly)
            cr.set_source_rgba(0, 0, 0, 0.35 * a * (1 - 0.5 * d))
            cr.fill()
            cr.restore()
            # picture, centred on the card's middle
            cr.save()
            self.path(cr, poly)
            cr.clip()
            surf = self.surfaces.get(self.items[i]["path"])
            if surf:
                ix = left + w / 2 + s / 2 - surf.get_width() / 2
                cr.set_source_surface(surf, ix, y)
                cr.paint_with_alpha(a)
            else:
                cr.set_source_rgba(*rgba(SURFACE0, 0.9 * a))
                cr.paint()
            # the further from the middle, the dimmer
            cr.set_source_rgba(*rgba(CRUST, 0.45 * d * a))
            cr.paint()
            cr.restore()
            # outline: accent on the selected card
            self.path(cr, poly)
            if sel:
                cr.set_source_rgba(*rgba(self.accent, a))
                cr.set_line_width(3)
            else:
                cr.set_source_rgba(*rgba(SURFACE1, 0.8 * a))
                cr.set_line_width(1.2)
            cr.stroke()
            e = self.items[i]
            if e["video"] and w > 40:            # ▶ badge, bottom-left
                bx, by = left + 14, y + h - 30
                cr.set_source_rgba(*rgba(CRUST, 0.75 * a))
                cr.arc(bx + 10, by + 10, 13, 0, 2 * math.pi)
                cr.fill()
                self.text(cr, I_PLAY, bx + 10, by + 10, 11, TEXT, alpha=a)

    @staticmethod
    def path(cr, poly):
        cr.move_to(*poly[0])
        for p in poly[1:]:
            cr.line_to(*p)
        cr.close_path()

    def draw_toolbar(self, cr, g, a):
        items = []                       # (kind, value, width)
        label = (f"/{self.search}▏" if self.search is not None else
                 {"All": "All", "Video": "Video"}.get(self.filter, self.filter))
        items.append(("label", label, 110))
        items.append(("sep", None, 9))
        items.append(("filter", "All", 34))
        if not self.mode.lock:
            items.append(("filter", "Video", 34))
        items.append(("sep", None, 9))
        for name, _ in COLOURS:
            items.append(("filter", name, 30))
        items.append(("sep", None, 9))
        items.append(("sync", None, 34))
        if not self.mode.lock:
            items.append(("trans", None, 34))
        items.append(("search", None, 34))
        pad, height = 10, 44
        total = sum(w for _, _, w in items) + 2 * pad
        x0 = g["W"] / 2 - total / 2
        y0 = g["cy"] - height - 26
        if self.mode.lock:
            self.text(cr, "\U000F033E  Lock screen", g["W"] / 2, y0 - 22, 11, SUBTEXT0,
                      bold=True, alpha=a)

        self.rounded(cr, x0, y0, total, height, height / 2)
        cr.set_source_rgba(*rgba(CRUST, 0.92 * a))
        cr.fill_preserve()
        cr.set_source_rgba(*rgba(SURFACE1, 0.9 * a))
        cr.set_line_width(1)
        cr.stroke()
        self.toolbar = []
        x, cy = x0 + pad, y0 + height / 2
        for kind, value, w in items:
            rect = (x, y0, w, height)
            hov = self.hover == (kind, value)
            if kind == "label":
                colour = SWATCH.get(self.filter, TEXT) if self.search is None else TEXT
                self.text(cr, label, x + w / 2, cy, 11, colour, bold=True, alpha=a)
            elif kind == "sep":
                cr.set_source_rgba(*rgba(SURFACE1, a))
                cr.rectangle(x + w / 2, y0 + 12, 1, height - 24)
                cr.fill()
            elif kind == "filter" and value in SWATCH:
                on = self.filter == value
                r = 9 if (on or hov) else 8
                if on:
                    cr.arc(x + w / 2, cy, r + 4, 0, 2 * math.pi)
                    cr.set_source_rgba(*rgba(TEXT, 0.9 * a))
                    cr.set_line_width(2)
                    cr.stroke()
                cr.arc(x + w / 2, cy, r, 0, 2 * math.pi)
                cr.set_source_rgba(*rgba(SWATCH[value], a))
                cr.fill()
                self.toolbar.append((rect, (kind, value)))
            else:
                icon = {"All": I_GRID, "Video": I_PLAY}.get(value) if kind == "filter" else \
                    (I_PALETTE if kind == "sync" else
                     self.transition_glyph() if kind == "trans" else I_SEARCH)
                on = (kind == "filter" and self.filter == value) or \
                     (kind == "sync" and self.sync) or (kind == "search" and self.search is not None) \
                     or (kind == "trans" and self.tstrip)
                if on or hov:
                    self.rounded(cr, x + 2, y0 + 7, w - 4, height - 14, 9)
                    cr.set_source_rgba(*rgba(SURFACE0, (1.0 if on else 0.7) * a))
                    cr.fill()
                colour = self.accent if on else (TEXT if hov else OVERLAY2)
                self.text(cr, icon, x + w / 2, cy, 14, colour, alpha=a)
                self.toolbar.append((rect, (kind, value)))
            x += w
        if self.tstrip and not self.mode.lock:
            self.draw_transitions(cr, g, a, y0 - 52)

    def transition_glyph(self):
        return next((gl for k, _, gl in TRANSITIONS if k == self.transition), I_TRANSITION)

    def draw_transitions(self, cr, g, a, y0):
        """The strip of transition chips above the toolbar (`t`)."""
        height, pad = 36, 6
        chips = []
        for kind, label, glyph in TRANSITIONS:
            chips.append((kind, label, glyph, 34 + len(label) * 8))
        total = sum(c[3] for c in chips) + 2 * pad
        x0 = g["W"] / 2 - total / 2
        self.rounded(cr, x0, y0, total, height, height / 2)
        cr.set_source_rgba(*rgba(CRUST, 0.92 * a))
        cr.fill_preserve()
        cr.set_source_rgba(*rgba(SURFACE1, 0.9 * a))
        cr.set_line_width(1)
        cr.stroke()
        x, cy = x0 + pad, y0 + height / 2
        for kind, label, glyph, w in chips:
            on = kind == self.transition
            hov = self.hover == ("pick-trans", kind)
            if on or hov:
                self.rounded(cr, x + 1, y0 + 5, w - 2, height - 10, (height - 10) / 2)
                cr.set_source_rgba(*rgba(self.accent if on else SURFACE0, (1.0 if on else 0.8) * a))
                cr.fill()
            colour = CRUST if on else (TEXT if hov else SUBTEXT0)
            self.text(cr, f"{glyph} {label}", x + w / 2, cy, 9, colour, bold=on, alpha=a)
            self.toolbar.append(((x, y0, w, height), ("pick-trans", kind)))
            x += w
        self.text(cr, "← →  choose   ·   p  preview   ·   Enter  done", g["W"] / 2,
                  y0 - 14, 8, OVERLAY0, alpha=a)

    def set_transition(self, kind, preview=True):
        self.transition = kind
        try:
            with open(TRANSITION_FILE, "w") as f:
                f.write(kind + "\n")
        except OSError:
            pass
        self.area.queue_draw()
        if preview:
            self.preview()

    def preview(self):
        """Play the chosen transition on the real wallpaper, from the current
        one to the selected card (or its neighbour, if that IS the current)."""
        if self.mode.lock or self.transition == "none" or not self.items:
            return
        cands = [self.items[self.target]] + self.items[self.target + 1:] + self.items[:self.target]
        e = next((c for c in cands if c["path"] != self.current and c["path"] != SCREENSHOT), None)
        if e is None:
            return
        subprocess.Popen([SETTER, "--preview", e["path"], self.transition],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True)

    def draw_caption(self, cr, g, a):
        e = self.items[self.target]
        bits = ["blurs whatever is on screen when it locks"] if e["path"] == SCREENSHOT \
            else [e["bucket"]] + (["animated"] if e["video"] else [])
        if e["path"] == self.current:
            bits.append(f"{I_CHECK} current")
        if self.sync and e["bucket"] in ACCENT_FOR:
            bits.append("sets accent")
        if not self.mode.lock:
            label = next((lb for k, lb, _ in TRANSITIONS if k == self.transition), "")
            bits.append(f"{self.transition_glyph()} {label}")
        sub = "  ·  ".join(bits)
        y = g["cy"] + g["ch"] + 40
        name = e["name"] if len(e["name"]) <= 60 else e["name"][:59] + "…"
        layout_w = max(len(name) * 9, len(sub) * 7.2) + 48
        self.rounded(cr, g["W"] / 2 - layout_w / 2, y - 24, layout_w, 50, 16)
        cr.set_source_rgba(*rgba(CRUST, 0.88 * a))
        cr.fill()
        self.text(cr, name, g["W"] / 2, y - 7, 11, TEXT, bold=True, alpha=a)
        self.text(cr, sub, g["W"] / 2, y + 12, 9, SWATCH.get(e["bucket"], SUBTEXT0), alpha=a)
        self.text(cr, f"{self.target + 1} / {len(self.items)}", g["W"] / 2, y + 44, 9,
                  OVERLAY0, alpha=a)

    # ── input ──
    def hit_toolbar(self, x, y):
        for (rx, ry, rw, rh), action in self.toolbar:
            if rx <= x < rx + rw and ry <= y < ry + rh:
                return action
        return None

    def hit_card(self, x, y):
        # the selected card is drawn last, so test in reverse draw order
        for poly, i in reversed(self.cards):
            if self.inside(poly, x, y):
                return i
        return None

    @staticmethod
    def inside(poly, x, y):
        c = False
        for k in range(len(poly)):
            (x1, y1), (x2, y2) = poly[k], poly[k - 1]
            if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1) + x1:
                c = not c
        return c

    def on_motion(self, _w, ev):
        h = self.hit_toolbar(ev.x, ev.y)
        if h != self.hover:
            self.hover = h
            self.area.queue_draw()

    def on_click(self, _w, ev):
        if ev.type != Gdk.EventType.BUTTON_PRESS:
            return True
        if ev.button == 3:
            Gtk.main_quit()
            return True
        action = self.hit_toolbar(ev.x, ev.y)
        if action:
            self.do(action)
            return True
        i = self.hit_card(ev.x, ev.y)
        if i is None:
            Gtk.main_quit()              # click on empty space: close
        elif i == self.target:
            self.apply()
        else:
            self.target = i
            self.request_cards()
            self.animate()
        return True

    def do(self, action):
        kind, value = action
        if kind == "filter":
            self.set_filter(value)
        elif kind == "sync":
            self.sync = not self.sync
            try:
                with open(self.mode.sync_file, "w") as f:
                    f.write("on\n" if self.sync else "off\n")
            except OSError:
                pass
            self.area.queue_draw()
        elif kind == "search":
            self.search = None if self.search is not None else ""
            self.refilter()
        elif kind == "trans":
            self.tstrip = not self.tstrip
            self.area.queue_draw()
        elif kind == "pick-trans":
            self.set_transition(value)

    def on_scroll(self, _w, ev):
        # Mouse wheel UP moves right (to the next card), DOWN moves left; the
        # touchpad goes the opposite way (two-finger DOWN = next) — the user's
        # choice, 2026-10-10. GTK's Wayland backend gives touchpad scrolls
        # their own source device (axis source "finger" -> TOUCHPAD).
        if ev.direction == Gdk.ScrollDirection.SMOOTH:
            ok, dx, dy = ev.get_scroll_deltas()
            dev = ev.get_source_device()
            touchpad = dev is not None and dev.get_source() == Gdk.InputSource.TOUCHPAD
            self.scroll_acc += (dy + dx) if touchpad else -(dy + dx)
            while abs(self.scroll_acc) >= 1.0:
                step = 1 if self.scroll_acc > 0 else -1
                self.scroll_acc -= step
                self.move(step)
        elif ev.direction in (Gdk.ScrollDirection.DOWN, Gdk.ScrollDirection.RIGHT):
            self.move(-1)
        elif ev.direction in (Gdk.ScrollDirection.UP, Gdk.ScrollDirection.LEFT):
            self.move(1)
        return True

    def on_key(self, _w, ev):
        k = ev.keyval
        name = Gdk.keyval_name(k) or ""
        if self.search is not None:                       # typing a search
            if k == Gdk.KEY_Escape:
                self.search = None
                self.refilter()
            elif k == Gdk.KEY_BackSpace:
                self.search = self.search[:-1]
                self.refilter()
            elif k in (Gdk.KEY_Return, Gdk.KEY_KP_Enter):
                self.apply()
            elif k in (Gdk.KEY_Left, Gdk.KEY_Right):
                self.move(-1 if k == Gdk.KEY_Left else 1)
            else:
                ch = Gdk.keyval_to_unicode(k)
                if ch and chr(ch).isprintable():
                    self.search += chr(ch)
                    self.refilter()
            return True
        if self.tstrip:                                   # choosing a transition
            i = TRANSITION_KINDS.index(self.transition)
            if k in (Gdk.KEY_Left, Gdk.KEY_h, Gdk.KEY_Up, Gdk.KEY_k):
                self.set_transition(TRANSITION_KINDS[(i - 1) % len(TRANSITION_KINDS)])
            elif k in (Gdk.KEY_Right, Gdk.KEY_l, Gdk.KEY_Down, Gdk.KEY_j, Gdk.KEY_Tab):
                self.set_transition(TRANSITION_KINDS[(i + 1) % len(TRANSITION_KINDS)])
            elif k == Gdk.KEY_p:
                self.preview()
            elif k in (Gdk.KEY_Escape, Gdk.KEY_Return, Gdk.KEY_KP_Enter, Gdk.KEY_t, Gdk.KEY_space):
                self.tstrip = False
                self.area.queue_draw()
            return True
        if k in (Gdk.KEY_Escape, Gdk.KEY_q):
            Gtk.main_quit()
        elif k in (Gdk.KEY_Left, Gdk.KEY_h, Gdk.KEY_Up, Gdk.KEY_k):
            self.move(-1)
        elif k in (Gdk.KEY_Right, Gdk.KEY_l, Gdk.KEY_Down, Gdk.KEY_j):
            self.move(1)
        elif k == Gdk.KEY_Home:
            self.move(-len(self.items))
        elif k == Gdk.KEY_End:
            self.move(len(self.items))
        elif k in (Gdk.KEY_Return, Gdk.KEY_KP_Enter, Gdk.KEY_space):
            self.apply()
        elif k == Gdk.KEY_Tab:
            self.cycle_filter(1)
        elif k == Gdk.KEY_ISO_Left_Tab:
            self.cycle_filter(-1)
        elif k == Gdk.KEY_a:
            self.set_filter("All")
        elif k == Gdk.KEY_v and not self.mode.lock:
            self.set_filter("Video")
        elif k == Gdk.KEY_c:
            self.do(("sync", None))
        elif k == Gdk.KEY_t and not self.mode.lock:
            self.do(("trans", None))
        elif k == Gdk.KEY_slash or (k == Gdk.KEY_f and ev.state & Gdk.ModifierType.CONTROL_MASK):
            self.search = ""
            self.refilter()
        elif name.isdigit() and 1 <= int(name) <= len(COLOURS):
            self.set_filter(COLOURS[int(name) - 1][0])
        return True

    def apply(self):
        if not self.items:
            return
        e = self.items[self.target]
        hexc = ACCENT_FOR.get(e["bucket"]) if self.sync else None
        if hexc and hexc.lower() == self.accent.lower():
            hexc = None
        # Detached, one after the other: the wallpaper first (instant), then
        # the accent (restarts the bars). Through Hyprland, like a keybind, so
        # nothing is tied to this process.
        script = '"$0" "$1"' + (' && "$2" "$3"' if hexc else "")
        target = "--screenshot" if e["path"] == SCREENSHOT else e["path"]
        argv = [self.mode.setter, target] + ([SET_ACCENT, hexc.lstrip("#")] if hexc else [])
        cmd = "sh -c " + GLib.shell_quote(script) + " " + " ".join(GLib.shell_quote(x) for x in argv)
        subprocess.run(["hyprctl", "dispatch", "exec", cmd], stdout=subprocess.DEVNULL)
        Gtk.main_quit()


def main():
    mode = Mode(lock="--lock" in sys.argv[1:])
    if close_running(mode):
        return 0                                   # same key again: toggled off
    with open(PIDFILE, "w") as f:
        f.write(f"{os.getpid()} {mode.name}\n")
    try:
        if mode.lock:
            try:
                grab_live()                        # before our surface maps
            except Exception as e:                 # noqa: BLE001 — the card just stays blank
                print(f"wallpaper-picker: live grab: {e}", file=sys.stderr)
        win = Picker(mode)
        win.connect("destroy", Gtk.main_quit)
        GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, Gtk.main_quit)
        win.show_all()
        win.area.grab_focus()
        Gtk.main()
    finally:
        try:
            with open(PIDFILE) as f:
                if f.read().split()[0] == str(os.getpid()):
                    os.remove(PIDFILE)
        except (OSError, IndexError):
            pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
