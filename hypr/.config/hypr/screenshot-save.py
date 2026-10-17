#!/usr/bin/python3
"""Ask what to do with a screenshot — run by screenshot.sh after every capture.

    screenshot-save.py <captured.png> <label>

The capture is already on the clipboard by the time this opens; this only
decides whether it is ALSO kept as a file, and where:

  Discard  (focused: Enter, or Escape)   delete the capture; the clipboard
                      copy stays. The DEFAULT — a reflexive Enter never leaves
                      a file behind.
  Save…    (Tab/→ then Enter, or click)   pick a folder — the system folder
                      picker, i.e. yazi via xdg-desktop-portal-termfilechooser
                      (navigate into the folder, then q). Starts in the last
                      folder you saved to.

Cancelling the folder picker comes back here rather than discarding, so a
stray q in yazi doesn't lose the shot. Closing the popup any other way
discards (the file is only a temp copy in $XDG_RUNTIME_DIR).

Normal toplevel window, centred and floated by the `screenshot-save`
windowrule in hyprland.conf; app_id from set_prgname(), like the other panels.
"""

import os
import shutil
import subprocess
import sys

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")       # pin BEFORE importing — see network-panel.py
gi.require_version("GdkPixbuf", "2.0")

from gi.repository import GLib  # noqa: E402

GLib.set_prgname("screenshot-save")    # app_id; must precede the Gtk/Gdk import

from gi.repository import Gdk, GdkPixbuf, Gtk  # noqa: E402

# The folder picker must go through the portal (→ yazi), not GTK's own dialog.
os.environ["GTK_USE_PORTAL"] = "1"

DEFAULT_DIR = os.path.expanduser("~/Pictures/Screenshots")
STATE = os.path.join(os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")),
                     "screenshot-last-dir")
ACCENT_FILE = os.path.expanduser("~/.config/hypr/theme/accent")

BASE, MANTLE, SURFACE0, SURFACE1 = "#1e1e2e", "#181825", "#313244", "#45475a"
TEXT, SUBTEXT, OVERLAY, RED = "#cdd6f4", "#a6adc8", "#6c7086", "#f38ba8"



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

def read_accent():
    """Live accent (SUPER+ALT+C), read at runtime like network-panel.py."""
    try:
        with open(ACCENT_FILE) as f:
            hexv = f.read().strip().lstrip("#")
        int(hexv, 16)
        if len(hexv) == 6:
            return "#" + hexv
    except (OSError, ValueError):
        pass
    return "#89b4fa"


ACCENT = read_accent()

CSS = f"""
window {{ background: {BASE}; color: {TEXT}; font-family: "JetBrainsMono Nerd Font"; }}
.title {{ font-size: 13pt; font-weight: 700; color: {TEXT}; }}
.meta {{ font-size: 9pt; color: {OVERLAY}; }}
.preview {{ background: {MANTLE}; border: 1px solid {SURFACE1}; border-radius: 8px; padding: 6px; }}
button {{ background: {SURFACE0}; color: {TEXT}; border: none; box-shadow: none;
          border-radius: 8px; padding: 7px 18px; font-weight: 600; }}
button:hover {{ background: {SURFACE1}; }}
button.save {{ background: {ACCENT}; color: {BASE}; }}
button.save:hover {{ background: shade({ACCENT}, 1.1); }}
button.discard:hover {{ color: {RED}; }}
/* Show which button Enter will press — Discard on open. */
button:focus {{ box-shadow: inset 0 0 0 2px {TEXT}; outline: none; }}
"""


def last_dir():
    try:
        with open(STATE) as f:
            d = f.read().strip()
        if os.path.isdir(d):
            return d
    except OSError:
        pass
    return DEFAULT_DIR


def remember_dir(d):
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    with open(STATE, "w") as f:
        f.write(d)


def notify(*args):
    subprocess.run(["notify-send", "-a", "Screenshot", *args],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


class SavePopup(Gtk.Window):
    def __init__(self, path, label):
        super().__init__(title="Save screenshot?")
        self.path = path
        self.set_resizable(False)
        self.set_border_width(16)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        self.add(box)

        title = Gtk.Label(label="Save screenshot?", xalign=0)
        title.get_style_context().add_class("title")
        box.pack_start(title, False, False, 0)

        pix = GdkPixbuf.Pixbuf.new_from_file(path)
        w, h = pix.get_width(), pix.get_height()
        scale = min(1.0, 520 / w, 320 / h)
        thumb = pix.scale_simple(max(1, int(w * scale)), max(1, int(h * scale)),
                                 GdkPixbuf.InterpType.BILINEAR)
        frame = Gtk.Box()
        frame.get_style_context().add_class("preview")
        frame.pack_start(Gtk.Image.new_from_pixbuf(thumb), True, True, 0)
        box.pack_start(frame, False, False, 0)

        meta = Gtk.Label(label=f"{label} · {w}×{h} · already copied to clipboard", xalign=0)
        meta.get_style_context().add_class("meta")
        box.pack_start(meta, False, False, 0)

        buttons = Gtk.Box(spacing=8)
        discard = Gtk.Button(label="Discard")
        discard.get_style_context().add_class("discard")
        discard.connect("clicked", lambda *_: self.discard())
        save = Gtk.Button(label="Save…")
        save.get_style_context().add_class("save")
        save.connect("clicked", lambda *_: self.save())
        buttons.pack_end(save, False, False, 0)
        buttons.pack_end(discard, False, False, 0)
        box.pack_start(buttons, False, False, 0)

        self.connect("key-press-event", self.on_key)
        self.connect("delete-event", lambda *_: self.discard() or True)
        # Discard is the default: it has focus on open, so Enter discards.
        discard.set_can_default(True)
        self.set_default(discard)
        discard.grab_focus()
        self.set_focus_visible(True)

    def on_key(self, _w, event):
        if event.keyval == Gdk.KEY_Escape:
            self.discard()
            return True
        return False                    # Enter / Space press the FOCUSED button

    def save(self):
        chooser = Gtk.FileChooserNative.new(
            "Save screenshot in…", self, Gtk.FileChooserAction.SELECT_FOLDER, "Save here", "Cancel")
        start = last_dir()
        os.makedirs(start, exist_ok=True)
        chooser.set_current_folder(start)
        resp = chooser.run()
        folder = chooser.get_filename() if resp == Gtk.ResponseType.ACCEPT else None
        chooser.destroy()
        if not folder:
            return                              # picker cancelled: back to the popup
        name = os.path.basename(self.path)
        dest = os.path.join(folder, name)
        stem, ext = os.path.splitext(name)
        n = 1
        while os.path.exists(dest):            # never overwrite an existing file
            dest = os.path.join(folder, f"{stem}-{n}{ext}")
            n += 1
        try:
            shutil.move(self.path, dest)
        except OSError as e:
            notify("-u", "critical", "Screenshot not saved", str(e))
            return
        remember_dir(folder)
        notify("-i", dest, "Screenshot saved", dest.replace(os.path.expanduser("~"), "~", 1))
        Gtk.main_quit()

    def discard(self):
        try:
            os.remove(self.path)
        except OSError:
            pass
        notify("Screenshot discarded", "Still on the clipboard")
        Gtk.main_quit()


def main():
    if len(sys.argv) < 2 or not os.path.isfile(sys.argv[1]):
        print("usage: screenshot-save.py <captured.png> [label]", file=sys.stderr)
        return 2
    provider = Gtk.CssProvider()
    provider.load_from_data(_rice_subst(CSS).encode())
    Gtk.StyleContext.add_provider_for_screen(
        Gdk.Screen.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
    win = SavePopup(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "Screenshot")
    win.show_all()
    Gtk.main()
    return 0


if __name__ == "__main__":
    sys.exit(main())
