#!/usr/bin/python3
"""Native messaging host for the PDF in Zathura Firefox extension.

Reads zathurarc the way zathurarc.js does for VS Code (set, map, unmap,
include, quoting, # comments), sends it as {"type": "config", "rc": ...},
and sends it again whenever the file or anything it includes changes.
Firefox starts it while a viewer is open and closes stdin when done.
"""
import json
import os
import struct
import sys
import threading
import time

CONFIG_DIR = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config"), "zathura")
ZATHURARC = os.path.join(CONFIG_DIR, "zathurarc")


def tokenize(line):
    """Words: "double" and 'single' quotes group, backslash escapes, an
    unquoted # starts a comment."""
    out, cur, quote, i = [], None, None, 0
    while i < len(line):
        c = line[i]
        if quote:
            if c == "\\" and i + 1 < len(line):
                i += 1
                cur += line[i]
            elif c == quote:
                quote = None
            else:
                cur += c
        elif c in "\"'":
            quote = c
            cur = cur or ""
        elif c == "\\" and i + 1 < len(line):
            i += 1
            cur = (cur or "") + line[i]
        elif c == "#" and cur is None:
            break
        elif c.isspace():
            if cur is not None:
                out.append(cur)
            cur = None
        else:
            cur = (cur or "") + c
        i += 1
    if cur is not None:
        out.append(cur)
    return out


def parse_file(path, out, depth):
    try:
        with open(path, encoding="utf-8") as f:
            text = f.read()
    except OSError:
        return
    for line in text.split("\n"):
        words = tokenize(line)
        if not words:
            continue
        cmd, args = words[0], words[1:]
        if cmd == "set" and args:
            out["options"][args[0]] = args[1] if len(args) > 1 else "true"
        elif cmd in ("map", "unmap"):
            mode = "normal"
            if args and args[0].startswith("[") and args[0].endswith("]"):
                mode = args.pop(0)[1:-1]
            if not args:
                continue
            if cmd == "map":
                fn = args[1] if len(args) > 1 else None
                arg = args[2] if len(args) > 2 else None
            else:
                fn = arg = None
            out["maps"].append({"mode": mode, "keys": args[0], "fn": fn, "arg": arg})
        elif cmd == "include" and args and depth < 8:
            inc = os.path.join(os.path.dirname(path), os.path.expanduser(args[0]))
            parse_file(inc, out, depth + 1)


def load():
    out = {"options": {}, "maps": []}
    parse_file(ZATHURARC, out, 0)
    return out


lock = threading.Lock()


def send(msg):
    data = json.dumps(msg).encode()
    with lock:
        sys.stdout.buffer.write(struct.pack("@I", len(data)) + data)
        sys.stdout.buffer.flush()


# Re-reading a small file twice a second is cheaper than being clever:
# set-accent.sh replaces it rather than editing it, and includes can change
# too, so compare what it says, not its mtime.
def watch():
    last = None
    while True:
        rc = load()
        if rc != last:
            last = rc
            send({"type": "config", "rc": rc})
        time.sleep(0.5)


def main():
    threading.Thread(target=watch, daemon=True).start()
    # Nothing to answer; stdin closing means Firefox is done with us.
    while sys.stdin.buffer.read(4096):
        pass


if __name__ == "__main__":
    try:
        main()
    except (BrokenPipeError, KeyboardInterrupt):
        pass
