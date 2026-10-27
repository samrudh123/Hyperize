#!/usr/bin/python3
"""Neovim keymaps for Settings › Keybindings › Neovim (SettingsKeybinds.qml).

    settings-nvim.py list                 JSON: every mapping Neovim has after
                                          startup (defaults, plugins incl. lazy
                                          key stubs, this config, the LSP buffer
                                          maps), overrides marked
    settings-nvim.py set MODE FROM TO     move the mapping at FROM to TO
    settings-nvim.py reset MODE FROM
    settings-nvim.py reset-all            (moved keys only; your own mappings stay)
    settings-nvim.py add MODE LHS RHS DESC   a mapping of your own (RHS in key
                                          notation: ":w<CR>", "<cmd>Lazy<CR>")
    settings-nvim.py remove MODE LHS
    settings-nvim.py delete MODE LHS GROUP [DESC RHS]
                                          an existing mapping: removed at startup
                                          (listed as deleted; `reset` brings it
                                          back); your own: removed for good
    settings-nvim.py add MODE LHS RHS DESC --edit GROUP
                                          EDIT an existing mapping (its action /
                                          description): stored like your own, but
                                          listed in GROUP as changed; `reset`
                                          drops it

Overrides go to ~/.config/nvim/keymap-overrides.json; the config's
lua/keymap-overrides.lua applies them at startup (running nvims pick them up
on their next start). FROM/TO are key notation: <leader>ff, <C-p>, gd …
Your own mappings live in the same file under "_custom" (a list of
{mode, lhs, rhs, desc}); keymap-overrides.lua sets them at startup.
"""

import json
import os
import subprocess
import sys
import tempfile

HYPR = os.path.dirname(os.path.abspath(__file__))
DUMP = os.path.join(HYPR, "settings-nvim-dump.lua")
NVIM_CFG = os.path.join(os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config")), "nvim")
OVR = os.path.join(NVIM_CFG, "keymap-overrides.json")


def canon(lhs):
    """case-normalise <…> key names (<C-p> == <C-P>), keep plain keys as typed"""
    out, i = [], 0
    while i < len(lhs):
        if lhs[i] == "<":
            j = lhs.find(">", i)
            if j > 0:
                out.append(lhs[i:j + 1].lower())
                i = j + 1
                continue
        out.append(lhs[i])
        i += 1
    return "".join(out).replace("<space>", "<leader>") if lhs.startswith(("<Space>", "<space>")) else "".join(out)


def read():
    try:
        with open(OVR, encoding="utf-8") as f:
            d = json.load(f)
            return d if isinstance(d, dict) else {}
    except (FileNotFoundError, ValueError):
        return {}


def write(d):
    d = {m: v for m, v in d.items() if v}
    tmp = OVR + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(d, f, indent=2, sort_keys=True)
        f.write("\n")
    os.replace(tmp, OVR)


def dump():
    fd, path = tempfile.mkstemp(suffix=".json")
    os.close(fd)
    try:
        subprocess.run(["nvim", "--headless", "-c", "luafile " + DUMP],
                       env={**os.environ, "SETTINGS_NVIM_OUT": path},
                       stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, timeout=20)
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (subprocess.TimeoutExpired, ValueError, FileNotFoundError):
        return []
    finally:
        os.unlink(path)


def main(argv):
    cmd = argv[0] if argv else "list"
    ov = read()
    customs = ov.get("_custom", [])
    moves = {m: v for m, v in ov.items() if m != "_custom" and isinstance(v, dict)}
    if cmd == "list":
        maps = dump()
        back = {(m, canon(to)): frm for m, v in moves.items() for frm, to in v.items()}
        mine = {(c["mode"], canon(c["lhs"])): c for c in customs}
        seen = set()
        for e in maps:
            frm = back.get((e["mode"], canon(e["lhs"])))
            e["orig"] = frm or e["lhs"]
            e["changed"] = bool(frm)
            c = mine.get((e["mode"], canon(e["lhs"])))
            if c and not e.get("buffer"):
                if c.get("edited"):               # an existing one, edited
                    e["group"], e["changed"], e["edited"] = c.get("group") or e["group"], True, True
                else:
                    e["custom"], e["group"] = True, "Your own mappings"
                e["desc"] = c.get("desc") or e["desc"]
                e["rhs"] = c["rhs"]
                seen.add((c["mode"], canon(c["lhs"])))
        for k, c in mine.items():                 # not in the dump (yet): still show it
            if c.get("deleted"):                  # deleted: show it, greyed, for Reset
                maps.append({"mode": c["mode"], "lhs": c["lhs"], "rawLhs": c["lhs"], "desc": c.get("desc", ""),
                             "rhs": c.get("rhs", ""), "buffer": False, "group": c.get("group") or "Your config",
                             "orig": back.get((c["mode"], canon(c["lhs"]))) or c["lhs"],
                             "changed": True, "deleted": True})
                continue
            if k not in seen and not c.get("edited"):
                maps.append({"mode": c["mode"], "lhs": c["lhs"], "rawLhs": c["lhs"], "desc": c.get("desc", ""),
                             "rhs": c["rhs"], "buffer": False, "group": "Your own mappings",
                             "orig": c["lhs"], "changed": False, "custom": True})
        print(json.dumps(maps))
    elif cmd == "add":
        group = argv[argv.index("--edit") + 1] if "--edit" in argv else None
        argv = [a for i, a in enumerate(argv) if a != "--edit" and not (i > 0 and argv[i - 1] == "--edit")]
        mode, lhs, rhs, desc = argv[1], argv[2], argv[3], (argv[4] if len(argv) > 4 else "")
        if mode not in ("n", "i", "x", "v", "t", "o", "c", "s") or not lhs or not rhs:
            print(json.dumps({"ok": False, "error": "a mode, keys and an action are needed"}))
            return 0
        rest = [c for c in customs if not (c["mode"] == mode and canon(c["lhs"]) == canon(lhs))]
        new = {"mode": mode, "lhs": lhs, "rhs": rhs, "desc": desc}
        if group is not None:
            new.update(edited=True, group=group)
        ov["_custom"] = rest + [new]
        write(ov)
        print(json.dumps({"ok": True}))
    elif cmd == "delete":
        mode, lhs = argv[1], argv[2]
        group = argv[3] if len(argv) > 3 else ""
        mine_ = [c for c in customs if c["mode"] == mode and canon(c["lhs"]) == canon(lhs)]
        rest = [c for c in customs if c not in mine_]
        if not any(not c.get("edited") and not c.get("deleted") for c in mine_):
            rest.append({"mode": mode, "lhs": lhs, "deleted": True, "group": group,
                         "desc": argv[4] if len(argv) > 4 else "", "rhs": argv[5] if len(argv) > 5 else ""})
        ov["_custom"] = rest                      # your own one: just gone
        write(ov)
        print(json.dumps({"ok": True}))
    elif cmd == "remove":
        mode, lhs = argv[1], argv[2]
        ov["_custom"] = [c for c in customs if not (c["mode"] == mode and canon(c["lhs"]) == canon(lhs))]
        write(ov)
        print(json.dumps({"ok": True}))
    elif cmd == "set" and any(c["mode"] == argv[1] and canon(c["lhs"]) == canon(argv[2]) for c in customs):
        for c in customs:                         # your own mapping: just new keys
            if c["mode"] == argv[1] and canon(c["lhs"]) == canon(argv[2]):
                c["lhs"] = argv[3]
        write(ov)
        print(json.dumps({"ok": True}))
    elif cmd == "set":
        mode, frm, to = argv[1], argv[2], argv[3]
        ov.setdefault(mode, {})
        if canon(frm) == canon(to):
            ov[mode].pop(frm, None)
        else:
            ov[mode][frm] = to
        write(ov)
        print(json.dumps({"ok": True}))
    elif cmd == "reset":
        mode, orig = argv[1], argv[2]
        now = moves.get(mode, {}).get(orig, orig)
        ov.get(mode, {}).pop(orig, None)
        gone = {canon(orig), canon(now)}
        ov["_custom"] = [c for c in customs if not ((c.get("edited") or c.get("deleted"))
                                                    and c["mode"] == mode and canon(c["lhs"]) in gone)]
        write(ov)
        print(json.dumps({"ok": True}))
    elif cmd == "reset-all":
        write({"_custom": [c for c in customs if not c.get("edited") and not c.get("deleted")]})
        print(json.dumps({"ok": True}))
    else:
        print(__doc__, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
