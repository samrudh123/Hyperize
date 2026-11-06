#!/usr/bin/python3
"""Discord (Vesktop) in the desktop's theme, accent and mode — live.

    discord-theme.py [hex]      hex defaults to the saved accent (theme/accent)

Called by app-accent.sh on every accent / theme / dark-light change. Writes
Vencord's QuickCSS (~/.config/vesktop/settings/quickCss.css), which Vencord
re-applies the moment the file changes — no restart.

The CSS is Catppuccin's Discord theme for the accent's ROLE
(catppuccin-mocha-<role>.theme.css, fetched once into theme/discord/), made
to match the desktop:
  * its .theme-dark half is Mocha and its .theme-light half is Latte; BOTH are
    recoloured into the CURRENT palette (rice-theme.py), so Discord follows
    the desktop's dark/light mode whatever Discord's own Appearance setting
    says (Dark, Light or Sync with computer)
  * the role's colour becomes the exact accent hex, so a custom accent (a
    wallpaper's, the picker's) shows as itself, not as the nearest role.

WHY IT WRITES IN PLACE: Vencord watches quickCss.css with fs.watch on the
FILE. A write-to-temp + rename (the old app-accent.sh did that) swaps the
inode: Vencord sees that one change and then its watch is dead, so every later
accent / theme change was ignored until Vesktop restarted. Truncating and
rewriting the same file keeps the watch alive (one write call; Vencord
debounces 50 ms before reading).
"""

import importlib.util
import os
import sys
import urllib.request

HYPR = os.path.expanduser("~/.config/hypr")
THEME = os.path.join(HYPR, "theme")
CACHE = os.path.join(THEME, "discord")
QCSS = os.path.expanduser("~/.config/vesktop/settings/quickCss.css")
URL = "https://catppuccin.github.io/discord/dist/catppuccin-mocha-{}.theme.css"

spec = importlib.util.spec_from_file_location("rice", os.path.join(HYPR, "rice-theme.py"))
rice = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rice)


def accent_arg():
    h = sys.argv[1] if len(sys.argv) > 1 else ""
    if not h:
        try:
            h = open(os.path.join(THEME, "accent")).read()
        except OSError:
            h = ""
    h = h.strip().lstrip("#").lower()
    return h if len(h) == 6 and all(c in "0123456789abcdef" for c in h) else None


def source(role):
    path = os.path.join(CACHE, f"catppuccin-mocha-{role}.theme.css")
    if not (os.path.isfile(path) and os.path.getsize(path)):
        os.makedirs(CACHE, exist_ok=True)
        with urllib.request.urlopen(URL.format(role), timeout=20) as r:
            data = r.read().decode("utf-8")
        if not data.strip():
            raise ValueError("empty download")
        with open(path + ".tmp", "w", encoding="utf-8") as f:
            f.write(data)
        os.replace(path + ".tmp", path)
    with open(path, encoding="utf-8") as f:
        return f.read()


def main():
    if not os.path.isdir(os.path.dirname(QCSS)):
        return 0                                    # no Vesktop here
    hexc = accent_arg()
    tid = rice.current()
    pal = rice.palette(tid)
    role = rice.nearest(hexc or pal[rice.THEMES[tid]["accent"]], tid)
    try:
        css = source(role)
    except Exception as e:                          # offline: keep what is there
        print(f"discord-theme: {e}", file=sys.stderr)
        return 1

    # Mocha (.theme-dark) and Latte (.theme-light) -> the current palette, in
    # one pass (no hex is in both flavours), then the role -> the exact accent
    m = dict(rice.table(tid))                       # empty at Mocha itself
    m.update(rice.latte_table(tid))
    if hexc and hexc != pal[role]:
        # the role's colour, wherever it comes from, as the exact accent
        m = {k: (hexc if v == pal[role] else v) for k, v in m.items()}
        m.setdefault(pal[role], hexc)
    # SVG icons in data: URIs spell `#` as %23, and a hex right after "%23"
    # (a "3") doesn't look like a colour to apply_map: mark the boundary
    css = css.replace("%23", "%23\x01")
    css = rice.apply_map(css, m).replace("\x01", "")

    out = ("/* Written by ~/.config/hypr/discord-theme.py — %s theme (%s), %s accent #%s.\n"
           "   Edits here are overwritten on the next accent / theme / mode change. */\n"
           % (tid, rice.mode_of(tid), role, hexc or pal[role])) + css
    try:
        with open(QCSS, encoding="utf-8") as f:
            if f.read() == out:
                return 0
    except OSError:
        pass
    with open(QCSS, "w", encoding="utf-8") as f:   # in place: see the docstring
        f.write(out)
    print(f"discord: {tid} {role} #{hexc}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
