#!/usr/bin/python3
"""Notification centre — the bell in the top bar, left of the settings cog.

    notif-center.py [toggle]    open / close the panel (bar on-click)
    notif-center.py phone       the same, opening on the Phone tab (the bottom
                                bar's phone-notifications pill)
    notif-center.py bar         long-running JSON for waybar's custom/notifications
    notif-center.py dnd [on|off|toggle]   do not disturb (bar right-click)
    notif-center.py serve       backend of the Quickshell panel (NotifPopup.qml):
                                JSON snapshots out, commands in — see serve()

Two tabs:

  System   everything posted to the notification server, from the history
           notif-log.py keeps (mako itself forgets almost at once).
  Phone    what is in the phone's notification shade RIGHT NOW, read from
           KDE Connect over D-Bus — × dismisses it on the phone too, Reply
           answers messages — and below it, "Earlier": KDE Connect's own
           notifications (pairing requests, pings, battery) and phone ones
           that have since gone from the phone.

Buttons on a notification (Accept / Reject, Confirm / Deny, …) work while it
is still LIVE, i.e. mako still has it: they go through `makoctl invoke`, which
is the only way to answer the app that posted it. After it has closed, the
app has stopped listening, so the history shows it without buttons.

Opening the panel marks everything read; the bell shows the unread count.
Do not disturb is mako's "do-not-disturb" mode (invisible=1 in mako/config,
critical ones still show), remembered across restarts in the state dir.

A normal toplevel window like network-panel.py / media-menu.py (app_id from
set_prgname; windowrule notif-center in hyprland.conf). Run again = close.
"""

import fcntl
import json
import os
import re
import signal
import subprocess
import sys
import time

STATE = os.path.join(os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")),
                     "notif-center")
HISTORY = os.path.join(STATE, "history.json")
DND_FILE = os.path.join(STATE, "dnd")
RUNTIME = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
LOCK = os.path.join(RUNTIME, "notif-center.lock")
ACCENT_FILE = os.path.expanduser("~/.config/hypr/theme/accent")

I_BELL = "\U000F009A"          # md-bell
I_BELL_UNREAD = "\U000F009E"   # md-bell_ring
I_BELL_OFF = "\U000F009B"      # md-bell_off
I_PHONE = "\U000F011C"         # md-cellphone
I_SYSTEM = "\U000F0379"        # md-monitor
I_CLOSE = "\U000F0156"         # md-close


# ── history (shared with notif-log.py) ────────────────────────────────────
class Locked:
    """Same protocol as notif-log.py: flock, re-read, modify, atomic write."""

    def __enter__(self):
        os.makedirs(STATE, mode=0o700, exist_ok=True)
        self.fd = open(HISTORY + ".lock", "w")
        fcntl.flock(self.fd, fcntl.LOCK_EX)
        self.data = load()
        self.dirty = False
        return self

    def __exit__(self, *exc):
        if self.dirty and not exc[0]:
            tmp = HISTORY + ".tmp"
            with open(tmp, "w") as f:
                json.dump(self.data, f, ensure_ascii=False)
            os.replace(tmp, HISTORY)
        fcntl.flock(self.fd, fcntl.LOCK_UN)
        self.fd.close()



def _rice_subst(css):
    """Desktop THEMES (SUPER+SHIFT+T): this CSS is written in Catppuccin Mocha;
    recolour it into the current theme (rice-theme.py palette substitution)."""
    try:
        import importlib.util
        import os as _os
        spec = importlib.util.spec_from_file_location(
            "rice_theme", _os.path.expanduser("~/.config/hypr/rice-theme.py"))
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return mod.subst(css, mod.current())
    except Exception:              # noqa: BLE001 — fall back to Mocha
        return css

def load():
    try:
        with open(HISTORY) as f:
            data = json.load(f)
    except (OSError, ValueError):
        data = {}
    data.setdefault("entries", [])
    data.setdefault("next_key", 1)
    data.setdefault("seen", 0)
    return data


def is_phone(e):
    """KDE Connect posts both its own notices and the phone's relayed ones."""
    app = (e.get("app") or "").lower()
    desk = str((e.get("hints") or {}).get("desktop-entry", "")).lower()
    return "kde connect" in app or "kdeconnect" in app or "kdeconnect" in desk


def unread(data):
    return [e for e in data["entries"]
            if e.get("time", 0) > data["seen"] and e.get("closed") != 2 and not e.get("acted")]


# ── do not disturb ─────────────────────────────────────────────────────────
def dnd_on():
    return os.path.exists(DND_FILE)


def set_mode(mode, on):
    subprocess.run(["makoctl", "mode", "-a" if on else "-r", mode],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def set_dnd(on):
    os.makedirs(STATE, mode=0o700, exist_ok=True)
    if on:
        open(DND_FILE, "w").close()
    elif os.path.exists(DND_FILE):
        os.remove(DND_FILE)
    set_mode("do-not-disturb", on)


# ── waybar module ──────────────────────────────────────────────────────────
def bar():
    """One JSON line per change. Polls mtimes once a second — a stat, not a
    subprocess — rather than a signal, which would hit both bars."""
    if dnd_on():                       # mako forgets its mode when it restarts
        set_dnd(True)
    last_sig, last_line = None, None
    while True:
        try:
            sig = (os.stat(HISTORY).st_mtime_ns if os.path.exists(HISTORY) else 0, dnd_on())
        except OSError:
            sig = (0, dnd_on())
        if sig != last_sig:
            last_sig = sig
            data = load()
            new = unread(data)
            n_phone = sum(is_phone(e) for e in new)
            if sig[1]:
                icon, cls = I_BELL_OFF, "dnd"
            elif new:
                icon, cls = I_BELL_UNREAD, "unread"
            else:
                icon, cls = I_BELL, "empty"
            text = f"{icon} {len(new)}" if new else icon
            tip = (f"{len(new)} unread — {len(new) - n_phone} system, {n_phone} phone"
                   if new else "No new notifications")
            if sig[1]:
                tip = "Do not disturb is ON (popups hidden)\n" + tip
            tip += "\nClick: notifications · Right-click: do not disturb"
            line = json.dumps({"text": text, "tooltip": tip, "class": cls}, ensure_ascii=False)
            if line != last_line:
                print(line, flush=True)
                last_line = line
        time.sleep(1)


# ── Quickshell panel backend ───────────────────────────────────────────────
# NotifPopup.qml (the bell's panel since 2026-10-27) runs `serve` while it is
# open: one JSON snapshot per change on stdout, commands on stdin. Opening
# does what the GTK panel did — marks everything read, hides mako's popups
# (mode panel-open) — and closing (stdin EOF / SIGTERM) undoes the mode and
# marks what arrived meanwhile read too.
#
#   stdin:  remove KEY · clear system|phone · invoke ID ACTION · dnd on|off
#           phone-dismiss PATH · phone-action PATH NAME · phone-reply PATH TEXT
#           refresh
KDEC = "org.kde.kdeconnect"
N_IFACE = "org.kde.kdeconnect.device.notifications"
ALLOWED_TAGS = re.compile(r"<(/?)(b|i|u|a)(\s[^>]*)?>", re.I)


def styled(body):
    """Notification body markup -> Qt StyledText: keep b/i/u/a, escape the
    rest (bodies are often plain text with a stray < or &), \n -> <br>."""
    import html
    out, pos = [], 0
    for m in ALLOWED_TAGS.finditer(body or ""):
        out.append(html.escape(html.unescape(re.sub(r"<[^>]+>", "", body[pos:m.start()])), quote=False))
        out.append(m.group(0) if m.group(2).lower() != "a" or m.group(1) else
                   "<a%s>" % (m.group(3) or ""))
        pos = m.end()
    out.append(html.escape(html.unescape(re.sub(r"<[^>]+>", "", (body or "")[pos:])), quote=False))
    return "".join(out).strip().replace("\n", "<br>")


class Kdec:
    def __init__(self):
        from gi.repository import Gio, GLib
        self.Gio, self.GLib = Gio, GLib
        self.bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)

    def call(self, path, iface, method, args=None):
        try:
            r = self.bus.call_sync(KDEC, path, iface, method, args, None,
                                   self.Gio.DBusCallFlags.NO_AUTO_START, 800, None)
            return r.unpack() if r else ()
        except self.GLib.Error:
            return None

    def devices(self):
        r = self.call("/modules/kdeconnect", "org.kde.kdeconnect.daemon", "devices",
                      self.GLib.Variant("(bb)", (False, True)))
        out = []
        for dev in (r[0] if r else []):
            props = self.call(f"/modules/kdeconnect/devices/{dev}", "org.freedesktop.DBus.Properties",
                              "GetAll", self.GLib.Variant("(s)", ("org.kde.kdeconnect.device",)))
            props = props[0] if props else {}
            out.append({"id": dev, "name": props.get("name", "Phone"),
                        "reachable": bool(props.get("isReachable"))})
        return out

    def notes(self, dev):
        base = f"/modules/kdeconnect/devices/{dev}/notifications"
        r = self.call(base, N_IFACE, "activeNotifications")
        out = []
        for nid in (r[0] if r else []):
            path = f"{base}/{nid}"
            props = self.call(path, "org.freedesktop.DBus.Properties", "GetAll",
                              self.GLib.Variant("(s)", (N_IFACE + ".notification",)))
            if not props:
                continue
            p = props[0]
            out.append({"path": path, "app": p.get("appName", "Phone"),
                        "summary": p.get("title", "") or p.get("ticker", ""),
                        "body": styled(p.get("text", "")), "raw": p.get("text", ""),
                        "icon": p.get("iconPath", "") if p.get("hasIcon") else "",
                        "actions": list(p.get("actions", []) or []),
                        "replyable": bool(p.get("replyId")),
                        "dismissable": bool(p.get("dismissable", True))})
        return out

    def note_call(self, path, method, arg=None):
        self.call(path, N_IFACE + ".notification", method,
                  self.GLib.Variant("(s)", (arg,)) if arg is not None else None)


def entry_json(e, seen_before):
    hints = e.get("hints") or {}
    acts = e.get("actions") or []
    live = bool(e.get("live") and e.get("id"))
    app = (hints.get("x-kde-display-appname") or e.get("app")
           or str(hints.get("desktop-entry", "")).split(".")[-1] or "Notification")
    return {"key": e["key"], "id": e.get("id"), "live": live, "app": app,
            "icon": e.get("icon") or "", "image": str(hints.get("image-path", "") or ""),
            "desktop": str(hints.get("desktop-entry", "") or ""),
            "summary": e.get("summary", ""), "body": styled(e.get("body", "")),
            "time": e.get("time", 0), "critical": e.get("urgency") == 2,
            "unread": e.get("time", 0) > seen_before,
            "actions": [[k, l] for k, l in acts if k != "default"] if live else [],
            "hasDefault": live and any(k == "default" for k, _ in acts)}


def serve():
    import threading
    import ctypes
    ctypes.CDLL("libc.so.6", use_errno=True).prctl(1, signal.SIGTERM)   # PR_SET_PDEATHSIG
    seen_before = load()["seen"]

    def mark_read():
        with Locked() as h:
            h.data["seen"] = time.time()
            h.dirty = True

    def finish(*_):
        set_mode("panel-open", False)
        mark_read()
        os._exit(0)

    signal.signal(signal.SIGTERM, finish)
    mark_read()
    set_mode("panel-open", True)
    kd = Kdec()
    poke = threading.Event()

    def run(*argv):
        subprocess.Popen(argv, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True)

    def command(line):
        parts = line.rstrip("\n").split(" ", 2)
        cmd, a = parts[0], parts[1:]
        if cmd == "remove" and a:
            with Locked() as h:
                gone = [e for e in h.data["entries"] if str(e["key"]) == a[0]]
                h.data["entries"] = [e for e in h.data["entries"] if str(e["key"]) != a[0]]
                h.dirty = True
            for e in gone:
                if e.get("live") and e.get("id"):
                    run("makoctl", "dismiss", "-n", str(e["id"]))
        elif cmd == "clear" and a:
            phone_tab = a[0] == "phone"
            with Locked() as h:
                gone = [e for e in h.data["entries"] if is_phone(e) == phone_tab]
                h.data["entries"] = [e for e in h.data["entries"] if is_phone(e) != phone_tab]
                h.dirty = True
            for e in gone:
                if e.get("live") and e.get("id"):
                    run("makoctl", "dismiss", "-n", str(e["id"]))
        elif cmd == "invoke" and len(a) == 2:
            run("makoctl", "invoke", "-n", a[0], a[1])
        elif cmd == "dnd" and a:
            set_dnd(a[0] == "on")
        elif cmd == "phone-dismiss" and a:
            kd.note_call(a[0], "dismiss")
        elif cmd == "phone-action" and len(a) == 2:
            kd.note_call(a[0], "sendAction", a[1])
        elif cmd == "phone-reply" and len(a) == 2:
            kd.note_call(a[0], "sendReply", a[1])
        poke.set()

    def reader():
        for line in sys.stdin:
            try:
                command(line)
            except Exception as ex:         # noqa: BLE001 — keep serving
                print(f"notif-center serve: {line!r}: {ex}", file=sys.stderr)
        finish()

    threading.Thread(target=reader, daemon=True).start()

    last, phone_every = None, 0
    devices, phone = [], []
    while True:
        if phone_every <= 0 or poke.is_set():
            devices = kd.devices()
            phone = [dict(d, notes=kd.notes(d["id"]) if d["reachable"] else []) for d in devices]
            phone_every = 2                     # KDE Connect: every 2 s (D-Bus calls)
        phone_every -= 1
        poke.clear()
        data = load()
        live_texts = [(n["summary"], n["raw"]) for d in phone for n in d["notes"]]

        def on_phone_now(e):
            s_, b_ = e.get("summary", ""), e.get("body", "")
            return any(t and x and t in s_ + b_ and x in s_ + b_ for t, x in live_texts)

        entries = list(reversed(data["entries"]))
        snap = {
            "dnd": dnd_on(), "seenBefore": seen_before,
            "system": [entry_json(e, seen_before) for e in entries if not is_phone(e)],
            "earlier": [entry_json(e, seen_before) for e in entries
                        if is_phone(e) and not on_phone_now(e)],
            "phone": phone,
        }
        line = json.dumps(snap, ensure_ascii=False)
        if line != last:
            print(line, flush=True)
            last = line
        poke.wait(0.5)


# ── panel ──────────────────────────────────────────────────────────────────
def close_network_panel():
    """The Wi-Fi dropdown (network-panel.py) opens in the same top-right
    corner: close it so the two never stack. It does the same for this."""
    try:
        fd = os.open(os.path.join(RUNTIME, "network-panel.lock"), os.O_RDWR)
    except OSError:
        return
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        fcntl.flock(fd, fcntl.LOCK_UN)            # nobody holds it: not open
    except BlockingIOError:
        pid = os.pread(fd, 32, 0).decode().strip()
        if pid.isdigit():
            try:
                os.kill(int(pid), signal.SIGTERM)
            except ProcessLookupError:
                pass
    finally:
        os.close(fd)


def toggle_or_claim():
    """flock single instance: a second launch closes the open panel."""
    fd = os.open(LOCK, os.O_RDWR | os.O_CREAT, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        pid = os.pread(fd, 32, 0).decode().strip()
        if pid.isdigit():
            try:
                os.kill(int(pid), signal.SIGTERM)
            except ProcessLookupError:
                pass
        return True
    os.ftruncate(fd, 0)
    os.pwrite(fd, str(os.getpid()).encode(), 0)
    toggle_or_claim.fd = fd
    return False


def read_accent():
    try:
        with open(ACCENT_FILE) as fh:
            hexval = fh.read().strip().lstrip("#")
        if re.fullmatch(r"[0-9a-fA-F]{6}", hexval):
            return "#" + hexval
    except OSError:
        pass
    return "#89b4fa"


def ago(t):
    d = time.time() - t
    if d < 60:
        return "now"
    if d < 3600:
        return f"{int(d // 60)}m ago"
    lt, today = time.localtime(t), time.localtime()
    if lt.tm_yday == today.tm_yday and lt.tm_year == today.tm_year:
        return time.strftime("%H:%M", lt)
    if d < 7 * 86400:
        return time.strftime("%a %H:%M", lt)
    return time.strftime("%d %b", lt)


def panel(tab=None):
    if toggle_or_claim():
        return 0
    close_network_panel()

    import gi
    gi.require_version("Gtk", "3.0")
    gi.require_version("Gdk", "3.0")         # pin BEFORE importing — see network-panel.py
    gi.require_version("GdkPixbuf", "2.0")
    gi.require_version("GLibUnix", "2.0")
    from gi.repository import GLib
    GLib.set_prgname("notif-center")         # app_id; must precede the Gtk/Gdk import
    from gi.repository import Gdk, GdkPixbuf, Gio, GLibUnix, Gtk, Pango

    ACCENT = read_accent()
    BASE, MANTLE, SURFACE0, SURFACE1 = "#1e1e2e", "#181825", "#313244", "#45475a"
    TEXT, SUBTEXT, OVERLAY, RED = "#cdd6f4", "#a6adc8", "#6c7086", "#f38ba8"
    CSS = f"""
    window, .panel {{ background: {BASE}; color: {TEXT};
                      font-family: "JetBrainsMono Nerd Font"; }}
    .top {{ background: {MANTLE}; padding: 10px 12px; }}
    .title {{ font-size: 12pt; font-weight: 700; }}
    notebook header {{ background: {MANTLE}; border: none; }}
    notebook header tab {{ color: {OVERLAY}; padding: 8px 18px; border: none;
                           background: transparent; font-weight: 600; }}
    notebook header tab:checked {{ color: {ACCENT}; box-shadow: inset 0 -2px 0 {ACCENT}; }}
    notebook > stack, scrolledwindow, viewport {{ background: {BASE}; }}
    list, row {{ background: transparent; }}
    row {{ padding: 0; }}
    row:selected, row:focus {{ background: transparent; outline: none; }}
    .card {{ background: {MANTLE}; border-radius: 10px; padding: 10px 12px;
             margin: 6px 10px 0 10px; border-left: 3px solid transparent; }}
    .card.unread {{ border-left: 3px solid {ACCENT}; }}
    .card.critical {{ border-left: 3px solid {RED}; }}
    .card:hover {{ background: {SURFACE0}; }}
    .app {{ font-size: 9pt; color: {SUBTEXT}; font-weight: 600; }}
    .when {{ font-size: 9pt; color: {OVERLAY}; }}
    .summary {{ font-size: 10.5pt; font-weight: 700; color: {TEXT}; }}
    .body {{ font-size: 10pt; color: {SUBTEXT}; }}
    .section {{ font-size: 9pt; font-weight: 700; color: {OVERLAY};
                padding: 12px 14px 0 14px; }}
    .empty {{ color: {OVERLAY}; padding: 40px 0; }}
    .glyph {{ font-size: 16pt; color: {SUBTEXT}; }}
    button {{ background: {SURFACE0}; color: {TEXT}; border: none; box-shadow: none;
              border-radius: 6px; padding: 4px 12px; font-size: 9pt; }}
    button:hover {{ background: {SURFACE1}; }}
    button.suggested-action {{ background: {ACCENT}; color: {BASE}; font-weight: 700; }}
    button.close {{ background: transparent; padding: 0 4px; color: {OVERLAY}; min-height: 0; }}
    button.close:hover {{ color: {RED}; }}
    entry {{ background: {SURFACE0}; color: {TEXT}; border: none; border-radius: 6px;
             padding: 5px 8px; }}
    switch {{ background: {SURFACE1}; border: 1px solid {SURFACE1}; box-shadow: none; }}
    switch:checked {{ background: {ACCENT}; border: 1px solid {ACCENT}; box-shadow: none; }}
    switch slider {{ background: {TEXT}; border: none; box-shadow: none; }}
    switch:checked slider {{ background: {BASE}; }}
    .dim {{ color: {OVERLAY}; font-size: 9pt; }}
    """

    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    KDEC = "org.kde.kdeconnect"
    N_IFACE = "org.kde.kdeconnect.device.notifications"

    def kcall(path, iface, method, args=None, rtype=None):
        try:
            r = bus.call_sync(KDEC, path, iface, method, args, rtype,
                              Gio.DBusCallFlags.NO_AUTO_START, 800, None)
            return r.unpack() if r else ()
        except GLib.Error:
            return None

    def phone_devices():
        """[(device id, name, reachable)] for paired devices."""
        r = kcall("/modules/kdeconnect", "org.kde.kdeconnect.daemon", "devices",
                  GLib.Variant("(bb)", (False, True)))
        out = []
        for dev in (r[0] if r else []):
            props = kcall(f"/modules/kdeconnect/devices/{dev}", "org.freedesktop.DBus.Properties",
                          "GetAll", GLib.Variant("(s)", ("org.kde.kdeconnect.device",)))
            props = props[0] if props else {}
            out.append((dev, props.get("name", "Phone"), bool(props.get("isReachable"))))
        return out

    def phone_notifications(dev):
        base = f"/modules/kdeconnect/devices/{dev}/notifications"
        r = kcall(base, N_IFACE, "activeNotifications")
        out = []
        for nid in (r[0] if r else []):
            path = f"{base}/{nid}"
            props = kcall(path, "org.freedesktop.DBus.Properties", "GetAll",
                          GLib.Variant("(s)", (N_IFACE + ".notification",)))
            if props:
                out.append((path, props[0]))
        return out

    def set_body(label, body):
        """mako takes body markup; render it when Pango accepts it, else plain."""
        try:
            Pango.parse_markup(body, -1, "\0")
            label.set_markup(body)
        except GLib.Error:
            label.set_text(re.sub(r"<[^>]+>", "", body))

    def icon_widget(name, glyph):
        """App icon from a path, file:// URI or theme name; else a glyph."""
        name = (name or "").strip()
        if name.startswith("file://"):
            name = GLib.filename_from_uri(name)[0]
        try:
            if name.startswith("/") and os.path.isfile(name):
                pb = GdkPixbuf.Pixbuf.new_from_file_at_size(name, 28, 28)
                return Gtk.Image.new_from_pixbuf(pb)
            if name and Gtk.IconTheme.get_default().has_icon(name):
                return Gtk.Image.new_from_icon_name(name, Gtk.IconSize.DND)
        except GLib.Error:
            pass
        lbl = Gtk.Label(label=glyph)
        lbl.get_style_context().add_class("glyph")
        return lbl

    def run(*argv):
        subprocess.Popen(argv, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True)

    class Panel(Gtk.Window):
        def __init__(self):
            super().__init__(title="Notifications")
            self.set_default_size(440, 620)
            self.get_style_context().add_class("panel")
            data = load()
            self.seen_before = data["seen"]          # unread = newer than this
            with Locked() as h:                      # opening marks all read
                h.data["seen"] = time.time()
                h.dirty = True
            self.sig = None
            self.phone_sig = None
            self.replying = False

            outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            self.add(outer)

            top = Gtk.Box(spacing=10)
            top.get_style_context().add_class("top")
            title = Gtk.Label(label=f"{I_BELL}  Notifications", xalign=0)
            title.get_style_context().add_class("title")
            top.pack_start(title, True, True, 0)
            dl = Gtk.Label(label="Do not disturb")
            dl.get_style_context().add_class("dim")
            top.pack_start(dl, False, False, 0)
            self.dnd = Gtk.Switch(active=dnd_on(), valign=Gtk.Align.CENTER)
            self.dnd.connect("notify::active", lambda s, _p: set_dnd(s.get_active()))
            top.pack_start(self.dnd, False, False, 0)
            clear = Gtk.Button(label="Clear")
            clear.set_tooltip_text("Clear this tab's history (phone: only 'Earlier')")
            clear.connect("clicked", self.on_clear)
            top.pack_start(clear, False, False, 0)
            outer.pack_start(top, False, False, 0)

            self.nb = Gtk.Notebook()
            self.lists, self.tabs = {}, {}
            for key, glyph, name in (("system", I_SYSTEM, "System"), ("phone", I_PHONE, "Phone")):
                sw = Gtk.ScrolledWindow()
                sw.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
                box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
                box.set_margin_bottom(10)
                sw.add(box)
                self.lists[key] = box
                self.tabs[key] = Gtk.Label(label=f"{glyph}  {name}")
                sw.show_all()            # GtkNotebook won't switch to a hidden page
                self.nb.append_page(sw, self.tabs[key])
            outer.pack_start(self.nb, True, True, 0)

            self.refresh()
            # Open on the tab asked for, else the one with the newest unread
            # notification.
            new = [e for e in data["entries"] if e.get("time", 0) > self.seen_before]
            if tab == "phone" or (tab is None and new and is_phone(new[-1])):
                self.nb.set_current_page(1)

            # Popups would sit on top of the panel (mako draws on the overlay
            # layer, top right). Hide them while it is open — mode panel-open
            # in mako/config is invisible=1, which keeps them LIVE, so their
            # buttons here still work — and let them back when it closes.
            set_mode("panel-open", True)
            self.connect("destroy", lambda *_: set_mode("panel-open", False))

            GLib.timeout_add(1000, self.tick)
            self.connect("key-press-event", self.on_key)
            self.connect("focus-out-event", self.on_focus_out)
            self.connect("destroy", Gtk.main_quit)

        # ── building ──
        def clear_box(self, box):
            for c in box.get_children():
                box.remove(c)

        def section(self, box, text):
            lbl = Gtk.Label(label=text, xalign=0)
            lbl.get_style_context().add_class("section")
            box.pack_start(lbl, False, False, 0)

        def empty(self, box, text):
            lbl = Gtk.Label(label=text)
            lbl.get_style_context().add_class("empty")
            box.pack_start(lbl, False, False, 0)

        def card(self, *, icon, glyph, app, when, summary, body, unread_=False,
                 critical=False, buttons=(), on_close=None, close_tip="Remove",
                 on_click=None, reply=None):
            ev = Gtk.EventBox()
            outer = Gtk.Box(spacing=12)
            ctx = outer.get_style_context()
            ctx.add_class("card")
            if critical:
                ctx.add_class("critical")
            elif unread_:
                ctx.add_class("unread")
            ev.add(outer)
            iw = icon_widget(icon, glyph)
            iw.set_valign(Gtk.Align.START)
            outer.pack_start(iw, False, False, 0)

            col = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=3)
            outer.pack_start(col, True, True, 0)
            head = Gtk.Box(spacing=6)
            a = Gtk.Label(label=app, xalign=0)
            a.get_style_context().add_class("app")
            a.set_ellipsize(Pango.EllipsizeMode.END)
            head.pack_start(a, True, True, 0)
            w = Gtk.Label(label=when)
            w.get_style_context().add_class("when")
            head.pack_start(w, False, False, 0)
            if on_close:
                x = Gtk.Button(label=I_CLOSE)
                x.get_style_context().add_class("close")
                x.set_tooltip_text(close_tip)
                x.connect("clicked", lambda *_: on_close())
                head.pack_start(x, False, False, 0)
            col.pack_start(head, False, False, 0)
            if summary:
                s = Gtk.Label(label=summary, xalign=0)
                s.get_style_context().add_class("summary")
                s.set_line_wrap(True)
                s.set_line_wrap_mode(Pango.WrapMode.WORD_CHAR)
                s.set_max_width_chars(36)
                col.pack_start(s, False, False, 0)
            if body:
                b = Gtk.Label(xalign=0)
                b.get_style_context().add_class("body")
                set_body(b, body)
                b.set_line_wrap(True)
                b.set_line_wrap_mode(Pango.WrapMode.WORD_CHAR)
                b.set_max_width_chars(36)
                b.set_lines(5)
                b.set_ellipsize(Pango.EllipsizeMode.END)
                col.pack_start(b, False, False, 0)
            if buttons or reply:
                row = Gtk.Box(spacing=6)
                row.set_margin_top(6)
                for i, (label, cb) in enumerate(buttons):
                    btn = Gtk.Button(label=label)
                    if i == 0:
                        btn.get_style_context().add_class("suggested-action")
                    btn.connect("clicked", lambda _b, cb=cb: cb())
                    row.pack_start(btn, False, False, 0)
                if reply:
                    entry = Gtk.Entry(placeholder_text="Reply…")
                    entry.set_no_show_all(True)
                    rb = Gtk.Button(label="Reply")

                    def open_reply(_b, entry=entry, rb=rb):
                        rb.hide()
                        entry.show()
                        entry.grab_focus()
                        self.replying = True

                    def send(e, reply=reply):
                        if e.get_text().strip():
                            reply(e.get_text())
                        self.replying = False

                    rb.connect("clicked", open_reply)
                    entry.connect("activate", send)
                    row.pack_start(rb, False, False, 0)
                    row.pack_start(entry, True, True, 0)
                col.pack_start(row, False, False, 0)
            if on_click:
                ev.connect("button-release-event",
                           lambda _w, e: on_click() if e.button == 1 else None)
            return ev

        def log_card(self, e, glyph):
            nid, live = e.get("id"), e.get("live")
            buttons = []
            if live and nid:
                for key, label in e.get("actions") or []:
                    if key != "default":
                        buttons.append((label, lambda k=key: self.invoke(nid, k)))
            has_default = live and nid and any(k == "default" for k, _ in e.get("actions") or [])
            app = (e.get("hints") or {}).get("x-kde-display-appname") or e.get("app") or "Unknown"
            return self.card(
                icon=e.get("icon") or (e.get("hints") or {}).get("image-path", ""),
                glyph=glyph, app=app, when=ago(e.get("time", 0)),
                summary=e.get("summary", ""), body=e.get("body", ""),
                unread_=e.get("time", 0) > self.seen_before, critical=e.get("urgency") == 2,
                buttons=buttons, on_close=lambda k=e["key"], n=nid, lv=live: self.remove(k, n, lv),
                on_click=(lambda: self.invoke(nid, "default")) if has_default else None)

        def refresh(self):
            data = load()
            entries = data["entries"]
            self.sig = (os.stat(HISTORY).st_mtime_ns if os.path.exists(HISTORY) else 0)

            # ── system ──
            box = self.lists["system"]
            self.clear_box(box)
            sys_entries = [e for e in reversed(entries) if not is_phone(e)]
            for e in sys_entries:
                box.pack_start(self.log_card(e, I_SYSTEM), False, False, 0)
            if not sys_entries:
                self.empty(box, "No notifications")
            n_sys = sum(1 for e in sys_entries if e.get("time", 0) > self.seen_before)
            self.tabs["system"].set_text(f"{I_SYSTEM}  System" + (f"  {n_sys}" if n_sys else ""))

            # ── phone ──
            box = self.lists["phone"]
            self.clear_box(box)
            live_texts = []
            n_live = 0
            devices = phone_devices()
            if not devices:
                self.section(box, "NO PHONE PAIRED — pair in kdeconnect-app")
            for dev, name, reachable in devices:
                if not reachable:
                    self.section(box, f"{name.upper()} — NOT CONNECTED")
                    continue
                notes = phone_notifications(dev)
                self.section(box, f"ON {name.upper()} NOW")
                if not notes:
                    self.empty(box, "Nothing in the phone's notification shade")
                for path, p in notes:
                    n_live += 1
                    live_texts.append((p.get("title", ""), p.get("text", "")))
                    buttons = [(a, lambda pa=path, a=a: self.phone_call(pa, "sendAction", a))
                               for a in p.get("actions", []) or []]
                    reply = ((lambda txt, pa=path: self.phone_call(pa, "sendReply", txt))
                             if p.get("replyId") else None)
                    box.pack_start(self.card(
                        icon=p.get("iconPath", "") if p.get("hasIcon") else "", glyph=I_PHONE,
                        app=p.get("appName", "Phone"), when=name,
                        summary=p.get("title", "") or p.get("ticker", ""), body=p.get("text", ""),
                        buttons=buttons, reply=reply,
                        on_close=((lambda pa=path: self.phone_call(pa, "dismiss"))
                                  if p.get("dismissable", True) else None),
                        close_tip="Dismiss on the phone"), False, False, 0)

            def on_phone_now(e):
                s, b = e.get("summary", ""), e.get("body", "")
                return any(t and x and t in s + b and x in s + b for t, x in live_texts)

            earlier = [e for e in reversed(entries) if is_phone(e) and not on_phone_now(e)]
            self.section(box, "EARLIER")
            for e in earlier:
                box.pack_start(self.log_card(e, I_PHONE), False, False, 0)
            if not earlier:
                self.empty(box, "Nothing earlier")
            n_ph = sum(1 for e in earlier if e.get("time", 0) > self.seen_before) + n_live
            self.tabs["phone"].set_text(f"{I_PHONE}  Phone" + (f"  {n_ph}" if n_ph else ""))
            self.phone_sig = self.phone_signature()
            for b in self.lists.values():
                b.show_all()

        def phone_signature(self):
            sig = []
            for dev, _n, reachable in phone_devices():
                sig.append((dev, reachable))
                if reachable:
                    r = kcall(f"/modules/kdeconnect/devices/{dev}/notifications", N_IFACE,
                              "activeNotifications")
                    sig.append(tuple(r[0]) if r else ())
            return sig

        def tick(self):
            if self.replying:            # don't rebuild under a half-typed reply
                return True
            mt = os.stat(HISTORY).st_mtime_ns if os.path.exists(HISTORY) else 0
            if mt != self.sig or self.phone_signature() != self.phone_sig:
                self.refresh()
            return True

        # ── actions ──
        def invoke(self, nid, key):
            # mako forwards it to the app, then closes the popup.
            run("makoctl", "invoke", "-n", str(nid), key)
            GLib.timeout_add(400, lambda: self.refresh() and False)

        def remove(self, key, nid, live):
            if live and nid:
                run("makoctl", "dismiss", "-n", str(nid))
            with Locked() as h:
                h.data["entries"] = [e for e in h.data["entries"] if e["key"] != key]
                h.dirty = True
            self.refresh()

        def phone_call(self, path, method, arg=None):
            kcall(path, N_IFACE + ".notification", method,
                  GLib.Variant("(s)", (arg,)) if arg is not None else None)
            self.replying = False
            GLib.timeout_add(600, lambda: self.refresh() and False)

        def on_clear(self, *_):
            phone_tab = self.nb.get_current_page() == 1
            with Locked() as h:
                gone = [e for e in h.data["entries"] if is_phone(e) == phone_tab]
                h.data["entries"] = [e for e in h.data["entries"] if is_phone(e) != phone_tab]
                h.dirty = True
            for e in gone:
                if e.get("live") and e.get("id"):
                    run("makoctl", "dismiss", "-n", str(e["id"]))
            self.refresh()

        def on_key(self, _w, event):
            if event.keyval == Gdk.KEY_Escape:
                Gtk.main_quit()
                return True
            return False

        def on_focus_out(self, *_):
            Gtk.main_quit()              # a popup: clicking elsewhere dismisses it
            return False

    provider = Gtk.CssProvider()
    provider.load_from_data(_rice_subst(CSS).encode())
    Gtk.StyleContext.add_provider_for_screen(
        Gdk.Screen.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
    win = Panel()
    win.show_all()
    GLibUnix.signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, lambda: Gtk.main_quit() or False)
    try:
        Gtk.main()
    finally:
        set_mode("panel-open", False)
    return 0


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "toggle"
    if cmd == "toggle":
        sys.exit(panel())
    elif cmd == "phone":
        sys.exit(panel("phone"))
    elif cmd == "bar":
        # SIGTERM us when Quickshell exits (bar() only prints on change, so an
        # idle one would never hit a broken pipe and outlive the restart)
        import ctypes
        ctypes.CDLL("libc.so.6", use_errno=True).prctl(1, signal.SIGTERM)   # PR_SET_PDEATHSIG
        try:
            bar()
        except (KeyboardInterrupt, BrokenPipeError):
            pass
    elif cmd == "serve":
        try:
            serve()
        except (KeyboardInterrupt, BrokenPipeError):
            set_mode("panel-open", False)
    elif cmd == "dnd":
        arg = sys.argv[2] if len(sys.argv) > 2 else "toggle"
        set_dnd({"on": True, "off": False}.get(arg, not dnd_on()))
    else:
        print(__doc__, file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
