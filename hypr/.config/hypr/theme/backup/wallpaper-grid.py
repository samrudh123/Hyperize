#!/usr/bin/python3
"""A grid of wallpaper thumbnails — SUPER+W (desktop), SUPER+SHIFT+W (lock).

Replaces the old fuzzel pickers, which could only list file names: choosing a
wallpaper from its filename means opening the folder to see what you are picking.

Two modes, one window — same thumbnails, different setter:

  wallpaper-grid.py            desktop wallpaper  -> set-wallpaper.sh
  wallpaper-grid.py --lock     lock screen image  -> set-lockscreen.sh

Deliberately a **normal toplevel window**, not a layer-shell surface. Layer
surfaces on this setup have cost real time — dead blur rules keyed on the wrong
namespace, and a GTK drag that froze the whole seat (landmines 13 and 16). A
plain window needs none of that: one `windowrule` floats and centres it, and
Hyprland's own keybinds and focus handling apply normally. Both modes keep the
same app_id so a single pair of rules covers them.

Setting is delegated to the shell scripts so the saved-state file, swaybg's
no-flash replacement and hyprlock.conf's backup-and-verify edit stay in exactly
one place each.

  Click or Enter   set that wallpaper and close
  Escape / q       close, change nothing
  arrows / Tab     move around the grid
"""

import hashlib
import os
import re
import subprocess
import sys

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import GdkPixbuf, GLib, Gtk  # noqa: E402

# app_id comes from prgname on Wayland, and the windowrule matches on it.
# Must be set before the first window is realised.
GLib.set_prgname("wallpaper-grid")

HOME = os.path.expanduser("~")
WALLPAPERS = os.path.join(HOME, "Pictures/wallpapers")
# Ubuntu's stock backgrounds, offered for the DESKTOP only (see Mode.sources).
# The lock screen deliberately stays a short, curated list.
SYSTEM_WALLPAPERS = "/usr/share/backgrounds"
SETTER = os.path.join(HOME, ".config/hypr/set-wallpaper.sh")
LOCK_SETTER = os.path.join(HOME, ".config/hypr/set-lockscreen.sh")
STATE = os.path.join(HOME, ".config/hypr/wallpaper")
LOCK_CONF = os.path.join(HOME, ".config/hypr/hyprlock.conf")
CACHE = os.path.join(HOME, ".cache/wallpaper-thumbs")

# hyprlock takes the literal word `screenshot` instead of a path: blur whatever
# is on screen at lock time. It gets a tile of its own, first in the grid.
SCREENSHOT = "screenshot"

EXTS = (".png", ".jpg", ".jpeg", ".webp", ".bmp")
THUMB_W, THUMB_H = 320, 180
COLUMNS = 3

CSS = b"""
window { background-color: #1e1e2e; }
#grid { padding: 14px; }
flowboxchild {
  padding: 8px;
  margin: 6px;
  border-radius: 14px;
  border: 1px solid transparent;
}
flowboxchild:selected, flowboxchild:focus {
  background-color: #313244;
  border-color: #cba6f7;
}
label { color: #cdd6f4; font-family: "JetBrainsMono Nerd Font", monospace;
        font-size: 12px; padding-top: 6px; }
#current { color: #a6e3a1; font-weight: bold; }
#header { color: #bac2de; font-size: 13px; padding: 10px 14px 0 14px; }
#placeholder {
  background-color: #45475a;
  border-radius: 10px;
  color: #bac2de;
  font-size: 22px;
}
"""


def wallpapers(dirs=(WALLPAPERS,)):
    """Image files from `dirs`, in the order given, first occurrence wins.

    Personal wallpapers come first so they stay at the top of the grid.

    Deduplicated by realpath, not by name: /usr/share/backgrounds ships
    `ubuntu-default-greyscale-wallpaper.png` as a symlink to
    `Resolute_Raccoon_Wallpaper_Dimmed_3840x2160.png` in the same directory,
    and without this the same picture appears twice in the grid.
    """
    out, seen = [], set()
    for d in dirs:
        if not os.path.isdir(d):
            continue
        for f in sorted(os.listdir(d)):
            if not f.lower().endswith(EXTS):
                continue
            path = os.path.join(d, f)
            if not os.path.isfile(path):        # skips subdirs, e.g. contest/
                continue
            key = os.path.realpath(path)
            if key in seen:
                continue
            seen.add(key)
            out.append(path)
    return out


def thumbnail(path):
    """Return a cached thumbnail path, keyed on mtime so edits are picked up."""
    os.makedirs(CACHE, exist_ok=True)
    stamp = int(os.path.getmtime(path))
    # Key on the full path, not just the basename: with more than one source
    # directory two different images can share a name and would otherwise
    # collide in the cache, showing the wrong thumbnail.
    tag = hashlib.sha1(path.encode()).hexdigest()[:8]
    out = os.path.join(CACHE, f"{os.path.basename(path)}.{tag}.{stamp}.png")
    if os.path.exists(out):
        return out
    try:
        from PIL import Image

        im = Image.open(path)
        im.thumbnail((THUMB_W, THUMB_H), Image.LANCZOS)
        im.convert("RGB").save(out, "PNG")
        return out
    except Exception as e:                      # unreadable or not an image
        print(f"thumbnail failed for {path}: {e}", file=sys.stderr)
        return None


def current():
    """Path of the current DESKTOP wallpaper, per set-wallpaper.sh's state file."""
    try:
        with open(STATE) as fh:
            return fh.read().strip()
    except OSError:
        return ""


def current_lock():
    """Current lock image: the `path =` line in hyprlock.conf's background block.

    Same block-scoped read as set-lockscreen.sh --show, so the two never
    disagree about what is set.
    """
    try:
        with open(LOCK_CONF) as fh:
            conf = fh.read()
    except OSError:
        return ""
    block = re.search(r"background\s*\{.*?\}", conf, re.S)
    if not block:
        return ""
    line = re.search(r"^\s*path\s*=\s*(.+?)\s*$", block.group(0), re.M)
    return line.group(1) if line else ""


class Mode:
    """What differs between the two pickers. Everything else is shared."""

    def __init__(self, lock):
        self.lock = lock
        if lock:
            self.title = "Lock screen"
            self.setter = LOCK_SETTER
            self.noun = "lock screen"
            self.current = current_lock()
            self.sources = (WALLPAPERS,)
        else:
            self.title = "Wallpaper"
            self.setter = SETTER
            self.noun = "wallpapers"
            self.current = current()
            # Desktop only: Ubuntu's stock backgrounds are offered here but
            # not on the lock screen.
            self.sources = (WALLPAPERS, SYSTEM_WALLPAPERS)

    def entries(self, paths):
        # `screenshot` is lock-only, and goes first so it is the default focus
        # target when nothing else is set.
        return ([SCREENSHOT] + paths) if self.lock else paths


class Picker(Gtk.Window):
    def __init__(self, mode, entries):
        super().__init__(title=mode.title)
        self.mode = mode
        self.entries = entries
        # Size to content rather than a fixed windowrule size: one row of three
        # wallpapers in a 520px-tall window left most of it empty. Caps at three
        # rows, after which the ScrolledWindow takes over.
        import math
        rows = max(1, min(math.ceil(len(entries) / COLUMNS), 3))
        self.set_default_size(COLUMNS * (THUMB_W + 34) + 24,
                              46 + rows * (THUMB_H + 58) + 16)
        now = mode.current

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.add(outer)

        header = Gtk.Label(
            label=f"{len(entries)} {mode.noun}  ·  Enter to set  ·  Esc to close")
        header.set_name("header")
        header.set_xalign(0)
        outer.pack_start(header, False, False, 0)

        scroller = Gtk.ScrolledWindow()
        scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        outer.pack_start(scroller, True, True, 0)

        self.flow = Gtk.FlowBox()
        self.flow.set_name("grid")
        self.flow.set_valign(Gtk.Align.START)
        self.flow.set_max_children_per_line(COLUMNS)
        self.flow.set_min_children_per_line(COLUMNS)
        self.flow.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self.flow.connect("child-activated", self.on_activate)
        scroller.add(self.flow)

        for entry in entries:
            self.flow.add(self.tile(entry, entry == now))

        self.connect("key-press-event", self.on_key)
        self.connect("destroy", Gtk.main_quit)

    def tile(self, path, is_current):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        if path == SCREENSHOT:
            box.pack_start(self.placeholder("live screen"), False, False, 0)
            name = "screenshot — blur the live screen"
        else:
            thumb = thumbnail(path)
            if thumb:
                try:
                    pb = GdkPixbuf.Pixbuf.new_from_file(thumb)
                    box.pack_start(Gtk.Image.new_from_pixbuf(pb), False, False, 0)
                except GLib.Error:
                    thumb = None
            if not thumb:
                box.pack_start(self.placeholder("(no preview)"), False, False, 0)
            name = os.path.basename(path)

        label = Gtk.Label(label=("● " + name) if is_current else name)
        label.set_max_width_chars(28)
        label.set_ellipsize(3)                  # Pango.EllipsizeMode.END
        if is_current:
            label.set_name("current")
        box.pack_start(label, False, False, 0)
        return box

    def placeholder(self, text):
        """A thumbnail-sized stand-in, so tiles without an image still line up."""
        label = Gtk.Label(label=text)
        label.set_name("placeholder")
        label.set_size_request(THUMB_W, THUMB_H)
        return label

    def on_activate(self, _flow, child):
        entry = self.entries[child.get_index()]
        # Let the setter own swaybg / the hyprlock.conf edit.
        subprocess.Popen([self.mode.setter, entry], start_new_session=True)
        Gtk.main_quit()

    def on_key(self, _w, event):
        from gi.repository import Gdk

        if event.keyval in (Gdk.KEY_Escape, Gdk.KEY_q):
            Gtk.main_quit()
            return True
        return False


def main():
    mode = Mode(lock="--lock" in sys.argv[1:])
    paths = wallpapers(mode.sources)
    if not paths and not mode.lock:
        subprocess.run(["notify-send", "-a", "Wallpaper", "No wallpapers found",
                        WALLPAPERS])
        return 1

    provider = Gtk.CssProvider()
    provider.load_from_data(CSS)
    Gtk.StyleContext.add_provider_for_screen(
        Gdk_screen(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

    entries = mode.entries(paths)
    win = Picker(mode, entries)
    win.show_all()
    # Focus the current choice if it is in the grid, else the first tile.
    index = entries.index(mode.current) if mode.current in entries else 0
    child = win.flow.get_child_at_index(index)
    if child:
        win.flow.select_child(child)
        child.grab_focus()
    Gtk.main()
    return 0


def Gdk_screen():
    from gi.repository import Gdk

    return Gdk.Screen.get_default()


if __name__ == "__main__":
    sys.exit(main())
