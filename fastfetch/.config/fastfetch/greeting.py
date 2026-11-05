#!/usr/bin/env python3
"""The terminal greeting (zsh `fortunefetch` / `ff`): which logo, which cowsay
cow, which fastfetch details. Settings › Terminal drives it.

  greeting.py state                 JSON: choices + catalogues + logo thumbnails
  greeting.py set logo ID           pick a logo   (ids in `state`, "none" = no logo)
  greeting.py set cow NAME          pick a cow    ("random", "none" = no fortune)
  greeting.py set module ID 0|1     show / hide a fastfetch detail
  greeting.py preview [FORTUNE]     JSON {html, cols, rows, fortune}: the greeting
                                    as the terminal draws it (same fortune if given)

Writes:
  greeting.json   the choices (this folder)
  greeting.env    what zsh's fortunefetch sources: FF_LOGO (a data logo file,
                  "" = none), FF_COW (name / random / ""), FF_ARGS (extra
                  --logo-color-N for builtin logos with more than 2 colours)
  logo.txt        the picked builtin logo, as fastfetch data ($1 $2 … colours)
  logo-small.txt  its small version (FF_LOGO_SMALL / FF_ARGS_SMALL in greeting.env)
  config.jsonc    its "modules" list, rebuilt from the details switched on
  config-compact.jsonc
                  the same config with a short "modules" list (COMPACT) and no
                  logo padding: what zsh draws when the full greeting is taller
                  than the terminal (a top/bottom split)
"""
import json
import os
import random
import re
import shlex
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.expanduser("~/.config/fastfetch")
SETTINGS = os.path.join(HERE, "greeting.json")
ENV = os.path.join(HERE, "greeting.env")
LOGO_TXT = os.path.join(HERE, "logo.txt")
LOGO_SMALL_TXT = os.path.join(HERE, "logo-small.txt")
RICE_LOGO = os.path.join(HERE, "ubuntu-small.txt")
CONFIG = os.path.join(HERE, "config.jsonc")
CONFIG_COMPACT = os.path.join(HERE, "config-compact.jsonc")
GHOSTTY = os.path.expanduser("~/.config/ghostty/config")
COWS_DIR = "/usr/share/cowsay/cows"
FORTUNE = "/usr/games/fortune"
COWSAY = "/usr/games/cowsay"

LOGOS = [
    ("rice", "Ubuntu small (rice)"),
    ("ubuntu", "Ubuntu"),
    ("ubuntu_old", "Ubuntu classic"),
    ("ubuntu_old2", "Ubuntu retro"),
    ("ubuntu_old2_small", "Ubuntu tiny"),
    ("ubuntu-budgie", "Ubuntu Budgie"),
    ("ubuntu-cinnamon", "Ubuntu Cinnamon"),
    ("ubuntu-gnome", "Ubuntu GNOME"),
    ("ubuntu-kylin", "Ubuntu Kylin"),
    ("ubuntu-mate", "Ubuntu MATE"),
    ("ubuntu-studio", "Ubuntu Studio"),
    ("ubuntu-sway", "Ubuntu Sway"),
    ("ubuntu-touch", "Ubuntu Touch"),
    ("ubuntu-unity", "Ubuntu Unity"),
    ("kubuntu", "Kubuntu"),
    ("lubuntu", "Lubuntu"),
    ("xubuntu", "Xubuntu"),
    ("none", "No logo"),
]
# the logo of the compact greeting (short terminals): a builtin small variant
# where fastfetch has one, otherwise the rice's small Ubuntu
SMALL_LOGOS = {"ubuntu_old": "ubuntu_old2_small", "ubuntu_old2": "ubuntu_old2_small",
               "ubuntu_old2_small": "ubuntu_old2_small", "none": "none"}

# ── fastfetch details ───────────────────────────────────────────────────────
# Three boxed sections (keys in accent slots 53 / 54 / 57, as before); the
# default-on set is what config.jsonc had. Keys are icon + a 7-wide name so
# the values line up.
SECTIONS = [("system", "System", "38;5;53"), ("desktop", "Desktop", "38;5;54"), ("hardware", "Hardware", "38;5;57")]
MODULES = [
    # id, label, section, icon, name in the key, on by default, extra fields
    ("os", "OS", "system", 0xF0379, "os", True, {}),
    ("host", "Laptop model", "system", 0xF0322, "host", False, {"format": "{name}"}),
    ("kernel", "Kernel", "system", 0xF17C, "kernel", True, {}),
    ("uptime", "Uptime", "system", 0xF0150, "uptime", True, {}),
    ("packages", "Packages", "system", 0xF03D6, "pkgs", True, {}),
    ("shell", "Shell", "system", 0xF018D, "shell", True, {}),
    ("terminal", "Terminal", "system", 0xF07B7, "term", True, {}),
    ("editor", "Editor", "system", 0xF03EB, "editor", False, {}),
    ("initsystem", "Init system", "system", 0xF0493, "init", False, {}),
    ("locale", "Locale", "system", 0xF05CA, "locale", False, {}),
    ("datetime", "Date & time", "system", 0xF00F0, "date", False, {}),
    ("wm", "Window manager", "desktop", 0xF05B2, "wm", True, {}),
    ("lm", "Login manager", "desktop", 0xF0342, "login", False, {}),
    ("theme", "GTK theme", "desktop", 0xF027C, "theme", True, {}),
    ("icons", "Icon theme", "desktop", 0xF003B, "icons", True, {}),
    ("font", "Font", "desktop", 0xF06D6, "font", False, {}),
    ("cursor", "Cursor", "desktop", 0xF037D, "cursor", False, {}),
    ("display", "Display", "desktop", 0xF037A, "display", True, {}),
    ("cpu", "CPU", "hardware", 0xF0EE0, "cpu", True, {"showPeCoreCount": True}),
    ("gpu", "GPU", "hardware", 0xF08AE, "gpu", True, {}),
    ("memory", "Memory", "hardware", 0xF035B, "memory", True, {}),
    ("swap", "Swap", "hardware", 0xF04E1, "swap", False, {}),
    ("disk", "Disk", "hardware", 0xF02CA, "disk", True, {}),
    ("battery", "Battery", "hardware", 0xF0084, "battery", True, {}),
    ("brightness", "Brightness", "hardware", 0xF00DF, "bright", False, {}),
    ("sound", "Sound", "hardware", 0xF057E, "sound", False, {}),
    ("wifi", "Wi-Fi", "hardware", 0xF05A9, "wifi", False, {"format": "{ssid} · {band} GHz · {signal-quality}%"}),
    ("localip", "Local IP", "hardware", 0xF0A5F, "ip", False, {}),
    ("media", "Now playing", "hardware", 0xF075A, "media", False, {}),
    ("processes", "Processes", "hardware", 0xF0279, "procs", False, {}),
    ("loadavg", "Load average", "hardware", 0xF012A, "load", False, {}),
]
# not in a box: the user@host title above, the palette dots below
EXTRA = [("title", "user@host title", True), ("colors", "Colour dots", True)]
# the compact greeting: these (when switched on) in two boxed groups, no
# colour dots — about 19 rows, so it fits a top/bottom split (24 rows)
COMPACT = [["os", "kernel", "uptime", "packages", "shell", "terminal", "wm"],
           ["cpu", "memory", "disk", "battery", "brightness", "sound", "wifi"]]
COMPACT_EXTRA = {"disk": {"folders": "/:/home"},
                 "sound": {"format": "{volume-percentage-bar}"}}
BOX = "\u001b[38;2;88;91;112m"


# details drawn on two lines: the first line's format, then a second line
# under it (blank key, so the value lines up). Sound: the device name, and
# its volume bar below it rather than trailing the long name.
TWO_LINES = {"sound": ({"format": "{name}"}, {"format": "{volume-percentage-bar}"})}


def module_lines(m):
    e = module_entry(m)
    if m[0] not in TWO_LINES:
        return [e]
    first, second = TWO_LINES[m[0]]
    return [{**e, **first}, {"type": m[0], "key": " " * len(e["key"]), **second}]


def module_entry(m):
    mid, _label, sec, icon, name, _on, extra = m
    colour = dict((s[0], s[2]) for s in SECTIONS)[sec]
    keyname = name.ljust(7) if len(name) < 7 else name
    return {"type": mid, "key": "  %s %s" % (chr(icon), keyname), "keyColor": colour, **extra}


# ── settings ────────────────────────────────────────────────────────────────
def load():
    try:
        with open(SETTINGS) as f:
            s = json.load(f)
    except (OSError, ValueError):
        s = {}
    s.setdefault("logo", "rice")
    s.setdefault("cow", "default")
    mods = s.setdefault("modules", {})
    for m in MODULES:
        mods.setdefault(m[0], m[5])
    for e in EXTRA:
        mods.setdefault(e[0], e[2])
    return s


def save(s):
    tmp = SETTINGS + ".tmp"
    with open(tmp, "w") as f:
        json.dump(s, f, indent=2)
        f.write("\n")
    os.replace(tmp, SETTINGS)


def cows():
    try:
        return sorted(n[:-4] for n in os.listdir(COWS_DIR) if n.endswith(".cow"))
    except OSError:
        return []


# ── logos ───────────────────────────────────────────────────────────────────
SGR = re.compile(r"\x1b\[([0-9;?]*)([A-Za-z])")
MARK = 200  # --logo-color-N = 38;5;(200+N) while extracting


def run_ff(args):
    return subprocess.run(["fastfetch", "--pipe", "false", "-s", "none",
                           "--logo-padding-top", "0", "--logo-padding-left", "0",
                           "--logo-padding-right", "0", *args],
                          capture_output=True, text=True, timeout=5).stdout


def extract_logo(lid):
    """A builtin logo as fastfetch data ($N colours), plus its own colours
    for N >= 3 (fastfetch's config only sets 1 and 2)."""
    marks = []
    for n in range(1, 10):
        marks += ["--logo-color-%d" % n, "38;5;%d" % (MARK + n)]
    marked = run_ff(["--logo-type", "builtin", "-l", lid, *marks])
    plain = run_ff(["--logo-type", "builtin", "-l", lid])
    # the colour runs come in the same order in both renders
    seq_m = [p for p, c in SGR.findall(marked) if c == "m" and p.startswith("38;5;2")]
    seq_p = [p for p, c in SGR.findall(plain) if c == "m" and p not in ("", "0", "1")]
    own = {}
    for a, b in zip(seq_m, seq_p):
        n = int(a.split(";")[2]) - MARK
        if n >= 3 and 1 <= n <= 9:
            own[n] = b
    # cut at the first cursor move (end of the logo), then $N for the marks
    text = marked
    cut = re.search(r"\x1b\[\d*[GA]", text)
    if cut:
        text = text[:cut.start()]
    out, pos = [], 0
    for mt in SGR.finditer(text):
        out.append(text[pos:mt.start()].replace("$", "$$"))
        p, c = mt.groups()
        if c == "m" and p.startswith("38;5;") and MARK < int(p.split(";")[2]) <= MARK + 9:
            out.append("$%d" % (int(p.split(";")[2]) - MARK))
        pos = mt.end()
    out.append(text[pos:].replace("$", "$$"))
    lines = "".join(out).split("\n")
    while lines and not lines[0].strip("$0123456789 "):
        lines.pop(0)
    while lines and not lines[-1].strip("$0123456789 "):
        lines.pop()
    return "\n".join(lines), own


def logo_file(lid, txt):
    """(data logo file, extra fastfetch args) for logo id `lid`; a builtin
    one is extracted into `txt`."""
    if lid == "rice":
        return RICE_LOGO, []
    if lid == "none":
        return "", []
    data, own = extract_logo(lid)
    with open(txt, "w") as f:
        f.write(data + "\n")
    args = []
    for n, code in sorted(own.items()):
        args += ["--logo-color-%d" % n, code]
    return txt, args


def write_outputs(s):
    """greeting.env + logo.txt + config.jsonc's modules from the settings."""
    lid = s["logo"]
    path, args = logo_file(lid, LOGO_TXT)
    small = SMALL_LOGOS.get(lid, "rice")
    spath, sargs = (path, args) if small == lid else logo_file(small, LOGO_SMALL_TXT)
    cow = s["cow"] if s["cow"] != "none" else ""
    home = os.path.expanduser("~")

    def q(p):                                   # $HOME-relative: the dotfiles move between machines
        return '"$HOME%s"' % p[len(home):] if p.startswith(home + "/") else shlex.quote(p)
    with open(ENV, "w") as f:
        f.write("# written by greeting.py (Settings › Terminal) — sourced by fortunefetch in ~/.zshrc\n")
        f.write("FF_LOGO=%s\n" % q(path))
        f.write("FF_LOGO_SMALL=%s\n" % q(spath))
        f.write("FF_COW=%s\n" % shlex.quote(cow))
        f.write("FF_ARGS=(%s)\n" % " ".join(shlex.quote(a) for a in args))
        f.write("FF_ARGS_SMALL=(%s)\n" % " ".join(shlex.quote(a) for a in sargs))
    write_config(s)


def write_config(s):
    with open(CONFIG) as f:
        cfg = json.load(f)
    on = s["modules"]
    mods = ["break"]
    if on.get("title"):
        mods.append({"type": "title", "color": {"user": "38;5;53", "at": "white", "host": "38;5;54"}})
    groups = []
    for sid, _name, _c in SECTIONS:
        g = [e for m in MODULES if m[2] == sid and on.get(m[0]) for e in module_lines(m)]
        if g:
            groups.append(g)
    if groups:
        mods.append({"type": "custom", "format": BOX + "╭" + "─" * 40 + "╮"})
        for i, g in enumerate(groups):
            if i:
                mods.append({"type": "custom", "format": BOX + "├" + "─" * 40 + "┤"})
            mods += g
        mods.append({"type": "custom", "format": BOX + "╰" + "─" * 40 + "╯"})
    if on.get("colors"):
        mods += ["break", {"type": "colors", "paddingLeft": 4, "symbol": "circle"}]
    mods.append("break")
    cfg["modules"] = mods
    dump(cfg, CONFIG)

    # the compact one
    byid = dict((m[0], m) for m in MODULES)
    mods = []
    if on.get("title"):
        mods.append({"type": "title", "color": {"user": "38;5;53", "at": "white", "host": "38;5;54"}})
    groups = [[{**module_entry(byid[i]), **COMPACT_EXTRA.get(i, {})} for i in g if on.get(i)]
              for g in COMPACT]
    groups = [g for g in groups if g]
    if groups:
        mods.append({"type": "custom", "format": BOX + "╭" + "─" * 40 + "╮"})
        for i, g in enumerate(groups):
            if i:
                mods.append({"type": "custom", "format": BOX + "├" + "─" * 40 + "┤"})
            mods += g
        mods.append({"type": "custom", "format": BOX + "╰" + "─" * 40 + "╯"})
    small = json.loads(json.dumps(cfg))
    small["modules"] = mods
    small.setdefault("logo", {}).setdefault("padding", {})["top"] = 0
    dump(small, CONFIG_COMPACT)


def dump(cfg, path):
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(cfg, f, indent=2, ensure_ascii=False)
        f.write("\n")
    os.replace(tmp, path)


# ── terminal → HTML (for the previews) ──────────────────────────────────────
def palette():
    pal = {}
    fg, bg = "#e0def4", "#191724"
    try:
        for line in open(GHOSTTY):
            line = line.strip()
            m = re.match(r"palette\s*=\s*(\d+)\s*=\s*#?([0-9a-fA-F]{6})", line)
            if m:
                pal[int(m.group(1))] = "#" + m.group(2).lower()
                continue
            m = re.match(r"(foreground|background)\s*=\s*#?([0-9a-fA-F]{6})$", line)
            if m:
                if m.group(1) == "foreground":
                    fg = "#" + m.group(2).lower()
                else:
                    bg = "#" + m.group(2).lower()
    except OSError:
        pass
    return pal, fg, bg


def xterm(n, pal):
    if n in pal:
        return pal[n]
    if n < 16:
        base = ["000000", "cd0000", "00cd00", "cdcd00", "0000ee", "cd00cd", "00cdcd", "e5e5e5",
                "7f7f7f", "ff0000", "00ff00", "ffff00", "5c5cff", "ff00ff", "00ffff", "ffffff"]
        return "#" + base[n]
    if n < 232:
        n -= 16
        lv = [0, 95, 135, 175, 215, 255]
        return "#%02x%02x%02x" % (lv[n // 36], lv[n // 6 % 6], lv[n % 6])
    v = 8 + (n - 232) * 10
    return "#%02x%02x%02x" % (v, v, v)


def emulate(text):
    """A tiny terminal: the cells fastfetch's output leaves on screen."""
    pal, dfg, dbg = palette()
    rows = [[]]
    r = c = 0
    fg, bg, bold = None, None, False

    def put(ch):
        nonlocal c
        while len(rows) <= r:
            rows.append([])
        row = rows[r]
        while len(row) <= c:
            row.append((" ", None, None, False))
        row[c] = (ch, fg, bg, bold)
        c += 1

    pos = 0
    for mt in list(SGR.finditer(text)) + [None]:
        chunk = text[pos:mt.start()] if mt else text[pos:]
        for ch in chunk:
            if ch == "\n":
                r += 1
                c = 0
                while len(rows) <= r:
                    rows.append([])
            elif ch == "\r":
                c = 0
            elif ch == "\t":
                c = (c // 8 + 1) * 8
            elif ch >= " ":
                put(ch)
        if not mt:
            break
        pos = mt.end()
        p, cmd = mt.groups()
        if p.startswith("?"):
            continue
        nums = [int(x) if x else 0 for x in p.split(";")] if p else [0]
        k = nums[0] or 1
        if cmd == "A":
            r = max(0, r - k)
        elif cmd == "B":
            r += k
        elif cmd == "C":
            c += k
        elif cmd == "D":
            c = max(0, c - k)
        elif cmd == "G":
            c = k - 1
        elif cmd == "m":
            i = 0
            while i < len(nums):
                n = nums[i]
                if n == 0:
                    fg, bg, bold = None, None, False
                elif n == 1:
                    bold = True
                elif n == 22:
                    bold = False
                elif 30 <= n <= 37:
                    fg = xterm(n - 30, pal)
                elif 90 <= n <= 97:
                    fg = xterm(n - 90 + 8, pal)
                elif 40 <= n <= 47:
                    bg = xterm(n - 40, pal)
                elif 100 <= n <= 107:
                    bg = xterm(n - 100 + 8, pal)
                elif n == 39:
                    fg = None
                elif n == 49:
                    bg = None
                elif n in (38, 48) and i + 1 < len(nums):
                    if nums[i + 1] == 5 and i + 2 < len(nums):
                        col = xterm(nums[i + 2], pal)
                        i += 2
                    elif nums[i + 1] == 2 and i + 4 < len(nums):
                        col = "#%02x%02x%02x" % tuple(nums[i + 2:i + 5])
                        i += 4
                    else:
                        col = None
                    if n == 38:
                        fg = col
                    else:
                        bg = col
                i += 1
    # trim trailing blank rows / cells
    def blank(cell):
        return cell[0] == " " and cell[2] is None
    for row in rows:
        while row and blank(row[-1]):
            row.pop()
    while rows and not rows[-1]:
        rows.pop()
    while rows and not rows[0]:
        rows.pop(0)
    return rows, dfg, dbg


def esc(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def to_html(rows, dfg):
    out = []
    for row in rows:
        line, run, style = [], [], None
        for ch, fg, bg, bold in row + [(None, None, None, None)]:
            st = (fg, bg, bold)
            if st != style or ch is None:
                if run:
                    s = "".join(run)
                    css = "color:%s;" % (style[0] or dfg)
                    if style[1]:
                        css += "background-color:%s;" % style[1]
                    if style[2]:
                        css += "font-weight:bold;"
                    line.append('<span style="%s">%s</span>' % (css, esc(s)))
                run, style = [], st
            if ch is not None:
                run.append(ch)
        out.append("".join(line))
    return "\n".join(out)


def html_block(rows, dfg, font="JetBrainsMono Nerd Font"):
    return ('<pre style="font-family:\'%s\'; margin:0;">' % font) + to_html(rows, dfg) + "</pre>"


def thumb(lid):
    if lid == "none":
        return {"html": "", "cols": 0, "rows": 0}
    args = ["--logo-type", "file", "--logo", RICE_LOGO] if lid == "rice" else ["--logo-type", "builtin", "-l", lid]
    try:
        rows, dfg, _ = emulate(run_ff(args))
    except Exception:
        return {"html": "", "cols": 0, "rows": 0}
    return {"html": html_block(rows, dfg), "cols": max((len(x) for x in rows), default=0), "rows": len(rows)}


# ── the greeting as fortunefetch builds it ──────────────────────────────────
def new_fortune():
    try:
        return subprocess.run([FORTUNE, "-s"], capture_output=True, text=True, timeout=3).stdout
    except (OSError, subprocess.SubprocessError):
        return "Hello!"


def cow_text(cow, fortune):
    if not cow or cow == "none" or not os.access(COWSAY, os.X_OK):
        return ""
    if cow == "random":
        cow = random.choice(cows() or ["default"])
    out = subprocess.run([COWSAY, "-f", cow, "-W", "20"], input=fortune,
                         capture_output=True, text=True, timeout=3).stdout
    lines = [ln.expandtabs() for ln in out.rstrip("\n").split("\n")]
    # as zsh does: the animal (below the bubble) moves up to 4 columns left
    bub = max((i for i, ln in enumerate(lines) if re.fullmatch(r" -+", ln)), default=-1)
    body = [ln for ln in lines[bub + 1:] if ln.strip()]
    if bub >= 0 and body:
        k = min(4, *(len(ln) - len(ln.lstrip(" ")) for ln in body))
        lines[bub + 1:] = [ln[k:] for ln in lines[bub + 1:]]
    return "\n".join("$1" + ln.replace("$", "$$") for ln in lines)


def preview(fortune=None):
    s = load()
    if fortune is None:
        fortune = new_fortune()
    lid = s["logo"]
    args = []
    if lid == "rice":
        art = open(RICE_LOGO).read().rstrip("\n")
    elif lid == "none":
        art = ""
    else:
        art, own = extract_logo(lid)
        for n, code in sorted(own.items()):
            args += ["--logo-color-%d" % n, code]
    cow = cow_text(s["cow"], fortune)
    logo = art + "\n\n" + cow if art and cow else art + cow
    # run from here fastfetch would call the shell "greeting.py" and the
    # terminal "qs": a copy of the config names what the greeting runs in
    cfg_path = CONFIG
    try:
        with open(CONFIG) as f:
            cfg = json.load(f)
        try:
            zsh = "zsh " + subprocess.run(["zsh", "--version"], capture_output=True, text=True,
                                          timeout=2).stdout.split()[1]
        except (OSError, IndexError, subprocess.SubprocessError):
            zsh = "zsh"
        for m in cfg.get("modules", []):
            if isinstance(m, dict) and m.get("type") == "terminal":
                m["format"] = "ghostty"
            elif isinstance(m, dict) and m.get("type") == "shell":
                m["format"] = zsh
        cfg_path = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "greeting-preview.jsonc")
        with open(cfg_path, "w") as f:
            json.dump(cfg, f, ensure_ascii=False)
    except (OSError, ValueError):
        pass
    ff = ["fastfetch", "-c", cfg_path, "--pipe", "false", *args]
    ff += ["--logo-type", "data", "--logo", logo] if logo else ["-l", "none"]
    env = dict(os.environ, COLUMNS="400")
    out = subprocess.run(ff, capture_output=True, text=True, timeout=10, env=env).stdout
    rows, dfg, dbg = emulate(out)
    return {"html": html_block(rows, dfg), "cols": max((len(x) for x in rows), default=0),
            "rows": len(rows), "fortune": fortune, "bg": dbg, "fg": dfg}


def state():
    s = load()
    with ThreadPoolExecutor(8) as ex:
        thumbs = list(ex.map(thumb, [l[0] for l in LOGOS]))
    return {
        "logo": s["logo"],
        "cow": s["cow"],
        "logos": [{"id": l[0], "name": l[1], **t} for l, t in zip(LOGOS, thumbs)],
        "cows": cows(),
        "sections": [{"id": x[0], "name": x[1]} for x in SECTIONS],
        "modules": [{"id": m[0], "name": m[1], "section": m[2], "icon": chr(m[3]),
                     "on": bool(s["modules"].get(m[0]))} for m in MODULES],
        "extras": [{"id": e[0], "name": e[1], "on": bool(s["modules"].get(e[0]))} for e in EXTRA],
    }


def main(argv):
    cmd = argv[1] if len(argv) > 1 else "state"
    if cmd == "state":
        print(json.dumps(state()))
    elif cmd == "set" and len(argv) >= 4:
        s = load()
        what, val = argv[2], argv[3]
        if what == "logo" and val in [l[0] for l in LOGOS]:
            s["logo"] = val
        elif what == "cow" and (val in ("random", "none") or val in cows()):
            s["cow"] = val
        elif what == "module" and len(argv) >= 5 and argv[3] in s["modules"]:
            s["modules"][argv[3]] = argv[4] not in ("0", "false", "off")
        else:
            sys.exit("greeting.py: bad setting %r" % argv[2:])
        save(s)
        write_outputs(s)
        print(json.dumps({"ok": True}))
    elif cmd == "apply":                  # rewrite the outputs from greeting.json
        s = load()
        save(s)
        write_outputs(s)
    elif cmd == "preview":
        print(json.dumps(preview(argv[2] if len(argv) > 2 else None)))
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv)
