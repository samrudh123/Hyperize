#!/usr/bin/python3
"""A grid of accent colours — SUPER+ALT+C.

Moving the selection previews the colour on the live desktop; Enter keeps it,
Escape puts back whatever you started with.

  Click / Enter    commit this colour
  arrows / Tab     move around the grid (previews as you go)
  Escape / q       restore the colour you opened with, and close

WHAT IS ACTUALLY LIVE

Not everything can repaint without being restarted, so preview and commit do
different amounts of work — see set-accent.sh for the file-level detail.

  instant   window borders   `hyprctl keyword`, no file is written at all
  instant   both bars        waybar re-reads its CSS on change (reload_style_on_change)
  instant   notifications    `makoctl reload`
  on commit sidebar          nwg-dock has no css-reload signal, so it is the
                             one thing that has to be restarted
  next open drawer, fuzzel, hyprlock, screenshot selection box

So the preview is honest about the bar and the borders — the parts you are
actually looking at while choosing — and the rest catches up on commit.

Deliberately a normal toplevel window, for the same reasons as
wallpaper-grid.py: layer surfaces on this setup have cost real time, and a
plain window gets Hyprland's own focus handling for free.
"""

import os
import subprocess
import sys

import gi

gi.require_version("Gtk", "3.0")
# Gdk must be pinned too. Importing it in the same statement as Gtk resolves
# Gdk FIRST, which picks up 4.0 where it is installed and then fails with
# "Requiring namespace 'Gdk' version '3.0', but '4.0' is already loaded".
# wallpaper-grid.py sidesteps this by importing Gdk lazily inside a function,
# after Gtk3 has already pulled in Gdk 3; being explicit is sturdier.
gi.require_version("Gdk", "3.0")

# app_id comes from prgname on Wayland, and the windowrules match on it. It has
# to be set before ANY of Gtk/Gdk is imported: importing Gdk eagerly locks the
# app_id in first, and the window then comes up as "Accent-picker.py" (GTK's
# fallback, derived from argv[0]) so the float/center rules never match.
# wallpaper-grid.py avoids this by importing Gdk lazily inside a function;
# importing GLib alone, naming ourselves, then pulling in the rest is clearer.
from gi.repository import GLib  # noqa: E402

GLib.set_prgname("accent-picker")

from gi.repository import Gdk, Gtk  # noqa: E402

SETTER = os.path.expanduser("~/.config/hypr/set-accent.sh")

# Catppuccin Mocha's accent ramp — the palette the rest of the theme is built
# from, so these are the colours that actually look right against the base.
PALETTE = [
    ("Rosewater", "f5e0dc"), ("Flamingo", "f2cdcd"), ("Pink", "f5c2e7"),
    ("Mauve", "cba6f7"),     ("Red", "f38ba8"),      ("Maroon", "eba0ac"),
    ("Peach", "fab387"),     ("Yellow", "f9e2af"),   ("Green", "a6e3a1"),
    ("Teal", "94e2d5"),      ("Sky", "89dceb"),      ("Sapphire", "74c7ec"),
    ("Blue", "89b4fa"),      ("Lavender", "b4befe"),
]

# Desktop THEMES (SUPER+T): offer the CURRENT theme's accents (same 14 roles)
# and draw the picker in its colours — rice-theme.py's palette substitution.
def _rice():
    import importlib.util
    try:
        spec = importlib.util.spec_from_file_location(
            "rice_theme", os.path.expanduser("~/.config/hypr/rice-theme.py"))
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return mod, mod.current()
    except Exception:              # noqa: BLE001 — the picker must still open
        return None, "mocha"


_RT, _TID = _rice()
if _RT and _TID != "mocha":
    _pal = _RT.palette(_TID)
    PALETTE = [(name, _pal[name.lower()]) for name, _ in PALETTE]

CUSTOM = "custom"
COLUMNS = 5
# Held arrow keys would otherwise fire a preview per repeat; settle first.
DEBOUNCE_MS = 120

CSS = b"""
window { background-color: #1e1e2e; }
#head { color: #cdd6f4; font-size: 13px; padding: 14px 16px 4px 16px; }
#hint { color: #6c7086; font-size: 11px; padding: 0 16px 12px 16px; }
flowboxchild { padding: 6px; border-radius: 12px; }
flowboxchild:selected { background-color: #313244; }
.swatch { border-radius: 10px; min-width: 104px; min-height: 64px;
          border: 2px solid rgba(255,255,255,0.10); }
.name { color: #cdd6f4; font-size: 11px; padding-top: 5px; }
.current { color: #a6e3a1; font-size: 11px; padding-top: 5px; }
"""
if _RT and _TID != "mocha":
    CSS = _RT.subst(CSS.decode(), _TID).encode()


def run(*args):
    try:
        subprocess.run([SETTER, *args], timeout=20,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception as e:
        print(f"set-accent.sh {' '.join(args)}: {e}", file=sys.stderr)


def current():
    try:
        out = subprocess.run([SETTER, "--show"], capture_output=True,
                             text=True, timeout=10)
        return out.stdout.strip().lstrip("#").lower()
    except Exception:
        return ""


class Picker(Gtk.Window):
    def __init__(self, start):
        super().__init__(title="Accent colour")
        self.start = start          # what Escape goes back to
        self.committed = False
        self.pending = None         # debounce source id
        self.set_default_size(620, 420)
        self.set_position(Gtk.WindowPosition.CENTER)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        head = Gtk.Label(label="Accent colour", xalign=0)
        head.set_name("head")
        hint = Gtk.Label(
            label="Enter to keep  ·  Esc to put it back  ·  arrows to preview",
            xalign=0)
        hint.set_name("hint")
        box.pack_start(head, False, False, 0)
        box.pack_start(hint, False, False, 0)

        self.flow = Gtk.FlowBox()
        self.flow.set_valign(Gtk.Align.START)
        self.flow.set_max_children_per_line(COLUMNS)
        self.flow.set_min_children_per_line(COLUMNS)
        self.flow.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self.flow.set_homogeneous(True)
        self.flow.connect("selected-children-changed", self.on_selection)
        self.flow.connect("child-activated", self.on_activate)

        self.entries = [hex_ for _, hex_ in PALETTE] + [CUSTOM]
        for name, hex_ in PALETTE:
            self.flow.add(self.tile(name, hex_, hex_ == start))
        self.flow.add(self.custom_tile())

        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.add(self.flow)
        box.pack_start(scroll, True, True, 0)
        self.add(box)

        self.connect("key-press-event", self.on_key)
        self.connect("destroy", self.on_destroy)

    def _cell(self, css_decl, label, is_current):
        """css_decl is a full declaration, e.g. `background-color: #cba6f7`.

        It is not just a colour because GTK will not accept a gradient in
        background-color — that raises
        "'linear-gradient' is not a valid color name" — so the Custom tile has
        to set background-image instead.
        """
        cell = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        sw = Gtk.Box()
        sw.get_style_context().add_class("swatch")
        prov = Gtk.CssProvider()
        prov.load_from_data(f".swatch {{ {css_decl}; }}".encode())
        sw.get_style_context().add_provider(prov, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        cell.pack_start(sw, True, True, 0)
        lbl = Gtk.Label(label=f"{label}  ●" if is_current else label)
        lbl.get_style_context().add_class("current" if is_current else "name")
        cell.pack_start(lbl, False, False, 0)
        return cell

    def tile(self, name, hex_, is_current):
        return self._cell(f"background-color: #{hex_}", name, is_current)

    def custom_tile(self):
        # A hint of the ramp, so the tile reads as "anything else".
        grad = ("background-image: linear-gradient(135deg,#f38ba8 0%,"
                "#fab387 25%,#a6e3a1 50%,#89b4fa 75%,#cba6f7 100%)")
        return self._cell(grad, "Custom…", False)

    # ── preview ────────────────────────────────────────────────────────────
    def on_selection(self, _flow):
        children = self.flow.get_selected_children()
        if not children:
            return
        value = self.entries[children[0].get_index()]
        if value == CUSTOM:
            return                      # nothing to preview until one is chosen
        if self.pending:
            GLib.source_remove(self.pending)
        self.pending = GLib.timeout_add(DEBOUNCE_MS, self._preview, value)

    def _preview(self, hex_):
        self.pending = None
        run("--preview", hex_)
        return False                    # one-shot

    # ── commit ─────────────────────────────────────────────────────────────
    def on_activate(self, _flow, child):
        value = self.entries[child.get_index()]
        if value == CUSTOM:
            self.pick_custom()
            return
        self.commit(value)

    def pick_custom(self):
        dlg = Gtk.ColorChooserDialog(title="Pick an accent", transient_for=self)
        dlg.set_use_alpha(False)
        if dlg.run() == Gtk.ResponseType.OK:
            c = dlg.get_rgba()
            hex_ = "%02x%02x%02x" % (round(c.red * 255), round(c.green * 255),
                                     round(c.blue * 255))
            dlg.destroy()
            self.commit(hex_)
        else:
            dlg.destroy()

    def commit(self, hex_):
        if self.pending:
            GLib.source_remove(self.pending)
            self.pending = None
        self.committed = True
        run(hex_)
        self.destroy()

    # ── leaving without committing ─────────────────────────────────────────
    def on_key(self, _w, event):
        key = Gdk.keyval_name(event.keyval)
        if key in ("Escape", "q"):
            self.destroy()
            return True
        return False

    def on_destroy(self, _w=None):
        if not self.committed:
            # Undo whatever the preview did. --restore re-renders every file
            # from the saved accent, so a half-previewed state cannot survive.
            run("--restore")
        Gtk.main_quit()


def main():
    start = current()
    provider = Gtk.CssProvider()
    provider.load_from_data(CSS)
    Gtk.StyleContext.add_provider_for_screen(
        Gdk.Screen.get_default(), provider,
        Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)

    win = Picker(start)
    win.show_all()
    if start in win.entries:
        child = win.flow.get_child_at_index(win.entries.index(start))
        if child:
            win.flow.select_child(child)
            child.grab_focus()
    Gtk.main()
    return 0


if __name__ == "__main__":
    sys.exit(main())
