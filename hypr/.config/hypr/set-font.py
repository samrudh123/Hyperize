#!/usr/bin/python3
"""The rice's fonts — Settings › Appearance › Font (SettingsAppearance.qml).

    set-font.py get                     JSON: {shell, apps, choices: [{family, mono}]}
    set-font.py set FAMILY --shell      the Quickshell shell (bars, popups,
                                        settings): theme/font-shell, which
                                        Theme.qml follows live
    set-font.py set FAMILY --apps       apps & the system (below): theme/font-apps
    set-font.py set FAMILY --all        both
    set-font.py apply                   re-apply theme/font-apps everywhere
                                        (after a fresh install)

"Apps & system" is, as far as each one allows:
    GTK 3/4      gsettings font-name / document-font-name / monospace-font-name,
                 gtk-3.0 + gtk-4.0 settings.ini, gtk-4.0/gtk.css monospace var
    Qt / KDE     kdeglobals [General] font, fixed, menuFont, toolBarFont,
                 smallestReadableFont (KDE platform theme; new processes)
    fontconfig   conf.d/60-rice-font.conf: sans-serif and monospace prefer it
                 (what web pages, Electron and anything unstyled fall back to)
    Hyprland     misc:font_family (group bars and Hyprland's own text)
    ghostty, mako, fuzzel, hyprlock, zathura, nwg-bar
A proportional family (Adwaita Sans, …) can't run a terminal: the
monospace-only places (ghostty, monospace aliases, gtk monospace) then get
AdwaitaMono Nerd Font. Sizes are kept, only the family changes.

ghostty, mako, fuzzel, hyprlock, zathura, nwg-bar, gtk4.css and hyprland.conf
are set-accent.sh templates: the same edit goes to the live file AND its
template (theme/templates/…; else the next accent or theme change would put
the old font back). `set-accent.sh --resync` alone can't carry it: font
lines sit next to accent lines in mako/nwg-bar, and its patch refuses those.
"""

import configparser
import json
import os
import re
import subprocess
import sys

HOME = os.path.expanduser("~")
HYPR = os.path.join(HOME, ".config/hypr")
STATE_SHELL = os.path.join(HYPR, "theme/font-shell")
STATE_APPS = os.path.join(HYPR, "theme/font-apps")
DEFAULT = "AdwaitaMono Nerd Font"
MONO_FALLBACK = "AdwaitaMono Nerd Font"

# the curated choices, shown when installed (build/fonts.sh installs them)
CHOICES = ["AdwaitaMono Nerd Font", "Adwaita Sans", "JetBrainsMono Nerd Font", "GeistMono Nerd Font",
           "FiraCode Nerd Font", "CaskaydiaCove Nerd Font", "Hack Nerd Font", "Ubuntu Sans",
           "Ubuntu Sans Mono", "Cantarell", "Noto Sans"]


def run(*cmd):
    return subprocess.run(cmd, capture_output=True, text=True)


def installed(family):
    return run("fc-list", f":family={family}", "family").stdout.strip() != ""


def is_mono(family):
    return "spacing=100" in run("fc-list", f":family={family}", "spacing").stdout


def read_state(path):
    try:
        with open(path, encoding="utf-8") as f:
            v = f.read().strip()
            return v or DEFAULT
    except FileNotFoundError:
        return DEFAULT


def write_state(path, family):
    with open(path, "w", encoding="utf-8") as f:
        f.write(family + "\n")


def edit(path, fn):
    """rewrite a file through fn(text) -> text; True if it changed"""
    try:
        with open(path, encoding="utf-8") as f:
            old = f.read()
    except FileNotFoundError:
        return False
    new = fn(old)
    if new == old:
        return False
    with open(path, "w", encoding="utf-8") as f:     # in place: same inode
        f.write(new)
    return True


def sub(pattern, repl, flags=re.M):
    return lambda t: re.sub(pattern, repl, t, flags=flags)


def apply_apps(fam):
    mono = fam if is_mono(fam) else MONO_FALLBACK
    done, templated = [], False

    # ── GTK ──
    for key, f in (("font-name", fam), ("document-font-name", fam), ("monospace-font-name", mono)):
        cur = run("gsettings", "get", "org.gnome.desktop.interface", key).stdout.strip().strip("'")
        size = (re.search(r"(\d+(?:\.\d+)?)$", cur) or [None, "11"])[1]
        run("gsettings", "set", "org.gnome.desktop.interface", key, f"{f} {size}")
    done.append("gsettings")
    for p in (".config/gtk-3.0/settings.ini", ".config/gtk-4.0/settings.ini"):
        if edit(os.path.join(HOME, p), sub(r"^(gtk-font-name=).*?([ \t]\d+)?$", lambda m: f"{m[1]}{fam}{m[2] or ' 11'}")):
            done.append(p)

    # ── Qt / KDE ──
    rc = os.path.join(HOME, ".config/kdeglobals")
    qfont = lambda f, s: f"{f},{s},-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
    for key, f, s in (("font", fam, 10), ("menuFont", fam, 10), ("toolBarFont", fam, 10),
                      ("smallestReadableFont", fam, 8), ("fixed", mono, 10)):
        run("kwriteconfig6", "--file", rc, "--group", "General", "--key", key, qfont(f, s))
    done.append("kdeglobals")

    # ── fontconfig ──
    fc = os.path.join(HOME, ".config/fontconfig/conf.d/60-rice-font.conf")
    os.makedirs(os.path.dirname(fc), exist_ok=True)
    with open(fc, "w", encoding="utf-8") as f:
        f.write(f"""<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<!-- Written by ~/.config/hypr/set-font.py (Settings › Appearance › Font) —
     changes here are overwritten. The rice's font first for the generic
     families; the usual faces stay behind it for missing glyphs. -->
<fontconfig>
  <alias binding="same"><family>sans-serif</family>
    <prefer><family>{fam}</family><family>Noto Sans</family><family>Noto Color Emoji</family></prefer></alias>
  <alias binding="same"><family>system-ui</family>
    <prefer><family>{fam}</family><family>Noto Sans</family></prefer></alias>
  <alias binding="same"><family>monospace</family>
    <prefer><family>{mono}</family><family>DejaVu Sans Mono</family></prefer></alias>
</fontconfig>
""")
    done.append("fontconfig")

    # ── the templated files ──
    t = lambda p: os.path.join(HOME, p)
    tpl = {".config/ghostty/config": "ghostty-config", ".config/mako/config": "mako-config",
           ".config/fuzzel/fuzzel.ini": "fuzzel.ini", ".config/hypr/hyprlock.conf": "hyprlock.conf",
           ".config/zathura/zathurarc": "zathurarc", ".config/nwg-bar/style.css": "nwg-bar-style.css",
           ".config/gtk-4.0/gtk.css": "gtk4.css", ".config/hypr/hyprland.conf": "hyprland.conf"}
    edits = [
        (".config/ghostty/config", sub(r'^font-family = .*$', f'font-family = "{mono}"')),
        (".config/mako/config", sub(r"^font=.*?([ \t]\d+)$", lambda m: f"font={fam}{m[1]}")),
        (".config/fuzzel/fuzzel.ini", sub(r"^font=[^:\n]*", f"font={fam}")),
        (".config/hypr/hyprlock.conf", sub(
            r"^([ \t]*font_family[ \t]*=[ \t]*).*?([ \t](?:ExtraBold|SemiBold|Bold|Medium|Light))?[ \t]*$",
            lambda m: f"{m[1]}{fam}{m[2] or ''}")),
        (".config/zathura/zathurarc", sub(r'^(set font[ \t]+")[^"]*?([ \t]\d+)"', lambda m: f'{m[1]}{fam}{m[2]}"')),
        (".config/nwg-bar/style.css", sub(r'font-family: "[^"]*"', f'font-family: "{fam}"')),
        (".config/gtk-4.0/gtk.css", sub(r'(--monospace-font-family: )"[^"]*"', lambda m: f'{m[1]}"{mono}"')),
    ]

    def hypr_font(text):
        if re.search(r"^misc \{[^}]*?^\s*font_family\s*=", text, re.M | re.S):
            return re.sub(r"(^misc \{[^}]*?^[ \t]*font_family[ \t]*=[ \t]*)[^\n#]*?([ \t]*(?:#.*)?)$",
                          lambda m: f"{m[1]}{fam}{m[2]}", text, count=1, flags=re.M | re.S)
        return re.sub(r"^misc \{\n", "misc {\n    # Hyprland's own text (group bars …) — set-font.py\n"
                      f"    font_family = {fam}\n", text, count=1, flags=re.M)
    edits.append((".config/hypr/hyprland.conf", hypr_font))

    for p, fn in edits:
        edit(os.path.join(HYPR, "theme/templates", tpl[p]), fn)    # the template first
        if edit(t(p), fn):
            done.append(p)
            templated = True
    if templated:                                 # should find nothing left to do
        r = run(os.path.join(HYPR, "set-accent.sh"), "--resync")
        if r.returncode != 0:
            for rej in os.listdir(os.path.join(HYPR, "theme/templates")):
                if rej.endswith(".rej"):
                    os.remove(os.path.join(HYPR, "theme/templates", rej))
            done.append("RESYNC FAILED: " + (r.stderr or r.stdout).strip()[:200])

    # ── live reloads ──
    run("hyprctl", "keyword", "misc:font_family", fam)
    run("makoctl", "reload")
    run("pkill", "-USR2", "-x", "ghostty")          # ghostty reloads its config
    run("fc-cache", "-f")
    return done


def main(argv):
    cmd = argv[0] if argv else "get"
    if cmd == "get":
        print(json.dumps({
            "shell": read_state(STATE_SHELL), "apps": read_state(STATE_APPS),
            "choices": [{"family": f, "mono": is_mono(f)} for f in CHOICES if installed(f)],
        }))
        return 0
    if cmd == "apply":
        print(json.dumps({"ok": True, "done": apply_apps(read_state(STATE_APPS))}))
        return 0
    if cmd == "set" and len(argv) >= 2:
        fam = argv[1]
        where = argv[2] if len(argv) > 2 else "--all"
        if not installed(fam):
            print(json.dumps({"ok": False, "error": f"{fam} is not installed"}))
            return 1
        done = []
        if where in ("--shell", "--all"):
            write_state(STATE_SHELL, fam)
            done.append("shell")
        if where in ("--apps", "--all"):
            write_state(STATE_APPS, fam)
            done += apply_apps(fam)
        print(json.dumps({"ok": True, "done": done}))
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
