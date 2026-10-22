#!/usr/bin/python3
"""Displays — duplicate or extend onto external monitors (the top bar's
display pill, shown only while more than one monitor is connected).

    display-mode.py status            JSON for the pill
    display-mode.py sync              re-apply the remembered layout, then status
                                      (the pill runs it on monitor hotplug and
                                      config reload: a reload resets the rules)
    display-mode.py set mirror        duplicate the main screen on every external
    display-mode.py set extend [DIR]  extend; DIR = right (default) left above below
    display-mode.py toggle [--notify] duplicate <-> extend (keeps the last DIR);
                                      --notify (SUPER+P) pops an OSD saying which

Every command prints the status JSON afterwards.

The main screen is the laptop panel (eDP/LVDS/DSI), else the first monitor.
Changes are runtime `hyprctl keyword monitor` rules (hyprland.conf keeps its
catch-all `monitor = ,preferred,auto,1`). A monitor seen for the first time
is DUPLICATED (DEFAULT below; `sync` applies it a moment after hotplug).
Once you pick a mode for it, that choice is remembered per external monitor
(by make/model/serial) in ~/.local/state/display/layouts.json: the desk
monitor extends to wherever it was, a projector keeps duplicating.
"""

import json
import os
import subprocess
import sys
import time

STATE = os.path.join(os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")),
                     "display", "layouts.json")
DIRS = {"right": "auto-right", "left": "auto-left", "above": "auto-up", "below": "auto-down"}
# for monitors with no remembered choice
DEFAULT = {"mode": "mirror", "dir": "right"}


def hyprctl(*args):
    return subprocess.run(["hyprctl", *args], capture_output=True, text=True).stdout


def monitors():
    try:
        return json.loads(hyprctl("monitors", "all", "-j"))
    except json.JSONDecodeError:
        return []


def is_internal(m):
    return m["name"].startswith(("eDP", "LVDS", "DSI"))


def split(mons):
    """(main screen, externals)"""
    if not mons:
        return None, []
    main = next((m for m in mons if is_internal(m)), min(mons, key=lambda m: m["id"]))
    return main, [m for m in mons if m is not main]


def key(m):
    return m.get("description") or m["name"]


def mirrored(m):
    return m.get("mirrorOf", "none") not in ("none", "", None)


def logical(m):
    w, h = m["width"] / m["scale"], m["height"] / m["scale"]
    return (h, w) if m.get("transform", 0) % 2 else (w, h)


def side(main, m):
    """where an extended monitor sits relative to the main screen"""
    mw, mh = logical(main)
    w, h = logical(m)
    if m["x"] >= main["x"] + mw - 1:
        return "right"
    if m["x"] + w <= main["x"] + 1:
        return "left"
    if m["y"] + h <= main["y"] + 1:
        return "above"
    if m["y"] >= main["y"] + mh - 1:
        return "below"
    return "overlap"


def load():
    try:
        with open(STATE) as f:
            return json.load(f)
    except (OSError, json.JSONDecodeError):
        return {}


def save(layouts):
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    tmp = STATE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(layouts, f, indent=1)
    os.replace(tmp, STATE)


def rule(m, main, mode, direction):
    if mode == "mirror":
        return f"{m['name']},preferred,auto,1,mirror,{main['name']}"
    return f"{m['name']},preferred,{DIRS.get(direction, 'auto-right')},1"


def apply(main, ext, mode, direction):
    for m in ext:
        hyprctl("keyword", "monitor", rule(m, main, mode, direction))


def status(mons=None):
    mons = monitors() if mons is None else mons
    main, ext = split(mons)
    if not ext:
        mode, direction = "single", ""
    elif any(mirrored(m) for m in ext):
        mode, direction = "mirror", ""
    else:
        mode, direction = "extend", side(main, ext[0])
    last = load().get("_last", {})
    return {
        "count": len(mons),
        "mode": mode,
        "dir": direction or last.get("dir", "right"),
        "main": main["name"] if main else "",
        "monitors": [{
            "name": m["name"],
            "desc": m.get("description", ""),
            "model": " ".join(x for x in (m.get("make", ""), m.get("model", "")) if x).strip(),
            "res": f"{m['width']}x{m['height']}",
            "hz": round(m.get("refreshRate", 0)),
            "scale": m["scale"],
            "main": m is main,
            "mirrored": mirrored(m),
            "disabled": m.get("disabled", False),
        } for m in mons],
    }


def settle(want):
    """wait (briefly) until Hyprland reports the new layout"""
    for _ in range(20):
        mons = monitors()
        if status(mons)["mode"] == want:
            return mons
        time.sleep(0.05)
    return None


def cmd_set(mode, direction=None):
    mons = monitors()
    main, ext = split(mons)
    layouts = load()
    direction = direction or layouts.get("_last", {}).get("dir", "right")
    if mode not in ("mirror", "extend") or direction not in DIRS:
        sys.exit(f"usage: set mirror | set extend [{'|'.join(DIRS)}]")
    if ext:
        apply(main, ext, mode, direction)
        for m in ext:
            layouts[key(m)] = {"mode": mode, "dir": direction}
    layouts["_last"] = {"mode": mode, "dir": direction}
    save(layouts)
    if ext:
        settle(mode)


def notify(body):
    """one OSD notification, replaced on every press"""
    idfile = os.path.join(os.path.dirname(STATE), "notify-id")
    try:
        with open(idfile) as f:
            nid = f.read().strip()
    except OSError:
        nid = ""
    out = subprocess.run(["notify-send", "-a", "Displays", "-c", "osd", "-t", "1500", "-p",
                          *(["-r", nid] if nid else []), "Displays", body],
                         capture_output=True, text=True).stdout.strip()
    if out:
        os.makedirs(os.path.dirname(idfile), exist_ok=True)
        with open(idfile, "w") as f:
            f.write(out)


def cmd_sync():
    """put each external back the way it was last set; unknown ones get DEFAULT"""
    mons = monitors()
    main, ext = split(mons)
    layouts = load()
    for m in ext:
        want = layouts.get(key(m), DEFAULT)
        if want["mode"] == "mirror" and main.get("disabled"):
            continue                        # nothing to copy (laptop panel off)
        if want["mode"] == "mirror":
            ok = mirrored(m)
        else:
            ok = not mirrored(m) and side(main, m) == want.get("dir", "right")
        if not ok:
            apply(main, [m], want["mode"], want.get("dir", "right"))


def main():
    args = sys.argv[1:] or ["status"]
    if args[0] == "set" and len(args) >= 2:
        cmd_set(args[1], args[2] if len(args) > 2 else None)
    elif args[0] == "toggle":
        st = status()
        if st["mode"] == "single":          # nothing to switch: don't touch the memory
            if "--notify" in args:
                notify("No second display connected")
        else:
            cmd_set("extend" if st["mode"] == "mirror" else "mirror", st["dir"])
            if "--notify" in args:
                st = status()
                notify("Duplicated" if st["mode"] == "mirror" else f"Extended — external screen {st['dir']}")
    elif args[0] == "sync":
        cmd_sync()
    elif args[0] != "status":
        sys.exit(__doc__)
    print(json.dumps(status()), flush=True)


if __name__ == "__main__":
    main()
