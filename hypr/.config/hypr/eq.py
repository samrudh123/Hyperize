#!/usr/bin/python3
"""The music panel's equalizer (Quickshell MediaPopup.qml) — controls the
PipeWire filter-chain in ~/.config/pipewire/rice-eq.conf (rice-eq.service,
a WirePlumber smart filter in front of the default sink).

    eq.py get                 print the state as JSON
    eq.py set BAND DB         band 1-10, -12..12 dB (preset becomes Custom)
    eq.py preset NAME         Flat Bass Treble Vocal Pop Rock Jazz Classic
    eq.py on|off|toggle       bypass the whole chain (smart filter disabled)
    eq.py apply [--wait]      push the saved state to the running filter
                              (rice-eq.service runs this after it starts)
    eq.py serve               the panel's feed: one command per stdin line
                              ("set 3 4.5", "preset Rock", "on", …), prints
                              the state as one JSON line after each

State: ~/.local/state/eq/state.json  {"bands": [10 dB], "preset", "enabled"}.
Boosts would clip, so a preamp (the chain's first node) takes off the
largest positive gain.
"""

import json
import os
import subprocess
import sys
import time

FREQS = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
PRESETS = {
    "Flat":    [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    "Bass":    [5, 7, 5, 2, 1, 0, 0, 0, 1, 2],
    "Treble":  [-2, -1, 0, 1, 2, 3, 4, 5, 6, 6],
    "Vocal":   [-2, -1, 1, 3, 5, 5, 4, 2, 1, 0],
    "Pop":     [2, 4, 2, 0, 1, 2, 4, 2, 1, 2],
    "Rock":    [5, 4, 2, -1, -2, -1, 2, 4, 5, 6],
    "Jazz":    [3, 3, 1, 1, 1, 1, 2, 1, 2, 3],
    "Classic": [0, 1, 2, 2, 2, 2, 1, 2, 3, 4],
}
NODE = "rice-eq"
STATE = os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"),
                     "eq", "state.json")


def load():
    try:
        with open(STATE) as f:
            s = json.load(f)
        bands = [max(-12.0, min(12.0, float(x))) for x in s.get("bands", [])][:10]
        bands += [0.0] * (10 - len(bands))
        return {"bands": bands, "preset": str(s.get("preset", "Custom")),
                "enabled": bool(s.get("enabled", True))}
    except (OSError, ValueError, TypeError):
        return {"bands": [0.0] * 10, "preset": "Flat", "enabled": True}


def save(s):
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    tmp = STATE + ".tmp"
    with open(tmp, "w") as f:
        json.dump({k: s[k] for k in ("bands", "preset", "enabled")}, f)
    os.replace(tmp, STATE)


_node_id = None


def node_id(refresh=False):
    """Global id of the filter's sink node (None if the service isn't up)."""
    global _node_id
    if _node_id is not None and not refresh:
        return _node_id
    _node_id = None
    try:
        out = subprocess.run(["pw-cli", "ls", "Node"], capture_output=True, text=True, timeout=3).stdout
    except (OSError, subprocess.TimeoutExpired):
        return None
    cur = None
    for line in out.splitlines():
        line = line.strip()
        if line.startswith("id "):
            cur = line.split()[1].rstrip(",")
        elif line.startswith("node.name") and line.split("=", 1)[1].strip().strip('"') == NODE:
            _node_id = int(cur)
            break
    return _node_id


def push(s):
    """Set the running filter's controls (and its bypass) from state `s`."""
    nid = node_id()
    if nid is None:
        return False
    gains = s["bands"]
    head = max(0.0, max(gains))
    params = ['"preamp:Mult" %.6f' % (10 ** (-head / 20))]
    params += ['"eq_band_%d:Gain" %.2f' % (i + 1, g) for i, g in enumerate(gains)]
    cmd = ["pw-cli", "set-param", str(nid), "Props", "{ params = [ " + " ".join(params) + " ] }"]
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=3)
    if r.returncode != 0 or "rror" in r.stderr:
        nid = node_id(refresh=True)                 # the service restarted
        if nid is None:
            return False
        cmd[2] = str(nid)
        subprocess.run(cmd, capture_output=True, timeout=3)
    set_enabled(s["enabled"], nid)
    return True


_applied = None          # (node id, enabled) last written to the metadata


def set_enabled(on, nid):
    global _applied
    if _applied == (nid, on):            # a band drag: don't touch the bypass
        return
    _applied = (nid, on)
    # absent key = enabled; the metadata wins over the node's properties
    if on:
        subprocess.run(["pw-metadata", "-n", "filters", "-d", str(nid), "filter.smart.disabled"],
                       capture_output=True, timeout=3)
    else:
        subprocess.run(["pw-metadata", "-n", "filters", str(nid), "filter.smart.disabled", "true", "Spa:String:JSON"],
                       capture_output=True, timeout=3)


def command(s, argv):
    """Apply one command to state `s`; returns the new state (saved+pushed)."""
    if not argv:
        return s
    c = argv[0]
    if c == "set" and len(argv) >= 3:
        i = int(argv[1]) - 1
        if 0 <= i < 10:
            s["bands"][i] = round(max(-12.0, min(12.0, float(argv[2]))), 1)
            s["preset"] = next((n for n, v in PRESETS.items() if v == s["bands"]), "Custom")
    elif c == "preset" and len(argv) >= 2 and argv[1] in PRESETS:
        s["bands"] = [float(x) for x in PRESETS[argv[1]]]
        s["preset"] = argv[1]
    elif c in ("on", "off", "toggle"):
        s["enabled"] = (not s["enabled"]) if c == "toggle" else c == "on"
    elif c != "apply":
        return s
    save(s)
    s["live"] = push(s)
    return s


def emit(s):
    print(json.dumps({**s, "freqs": FREQS, "presets": list(PRESETS)}), flush=True)


def main():
    args = sys.argv[1:] or ["get"]
    s = load()
    if args[0] == "get":
        s["live"] = node_id() is not None
        emit(s)
    elif args[0] == "apply" and "--wait" in args:
        for _ in range(40):                          # the node appears ~0.1-1 s after start
            if node_id(refresh=True) is not None:
                break
            time.sleep(0.25)
        time.sleep(0.3)                              # let WirePlumber register it
        command(s, ["apply"])
    elif args[0] == "serve":
        s["live"] = node_id() is not None
        emit(s)
        for line in sys.stdin:
            parts = line.split()
            if not parts:
                continue
            try:
                s = command(load() if parts[0] == "reload" else s, parts)
            except (ValueError, OSError, subprocess.TimeoutExpired) as e:
                print("eq.py:", e, file=sys.stderr)
            emit(s)
    else:
        emit(command(s, args))


if __name__ == "__main__":
    main()
