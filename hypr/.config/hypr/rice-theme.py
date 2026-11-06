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

    rice-theme.py list [dark|light]        themes as JSON (for the picker); each
                                           has "mode" and "family" (its dark id)
    rice-theme.py current                  the active theme's id
    rice-theme.py mode [id]                dark | light
    rice-theme.py variant MODE [id]        the same theme in MODE: rosepine ->
                                           rosepine-light (Rosé Pine Dawn) …
    rice-theme.py palette [id]             {role: "#hex"} (+ "id", "name", "accent")
    rice-theme.py subst [id] [--ints]      stdin -> stdout, Mocha -> theme
    rice-theme.py subst-file [--ints] [--theme id] FILE...   in place
    rice-theme.py map-accent HEX FROM TO   the accent's role carried across themes
    rice-theme.py nearest HEX [id]         nearest accent ROLE NAME in a theme
    rice-theme.py derive HEX [id]          colours derived from the accent, as
                                           "TOKEN hex" lines (set-accent.sh)
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

# LIGHT MODE (Settings › Appearance › Mode, `set-theme.sh --mode light`): each
# theme's own light flavour, as `<id>-light`, in the same Mocha ROLES — base /
# mantle / crust are the light paper, surfaces get darker as they rise, text
# is dark, accents are the flavour's deeper inks. Everything themed passes
# through the same substitution, so a light theme needs nothing else; the few
# switches that are dark/light flags rather than colours (GTK colour-scheme,
# icon inheritance, Claude Code / Neovim / LibreOffice base) read `mode`.
LIGHT = {
    "mocha": {
        "name": "Catppuccin Latte",
        "colors": "dc8a78 dd7878 ea76cb 8839ef d20f39 e64553 fe640b df8e1d 40a02b 179299 "
                  "04a5e5 209fb5 1e66f5 7287fd 4c4f69 5c5f77 6c6f85 7c7f93 8c8fa1 9ca0b0 "
                  "acb0be bcc0cc ccd0da eff1f5 e6e9ef dce0e8",
    },
    "tokyonight": {
        "name": "Tokyo Night Day",
        "colors": "b06a76 c4566d b74ba6 9854f1 f52a65 c64343 b15c00 8c6c3e 587539 118c74 "
                  "007197 188092 2e7de9 7847bd 3760bf 4c62b0 6172b0 6f77a2 848cb5 9399bd "
                  "a8aecb b6bbd2 c4c8da e1e2e7 d8dae3 d0d3de",
    },
    "gruvbox": {
        "name": "Gruvbox Light",
        "colors": "b0715a c26a5a b16286 8f3f71 9d0006 cc241d af3a03 b57614 79740e 427b58 "
                  "689d6a 458588 076678 7c6f9e 3c3836 504945 665c54 7c6f64 928374 a89984 "
                  "bdae93 d5c4a1 e3d4ab fbf1c7 f4e8bf ede0b8",
    },
    "nord": {
        "name": "Nord Light",
        "colors": "b07e72 b66a6a a8669c 9a6b96 bf616a a3545c c26a45 a87d1c 6b8f4e 4f8f8c "
                  "3f8ea3 4f7aa8 3b6ea8 6f7cb8 2e3440 3b4252 4c566a 616e88 7b88a1 8e98aa "
                  "a9b2c3 bdc5d3 d0d7e2 eceff4 e5e9f0 dde3ec",
    },
    "rosepine": {
        "name": "Rosé Pine Dawn",
        "colors": "c7958f d7827e c86a9e 907aa9 b4637a b8505a d98a52 ea9d34 4f8f6a 56949f "
                  "5b9bb0 286983 3e7fa1 7a72b8 575279 676389 797593 8a86a0 9893a5 aaa5b6 "
                  "cecacd dfdad9 e9e2dc faf4ed f4ede8 f2e9e1",
    },
    "everforest": {
        "name": "Everforest Light",
        "colors": "d78f7f e0727a e07a9a df69ba f85552 e66868 f57d26 dfa000 8da101 35a77c "
                  "3aa5a0 3a94c5 4f86c6 8a7fc0 5c6a72 667680 708089 829181 939f91 a6b0a0 "
                  "bdc3af d3d1bb e6e2cc fdf6e3 f4f0d9 efebd4",
    },
    "dracula": {
        "name": "Alucard (Dracula Light)",
        "colors": "b4677f c24f75 a3144d 644ac9 cb3a2a b03a3a a34d14 846e15 14710a 0b7a5a "
                  "036a96 1a6fa8 3d5ec9 7a63d0 1f1f1f 3e3c35 5a5644 6c664b 8f8a70 aaa691 "
                  "c9c6bb d9d6c8 e8e4d3 fffbeb f6f2e1 efebd9",
    },
    "kanagawa": {
        "name": "Kanagawa Lotus",
        "colors": "b8776a c25b6a b35b79 624c83 c84053 d7474b cc6d00 de9800 6f894e 597b75 "
                  "4e8ca2 5a7785 4d699b 766b90 545464 5f5f6e 716e61 8a8980 9e9a8c b0ab95 "
                  "c4bd94 d5cea3 dcd5ac f2ecbc e9e2b4 e5ddb0",
    },
}
for _fam, _t in LIGHT.items():
    THEMES[_fam]["mode"] = "dark"
    THEMES[_fam + "-light"] = dict(_t, accent=THEMES[_fam]["accent"], mode="light")
LIGHT_ORDER = [f + "-light" for f in ORDER]


def mode_of(tid):
    return THEMES.get(tid, {}).get("mode", "dark")


def family(tid):
    return tid[:-len("-light")] if tid.endswith("-light") else tid


def variant(tid, mode):
    """The same theme in `mode` ("dark" | "light")."""
    f = family(tid)
    return f + "-light" if mode == "light" else f

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
# ...in a LIGHT theme `text` is dark, and that light-on-accent foreground has
# to stay light: the theme's paper, a touch whiter.
GTK_MIXES_LIGHT = {"eff1f5": ("base", "#ffffff", 0.60)}


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
    gmix = GTK_MIXES_LIGHT if mode_of(tid) == "light" else GTK_MIXES
    for h, (a, b, t) in list(MIXES.items()) + (list(gmix.items()) if gtk else []):
        ta = dst[a] if a in dst else a.lstrip("#")
        tb = dst[b] if b in dst else b.lstrip("#")
        out[h] = mix(ta, tb, t)
    return {k: v for k, v in out.items() if k != v}


# A template can hold BOTH modes of the theme at once, for an app that
# switches between them by itself, live (GTK4's `@media (prefers-color-scheme)`
# in gtk-4.0/gtk.css): lines between a `rice:mode dark` and a `rice:mode end`
# marker are recoloured into the theme's dark flavour, between `rice:mode
# light` and the end marker into its light one — whichever mode is current.
# The marker lines (comments in the file's own syntax) stay in the output, so
# --resync's diff of live file against template still lines up.
MODE_MARK = re.compile(r"^[ \t]*(?:/\*|#|//)[ \t]*rice:mode (dark|light|end)[ \t]*(?:\*/)?[ \t]*$\n?", re.M)


def subst(text, tid, ints=False, gtk=False):
    if "rice:mode " not in text:
        return _subst(text, tid, ints, gtk)
    out, pos, cur = [], 0, tid
    for mo in MODE_MARK.finditer(text):
        out.append(_subst(text[pos:mo.start()], cur, ints, gtk))
        out.append(mo.group(0))
        cur = tid if mo.group(1) == "end" else variant(tid, mo.group(1))
        pos = mo.end()
    out.append(_subst(text[pos:], cur, ints, gtk))
    return "".join(out)


def _subst(text, tid, ints=False, gtk=False):
    return apply_map(text, table(tid, gtk), ints)


def latte_table(tid):
    """{Catppuccin LATTE hex: theme hex} by role — for files that carry a
    Latte half next to the Mocha one (Catppuccin's Discord CSS styles
    .theme-light in Latte)."""
    src, dst = palette("mocha-light"), palette(tid)
    return {src[r]: dst[r] for r in ROLES if src[r] != dst[r]}


def apply_map(text, m, ints=False):
    """Every colour in `m` ({hex: hex}, lower-case, no #) replaced: hex (any
    case, also the colour part of an 8-digit one), `r, g, b` triplets and,
    with ints, LibreOffice decimal longs."""
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
    if max(t) - min(t) < 24:
        # a grey (a black-and-white wallpaper's accent): by distance a mid grey
        # lands on green, so the apps that only take a role name (GTK theme,
        # Discord, folders, …) went green on a black-and-white desktop. Take
        # the theme's most neutral accent instead (rosewater, in most).
        return min(ACCENTS, key=lambda r: max(rgb(p[r])) - min(rgb(p[r])))
    return min(ACCENTS, key=lambda r: sum((a - b) ** 2 for a, b in zip(rgb(p[r]), t)))


def map_accent(hexc, src, dst):
    """The accent's role in `src` (exact match, else nearest), in `dst`."""
    hexc = hexc.lstrip("#").lower()
    ps, pd = palette(src), palette(dst)
    for r in ACCENTS:
        if ps[r] == hexc:
            return pd[r]
    t = rgb(hexc)
    if max(t) - min(t) < 24:
        # a grey has no role: it stays the same grey — mirrored in lightness
        # across a dark <-> light switch, so a pale grey accent on the dark
        # desktop becomes a deep one on the light paper (and back)
        if mode_of(src) != mode_of(dst):
            return hexof(255 - v for v in t)
        return hexc
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


# Colours derived from the accent, for templates that want more than one
# accent-family colour (ghostty's palette slots 53-57, which the shell draws
# with). set-accent.sh puts them in for @@<NAME>@@ the same way it puts the
# accent in for @@ACCENT@@.
#   ACCENT_COMP   the complementary hue (HLS hue + 180°, same L and S; for a
#                 grey accent, the same grey darker), so it
#                 sits next to the accent at the same weight
#   ACCENT_THIRD  the hue a quarter turn on (+90°, same L and S): with the
#                 complement it makes a square scheme, the accent and its
#                 complement plus one more that belongs to both (grey: the
#                 grey between the two)
#   ACCENT_MID    accent sunk 60% into the theme's surface0: a dark tint that
#                 still reads as the accent, for text-coloured labels on top
#   ACCENT_LOW    accent sunk 80% into surface0: barely-tinted, for accent-
#                 coloured labels on top
#   ACCENT_HI     accent lifted 45% toward the theme's text: a pastel for
#                 accent-coloured text that has to stay readable (btop titles,
#                 selected row, the top of its gradients)
#   ACCENT_COMP_MID, ACCENT_THIRD_MID   the other two hues sunk like ACCENT_MID,
#                 so each can start a gradient the way the accent does (btop)
def derive(hexc, tid):
    import colorsys
    a = hexc.lstrip("#").lower()
    pal = palette(tid)
    s0 = pal["surface0"]
    h, l, s = colorsys.rgb_to_hls(*(v / 255 for v in rgb(a)))
    if s < 0.15:
        # a grey (a black-and-white wallpaper's accent) has no opposite hue:
        # its partner is the same grey a shade darker, so the pair still
        # reads as two colours — and stays black and white
        comp = hexof(v * 255 for v in colorsys.hls_to_rgb(h, l * 0.72, s))
        third = hexof(v * 255 for v in colorsys.hls_to_rgb(h, l * 0.86, s))
    else:
        comp = hexof(v * 255 for v in colorsys.hls_to_rgb((h + 0.5) % 1.0, l, s))
        third = hexof(v * 255 for v in colorsys.hls_to_rgb((h + 0.25) % 1.0, l, s))
    out = {"ACCENT_COMP": comp, "ACCENT_THIRD": third,
            "ACCENT_MID": mix(a, s0, 0.40), "ACCENT_LOW": mix(a, s0, 0.20),
            "ACCENT_HI": mix(a, pal["text"], 0.55),
            "ACCENT_COMP_MID": mix(comp, s0, 0.40),
            "ACCENT_THIRD_MID": mix(third, s0, 0.40)}
    # Both modes of the theme at once, for an app that holds a dark and a
    # light theme side by side and so can flip between them live (VS Code's
    # Catppuccin Mocha + Latte overrides): DARK_<ROLE> / LIGHT_<ROLE>, and
    # FLAVOUR = the Catppuccin flavour of the current mode.
    for m in ("dark", "light"):
        for r, h in palette(variant(tid, m)).items():
            out[f"{m.upper()}_{r.upper()}"] = h
    light = mode_of(tid) == "light"
    out["FLAVOUR"] = "Latte" if light else "Mocha"
    out["FLAVOUR_ID"] = "latte" if light else "mocha"
    # the plain icon set whose symbolic icons read on this mode's paper
    # (mako's icon-path; Papirus-Mocha inherits the same — set-theme.sh)
    out["ICONS_BASE"] = "Papirus-Light" if light else "Papirus-Dark"
    # the accent in each mode (its role carried across), for a template that
    # holds both (gtk4.css)
    out["ACCENT_DARK"] = map_accent(a, tid, variant(tid, "dark"))
    out["ACCENT_LIGHT"] = map_accent(a, tid, variant(tid, "light"))
    return out


def as_json(tid):
    p = {r: "#" + h for r, h in palette(tid).items()}
    p.update({"id": tid, "name": THEMES[tid]["name"], "accent": THEMES[tid]["accent"],
              "mode": mode_of(tid), "family": family(tid)})
    return p


def main(argv):
    if not argv:
        print(__doc__, file=sys.stderr)
        return 2
    cmd, args = argv[0], argv[1:]
    if cmd == "list":
        # dark themes, then their light flavours; `list dark|light` for one set
        ids = {"dark": ORDER, "light": LIGHT_ORDER}.get(args[0] if args else "", ORDER + LIGHT_ORDER)
        print(json.dumps([as_json(t) for t in ids]))
    elif cmd == "mode":
        print(mode_of(args[0] if args else current()))
    elif cmd == "variant":
        print(variant(args[1] if len(args) > 1 else current(), args[0]))
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
    elif cmd == "derive":
        for k, v in derive(args[0], args[1] if len(args) > 1 else current()).items():
            print(k, v)
    elif cmd == "gtk":
        print(gtk(args[0], args[1] if len(args) > 1 else current()))
    else:
        print(f"unknown command {cmd}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
