#!/usr/bin/python3
"""Keybindings for Settings › Keybindings › Hyprland (SettingsKeybinds.qml).

    settings-keybinds.py list                 JSON: every bind in hyprland.conf,
                                              with its group, description and the
                                              combo it has now (overrides applied)
    settings-keybinds.py set ID MODS KEY      move bind ID to MODS+KEY (live + saved)
    settings-keybinds.py reset ID             back to hyprland.conf's combo
    settings-keybinds.py reset-all
    settings-keybinds.py capture on|off       the empty `kbcapture` submap, so a
                                              combo that is already bound reaches
                                              the settings panel instead of firing
    settings-keybinds.py add MODS KEY DISPATCHER ARG NAME [--force]
                                              a binding of your own (exec + a
                                              command, or any dispatcher)
    settings-keybinds.py edit ID MODS KEY DISPATCHER ARG NAME [--force]
                                              a custom one, or one of hyprland.conf's:
                                              its name, keys, what it runs
    settings-keybinds.py remove ID            ID = custom:cN (from `list`)
    settings-keybinds.py delete ID            any bind: hyprland.conf's are
                                              unbound (an override; Reset brings
                                              them back), your own are removed

ID = the ORIGINAL combo as written in hyprland.conf, normalised: "SUPER SHIFT|T".

hyprland.conf's bind lines are never rewritten. Changes live in
keybinds-user.conf, sourced at the very end of hyprland.conf:

    unbind = SUPER, T
    bind = SUPER ALT, Y, exec, …

and applied with a `hyprctl reload` (Hyprland would also auto-reload on the
file change; keyword unbind/bind on top of that doubled the bind). A reload
resets runtime monitor rules — display-mode.py `sync` restores them on
`configreloaded` (Displays.qml). Each override is preceded by a `# override: ID` marker line (and, when its
name or what it runs was edited too, a `# override-edit: {json}` line), each binding of
your own by `# custom: cN | NAME` (the bind line follows it); the file is
regenerated from those on every change (hand edits outside the markers are
not kept). A change Hyprland rejects (`hyprctl configerrors` naming this
file) is rolled back and reported. Paths stay as written in hyprland.conf ($vars, ~), so
the file stays home-path-free for the dotfiles repo.
"""

import json
import os
import re
import subprocess
import sys

HYPR = os.path.dirname(os.path.abspath(__file__))
CONF = os.path.join(HYPR, "hyprland.conf")
USER = os.path.join(HYPR, "keybinds-user.conf")

MOD_ORDER = ["SUPER", "SHIFT", "CTRL", "ALT", "MOD2", "MOD3", "MOD5"]
MOD_ALIAS = {"CONTROL": "CTRL", "WIN": "SUPER", "LOGO": "SUPER", "META": "SUPER",
             "MOD4": "SUPER", "MOD1": "ALT"}
BIND_RE = re.compile(r"^\s*(bind[a-z]*)\s*=\s*(.*)$")

HEADER = """\
# User keybind overrides — written by Settings › Keybindings
# (~/.config/hypr/settings-keybinds.py). Sourced at the END of hyprland.conf,
# so each `unbind` drops the original combo and the `bind` after it adds the
# new one. Edit binds in Settings (or reset them there) rather than by hand:
# this file is regenerated from the `# override:` markers.

# An empty submap: while Settings records a new combo it switches here so the
# keys reach the panel instead of firing their binds. Escape leaves it.
submap = kbcapture
bind = , Escape, submap, reset
submap = reset
"""


def norm_mods(s):
    s = s.replace("_", " ").replace("+", " ")
    out = set()
    for m in s.split():
        m = MOD_ALIAS.get(m.upper(), m.upper())
        out.add(m)
    return " ".join(sorted(out, key=lambda m: MOD_ORDER.index(m) if m in MOD_ORDER else 99))


def combo_id(mods, key):
    return norm_mods(mods) + "|" + key.strip().lower()


def read_vars(lines):
    v = {}
    for ln in lines:
        m = re.match(r"^\s*\$(\w+)\s*=\s*(.*?)\s*$", ln)
        if m:
            v[m.group(1)] = m.group(2)
    return v


def expand(s, vars_):
    # longest names first so $browserAlt beats $browser
    for k in sorted(vars_, key=len, reverse=True):
        s = s.replace("$" + k, vars_[k])
    return s


def split_comment(s):
    # a bind's trailing "# comment" (hyprlang: "##" is a literal #)
    i = 0
    while True:
        i = s.find("#", i)
        if i < 0:
            return s.rstrip(), ""
        if s[i:i + 2] == "##":
            i += 2
            continue
        return s[:i].rstrip(), s[i + 1:].strip()


# friendlier names for the commands binds run (by script / program + first arg)
NAMES = {
    ("focus-dir.py", "l"): "Focus left", ("focus-dir.py", "r"): "Focus right",
    ("focus-dir.py", "u"): "Focus up", ("focus-dir.py", "d"): "Focus down",
    ("workspace-scroll.sh", "next"): "Next workspace", ("workspace-scroll.sh", "prev"): "Previous workspace",
    ("opacity.sh", "up"): "Window more opaque", ("opacity.sh", "down"): "Window more transparent",
    ("opacity.sh", "reset"): "Reset window opacity",
    ("screenshot.sh", "region"): "Screenshot a region", ("screenshot.sh", "screen"): "Screenshot the screen",
    ("screenshot.sh", "window"): "Screenshot a window",
    ("brightness.sh", "up"): "Brightness up", ("brightness.sh", "down"): "Brightness down",
    ("playerctl", "next"): "Next track", ("playerctl", "previous"): "Previous track",
    ("playerctl", "play-pause"): "Play / pause",
    ("wpctl", "set-volume @DEFAULT_AUDIO_SINK@ 5%+"): "Volume up",
    ("wpctl", "set-volume -l"): "Volume up", ("wpctl", "set-volume @DEFAULT_AUDIO_SINK@ 5%-"): "Volume down",
    ("wpctl", "set-mute @DEFAULT_AUDIO_SINK@"): "Mute", ("wpctl", "set-mute @DEFAULT_AUDIO_SOURCE@"): "Mute microphone",
    ("hyprlock", ""): "Lock screen", ("dismiss-reminders.sh", ""): "Dismiss task reminders",
}
VAR_NAMES = {"terminal": "Terminal", "menu": "App launcher", "browser": "Browser (Zen)",
             "browserAlt": "Firefox", "editor": "VS Code", "fileMgr": "File manager (yazi)"}


def describe(dispatcher, arg, raw=""):
    a = arg.strip()
    if dispatcher == "exec":
        m = re.search(r"\$(\w+)\s*$", raw.strip())
        if m and m.group(1) in VAR_NAMES:
            return VAR_NAMES[m.group(1)]
        cmd = a.split("&")[-1].strip()
        if "ipc call" in cmd:
            return "Shell: " + cmd.split("ipc call", 1)[1].strip()
        words = cmd.split()
        prog, rest = "", ""
        for i, w in enumerate(words):
            if "=" in w and not w.startswith(("/", "~")):
                continue
            prog = os.path.basename(w)
            if prog not in ("python3", "sh", "bash", "env"):
                rest = " ".join(words[i + 1:])
                break
        for (p, first), name in NAMES.items():
            if p == prog and rest.startswith(first):
                return name
        return ("Run " + prog + (" " + rest if rest and len(rest) < 40 else "")).strip()
    nice = {"workspace": "Go to workspace", "movetoworkspace": "Move window to workspace",
            "killactive": "Close window", "togglefloating": "Toggle floating",
            "fullscreen": "Fullscreen", "movewindow": "Move window", "resizeactive": "Resize window",
            "togglespecialworkspace": "Toggle scratchpad", "exit": "Exit Hyprland",
            "pseudo": "Pseudo-tile", "togglesplit": "Toggle split", "resizewindow": "Resize window (drag)",
            "submap": "Submap"}
    if dispatcher == "fullscreen":
        return "Maximise" if a == "1" else "Fullscreen"
    if dispatcher in ("movewindow", "movefocus", "swapwindow") and a in ("l", "r", "u", "d"):
        return nice.get(dispatcher, dispatcher) + " " + {"l": "left", "r": "right", "u": "up", "d": "down"}[a]
    base = nice.get(dispatcher, dispatcher)
    return (base + " " + a).strip() if a else base


def classify(disp, arg):
    """a group for the binds hyprland.conf lists without a heading comment"""
    if disp in ("movetoworkspace", "movetoworkspacesilent"):
        return "Move to workspace"
    if disp in ("killactive", "togglefloating", "fullscreen", "pseudo", "togglesplit", "pin", "exit"):
        return "Windows"
    if "qs ipc" in arg or "picker" in arg or "panel" in arg or "tasks.py" in arg or "notif-center" in arg:
        return "Shell & panels"
    if "opacity.sh" in arg:
        return "Window opacity"
    return "Apps"


def clean_comment(c):
    """trailing comments are sometimes history ("was SUPER+P until …")"""
    c = re.split(r";\s| — ", c)[0].strip()
    c = re.sub(r"\s*\((was|moved|used to)[^)]*\)\s*$", "", c)
    # an implementation note cut off by the split ("Settings (SettingsPanel")
    if "(" in c and ")" not in c[c.index("("):]:
        c = c[:c.index("(")].strip()
    if not c or re.match(r"^(was|moved|used to)\b", c):
        return ""
    return c[:1].upper() + c[1:]


def parse():
    with open(CONF, encoding="utf-8") as f:
        lines = f.read().split("\n")
    vars_ = read_vars(lines)
    section = "General"
    group = ""
    comment_block = []
    prev_blank = True
    binds = []
    in_submap = False
    for ln in lines:
        s = ln.strip()
        if not s:
            prev_blank = True
            comment_block = []
            group = ""
            continue
        m = re.match(r"^#\s*─+\s*(.+?)\s*─+", s)
        if m:
            section = m.group(1)
            comment_block = []
            group = ""
            prev_blank = False
            continue
        if s.startswith("#"):
            comment_block.append(s.lstrip("#").strip())
            prev_blank = False
            continue
        if s.startswith("submap"):
            in_submap = not s.endswith("reset")
            continue
        bm = BIND_RE.match(ln)
        if not bm or in_submap:
            if comment_block:
                comment_block = []
            prev_blank = False
            continue
        if comment_block and not group:
            g = re.split(r" — |: |\(|\. ", comment_block[0])[0].strip().rstrip(".,")
            group = g[:1].upper() + g[1:] if 0 < len(g) <= 40 else ""
        kind, rest = bm.group(1), bm.group(2)
        body, comment = split_comment(rest)
        parts = [p.strip() for p in body.split(",", 3)]
        if len(parts) < 3:
            continue
        while len(parts) < 4:
            parts.append("")
        mods, key, disp, arg = parts
        emods = expand(mods, vars_)
        binds.append({
            "id": combo_id(emods, key),
            "kind": kind,
            "mods": norm_mods(emods),
            "key": key,
            "dispatcher": disp,
            "arg": arg,                      # raw, with $vars, for the user file
            "argExpanded": expand(arg, vars_),
            "desc": clean_comment(comment) or describe(disp, expand(arg, vars_), arg),
            "comment": comment,
            "group": group or (classify(disp, arg) if section == "Keybinds" else section),
            "section": section,
            "mouse": kind == "bindm" or key.startswith(("mouse", "switch:")) or key.startswith("mouse:"),
        })
        prev_blank = False
    return binds, vars_


def read_overrides():
    """{ID: {mods, key[, name, dispatcher, arg]}} from keybinds-user.conf's
    markers. `arg` is as typed (a # is one #; written out as ##)."""
    out = {}
    last = None
    try:
        with open(USER, encoding="utf-8") as f:
            for ln in f:
                m = re.match(r"^# override:\s*(.+?)\s*->\s*(.*?)\s*\|\s*(\S+)\s*$", ln)
                if m:
                    last = m.group(1)
                    out[last] = {"mods": m.group(2), "key": m.group(3)}
                    continue
                m = re.match(r"^# override-edit:\s*(\{.*\})\s*$", ln)
                if m and last in out:
                    try:
                        e = json.loads(m.group(1))
                        out[last].update({k: v for k, v in e.items() if k in ("name", "dispatcher", "arg", "deleted")})
                    except ValueError:
                        pass
                last = None if not ln.startswith("#") else last
    except FileNotFoundError:
        pass
    return out


def read_customs():
    """[{cid, name, mods, key, dispatcher, arg}] from the `# custom:` blocks."""
    out = []
    try:
        with open(USER, encoding="utf-8") as f:
            lines = f.read().split("\n")
    except FileNotFoundError:
        return out
    for i, ln in enumerate(lines):
        m = re.match(r"^# custom:\s*(c\d+)\s*\|\s*(.*?)\s*$", ln)
        if not m or i + 1 >= len(lines):
            continue
        bm = BIND_RE.match(lines[i + 1])
        if not bm:
            continue
        parts = [p.strip() for p in bm.group(2).split(",", 3)]
        while len(parts) < 4:
            parts.append("")
        out.append({"cid": m.group(1), "name": m.group(2), "mods": norm_mods(parts[0]),
                    "key": parts[1], "dispatcher": parts[2], "arg": parts[3].replace("##", "#")})
    return out


def custom_entries(customs, vars_):
    """the customs as `list` rows, shaped like hyprland.conf's binds"""
    rows = []
    for c in customs:
        rows.append({
            "id": "custom:" + c["cid"], "kind": "bind", "custom": True, "name": c["name"],
            "mods": c["mods"], "key": c["key"], "dispatcher": c["dispatcher"], "arg": c["arg"],
            "argExpanded": expand(c["arg"], vars_), "desc": c["name"] or describe(c["dispatcher"], expand(c["arg"], vars_), c["arg"]),
            "comment": "", "group": "Your own bindings", "section": "Custom", "mouse": False,
            "curMods": c["mods"], "curKey": c["key"], "changed": False,
            "curId": combo_id(c["mods"], c["key"]),
        })
    return rows


def write_overrides(ov, binds, customs=None):
    if customs is None:
        customs = read_customs()
    by_id = {b["id"]: b for b in binds}
    chunks = [HEADER]
    for bid, o in ov.items():
        b = by_id.get(bid)
        if not b:
            continue
        mods, key = o["mods"], o["key"]
        if o.get("deleted"):                       # deleted: only the unbind
            chunks.append(f"\n# override: {bid} -> {b['mods']} | {b['key']}\n"
                          f'# override-edit: {{"deleted": true}}\n'
                          f"# ({b.get('origDesc', b['desc'])} — deleted)\n"
                          f"unbind = {b['mods']}, {b['key']}\n")
            continue
        edit = {k: o[k] for k in ("name", "dispatcher", "arg") if k in o}
        disp = o.get("dispatcher") or b.get("origDispatcher", b["dispatcher"])
        arg = o["arg"].replace("#", "##") if "arg" in o else b.get("origArg", b["arg"])
        chunks.append(
            f"\n# override: {bid} -> {mods} | {key}\n"
            + (f"# override-edit: {json.dumps(edit, ensure_ascii=False)}\n" if edit else "")
            + f"# ({o.get('name') or b.get('origDesc', b['desc'])})\n"
            f"unbind = {b['mods']}, {b['key']}\n"
            f"{b['kind']} = {mods}, {key}, {disp}" + (f", {arg}" if arg else "") + "\n")
    if customs:
        chunks.append("\n# ── your own bindings (Settings › Keybindings › Add) ──\n")
    for c in customs:
        arg = c["arg"].replace("#", "##")              # hyprlang: ## is a literal #
        chunks.append(f"\n# custom: {c['cid']} | {c['name']}\n"
                      f"bind = {c['mods']}, {c['key']}, {c['dispatcher']}" + (f", {arg}" if arg else "") + "\n")
    tmp = USER + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write("".join(chunks))
    os.replace(tmp, USER)


def hyprctl(*args):
    r = subprocess.run(["hyprctl", *args], capture_output=True, text=True)
    return r.stdout.strip()


def effective(binds, ov, vars_=None):
    """apply the overrides: cur* = the combo now; desc / dispatcher / arg =
    what it is now (orig* keep hyprland.conf's, for writing and Reset)"""
    vars_ = vars_ or {}
    for b in binds:
        b["origDesc"], b["origDispatcher"], b["origArg"] = b["desc"], b["dispatcher"], b["arg"]
        o = ov.get(b["id"])
        if o:
            b["curMods"], b["curKey"], b["changed"] = norm_mods(o["mods"]), o["key"], True
            if o.get("name"):
                b["desc"] = o["name"]
            if o.get("dispatcher"):
                b["dispatcher"] = o["dispatcher"]
            if "arg" in o:
                b["arg"] = o["arg"].replace("#", "##")
                b["argExpanded"] = expand(o["arg"], vars_)
            b["edited"] = any(k in o for k in ("name", "dispatcher", "arg"))
        else:
            b["curMods"], b["curKey"], b["changed"], b["edited"] = b["mods"], b["key"], False, False
        b["deleted"] = bool(o and o.get("deleted"))
        b["argEdit"] = b["arg"].replace("##", "#")      # as typed, for the edit form
        # a deleted bind holds no combo (it can't clash with anything)
        b["curId"] = "" if b["deleted"] else combo_id(b["curMods"], b["curKey"])
    return binds


def conflicts(binds, bid, mods, key):
    want = combo_id(mods, key)
    return [b for b in binds if b["curId"] == want and b["id"] != bid]


def apply_checked(before):
    """reload; if Hyprland reports an error in our file, put `before` back"""
    res = hyprctl("reload")
    errs = [e for e in hyprctl("configerrors").split("\n") if "keybinds-user" in e]
    if errs:
        with open(USER, "w", encoding="utf-8") as f:
            f.write(before)
        hyprctl("reload")
        return {"ok": False, "error": errs[0].split(": ", 1)[-1][:200]}
    return {"ok": res in ("ok", ""), "hyprctl": res}


def clean(s):
    return " ".join(str(s).split())          # one line: no newlines in the conf


def main(argv):
    cmd = argv[0] if argv else "list"
    binds, vars_ = parse()
    ov = read_overrides()
    effective(binds, ov, vars_)
    customs = read_customs()
    every = custom_entries(customs, vars_) + binds
    try:
        with open(USER, encoding="utf-8") as f:
            before = f.read()
    except FileNotFoundError:
        before = HEADER
    if cmd == "list":
        print(json.dumps(every))
    elif cmd == "edit" and not argv[1].startswith("custom:"):
        a = [x for x in argv[1:] if x != "--force"]
        if len(a) < 6:
            print(json.dumps({"ok": False, "error": "usage: edit ID MODS KEY DISPATCHER ARG NAME"}))
            return 2
        bid = a[0]
        b = next((x for x in binds if x["id"] == bid), None)
        if not b:
            print(json.dumps({"ok": False, "error": "unknown bind " + bid}))
            return 1
        mods, key, disp, arg, name = norm_mods(a[1]), clean(a[2]), clean(a[3]), clean(a[4]), clean(a[5])
        if not key or not re.match(r"^[a-z]+$", disp):
            print(json.dumps({"ok": False, "error": "a key and a dispatcher (e.g. exec) are needed"}))
            return 0
        clash = conflicts(every, bid, mods, key)
        if clash and "--force" not in argv:
            print(json.dumps({"ok": False, "conflict": [c["desc"] for c in clash]}))
            return 0
        o = {"mods": mods, "key": key}
        if name and name != b["origDesc"]:
            o["name"] = name
        if disp != b["origDispatcher"]:
            o["dispatcher"] = disp
        if arg != b["origArg"].replace("##", "#"):
            o["arg"] = arg
        if combo_id(mods, key) == bid and len(o) == 2:
            ov.pop(bid, None)                     # back to exactly hyprland.conf's
        else:
            ov[bid] = o
        write_overrides(ov, binds, customs)
        print(json.dumps(apply_checked(before)))
    elif cmd in ("add", "edit"):
        a = [x for x in argv[1:] if x != "--force"]
        cid = None
        if cmd == "edit":
            cid, a = a[0].removeprefix("custom:"), a[1:]
        if len(a) < 5:
            print(json.dumps({"ok": False, "error": "usage: add MODS KEY DISPATCHER ARG NAME"}))
            return 2
        mods, key, disp, arg, name = norm_mods(a[0]), clean(a[1]), clean(a[2]), clean(a[3]), clean(a[4])
        if not key or not disp or not re.match(r"^[a-z]+$", disp):
            print(json.dumps({"ok": False, "error": "a key and a dispatcher (e.g. exec) are needed"}))
            return 0
        clash = conflicts(every, "custom:" + cid if cid else "", mods, key)
        if clash and "--force" not in argv:
            print(json.dumps({"ok": False, "conflict": [c["desc"] for c in clash]}))
            return 0
        entry = {"name": name, "mods": mods, "key": key, "dispatcher": disp, "arg": arg}
        if cid:
            for c in customs:
                if c["cid"] == cid:
                    c.update(entry)
        else:
            n = max([int(c["cid"][1:]) for c in customs] + [0]) + 1
            customs.append({"cid": f"c{n}", **entry})
        write_overrides(ov, binds, customs)
        print(json.dumps(apply_checked(before)))
    elif cmd == "delete" and not argv[1].startswith("custom:"):
        bid = argv[1]
        b = next((x for x in binds if x["id"] == bid), None)
        if not b:
            print(json.dumps({"ok": False, "error": "unknown bind " + bid}))
            return 1
        ov[bid] = {"mods": b["mods"], "key": b["key"], "deleted": True}
        write_overrides(ov, binds, customs)
        print(json.dumps(apply_checked(before)))
    elif cmd in ("remove", "delete"):
        cid = argv[1].removeprefix("custom:")
        write_overrides(ov, binds, [c for c in customs if c["cid"] != cid])
        print(json.dumps(apply_checked(before)))
    elif cmd == "check":
        print(json.dumps([b["desc"] for b in conflicts(every, argv[1], argv[2], argv[3])]))
    elif cmd == "set" and argv[1].startswith("custom:"):
        bid, mods, key = argv[1], norm_mods(argv[2]), argv[3]
        clash = conflicts(every, bid, mods, key)
        if clash and "--force" not in argv:
            print(json.dumps({"ok": False, "conflict": [c["desc"] for c in clash]}))
            return 0
        for c in customs:
            if "custom:" + c["cid"] == bid:
                c["mods"], c["key"] = mods, key
        write_overrides(ov, binds, customs)
        print(json.dumps(apply_checked(before)))
    elif cmd == "set":
        bid, mods, key = argv[1], norm_mods(argv[2]), argv[3]
        b = next((x for x in binds if x["id"] == bid), None)
        if not b:
            print(json.dumps({"ok": False, "error": "unknown bind " + bid}))
            return 1
        clash = conflicts(every, bid, mods, key)
        if clash and "--force" not in argv:
            print(json.dumps({"ok": False, "conflict": [c["desc"] for c in clash]}))
            return 0
        o = dict(ov.get(bid, {}), mods=mods, key=key)
        o.pop("deleted", None)
        if combo_id(mods, key) == b["id"] and len(o) == 2:
            ov.pop(bid, None)
        else:
            ov[bid] = o
        write_overrides(ov, binds)
        res = hyprctl("reload")
        print(json.dumps({"ok": res in ("ok", ""), "hyprctl": res}))
    elif cmd in ("reset", "reset-all"):
        ids = [argv[1]] if cmd == "reset" else list(ov)
        for bid in ids:
            b = next((x for x in binds if x["id"] == bid), None)
            if not b or bid not in ov:
                continue
            ov.pop(bid)
        write_overrides(ov, binds)
        hyprctl("reload")
        print(json.dumps({"ok": True}))
    elif cmd == "capture":
        on = len(argv) > 1 and argv[1] == "on"
        print(hyprctl("dispatch", "submap", "kbcapture" if on else "reset"))
    else:
        print(__doc__, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
