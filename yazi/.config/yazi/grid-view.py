#!/usr/bin/env python3
"""Grid view for yazi — Nautilus-style icons and thumbnails (Alt+G in yazi).

yazi only lists, so this is a separate full-screen view in the same terminal,
started by keymap.toml with `shell --block`. It draws through the kitty
graphics protocol (Ghostty speaks it — the same thing yazi's image preview
uses) and hands back to yazi on exit: `ya emit reveal <item>`, so yazi lands
on whatever was selected here, in whatever folder you walked to.

  arrows / hjkl   move               Enter, l on a folder  open it
  Enter on file   open (xdg-open)    Backspace, -          parent folder
  .               hidden files       PgUp PgDn Home End    jump
  mouse           click selects, double-click opens, wheel scrolls
  q  Esc  Alt+G   back to the list (on the selected item)

Thumbnails: images (Pillow), videos (ffmpeg, a frame at 1 s), PDFs (pdftoppm,
page 1); everything else gets a Nerd Font glyph in the theme's colours.
Cached in ~/.cache/yazi-grid, keyed on path + mtime + size + tile size.

Usage: grid-view.py [hovered-path]        from yazi (run in the folder to show)
       grid-view.py --yazi DIR|FILE      standalone: show DIR (or FILE's folder,
                                         FILE selected), then turn into yazi on
                                         the selected item (grid-open.sh)
"""
import base64
import hashlib
import json
import os
import re
import select
import signal
import struct
import subprocess
import sys
import termios
import time
import tty
import fcntl
import unicodedata
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps

HOME = Path.home()
CACHE = HOME / ".cache/yazi-grid"
FONT = HOME / ".local/share/fonts/JetBrainsMonoNerdFont-Regular.ttf"
YA = HOME / ".local/bin/ya"
TILE_W, TILE_H = 18, 10           # cells, border included; names get two lines

IMAGE_EXT = {"jpg", "jpeg", "png", "gif", "webp", "bmp", "tif", "tiff", "ico", "avif", "heic"}
VIDEO_EXT = {"mp4", "mkv", "webm", "mov", "avi", "m4v", "flv", "wmv", "mpg", "mpeg", "3gp"}


# ── theme ───────────────────────────────────────────────────────────────────

def load_theme():
    hypr = HOME / ".config/hypr/theme"
    try:
        pal = json.loads((hypr / "palette.json").read_text())
    except (OSError, ValueError):
        pal = {}
    try:
        accent = "#" + (hypr / "accent").read_text().strip()
    except OSError:
        accent = pal.get("blue", "#89b4fa")
    d = {"text": "#cdd6f4", "subtext0": "#a6adc8", "overlay0": "#6c7086", "surface0": "#313244",
         "surface1": "#45475a", "crust": "#11111b", "blue": "#89b4fa", "yellow": "#f9e2af",
         "green": "#a6e3a1", "peach": "#fab387", "red": "#f38ba8", "mauve": "#cba6f7",
         "teal": "#94e2d5", "sky": "#89dceb", "pink": "#f5c2e7", "lavender": "#b4befe",
         "sapphire": "#74c7ec", "maroon": "#eba0ac"}
    d.update({k: v for k, v in pal.items() if isinstance(v, str) and v.startswith("#")})
    d["accent"] = accent
    return d


THEME = load_theme()


def rgb(hexstr):
    h = hexstr.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def fg(name):
    return "\x1b[38;2;%d;%d;%dm" % rgb(THEME[name])


def bg(name):
    return "\x1b[48;2;%d;%d;%dm" % rgb(THEME[name])


RESET = "\x1b[0m"

# glyph, colour role — by extension, then a few special names
ICONS = {
    "dir": ("\U000F024B", "blue"), "file": ("\U000F0214", "subtext0"),
    "pdf": ("\U000F0226", "red"), "image": ("\U000F021F", "pink"),
    "video": ("\U000F022B", "mauve"), "audio": ("\U000F0223", "teal"),
    "archive": ("\U000F05C4", "yellow"), "text": ("\U000F0219", "text"),
    "code": ("\U000F022E", "green"), "py": ("\U000F0320", "yellow"),
    "js": ("\U000F031E", "yellow"), "ts": ("\U000F06E6", "blue"),
    "md": ("\U000F0354", "sky"), "json": ("\U000F0626", "peach"),
    "html": ("\U000F031D", "peach"), "css": ("\U000F031C", "blue"),
    "c": ("\U000F0671", "blue"), "cpp": ("\U000F0672", "blue"),
    "rs": ("\U000F1617", "peach"), "go": ("\U000F07D3", "sky"),
    "java": ("\U000F0B37", "red"), "sh": ("\U000F018D", "green"),
    "word": ("\U000F022C", "blue"), "sheet": ("\U000F021B", "green"),
    "slides": ("\U000F0227", "peach"), "db": ("\U000F01BC", "lavender"),
    "nb": ("\U000F082E", "peach"), "disc": ("\U000F05EE", "subtext0"),
    "key": ("\U000F0306", "yellow"), "conf": ("\U000F0493", "subtext0"),
    "app": ("\U000F08C6", "mauve"), "book": ("\U000F14F7", "sapphire"),
}
EXT_KIND = {}
for kind, exts in {
    "pdf": "pdf", "image": "jpg jpeg png gif webp bmp tif tiff ico svg avif heic xcf psd",
    "video": "mp4 mkv webm mov avi m4v flv wmv mpg mpeg 3gp",
    "audio": "mp3 flac wav ogg opus m4a aac wma",
    "archive": "zip tar gz tgz bz2 xz zst 7z rar deb rpm",
    "text": "txt log rst org", "py": "py pyi", "js": "js mjs cjs jsx", "ts": "ts tsx",
    "md": "md markdown mdx", "json": "json jsonc yaml yml toml", "html": "html htm xml",
    "css": "css scss sass", "c": "c h", "cpp": "cpp cc cxx hpp hh", "rs": "rs", "go": "go",
    "java": "java kt jar", "sh": "sh bash zsh fish", "word": "doc docx odt rtf",
    "sheet": "xls xlsx ods csv tsv", "slides": "ppt pptx odp", "db": "db sqlite sqlite3 sql",
    "nb": "ipynb", "disc": "iso img", "key": "pem key gpg asc pub", "conf": "conf ini cfg env lock",
    "app": "appimage desktop exe msi", "book": "epub mobi djvu",
    "code": "lua rb php r m swift dart vue svelte zig nim hs ml ex exs cs",
}.items():
    for e in exts.split():
        EXT_KIND[e] = kind


def kind_of(p, is_dir):
    if is_dir:
        return "dir"
    return EXT_KIND.get(p.suffix.lower().lstrip("."), "file")


# ── terminal ────────────────────────────────────────────────────────────────

class Term:
    def __init__(self):
        self.fd = os.open("/dev/tty", os.O_RDWR)
        self.saved = termios.tcgetattr(self.fd)
        tty.setraw(self.fd)
        self.buf = []
        self.write("\x1b[?1049h\x1b[?25l\x1b[?1000h\x1b[?1006h\x1b[2J")
        self.flush()

    def size(self):
        r, c, xp, yp = struct.unpack("HHHH", fcntl.ioctl(self.fd, termios.TIOCGWINSZ, b"\0" * 8))
        cw = xp / c if xp and c else 10.0
        ch = yp / r if yp and r else 20.0
        return r, c, cw, ch

    def write(self, s):
        self.buf.append(s)

    def flush(self):
        data = "".join(self.buf).encode()
        self.buf = []
        while data:
            n = os.write(self.fd, data)
            data = data[n:]

    def read(self, timeout):
        r, _, _ = select.select([self.fd], [], [], timeout)
        return os.read(self.fd, 4096) if r else b""

    def close(self):
        self.write("\x1b_Ga=d,d=A,q=2\x1b\\\x1b[?1006l\x1b[?1000l\x1b[0m\x1b[2J\x1b[?25h\x1b[?1049l")
        self.flush()
        termios.tcsetattr(self.fd, termios.TCSADRAIN, self.saved)
        os.close(self.fd)


def width(s):
    return sum(2 if unicodedata.east_asian_width(ch) in "WF" else 0 if unicodedata.combining(ch) else 1 for ch in s)


def fit(s, n):
    """Elide in the middle (keeps the extension), pad-free."""
    if width(s) <= n:
        return s
    keep = n - 1
    head, tail = s[: (keep + 1) // 2], s[-(keep // 2):] if keep // 2 else ""
    while width(head) + width(tail) > keep and head:
        head = head[:-1]
    return head + "…" + tail


def wrap2(s, n):
    """Two centred lines, Nautilus-style: break at a space, - or _ near the
    end of the first line if there is one, elide the rest in the middle."""
    if width(s) <= n:
        return [s, ""]
    cut = n
    for i in range(n, max(n * 3 // 5, 1) - 1, -1):
        if s[i - 1] in " -_.":
            cut = i
            break
    return [fit(s[:cut].rstrip(), n), fit(s[cut:].lstrip(), n)]


# ── thumbnails ──────────────────────────────────────────────────────────────

_font_cache = {}


def font(px):
    if px not in _font_cache:
        _font_cache[px] = ImageFont.truetype(str(FONT), px)
    return _font_cache[px]


def icon_png(kind, w, h):
    glyph, role = ICONS.get(kind, ICONS["file"])
    out = CACHE / f"icon-{kind}-{THEME[role].lstrip('#')}-{w}x{h}.png"
    if out.exists():
        return out
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    f = font(max(8, int(min(w, h) * 0.78)))
    l, t, r, b = d.textbbox((0, 0), glyph, font=f)
    d.text(((w - (r - l)) / 2 - l, (h - (b - t)) / 2 - t), glyph, font=f, fill=rgb(THEME[role]) + (255,))
    im.save(out)
    return out


def thumb_png(path, kind, w, h):
    """A w×h transparent canvas with the file's picture centred, or None."""
    try:
        st = path.stat()
    except OSError:
        return None
    key = hashlib.sha1(f"{path}|{st.st_mtime_ns}|{st.st_size}|{w}x{h}".encode()).hexdigest()
    out = CACHE / f"{key}.png"
    if out.exists():
        return out
    ext = path.suffix.lower().lstrip(".")
    src = None
    tmp = CACHE / f"{key}.src.png"
    try:
        if ext in IMAGE_EXT:
            src = Image.open(path)
            src.draft("RGB", (w * 2, h * 2))
            src = ImageOps.exif_transpose(src)
        elif ext in VIDEO_EXT:
            for ss in ("1", "0"):
                subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", ss, "-i", str(path), "-frames:v", "1",
                                "-vf", f"scale={w * 2}:-2", str(tmp)], timeout=15, capture_output=True)
                if tmp.exists() and tmp.stat().st_size:
                    break
            src = Image.open(tmp)
        elif ext == "pdf":
            subprocess.run(["pdftoppm", "-png", "-singlefile", "-f", "1", "-l", "1",
                            "-scale-to", str(max(w, h) * 2), str(path), str(tmp)[:-4]],
                           timeout=15, capture_output=True)
            src = Image.open(tmp)
        else:
            return None
        src.thumbnail((w - 4, h - 4))
        src = src.convert("RGBA")
        canvas = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        canvas.paste(src, ((w - src.width) // 2, (h - src.height) // 2), src)
        canvas.save(out)
        return out
    except Exception:
        return None
    finally:
        tmp.unlink(missing_ok=True)


# ── the view ────────────────────────────────────────────────────────────────

class Grid:
    def __init__(self, cwd, hovered):
        self.t = Term()
        self.cwd = Path(cwd)
        self.hidden = True                       # yazi.toml: show_hidden = true
        self.pool = ThreadPoolExecutor(max_workers=4)
        self.jobs = {}                           # index -> future (current listing only)
        self.placed = {}                         # index -> png path shown
        self.gen = 0                             # listing generation, invalidates jobs
        self.last_click = (0, -1)
        self.quit = False
        self.load(hovered)

    # listing
    def load(self, select_name=None):
        self.gen += 1
        self.jobs = {}
        try:
            items = list(os.scandir(self.cwd))
        except OSError:
            items = []
        if not self.hidden:
            items = [e for e in items if not e.name.startswith(".")]

        def natural(s):
            return [int(x) if x.isdigit() else x.lower() for x in re.split(r"(\d+)", s)]

        def isdir(e):
            try:
                return e.is_dir()
            except OSError:
                return False

        items.sort(key=lambda e: (not isdir(e), natural(e.name)))
        self.items = [(Path(e.path), isdir(e)) for e in items]
        self.sel = 0
        if select_name:
            for i, (p, _) in enumerate(self.items):
                if p.name == select_name:
                    self.sel = i
                    break
        self.top = 0
        self.redraw()

    # geometry
    def layout(self):
        rows, cols, cw, ch = self.t.size()
        self.rows, self.cols, self.cw, self.ch = rows, cols, cw, ch
        self.ncol = max(1, cols // TILE_W)
        self.x0 = (cols - self.ncol * TILE_W) // 2
        self.y0 = 2                               # under the header
        self.nrow = max(1, (rows - 3) // TILE_H)  # leave the footer line
        self.img_cols, self.img_rows = TILE_W - 4, TILE_H - 4
        self.img_px = (max(8, int(self.img_cols * cw)), max(8, int(self.img_rows * ch)))

    def visible(self):
        start = self.top * self.ncol
        return range(start, min(len(self.items), start + self.ncol * self.nrow))

    def origin(self, i):
        k = i - self.top * self.ncol
        return self.y0 + (k // self.ncol) * TILE_H, self.x0 + (k % self.ncol) * TILE_W

    def at(self, y, x):
        """Tile index under a 1-based terminal cell, or None."""
        r, c = (y - 1 - self.y0) // TILE_H, (x - 1 - self.x0) // TILE_W
        if y - 1 < self.y0 or x - 1 < self.x0 or not (0 <= r < self.nrow and 0 <= c < self.ncol):
            return None
        i = (self.top + r) * self.ncol + c
        return i if i < len(self.items) else None

    # drawing
    def move(self, y, x):
        self.t.write(f"\x1b[{y + 1};{x + 1}H")

    def place(self, i, png):
        y, x = self.origin(i)
        self.move(y + 1, x + 2)
        path = base64.b64encode(str(png).encode()).decode()
        img_id = i + 1
        self.t.write(f"\x1b_Ga=d,d=I,i={img_id},q=2\x1b\\")
        self.t.write(f"\x1b_Ga=T,t=f,f=100,i={img_id},c={self.img_cols},r={self.img_rows},C=1,q=2;{path}\x1b\\")
        self.placed[i] = png

    def draw_tile(self, i, selected):
        y, x = self.origin(i)
        p, isdir = self.items[i]
        border = fg("accent") if selected else ""
        h = "─" * (TILE_W - 2)
        if selected:
            self.move(y, x); self.t.write(border + "╭" + h + "╮" + RESET)
            for r in range(1, TILE_H - 1):
                self.move(y + r, x); self.t.write(border + "│" + RESET)
                self.move(y + r, x + TILE_W - 1); self.t.write(border + "│" + RESET)
            self.move(y + TILE_H - 1, x); self.t.write(border + "╰" + h + "╯" + RESET)
        else:
            blank = " " * TILE_W
            self.move(y, x); self.t.write(blank)
            for r in range(1, TILE_H - 1):
                self.move(y + r, x); self.t.write(" ")
                self.move(y + r, x + TILE_W - 1); self.t.write(" ")
            self.move(y + TILE_H - 1, x); self.t.write(blank)
        lines = wrap2(p.name + ("/" if isdir else ""), TILE_W - 4)
        col = "text" if not p.name.startswith(".") else "overlay0"
        for k, line in enumerate(lines):
            pad = TILE_W - 2 - width(line)
            label = " " * (pad // 2) + line + " " * (pad - pad // 2)
            self.move(y + TILE_H - 3 + k, x + 1)
            if selected:
                self.t.write(bg("accent") + fg("crust") + "\x1b[1m" + label + RESET)
            else:
                self.t.write(fg(col) + label + RESET)

    def header(self):
        shown = str(self.cwd).replace(str(HOME), "~", 1)
        n = len(self.items)
        left = f" \U000F024B  {shown}"
        right = f"{self.sel + 1 if n else 0}/{n}  " + ("" if self.hidden else "· hidden off  ")
        self.move(0, 0)
        self.t.write("\x1b[2K" + fg("accent") + "\x1b[1m" + fit(left, self.cols - width(right) - 1) + RESET)
        self.move(0, self.cols - width(right))
        self.t.write(fg("overlay0") + right + RESET)
        hint = " ↵ open · ⌫ up · . hidden · q / Alt+G back to list"
        if self.items:
            p, isdir = self.items[self.sel]
            info = "folder" if isdir else human(p)
            hint = f" {fit(p.name, self.cols // 2)}  ·  {info}   " + hint
        self.move(self.rows - 1, 0)
        self.t.write("\x1b[2K" + fg("overlay0") + fit(hint, self.cols - 1) + RESET)

    def redraw(self):
        self.layout()
        self.t.write("\x1b_Ga=d,d=A,q=2\x1b\\\x1b[2J")
        self.placed = {}
        if not self.items:
            self.move(self.rows // 2, max(0, self.cols // 2 - 6))
            self.t.write(fg("overlay0") + "(empty folder)" + RESET)
        for i in self.visible():
            self.draw_tile(i, i == self.sel)
            self.show_picture(i)
        self.header()
        self.t.flush()

    def show_picture(self, i):
        p, isdir = self.items[i]
        kind = kind_of(p, isdir)
        w, h = self.img_px
        ext = p.suffix.lower().lstrip(".")
        if not isdir and (ext in IMAGE_EXT or ext in VIDEO_EXT or ext == "pdf"):
            key = (i, self.gen, w, h)
            fut = self.jobs.get(i)
            if fut is None or fut.key != key:
                fut = self.pool.submit(thumb_png, p, kind, w, h)
                fut.key = key
                self.jobs[i] = fut
            if fut.done() and fut.result():
                self.place(i, fut.result())
                return
        self.place(i, icon_png(kind, w, h))

    def poll_jobs(self):
        changed = False
        vis = self.visible()
        for i, fut in list(self.jobs.items()):
            if fut.done():
                res = fut.result()
                if res and i in vis and self.placed.get(i) != res:
                    self.place(i, res)
                    changed = True
                del self.jobs[i]
        if changed:
            self.t.flush()

    # actions
    def select(self, i):
        if not self.items:
            return
        i = max(0, min(len(self.items) - 1, i))
        old, self.sel = self.sel, i
        row = i // self.ncol
        if row < self.top or row >= self.top + self.nrow:
            self.top = row if row < self.top else row - self.nrow + 1
            self.redraw()
            return
        if old != i and old in self.visible():
            self.draw_tile(old, False)
        self.draw_tile(i, True)
        self.header()
        self.t.flush()

    def scroll(self, d):
        maxtop = max(0, (len(self.items) - 1) // self.ncol - self.nrow + 1)
        top = max(0, min(maxtop, self.top + d))
        if top != self.top:
            self.top = top
            vis = self.visible()
            if self.sel not in vis and len(vis):
                self.sel = vis[0] if d > 0 else vis[-1]
            self.redraw()

    def activate(self):
        if not self.items:
            return
        p, isdir = self.items[self.sel]
        if isdir:
            self.cwd = p
            self.load()
        else:
            subprocess.Popen(["xdg-open", str(p)], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL, start_new_session=True)

    def parent(self):
        if self.cwd.parent != self.cwd:
            name = self.cwd.name
            self.cwd = self.cwd.parent
            self.load(name)

    # input
    def handle(self, data):
        i = 0
        while i < len(data):
            m = re.match(rb"\x1b\[<(\d+);(\d+);(\d+)([Mm])", data[i:])
            if m:
                self.mouse(int(m[1]), int(m[2]), int(m[3]), m[4] == b"M")
                i += m.end()
                continue
            for seq, act in KEYS:
                if data.startswith(seq, i):
                    act(self)
                    i += len(seq)
                    break
            else:
                if data[i:i + 1] == b"\x1b" and i == len(data) - 1:
                    self.quit = True                 # a lone Esc
                i += 1
            if self.quit:
                return

    def mouse(self, b, x, y, press):
        if b == 64:
            self.scroll(-1)
        elif b == 65:
            self.scroll(1)
        elif b == 0 and press:
            i = self.at(y, x)
            if i is None:
                return
            now = time.monotonic()
            double = self.last_click[1] == i and now - self.last_click[0] < 0.4
            self.last_click = (now, i)
            self.select(i)
            if double:
                self.activate()

    def run(self):
        signal.signal(signal.SIGTERM, lambda *a: setattr(self, "quit", True))
        resized = []
        signal.signal(signal.SIGWINCH, lambda *a: resized.append(1))
        try:
            while not self.quit:
                try:
                    data = self.t.read(0.05)
                except InterruptedError:
                    data = b""
                if resized:
                    resized.clear()
                    self.redraw()
                if data:
                    self.handle(data)
                self.poll_jobs()
        finally:
            self.pool.shutdown(wait=False, cancel_futures=True)
            self.t.close()
        return self.items[self.sel][0] if self.items else self.cwd


def human(p):
    try:
        n = p.stat().st_size
    except OSError:
        return "?"
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if n < 1024 or unit == "TB":
            return f"{n:.0f} {unit}" if unit == "B" else f"{n:.1f} {unit}"
        n /= 1024


def _quit(g):
    g.quit = True


def _toggle_hidden(g):
    g.hidden = not g.hidden
    name = g.items[g.sel][0].name if g.items else None
    g.load(name)


KEYS = [
    (b"\x1b[A", lambda g: g.select(g.sel - g.ncol)), (b"\x1bOA", lambda g: g.select(g.sel - g.ncol)),
    (b"\x1b[B", lambda g: g.select(g.sel + g.ncol)), (b"\x1bOB", lambda g: g.select(g.sel + g.ncol)),
    (b"\x1b[C", lambda g: g.select(g.sel + 1)), (b"\x1bOC", lambda g: g.select(g.sel + 1)),
    (b"\x1b[D", lambda g: g.select(g.sel - 1)), (b"\x1bOD", lambda g: g.select(g.sel - 1)),
    (b"\x1b[5~", lambda g: g.select(g.sel - g.ncol * g.nrow)),
    (b"\x1b[6~", lambda g: g.select(g.sel + g.ncol * g.nrow)),
    (b"\x1b[H", lambda g: g.select(0)), (b"\x1b[1~", lambda g: g.select(0)),
    (b"\x1b[F", lambda g: g.select(len(g.items) - 1)), (b"\x1b[4~", lambda g: g.select(len(g.items) - 1)),
    (b"\x1bg", _quit), (b"\x1bG", _quit),
    (b"k", lambda g: g.select(g.sel - g.ncol)), (b"j", lambda g: g.select(g.sel + g.ncol)),
    (b"l", lambda g: g.activate() if g.items and g.items[g.sel][1] else g.select(g.sel + 1)),
    (b"h", lambda g: g.select(g.sel - 1)),
    (b"\r", lambda g: g.activate()), (b"\n", lambda g: g.activate()),
    (b"\x7f", lambda g: g.parent()), (b"\x08", lambda g: g.parent()), (b"-", lambda g: g.parent()),
    (b"g", lambda g: g.select(0)), (b"G", lambda g: g.select(len(g.items) - 1)),
    (b".", _toggle_hidden),
    (b"q", _quit), (b"\x03", _quit),
]


def main():
    CACHE.mkdir(parents=True, exist_ok=True)
    args = sys.argv[1:]
    standalone = args[:1] == ["--yazi"]
    if standalone:
        args = args[1:]
    cwd = Path.cwd()
    hovered = None
    if standalone and args:
        p = Path(args[0]).expanduser()
        cwd, hovered = (p, None) if p.is_dir() else (p.parent, p.name)
    elif len(args) == 1:
        h = Path(args[0])
        if h.parent == cwd:
            hovered = h.name
    os.chdir(cwd)
    target = Grid(cwd, hovered).run()
    if standalone:
        # leaving the grid opens the normal yazi list on the selected item
        yazi = HOME / ".local/bin/yazi"
        os.execv(str(yazi), [str(yazi), str(target)])
    # back in yazi: land on what was selected here
    if os.environ.get("YAZI_ID") and YA.exists():
        subprocess.run([str(YA), "emit", "reveal", str(target)], capture_output=True)


if __name__ == "__main__":
    main()
