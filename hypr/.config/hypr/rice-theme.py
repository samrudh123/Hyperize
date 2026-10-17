#!/usr/bin/python3
"""Desktop colour themes — the palette library behind SUPER+SHIFT+T.

Every themed file on this desktop was written for Catppuccin Mocha. Rather
than re-tokenising all of them, a theme is a MAP from Mocha's 26 colour roles
(base, surface0, text, blue, …) to that theme's colour for the same role, and
anything Mocha-coloured is passed through `subst`: every Mocha hex (any case,
with or without `#`), every Mocha `r, g, b` triplet and — for LibreOffice —
every Mocha colour as a decimal long, becomes the theme's colour for that
role. At Mocha the substitution is the identity, so the files come out
byte-for-byte as before.

    rice-theme.py list                     themes as JSON (for the picker)
    rice-theme.py current                  the active theme's id
    rice-theme.py palette [id]             {role: "#hex"} (+ "id", "name", "accent")
    rice-theme.py subst [id] [--ints]      stdin -> stdout, Mocha -> theme
    rice-theme.py subst-file [--ints] [--theme id] FILE...   in place
    rice-theme.py map-accent HEX FROM TO   the accent's role carried across themes
    rice-theme.py nearest HEX [id]         nearest accent ROLE NAME in a theme
    rice-theme.py gtk ROLE [id]            build/refresh the GTK3 theme for a
                                           theme + accent role, print its name

State: ~/.config/hypr/theme/name (the theme id) and theme/palette.json
(written by set-theme.sh, read live by the Quickshell shell).
"""

import json
import os
import re
import shutil
import sys

HYPR = os.path.expanduser("~/.config/hypr")
NAME_FILE = os.path.join(HYPR, "theme/name")
GTK_THEMES = os.path.expanduser("~/.local/share/themes")

ROLES = ["rosewater", "flamingo", "pink", "mauve", "red", "maroon", "peach", "yellow",
         "green", "teal", "sky", "sapphire", "blue", "lavender", "text", "subtext1",
         "subtext0", "overlay2", "overlay1", "overlay0", "surface2", "surface1",
         "surface0", "base", "mantle", "crust"]
ACCENTS = ROLES[:14]

# Each palette lists the 26 roles in ROLES order. Accents are the theme's own
# colours where it has one for the role; where it has none (Gruvbox has no
# pink, Rosé Pine no green, …) a colour in its spirit stands in.
THEMES = {
    "mocha": {
        "name": "Catppuccin Mocha", "accent": "blue",
        "colors": "f5e0dc f2cdcd f5c2e7 cba6f7 f38ba8 eba0ac fab387 f9e2af a6e3a1 94e2d5 "
                  "89dceb 74c7ec 89b4fa b4befe cdd6f4 bac2de a6adc8 9399b2 7f849c 6c7086 "
                  "585b70 45475a 313244 1e1e2e 181825 11111b",
    },
    "tokyonight": {
        "name": "Tokyo Night", "accent": "blue",
        "colors": "f7c3c6 f7a8b0 fca7ea bb9af7 f7768e db4b4b ff9e64 e0af68 9ece6a 73daca "
                  "7dcfff 2ac3de 7aa2f7 b4bcf7 c0caf5 a9b1d6 9aa5ce 737aa2 5f6890 545c7e "
                  "414868 343a52 24283b 1a1b26 16161e 13131a",
    },
    "gruvbox": {
        "name": "Gruvbox Dark", "accent": "peach",
        "colors": "ebc2a8 ea9d84 e396ac d3869b fb4934 cc241d fe8019 fabd2f b8bb26 8ec07c "
                  "9cc4b8 458588 83a598 bda8c9 ebdbb2 bdae93 a89984 928374 7c6f64 665c54 "
                  "504945 3c3836 32302f 282828 1d2021 141617",
    },
    "nord": {
        "name": "Nord", "accent": "sky",
        "colors": "e5d0c9 d8a7a7 c895bf b48ead bf616a a3545c d08770 ebcb8b a3be8c 8fbcbb "
                  "88c0d0 81a1c1 5e81ac a9b5df eceff4 d8dee9 b0b8c7 7b88a1 6f7b94 616e88 "
                  "4c566a 434c5e 3b4252 2e3440 292e39 242933",
    },
    "rosepine": {
        "name": "Rosé Pine", "accent": "flamingo",
        "colors": "f4d6d4 ebbcba e6a1c4 c4a7e7 eb6f92 d7827e f0a58a f6c177 95c4a8 9ccfd8 "
                  "a9d7e0 3e8fb0 569fba b9b2f0 e0def4 c8c5e0 aeaac8 908caa 6e6a86 524f67 "
                  "403d52 26233a 1f1d2e 191724 16141f 12101a",
    },
    "everforest": {
        "name": "Everforest", "accent": "green",
        "colors": "e8cfc0 e6a5a5 e5a6c6 d699b6 e67e80 da6362 e69875 dbbc7f a7c080 83c092 "
                  "9ccfc6 7fbbb3 82a9c9 b2a8d3 d3c6aa c8bea4 b8b39c 9da9a0 859289 7a8478 "
                  "475258 3d484d 343f44 2d353b 232a2e 1e2326",
    },
    "dracula": {
        "name": "Dracula", "accent": "mauve",
        "colors": "ffd5e5 ffb3d0 ff79c6 bd93f9 ff5555 ff6e6e ffb86c f1fa8c 50fa7b 6ef3c5 "
                  "8be9fd 62d6e8 8aa9f9 d0b8ff f8f8f2 dadbe6 bfc2d6 8790bf 7380b2 6272a4 "
                  "545770 44475a 343746 282a36 21222c 191a21",
    },
    "kanagawa": {
        "name": "Kanagawa", "accent": "blue",
        "colors": "e6c4b4 e8a3a3 d27e99 957fb8 e46876 c34043 ffa066 e6c384 98bb6c 7aa89f "
                  "7fb4ca 658594 7e9cd8 9cabca dcd7ba c8c093 a6a69c 8a8980 727169 625e6e "
                  "54546d 363646 2a2a37 1f1f28 181820 16161d",
    },
}
ORDER = ["mocha", "tokyonight", "gruvbox", "nord", "rosepine", "everforest", "dracula", "kanagawa"]

# Mocha-derived shades that are not roles but turn up in themed files:
# (mocha hex) -> (role a, role b, share of a). Carried across as the same mix.
# eff1f5 is Catppuccin LATTE's base, which the Catppuccin GTK theme draws its
# light foregrounds with on dark backgrounds.
MIXES = {
    "353749": ("surface0", "surface1", 0.80),
    "393947": ("surface0", "surface1", 0.60),
    "484856": ("surface1", "surface2", 0.85),
}
# Only for the GTK theme: elsewhere eff1f5 is Latte's own base (spicetify's
# color.ini and similar files carry all four Catppuccin flavours).
GTK_MIXES = {"eff1f5": ("text", "#ffffff", 0.45)}


def palette(tid):
    t = THEMES[tid]
    hexes = t["colors"].split()
    assert len(hexes) == len(ROLES), tid
    return dict(zip(ROLES, hexes))


def current():
    try:
        with open(NAME_FILE) as f:
            tid = f.read().strip()
        return tid if tid in THEMES else "mocha"
    except OSError:
        return "mocha"


def rgb(h):
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def hexof(c):
    return "".join(f"{max(0, min(255, round(v))):02x}" for v in c)


def mix(a, b, t):
    ca, cb = rgb(a), rgb(b)
    return hexof(ca[i] * t + cb[i] * (1 - t) for i in range(3))


def table(tid, gtk=False):
    """{mocha hex: theme hex} for every role and known mix."""
    src, dst = palette("mocha"), palette(tid)
    out = {src[r]: dst[r] for r in ROLES}
    if tid == "mocha":
        return {}
    for h, (a, b, t) in list(MIXES.items()) + (list(GTK_MIXES.items()) if gtk else []):
        ta = dst[a] if a in dst else a.lstrip("#")
        tb = dst[b] if b in dst else b.lstrip("#")
        out[h] = mix(ta, tb, t)
    return {k: v for k, v in out.items() if k != v}


def subst(text, tid, ints=False, gtk=False):
    m = table(tid, gtk)
    if not m:
        return text

    def hexrep(mo):
        s = mo.group(0)
        new = m[s.lower()]
        return new.upper() if s.isupper() and any(c.isalpha() for c in s) else new
    # a bare 6-digit hex, or the colour part of an 8-digit one (rgba(45475aaa)
    # in hyprland.conf, cdd6f4ff in fuzzel.ini)
    hexpat = re.compile(r"(?<![0-9A-Za-z])(" + "|".join(m) + r")(?=(?:[0-9A-Fa-f]{2})?(?![0-9A-Za-z]))", re.I)
    text = hexpat.sub(hexrep, text)

    trip = {}
    for k, v in m.items():
        trip[rgb(k)] = rgb(v)

    def decrep(mo):
        nums = tuple(int(mo.group(i)) for i in (1, 3, 5))
        new = trip.get(nums)
        if not new:
            return mo.group(0)
        return f"{new[0]}{mo.group(2)}{new[1]}{mo.group(4)}{new[2]}"
    text = re.sub(r"(?<![\d.])(\d{1,3})(,\s*)(\d{1,3})(,\s*)(\d{1,3})(?![\d.])", decrep, text)

    if ints:
        longs = {int(k, 16): int(v, 16) for k, v in m.items()}
        text = re.sub(r"<value>(\d+)</value>",
                      lambda mo: f"<value>{longs.get(int(mo.group(1)), int(mo.group(1)))}</value>",
                      text)
    return text


def nearest(hexc, tid):
    p = palette(tid)
    t = rgb(hexc.lstrip("#").lower())
    return min(ACCENTS, key=lambda r: sum((a - b) ** 2 for a, b in zip(rgb(p[r]), t)))


def map_accent(hexc, src, dst):
    """The accent's role in `src` (exact match, else nearest), in `dst`."""
    hexc = hexc.lstrip("#").lower()
    ps, pd = palette(src), palette(dst)
    for r in ACCENTS:
        if ps[r] == hexc:
            return pd[r]
    return pd[nearest(hexc, src)]


def gtk(role, tid):
    """The Catppuccin Mocha GTK3 theme for `role`, recoloured into `tid`.
    Mocha itself is the shipped theme; others are generated once (and again
    if this script is newer) into ~/.local/share/themes."""
    base = f"catppuccin-mocha-{role}-standard+default"
    if tid == "mocha":
        return base
    src = os.path.join(GTK_THEMES, base)
    name = f"rice-{tid}-{role}-standard+default"
    dst = os.path.join(GTK_THEMES, name)
    stamp = os.path.join(dst, ".rice-theme")
    me = os.path.getmtime(os.path.abspath(__file__))
    if os.path.isdir(dst) and os.path.exists(stamp) and os.path.getmtime(stamp) >= me:
        return name
    if not os.path.isdir(src):
        return base
    tmp = dst + ".tmp"
    shutil.rmtree(tmp, ignore_errors=True)
    shutil.copytree(src, tmp, symlinks=True)
    for root, _dirs, files in os.walk(tmp):
        for f in files:
            p = os.path.join(root, f)
            if os.path.islink(p) or not f.endswith((".css", ".svg", ".theme", ".xml", "rc", ".ini")):
                continue
            try:
                with open(p, encoding="utf-8") as fh:
                    s = fh.read()
            except (UnicodeDecodeError, OSError):
                continue
            s2 = subst(s, tid, gtk=True).replace(base, name)
            if s2 != s:
                with open(p, "w", encoding="utf-8") as fh:
                    fh.write(s2)
    with open(os.path.join(tmp, ".rice-theme"), "w") as fh:
        fh.write(f"{tid} {role}\n")
    shutil.rmtree(dst, ignore_errors=True)
    os.replace(tmp, dst)
    return name


def as_json(tid):
    p = {r: "#" + h for r, h in palette(tid).items()}
    p.update({"id": tid, "name": THEMES[tid]["name"], "accent": THEMES[tid]["accent"]})
    return p


def main(argv):
    if not argv:
        print(__doc__, file=sys.stderr)
        return 2
    cmd, args = argv[0], argv[1:]
    if cmd == "list":
        print(json.dumps([as_json(t) for t in ORDER]))
    elif cmd == "current":
        print(current())
    elif cmd == "palette":
        print(json.dumps(as_json(args[0] if args else current()), indent=1))
    elif cmd == "subst":
        ids = [a for a in args if not a.startswith("--")]
        sys.stdout.write(subst(sys.stdin.read(), ids[0] if ids else current(), "--ints" in args))
    elif cmd == "subst-file":
        ints = "--ints" in args
        tid = current()
        if "--theme" in args:
            tid = args[args.index("--theme") + 1]
        files = [a for i, a in enumerate(args)
                 if a not in ("--ints", "--theme") and (i == 0 or args[i - 1] != "--theme")]
        for f in files:
            with open(f, encoding="utf-8") as fh:
                s = fh.read()
            s2 = subst(s, tid, ints)
            if s2 != s:
                tmp = f + ".rice-tmp"
                with open(tmp, "w", encoding="utf-8") as fh:
                    fh.write(s2)
                shutil.copymode(f, tmp)
                os.replace(tmp, f)
    elif cmd == "map-accent":
        print(map_accent(args[0], args[1], args[2]))
    elif cmd == "nearest":
        print(nearest(args[0], args[1] if len(args) > 1 else current()))
    elif cmd == "gtk":
        print(gtk(args[0], args[1] if len(args) > 1 else current()))
    else:
        print(f"unknown command {cmd}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
