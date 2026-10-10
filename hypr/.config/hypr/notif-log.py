#!/usr/bin/python3
"""Notification logger — the history behind the notification centre.

    exec-once from hyprland.conf; notif-center.py reads what this writes.

mako draws the popups but keeps almost nothing afterwards: `makoctl history`
is five entries deep by default, has no body and no timestamps. So this
watches the session bus instead. It becomes a D-Bus MONITOR (the mechanism
dbus-monitor uses) for:

  Notify(...)                 a notification posted — app, summary, body,
                              icon, actions, urgency — and the method return
                              that carries the id mako gave it
  NotificationClosed(id, why) it left the screen: it stays in the history,
                              but its buttons stop working (mako forgets it)
  ActionInvoked(id, key)      one of its buttons was used

and appends to ~/.local/state/notif-center/history.json (newest last, capped).
A notification that replaces another (replaces_id, e.g. a download finishing)
updates that entry instead of adding one. OSD-style ones are skipped: the
opacity / volume kind that carry a "value" progress hint, and anything marked
transient or x-canonical-private-synchronous.

Every write is lock + re-read + modify + atomic replace, because the panel
also edits the file (removing / clearing entries). The lock is
history.json.lock (flock).

Monitor connections can't send anything — not even replies — so the filter
returns None for everything it eats; otherwise GDBus would try to answer the
Notify calls it overhears.
"""

import fcntl
import json
import os
import sys
import time

import gi

gi.require_version("Gio", "2.0")
gi.require_version("GLibUnix", "2.0")
from gi.repository import Gio, GLib, GLibUnix  # noqa: E402

STATE = os.path.join(os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")),
                     "notif-center")
HISTORY = os.path.join(STATE, "history.json")
MAX_ENTRIES = 300
IFACE = "org.freedesktop.Notifications"
RULES = [
    f"type='method_call',interface='{IFACE}',member='Notify'",
    f"type='method_return',sender='{IFACE}'",
    f"type='signal',interface='{IFACE}',member='NotificationClosed'",
    f"type='signal',interface='{IFACE}',member='ActionInvoked'",
]
# Hints worth keeping (image-data is a whole bitmap — dropped).
KEEP_HINTS = {"desktop-entry", "category", "image-path", "x-kde-origin-name",
              "x-kde-appname", "x-kde-display-appname", "x-kde-reply-placeholder-text"}


# ── the file ───────────────────────────────────────────────────────────────
class Locked:
    """with Locked() as data: ... — read under the lock, written back on exit
    if data["dirty"] was set."""

    def __enter__(self):
        os.makedirs(STATE, mode=0o700, exist_ok=True)
        self.fd = open(HISTORY + ".lock", "w")
        fcntl.flock(self.fd, fcntl.LOCK_EX)
        try:
            with open(HISTORY) as f:
                self.data = json.load(f)
        except (OSError, ValueError):
            self.data = {}
        self.data.setdefault("entries", [])
        self.data.setdefault("next_key", 1)
        self.dirty = False
        return self

    def __exit__(self, *exc):
        if self.dirty and not exc[0]:
            self.data["entries"] = self.data["entries"][-MAX_ENTRIES:]
            tmp = HISTORY + ".tmp"
            with open(tmp, "w") as f:
                json.dump(self.data, f, ensure_ascii=False)
            os.replace(tmp, HISTORY)
        fcntl.flock(self.fd, fcntl.LOCK_UN)
        self.fd.close()


def latest_live(entries, nid):
    for e in reversed(entries):
        if e.get("id") == nid and e.get("live"):
            return e
    return None


# ── events (main thread) ───────────────────────────────────────────────────
pending = {}      # (sender, serial) -> entry key, until the reply gives the id


def on_notify(sender, serial, args):
    app, replaces, icon, summary, body, actions, hints, timeout = args
    if hints.get("transient") or hints.get("x-canonical-private-synchronous") \
            or "value" in hints:
        return
    acts = [[actions[i], actions[i + 1]] for i in range(0, len(actions) - 1, 2)]
    urgency = hints.get("urgency", 1)
    kept = {k: v for k, v in hints.items() if k in KEEP_HINTS and isinstance(v, (str, int, bool))}
    with Locked() as h:
        entries = h.data["entries"]
        old = latest_live(entries, replaces) if replaces else None
        if old:
            old.update({"summary": summary, "body": body, "icon": icon, "actions": acts,
                        "urgency": urgency, "hints": kept, "time": time.time()})
            key = old["key"]
        else:
            key = h.data["next_key"]
            h.data["next_key"] += 1
            entries.append({"key": key, "id": replaces or None, "app": app, "icon": icon,
                            "summary": summary, "body": body, "actions": acts,
                            "urgency": urgency, "hints": kept, "time": time.time(),
                            "live": True})
        h.dirty = True
    pending[(sender, serial)] = key


def on_return(dest, reply_serial, args):
    key = pending.pop((dest, reply_serial), None)
    if key is None or not args:
        return
    with Locked() as h:
        for e in reversed(h.data["entries"]):
            if e["key"] == key:
                e["id"] = args[0]
                h.dirty = True
                break


def on_closed(nid, reason):
    with Locked() as h:
        e = latest_live(h.data["entries"], nid)
        if e:
            e["live"] = False
            e["closed"] = reason          # 1 expired · 2 dismissed · 3 closed by app
            h.dirty = True


def on_action(nid, key):
    with Locked() as h:
        e = latest_live(h.data["entries"], nid)
        if e:
            e["acted"] = key
            h.dirty = True


def handle(kind, *a):
    try:
        {"notify": on_notify, "return": on_return,
         "closed": on_closed, "action": on_action}[kind](*a)
    except Exception as exc:                            # noqa: BLE001 — never die
        print(f"notif-log: {kind}: {exc!r}", file=sys.stderr, flush=True)
    return False


# ── the monitor ────────────────────────────────────────────────────────────
def message_filter(_conn, msg, _incoming):
    """Runs on GDBus's worker thread: only copy the fields out, then hand the
    work to the main loop."""
    t = msg.get_message_type()
    try:
        if t == Gio.DBusMessageType.METHOD_CALL and msg.get_member() == "Notify" \
                and msg.get_interface() == IFACE:
            GLib.idle_add(handle, "notify", msg.get_sender(), msg.get_serial(),
                          msg.get_body().unpack())
        elif t == Gio.DBusMessageType.METHOD_RETURN:
            body = msg.get_body()
            GLib.idle_add(handle, "return", msg.get_destination(), msg.get_reply_serial(),
                          body.unpack() if body else ())
        elif t == Gio.DBusMessageType.SIGNAL and msg.get_interface() == IFACE:
            if msg.get_member() == "NotificationClosed":
                GLib.idle_add(handle, "closed", *msg.get_body().unpack())
            elif msg.get_member() == "ActionInvoked":
                GLib.idle_add(handle, "action", *msg.get_body().unpack())
            else:
                return msg
        else:
            return msg            # e.g. the reply to BecomeMonitor itself
    except Exception as exc:                            # noqa: BLE001
        print(f"notif-log: filter: {exc!r}", file=sys.stderr, flush=True)
    return None


def main():
    lock = open(os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "notif-log.lock"), "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        print("notif-log: already running", file=sys.stderr)
        return 1

    addr = Gio.dbus_address_get_for_bus_sync(Gio.BusType.SESSION, None)
    conn = Gio.DBusConnection.new_for_address_sync(
        addr, Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT
        | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION, None, None)
    conn.call_sync("org.freedesktop.DBus", "/org/freedesktop/DBus",
                   "org.freedesktop.DBus.Monitoring", "BecomeMonitor",
                   GLib.Variant("(asu)", (RULES, 0)), None,
                   Gio.DBusCallFlags.NONE, -1, None)
    conn.add_filter(message_filter)

    loop = GLib.MainLoop()
    GLibUnix.signal_add(GLib.PRIORITY_DEFAULT, 15, loop.quit)
    GLibUnix.signal_add(GLib.PRIORITY_DEFAULT, 2, loop.quit)
    conn.connect("closed", lambda *_: loop.quit())     # bus gone: exit, don't spin
    loop.run()
    return 0


if __name__ == "__main__":
    sys.exit(main())
