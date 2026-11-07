#!/usr/bin/python3
"""Ask what to do with a screenshot or a screen recording — run by
screenshot.sh after every capture, and by screen-record.py when a recording
stops.

    screenshot-save.py <captured.png|recording.mp4> <label>

VIDEOS (by extension) are the same popup with a frame from the video, its
length and size, a Play button, and safer defaults — a recording can be an
hour of work:
  Save…    is FOCUSED (Enter); starts in the last folder a video went to
           (~/Videos/Recordings at first).
  Discard  only by a click / Tab-to-it; deletes the file.
  Escape / closing the window KEEPS it: moved to ~/Videos/Recordings (an OBS
           recording, already in OBS's own folder, stays there).
The saved path is printed on stdout, so screen-record.py can post its
"Recording saved" notification (Play / Show in folder / Copy) for it.

Screenshots:

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

VIDEO_EXT = (".mp4", ".mkv", ".webm", ".mov", ".flv", ".avi")
AUDIO_EXT = (".m4a", ".ogg", ".opus", ".mp3", ".wav", ".flac")
_ARG = sys.argv[1].lower() if len(sys.argv) > 1 else ""
IS_AUDIO = _ARG.endswith(AUDIO_EXT)                # sound-only recordings
IS_VIDEO = _ARG.endswith(VIDEO_EXT) or IS_AUDIO    # = any recording (same rules)
KIND = "recording" if IS_VIDEO else "screenshot"
APP = "Screen recorder" if IS_VIDEO else "Screenshot"
DEFAULT_DIR = os.path.expanduser("~/Music/Recordings" if IS_AUDIO else
                                 "~/Videos/Recordings" if IS_VIDEO else "~/Pictures/Screenshots")
STATE = os.path.join(os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")),
                     "audio-last-dir" if IS_AUDIO else
                     "recording-last-dir" if IS_VIDEO else "screenshot-last-dir")
# where Escape leaves a video: our own temp folder → the default folder;
# anywhere else (OBS's output folder) → where it is
PENDING_DIR = os.path.expanduser("~/.cache/screen-record")
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
    subprocess.run(["notify-send", "-a", APP, *args],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


class SavePopup(Gtk.Window):
    def __init__(self, path, label):
        super().__init__(title=f"Save {KIND}?")
        self.path = path
        self.set_resizable(False)
        self.set_border_width(16)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        self.add(box)

        title = Gtk.Label(label=f"Save {KIND}?", xalign=0)
        title.get_style_context().add_class("title")
        box.pack_start(title, False, False, 0)

        if IS_VIDEO:
            pix, w, h, info = video_preview(path)
        else:
            pix = GdkPixbuf.Pixbuf.new_from_file(path)
            w, h = pix.get_width(), pix.get_height()
            info = "already copied to clipboard"
        if pix:
            scale = min(1.0, 520 / pix.get_width(), 320 / pix.get_height())
            thumb = pix.scale_simple(max(1, int(pix.get_width() * scale)), max(1, int(pix.get_height() * scale)),
                                     GdkPixbuf.InterpType.BILINEAR)
            frame = Gtk.Box()
            frame.get_style_context().add_class("preview")
            frame.pack_start(Gtk.Image.new_from_pixbuf(thumb), True, True, 0)
            box.pack_start(frame, False, False, 0)

        size = f" · {w}×{h}" if w and h else ""
        meta = Gtk.Label(label=f"{label}{size} · {info}", xalign=0)
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
        if IS_VIDEO:
            play = Gtk.Button(label="Play")
            play.connect("clicked", lambda *_: subprocess.Popen(
                ["xdg-open", self.path], start_new_session=True,
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL))
            buttons.pack_end(play, False, False, 0)
        buttons.pack_end(discard, False, False, 0)
        box.pack_start(buttons, False, False, 0)
        if IS_VIDEO:
            hint = Gtk.Label(label="Esc keeps it in " + self.keep_dir().replace(os.path.expanduser("~"), "~", 1), xalign=0)
            hint.get_style_context().add_class("meta")
            box.pack_start(hint, False, False, 0)

        self.connect("key-press-event", self.on_key)
        self.connect("delete-event", lambda *_: self.leave() or True)
        # Screenshots: Discard is the default (focused, so Enter discards).
        # Videos: Save… is — a reflexive Enter must not delete a recording.
        first = save if IS_VIDEO else discard
        first.set_can_default(True)
        self.set_default(first)
        first.grab_focus()
        self.set_focus_visible(True)

    def keep_dir(self):
        here = os.path.dirname(os.path.abspath(self.path))
        return DEFAULT_DIR if os.path.realpath(here) == os.path.realpath(PENDING_DIR) else here

    def leave(self):
        """Escape / window closed: screenshots are discarded, videos kept."""
        if not IS_VIDEO:
            self.discard()
            return
        folder = self.keep_dir()
        if os.path.realpath(folder) == os.path.realpath(os.path.dirname(os.path.abspath(self.path))):
            print(self.path, flush=True)
            Gtk.main_quit()
            return
        self.save_to(folder)

    def on_key(self, _w, event):
        if event.keyval == Gdk.KEY_Escape:
            self.leave()
            return True
        return False                    # Enter / Space press the FOCUSED button

    def save(self):
        chooser = Gtk.FileChooserNative.new(
            f"Save {KIND} in…", self, Gtk.FileChooserAction.SELECT_FOLDER, "Save here", "Cancel")
        start = last_dir()
        os.makedirs(start, exist_ok=True)
        chooser.set_current_folder(start)
        resp = chooser.run()
        folder = chooser.get_filename() if resp == Gtk.ResponseType.ACCEPT else None
        chooser.destroy()
        if not folder:
            return                              # picker cancelled: back to the popup
        self.save_to(folder)

    def save_to(self, folder):
        os.makedirs(folder, exist_ok=True)
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
            notify("-u", "critical", f"{KIND.capitalize()} not saved", str(e))
            return
        remember_dir(folder)
        print(dest, flush=True)
        if not IS_VIDEO:                        # videos: screen-record.py says it
            notify("-i", dest, "Screenshot saved", dest.replace(os.path.expanduser("~"), "~", 1))
        Gtk.main_quit()

    def discard(self):
        try:
            os.remove(self.path)
        except OSError:
            pass
        if IS_VIDEO:
            notify("Recording discarded")
        else:
            notify("Screenshot discarded", "Still on the clipboard")
        Gtk.main_quit()


def video_preview(path):
    """(pixbuf of a frame or None, width, height, "1:23 · 45.6 MB")."""
    w = h = 0
    secs = 0.0
    try:
        out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0",
                              "-show_entries", "stream=width,height:format=duration",
                              "-of", "json", path], capture_output=True, text=True, timeout=5).stdout
        import json
        j = json.loads(out or "{}")
        st = (j.get("streams") or [{}])[0]
        w, h = int(st.get("width") or 0), int(st.get("height") or 0)
        secs = float((j.get("format") or {}).get("duration") or 0)
    except (OSError, ValueError, subprocess.SubprocessError):
        pass
    pix = None
    thumb = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), f"rec-thumb-{os.getpid()}.png")
    # a video: a frame from it; sound only: its waveform in the accent
    grab = (["-filter_complex", f"showwavespic=s=520x110:split_channels=0:colors={ACCENT}", "-frames:v", "1"]
            if IS_AUDIO else ["-frames:v", "1", "-vf", "scale=520:-2"])
    try:
        subprocess.run(["ffmpeg", "-v", "error", "-y"] + ([] if IS_AUDIO else ["-ss", f"{min(1.0, secs / 2):.2f}"])
                       + ["-i", path] + grab + [thumb],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=10)
        pix = GdkPixbuf.Pixbuf.new_from_file(thumb)
    except (OSError, GLib.Error, subprocess.SubprocessError):
        pix = None
    finally:
        try:
            os.remove(thumb)
        except OSError:
            pass
    s = int(round(secs))
    length = f"{s // 3600}:{s // 60 % 60:02d}:{s % 60:02d}" if s >= 3600 else f"{s // 60}:{s % 60:02d}"
    try:
        mb = os.path.getsize(path) / 1e6
    except OSError:
        mb = 0
    return pix, w, h, f"{length} · " + (f"{mb:.1f} MB" if mb >= 1 else f"{mb * 1000:.0f} KB")


def main():
    if len(sys.argv) < 2 or not os.path.isfile(sys.argv[1]):
        print("usage: screenshot-save.py <captured.png|recording.mp4> [label]", file=sys.stderr)
        return 2
    provider = Gtk.CssProvider()
    provider.load_from_data(_rice_subst(CSS).encode())
    Gtk.StyleContext.add_provider_for_screen(
        Gdk.Screen.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
    win = SavePopup(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else KIND.capitalize())
    win.show_all()
    Gtk.main()
    return 0


if __name__ == "__main__":
    sys.exit(main())
