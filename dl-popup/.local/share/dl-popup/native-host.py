#!/usr/bin/python3
"""Firefox native-messaging host for the dl-popup extension.

Firefox starts this once per message (runtime.sendNativeMessage), sends one
length-prefixed JSON message on stdin and waits for one reply on stdout.
The job is piped into `dl-popup add --stdin`, which shows the fuzzel popup
and prints what happened ({"action": "aria2" | "jd" | "firefox" | ...}).
Registered by ~/.mozilla/native-messaging-hosts/dl_popup.json.
"""
import json
import os
import struct
import subprocess
import sys

DL_POPUP = os.path.expanduser("~/.local/bin/dl-popup")


def read():
    raw = sys.stdin.buffer.read(4)
    if len(raw) < 4:
        sys.exit(0)
    return json.loads(sys.stdin.buffer.read(struct.unpack("@I", raw)[0]))


def send(obj):
    data = json.dumps(obj).encode()
    sys.stdout.buffer.write(struct.pack("@I", len(data)) + data)
    sys.stdout.buffer.flush()


msg = read()
if msg.get("cmd") == "ping":
    send({"ok": True})
elif msg.get("cmd") == "add":
    p = subprocess.run([DL_POPUP, "add", "--stdin"], input=json.dumps(msg["job"]),
                       capture_output=True, text=True)
    try:
        send(json.loads(p.stdout.strip().splitlines()[-1]))
    except (IndexError, ValueError):
        send({"action": "error", "error": (p.stderr or "dl-popup printed nothing")[-500:]})
else:
    send({"action": "error", "error": f"unknown command {msg.get('cmd')!r}"})
