#!/usr/bin/env python3
"""Catppuccin Mocha icons for the sidebar dock (nwg-dock-hyprland).

    dock-theme-icons.py [id...]  (re)generate the icon set (+ these ids)
    dock-theme-icons.py --list   show what each app gets

The dock is started with `-icondir OUT` (dock-start.sh). For every pinned
entry / window class X it draws OUT/X.svg instead of the app's own icon — a
local patch (patches/nwg-dock-hyprland-0.4.11-local.patch, change 5), so the
.desktop files, the app grid and fuzzel keep their normal icons.

Every icon is a flat, single-colour glyph in a Catppuccin Mocha colour — the
same Material Design icons the bars use, so Spotify / Firefox match their
pills. Vector paths taken straight out of the Nerd Font, so they stay sharp at
any -i size. Apps not in GLYPHS get, in order:

  1. the icon theme's own `<icon>-symbolic` drawing, recoloured, or
  2. a monogram: the first letter of the app's name in a rounded square,

in a colour picked from the app's id, so every app on the dock — running
unpinned ones included — is drawn the same way. Covered: every pinned entry,
every .desktop file (by file id and StartupWMClass) and every open window.

dock-start.sh runs this before every dock start (0.25 s), so newly installed
apps are picked up at login / `reload.sh dock`. dock-places.sh passes a new
disk's id BEFORE it writes the pin — the dock redraws as soon as the pinned
file changes, and an id with no icon yet would get the app's own.
"""

import configparser
import glob
import hashlib
import json
import os
import re
import subprocess
import sys

from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.ttLib import TTFont

HOME = os.path.expanduser("~")
OUT = os.path.join(HOME, ".local/share/nwg-dock-hyprland/mocha-icons")
PINNED = os.path.join(HOME, ".cache/nwg-dock-pinned")
FONT = os.path.join(HOME, ".local/share/fonts/JetBrainsMonoNerdFont-Regular.ttf")
FONT_BOLD = os.path.join(HOME, ".local/share/fonts/JetBrainsMonoNerdFont-Bold.ttf")
APP_DIRS = [
    os.path.join(HOME, ".local/share/applications"),
    "/usr/local/share/applications",
    "/usr/share/applications",
    "/var/lib/snapd/desktop/applications",
    "/var/lib/flatpak/exports/share/applications",
    os.path.join(HOME, ".local/share/flatpak/exports/share/applications"),
]

# Catppuccin Mocha
M = {
    "rosewater": "#f5e0dc", "flamingo": "#f2cdcd", "pink": "#f5c2e7", "mauve": "#cba6f7",
    "red": "#f38ba8", "maroon": "#eba0ac", "peach": "#fab387", "yellow": "#f9e2af",
    "green": "#a6e3a1", "teal": "#94e2d5", "sky": "#89dceb", "sapphire": "#74c7ec",
    "blue": "#89b4fa", "lavender": "#b4befe", "text": "#cdd6f4", "subtext1": "#bac2de",
    "subtext0": "#a6adc8", "overlay2": "#9399b2",
}
# Desktop THEMES (SUPER+SHIFT+T): the same roles in the current theme's colours
# (theme/palette.json, written by set-theme.sh).
try:
    with open(os.environ.get("RICE_PALETTE") or
              os.path.expanduser("~/.config/hypr/theme/palette.json")) as _f:
        _pal = json.load(_f)
    M = {k: _pal.get(k, v) for k, v in M.items()}
except (OSError, ValueError):
    pass

# Colours a fallback icon may get (picked from its app id).
ACCENTS = ["rosewater", "flamingo", "pink", "mauve", "red", "maroon", "peach", "yellow",
           "green", "teal", "sky", "sapphire", "blue", "lavender"]

# entry / class -> (Nerd Font glyph name, Mocha colour). Same glyphs as the
# bars where they overlap (now-playing.py: md-spotify, md-firefox, …).
GLYPHS = {
    "com.mitchellh.ghostty":  ("md-ghost", "mauve"),
    "org.gnome.Terminal":     ("md-console", "rosewater"),
    "firefox":                ("md-firefox", "peach"),
    "firefox_firefox":        ("md-firefox", "peach"),
    "org.gnome.Nautilus":     ("md-folder", "blue"),
    "com.samrudh.yazi":       ("md-folder_open", "yellow"),      # yazi (SUPER+E): its own class
    "com.samrudh.filepicker": ("md-folder_search", "yellow"),    # yazi as the file dialog
    "com.microsoft.VSCode":   ("md-microsoft_visual_studio_code", "sapphire"),
    "code":                   ("md-microsoft_visual_studio_code", "sapphire"),
    "Code":                   ("md-microsoft_visual_studio_code", "sapphire"),
    "vesktop":                ("md-discord", "lavender"),
    "discord":                ("md-discord", "lavender"),
    "spotify":                ("md-spotify", "green"),
    "Spotify":                ("md-spotify", "green"),
    "dev.local.btop":         ("md-gauge", "teal"),
    "btop":                   ("md-gauge", "teal"),
    "com.obsproject.Studio":  ("md-record_rec", "red"),
    "org.kde.kdenlive":       ("linux-kdenlive", "sky"),
    "JDownloader":            ("md-download", "yellow"),
    "brave-browser":          ("md-web", "maroon"),
    "Brave-browser":          ("md-web", "maroon"),
    "thunderbird":            ("md-email", "blue"),
    "org.gnome.Settings":     ("md-cog", "overlay2"),
    "YouTube Music":          ("md-music", "pink"),
    "com.github.th_ch.youtube_music": ("md-music", "pink"),
    "mpv":                    ("md-play_circle", "mauve"),
    "dock-trash":             ("md-trash_can_outline", "subtext0"),
}
# Prefix rules (dock-places.sh names disks dock-disk-<label>).
PREFIX_GLYPHS = [("dock-disk-", ("md-harddisk", "subtext0"))]
# The launcher button at the foot of the dock (dock-start.sh -ico).
LAUNCHER = ("md-view_grid", "overlay2")

SIZE = 64          # SVG canvas; the glyph's longer side fills FILL of it
FILL = 0.78


class Glyphs:
    def __init__(self, path):
        self.font = TTFont(path)
        self.gs = self.font.getGlyphSet()
        self.by_name = {v: v for v in self.font.getGlyphOrder()}
        self.cmap = self.font.getBestCmap()

    def path(self, name):
        """-> (svg path d, (xmin, ymin, xmax, ymax)) in font units, y up."""
        g = self.gs[name]
        bp = BoundsPen(self.gs)
        g.draw(bp)
        sp = SVGPathPen(self.gs)
        g.draw(sp)
        return sp.getCommands(), bp.bounds

    def for_char(self, ch):
        return self.cmap.get(ord(ch))


def glyph_svg(glyphs, name, colour, fill=FILL):
    d, (x0, y0, x1, y1) = glyphs.path(name)
    w, h = x1 - x0, y1 - y0
    s = SIZE * fill / max(w, h)
    # flip y (font units are y-up) and centre the glyph's ink box
    tx = (SIZE - w * s) / 2 - x0 * s
    ty = (SIZE + h * s) / 2 + y0 * s
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{SIZE}" height="{SIZE}" '
            f'viewBox="0 0 {SIZE} {SIZE}"><path fill="{colour}" '
            f'transform="matrix({s:.6f} 0 0 {-s:.6f} {tx:.3f} {ty:.3f})" d="{d}"/></svg>\n')


def monogram_svg(glyphs_bold, letter, colour):
    """First letter in a rounded square — for apps with no glyph or symbolic."""
    name = glyphs_bold.for_char(letter.upper()) or glyphs_bold.for_char("?")
    d, (x0, y0, x1, y1) = glyphs_bold.path(name)
    w, h = x1 - x0, y1 - y0
    s = SIZE * 0.40 / h
    tx = (SIZE - w * s) / 2 - x0 * s
    ty = (SIZE + h * s) / 2 + y0 * s
    inset, stroke = SIZE * 0.13, SIZE * 0.06
    side = SIZE - 2 * inset
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{SIZE}" height="{SIZE}" '
            f'viewBox="0 0 {SIZE} {SIZE}">'
            f'<rect x="{inset}" y="{inset}" width="{side}" height="{side}" rx="{side * 0.28:.2f}" '
            f'fill="none" stroke="{colour}" stroke-width="{stroke:.2f}"/>'
            f'<path fill="{colour}" transform="matrix({s:.6f} 0 0 {-s:.6f} {tx:.3f} {ty:.3f})" '
            f'd="{d}"/></svg>\n')


def symbolic_svg(icon, colour):
    """The icon theme's `<icon>-symbolic`, every colour replaced by `colour`."""
    if not icon or icon.startswith("/"):
        return None
    try:
        import gi
        gi.require_version("Gtk", "3.0")
        from gi.repository import Gtk
        info = Gtk.IconTheme.get_default().lookup_icon(icon + "-symbolic", 64, 0)
    except (ImportError, ValueError):
        return None
    path = info and info.get_filename()
    if not path or not path.endswith(".svg"):
        return None
    with open(path) as f:
        svg = f.read()
    svg = re.sub(r"#[0-9a-fA-F]{6}\b|#[0-9a-fA-F]{3}\b", colour, svg)
    # symbolic icons often leave the fill unset (= black): set one on the root
    # — unless the root already has one (Resources, Showtime: fill="none"); a
    # second fill attribute makes the file invalid XML, and Qt then can't load it
    root = re.search(r"<svg\b[^>]*>", svg)
    if root and not re.search(r"\sfill=", root.group(0)):
        svg = svg[:root.start()] + f'<svg fill="{colour}"' + svg[root.start() + 4:]
    return svg


def desktop_entries():
    """{id or StartupWMClass: (Name, Icon)} — first app dir wins, like XDG."""
    out = {}
    for d in APP_DIRS:
        for p in sorted(glob.glob(os.path.join(d, "*.desktop"))):
            cp = configparser.ConfigParser(interpolation=None, strict=False)
            try:
                cp.read(p, encoding="utf-8")
                e = cp["Desktop Entry"]
            except (configparser.Error, KeyError, UnicodeDecodeError):
                continue
            info = (e.get("Name", ""), e.get("Icon", ""))
            for key in (os.path.basename(p)[:-len(".desktop")], e.get("StartupWMClass", "")):
                if key and key not in out:
                    out[key] = info
    return out


def wanted_ids(entries, extra=()):
    ids = set(entries) | set(extra)
    try:
        with open(PINNED) as f:
            ids |= {l.strip() for l in f if l.strip()}
    except OSError:
        pass
    try:
        clients = json.loads(subprocess.run(["hyprctl", "-j", "clients"], capture_output=True,
                                            text=True).stdout or "[]")
        ids |= {c.get("class", "") for c in clients if c.get("class")}
    except ValueError:
        pass
    return sorted(i for i in ids if "/" not in i)


def pick_colour(app_id):
    h = int(hashlib.md5(app_id.lower().encode()).hexdigest(), 16)
    return M[ACCENTS[h % len(ACCENTS)]]


def rule_for(app_id):
    if app_id in GLYPHS:
        return GLYPHS[app_id]
    for prefix, rule in PREFIX_GLYPHS:
        if app_id.startswith(prefix):
            return rule
    low = {k.lower(): v for k, v in GLYPHS.items()}
    return low.get(app_id.lower())


def main():
    listing = "--list" in sys.argv[1:]
    extra = [a for a in sys.argv[1:] if not a.startswith("--")]
    glyphs, bold = Glyphs(FONT), Glyphs(FONT_BOLD)
    entries = desktop_entries()
    os.makedirs(OUT, exist_ok=True)
    made = {}
    for app_id in wanted_ids(entries, extra):
        name, icon = entries.get(app_id, ("", ""))
        rule = rule_for(app_id)
        if rule:
            svg, how = glyph_svg(glyphs, rule[0], M[rule[1]]), f"glyph {rule[0]} {rule[1]}"
        else:
            colour = pick_colour(app_id)
            svg, how = symbolic_svg(icon, colour), f"symbolic {icon}"
            if svg is None:
                letter = next((c for c in (name or app_id) if c.isalnum()), "?")
                svg, how = monogram_svg(bold, letter, colour), f"monogram {letter.upper()}"
        made[app_id + ".svg"] = svg
        if listing:
            print(f"{app_id:45} {how}")
    made["launcher.svg"] = glyph_svg(glyphs, LAUNCHER[0], M[LAUNCHER[1]])
    # write only what changed; drop icons for apps that are gone
    for fname, svg in made.items():
        p = os.path.join(OUT, fname)
        try:
            with open(p) as f:
                if f.read() == svg:
                    continue
        except OSError:
            pass
        with open(p + ".tmp", "w") as f:
            f.write(svg)
        os.replace(p + ".tmp", p)
    for fname in os.listdir(OUT):
        if fname.endswith(".svg") and fname not in made:
            os.remove(os.path.join(OUT, fname))
    if not listing:
        print(f"dock icons: {len(made)} in {OUT}")


if __name__ == "__main__":
    main()
