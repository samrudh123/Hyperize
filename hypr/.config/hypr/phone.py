#!/usr/bin/python3
"""Phone — the bottom bar's phone pill (KDE Connect).

    phone.py watch           one JSON line per change, for PhonePill.qml
    phone.py ring            make the phone ring (find my phone)
    phone.py clip            send this computer's clipboard to the phone
    phone.py send [FILE…]    share files to the phone; no FILE = pick in yazi
    phone.py browse          mount the phone over SFTP and open it in yazi
    phone.py ping [TEXT]     a ping (with a message) on the phone

Everything is read from kdeconnectd over D-Bus, which already has it: the
battery and signal plugins push changes, notifications come as signals. So
`watch` is event-driven, with a slow re-read as a safety net.

The phone is the first paired device of type "phone" (a reachable one wins);
PHONE_DEVICE=<id> picks another.
"""

import json
import os
import subprocess
import sys

from gi.repository import Gio, GLib

KDEC = "org.kde.kdeconnect"
ROOT = "/modules/kdeconnect"
DEV_IFACE = "org.kde.kdeconnect.device"
N_IFACE = "org.kde.kdeconnect.device.notifications"
HYPR = os.path.dirname(os.path.abspath(__file__))
PICK = os.path.join(HYPR, "pick-files.sh")

bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)


def call(path, iface, method, args=None, timeout=1500):
    try:
        r = bus.call_sync(KDEC, path, iface, method, args, None,
                          Gio.DBusCallFlags.NO_AUTO_START, timeout, None)
        return r.unpack() if r else ()
    except GLib.Error:
        return None


def props(path, iface):
    r = call(path, "org.freedesktop.DBus.Properties", "GetAll", GLib.Variant("(s)", (iface,)))
    return r[0] if r else {}


def find_device():
    """(id, device properties) of the phone, or (None, {})."""
    want = os.environ.get("PHONE_DEVICE")
    r = call(ROOT, "org.kde.kdeconnect.daemon", "devices", GLib.Variant("(bb)", (False, True)))
    best = (None, {})
    for dev in (r[0] if r else []):
        p = props(f"{ROOT}/devices/{dev}", DEV_IFACE)
        if want and dev != want:
            continue
        if not want and p.get("type") != "phone":
            continue
        if p.get("isReachable"):
            return dev, p
        if best[0] is None:
            best = (dev, p)
    return best


def state():
    dev, p = find_device()
    if dev is None:
        return {"available": call(ROOT, "org.freedesktop.DBus.Peer", "Ping") is not None,
                "paired": False}
    base = f"{ROOT}/devices/{dev}"
    out = {"available": True, "paired": True, "id": dev, "name": p.get("name", "Phone"),
           "reachable": bool(p.get("isReachable")), "battery": -1, "charging": False,
           "signal": -1, "network": "", "notifs": []}
    if not out["reachable"]:
        return out
    b = props(f"{base}/battery", "org.kde.kdeconnect.device.battery")
    out["battery"] = b.get("charge", -1)
    out["charging"] = bool(b.get("isCharging"))
    c = props(f"{base}/connectivity_report", "org.kde.kdeconnect.device.connectivity_report")
    out["signal"] = c.get("cellularNetworkStrength", -1)
    out["network"] = c.get("cellularNetworkType", "")
    r = call(f"{base}/notifications", N_IFACE, "activeNotifications")
    for nid in (r[0] if r else []):
        n = props(f"{base}/notifications/{nid}", N_IFACE + ".notification")
        if not n or not (n.get("title") or n.get("text")):
            continue
        out["notifs"].append({"id": nid, "app": n.get("appName", ""), "title": n.get("title", ""),
                              "text": (n.get("text") or "")[:120], "silent": bool(n.get("silent"))})
    return out


def cmd_watch():
    loop = GLib.MainLoop()
    pending = {"src": 0, "last": None}

    def emit():
        pending["src"] = 0
        line = json.dumps(state(), ensure_ascii=False)
        if line != pending["last"]:
            pending["last"] = line
            print(line, flush=True)
        return False

    def soon(*_):
        # signals come in bursts (a notification = posted + several updates)
        if not pending["src"]:
            pending["src"] = GLib.timeout_add(250, emit)

    bus.signal_subscribe(KDEC, None, None, None, None, Gio.DBusSignalFlags.NONE, soon)
    bus.signal_subscribe("org.freedesktop.DBus", "org.freedesktop.DBus", "NameOwnerChanged",
                         "/org/freedesktop/DBus", KDEC, Gio.DBusSignalFlags.NONE, soon)
    GLib.timeout_add_seconds(60, lambda: (soon(), True)[1])
    emit()
    loop.run()


def device_or_die():
    dev, p = find_device()
    if dev is None or not p.get("isReachable"):
        notify("Phone not connected", "KDE Connect can't reach the phone right now.")
        sys.exit(1)
    return f"{ROOT}/devices/{dev}", p.get("name", "Phone")


def notify(title, body=""):
    subprocess.Popen(["notify-send", "-a", "KDE Connect", "-i", "smartphone", title, body],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "watch"
    args = sys.argv[2:]
    if cmd == "watch":
        return cmd_watch()
    if cmd == "state":
        return print(json.dumps(state(), ensure_ascii=False, indent=1))
    base, name = device_or_die()
    if cmd == "ring":
        call(f"{base}/findmyphone", "org.kde.kdeconnect.device.findmyphone", "ring")
    elif cmd == "clip":
        call(f"{base}/clipboard", "org.kde.kdeconnect.device.clipboard", "sendClipboard")
        notify("Clipboard sent", f"to {name}")
    elif cmd == "ping":
        msg = " ".join(args)
        if msg:
            call(f"{base}/ping", "org.kde.kdeconnect.device.ping", "sendPing", GLib.Variant("(s)", (msg,)))
        else:
            call(f"{base}/ping", "org.kde.kdeconnect.device.ping", "sendPing")
    elif cmd == "send":
        files = args or subprocess.run([PICK], capture_output=True, text=True).stdout.splitlines()
        files = [os.path.abspath(f) for f in files if f and os.path.exists(f)]
        if not files:
            return
        urls = [GLib.filename_to_uri(f, None) for f in files]
        call(f"{base}/share", "org.kde.kdeconnect.device.share", "shareUrls", GLib.Variant("(as)", (urls,)))
        notify(f"Sending {len(files)} file{'s' * (len(files) > 1)} to {name}",
               "\n".join(os.path.basename(f) for f in files[:6]))
    elif cmd == "browse":
        sftp, iface = f"{base}/sftp", "org.kde.kdeconnect.device.sftp"
        ok = call(sftp, iface, "mountAndWait", timeout=20000)
        if not ok or not ok[0]:
            err = call(sftp, iface, "getMountError")
            notify("Couldn't open the phone's files", err[0] if err else "")
            return
        dirs = call(sftp, iface, "getDirectories")
        root = call(sftp, iface, "mountPoint")[0]
        # getDirectories: {path: label}, e.g. the internal storage
        target = next(iter(dirs[0]), root) if dirs and dirs[0] else root
        subprocess.Popen(["ghostty", "--gtk-single-instance=false", "--class=com.samrudh.yazi",
                          "-e", os.path.join(HYPR, "yazi-launch.sh"), target],
                         start_new_session=True)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
