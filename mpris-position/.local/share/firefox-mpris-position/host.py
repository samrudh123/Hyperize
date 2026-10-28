#!/usr/bin/python3
"""Native-messaging host for the mpris-position extension: one MPRIS player
PER FIREFOX TAB that plays YouTube / YouTube Music.

Firefox itself publishes ONE MPRIS player (firefox.instance_1_<pid>) for
whichever tab it last started — with two YouTube tabs playing, the bar showed
one of them and there was no way to see or reach the other. This host is
started by the extension's background page (runtime.connectNative, kept open
while Firefox runs) and gets the extension's list of media tabs. Each becomes
its own player:

    org.mpris.MediaPlayer2.firefox.tab_<tabId>     (playerctl: firefox.tab_<id>)

so playerctl -l, the bar and the media menu (media-menu.py) see every tab.
Controls (play/pause/seek/next/prev) go back to that tab's content script;
Raise() switches Firefox to the tab and focuses its window (hyprctl).

The tab the bar should show ("current": the focused Firefox window's tab if
it has media, else the last one you were on that has) is written to
$XDG_RUNTIME_DIR/firefox-tabs.current for now-playing.py, which then hides
Firefox's own player and the other tabs (they stay in the menu).

Zen Browser runs the same extension and host (Zen reads the same
~/.mozilla/native-messaging-hosts): there everything is "zen" instead —
zen.tab_<id>, zen-tabs.current, window class zen.

Registered by ~/.mozilla/native-messaging-hosts/firefox_tabs.json. Exits
when Firefox closes (stdin EOF); the players go with it. Log:
~/.local/state/firefox-tabs/host.log.
"""
import json
import os
import struct
import subprocess
import sys
import threading
import time

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

MPRIS_PATH = "/org/mpris/MediaPlayer2"
ROOT_IFACE = "org.mpris.MediaPlayer2"
PLAYER_IFACE = "org.mpris.MediaPlayer2.Player"
RT = os.environ.get("XDG_RUNTIME_DIR", "/tmp")


def _browser():
    """"zen" when Zen Browser started us (same extension, same host), else
    "firefox". Names the players (zen.tab_<id>), the current-tab file and
    the window class, so both browsers can run side by side."""
    pid = os.getppid()
    for _ in range(6):
        try:
            with open(f"/proc/{pid}/comm") as f:
                if f.read().strip().startswith("zen"):
                    return "zen"
            with open(f"/proc/{pid}/stat") as f:
                pid = int(f.read().rsplit(")", 1)[1].split()[1])
        except (OSError, ValueError, IndexError):
            break
        if pid <= 1:
            break
    return "firefox"


BROWSER = os.environ.get("FIREFOX_TABS_BROWSER") or _browser()
BROWSER_NAME = {"zen": "Zen"}.get(BROWSER, "Firefox")
CURRENT = os.path.join(RT, f"{BROWSER}-tabs.current")
LOG = os.path.expanduser("~/.local/state/firefox-tabs/host.log")
SEEK_JUMP = 1.5         # s off the expected position = a seek → Seeked signal

MPRIS_XML = """
<node>
  <interface name="org.mpris.MediaPlayer2">
    <method name="Raise"/>
    <method name="Quit"/>
    <property name="CanQuit" type="b" access="read"/>
    <property name="CanRaise" type="b" access="read"/>
    <property name="HasTrackList" type="b" access="read"/>
    <property name="Identity" type="s" access="read"/>
    <property name="DesktopEntry" type="s" access="read"/>
    <property name="SupportedUriSchemes" type="as" access="read"/>
    <property name="SupportedMimeTypes" type="as" access="read"/>
  </interface>
  <interface name="org.mpris.MediaPlayer2.Player">
    <method name="Next"/>
    <method name="Previous"/>
    <method name="Pause"/>
    <method name="PlayPause"/>
    <method name="Stop"/>
    <method name="Play"/>
    <method name="Seek"><arg direction="in" name="Offset" type="x"/></method>
    <method name="SetPosition">
      <arg direction="in" name="TrackId" type="o"/>
      <arg direction="in" name="Position" type="x"/>
    </method>
    <method name="OpenUri"><arg direction="in" name="Uri" type="s"/></method>
    <signal name="Seeked"><arg name="Position" type="x"/></signal>
    <property name="PlaybackStatus" type="s" access="read"/>
    <property name="Rate" type="d" access="read"/>
    <property name="Metadata" type="a{sv}" access="read"/>
    <property name="Volume" type="d" access="read"/>
    <property name="Position" type="x" access="read"/>
    <property name="MinimumRate" type="d" access="read"/>
    <property name="MaximumRate" type="d" access="read"/>
    <property name="CanGoNext" type="b" access="read"/>
    <property name="CanGoPrevious" type="b" access="read"/>
    <property name="CanPlay" type="b" access="read"/>
    <property name="CanPause" type="b" access="read"/>
    <property name="CanSeek" type="b" access="read"/>
    <property name="CanControl" type="b" access="read"/>
    <property name="Shuffle" type="b" access="readwrite"/>
    <property name="LoopStatus" type="s" access="readwrite"/>
  </interface>
</node>
"""
IFACES = Gio.DBusNodeInfo.new_for_xml(MPRIS_XML).interfaces


def log(*a):
    try:
        os.makedirs(os.path.dirname(LOG), exist_ok=True)
        with open(LOG, "a") as f:
            f.write(time.strftime("%F %T ") + " ".join(str(x) for x in a) + "\n")
    except OSError:
        pass


# ── native messaging (stdin/stdout, 4-byte length prefix) ──────────────────
_out_lock = threading.Lock()


def send(obj):
    if os.environ.get("FIREFOX_TABS_DEBUG"):
        log("->", obj)
    data = json.dumps(obj).encode()
    with _out_lock:
        sys.stdout.buffer.write(struct.pack("@I", len(data)) + data)
        sys.stdout.buffer.flush()


def reader():
    while True:
        raw = sys.stdin.buffer.read(4)
        if len(raw) < 4:
            GLib.idle_add(quit_)
            return
        msg = json.loads(sys.stdin.buffer.read(struct.unpack("@I", raw)[0]))
        GLib.idle_add(apply, msg)


# ── one MPRIS player per tab ───────────────────────────────────────────────
class TabPlayer:
    def __init__(self, tab):
        self.tab = tab
        self.name = f"{BROWSER}.tab_{tab}"
        self.s = {}                       # last state from the extension
        self.at = time.monotonic()        # when s["position"] was true
        # Its own connection: the MPRIS object path is fixed, so two players
        # can't share one connection.
        addr = Gio.dbus_address_get_for_bus_sync(Gio.BusType.SESSION, None)
        self.conn = Gio.DBusConnection.new_for_address_sync(
            addr, Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT
            | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION, None, None)
        for iface in IFACES:
            self.conn.register_object_with_closures2(MPRIS_PATH, iface, self.on_call, self.on_get,
                                                     self.on_set)
        self.owner = 0

    def publish(self):
        if not self.owner:
            self.owner = Gio.bus_own_name_on_connection(
                self.conn, "org.mpris.MediaPlayer2." + self.name,
                Gio.BusNameOwnerFlags.NONE, None, None)

    def close(self):
        if self.owner:
            Gio.bus_unown_name(self.owner)
            self.owner = 0
        try:
            self.conn.close_sync(None)
        except GLib.Error:
            pass

    # position, extrapolated while playing
    def position(self):
        p = self.s.get("position", 0.0)
        if self.s.get("playing") and not self.s.get("stalled"):
            p += (time.monotonic() - self.at) * self.s.get("rate", 1.0)
        d = self.s.get("duration", 0.0)
        return int(max(0.0, min(p, d) if d > 0 else p) * 1_000_000)

    def trackid(self):
        return f"/org/mpris/MediaPlayer2/{BROWSER}/tab_{self.tab}"

    def metadata(self):
        s = self.s
        md = {"mpris:trackid": GLib.Variant("o", self.trackid())}
        if s.get("duration", 0) > 0:
            md["mpris:length"] = GLib.Variant("x", int(s["duration"] * 1_000_000))
        md["xesam:title"] = GLib.Variant("s", s.get("title") or "")
        if s.get("artist"):
            md["xesam:artist"] = GLib.Variant("as", [s["artist"]])
        if s.get("album"):
            md["xesam:album"] = GLib.Variant("s", s["album"])
        if s.get("art"):
            md["mpris:artUrl"] = GLib.Variant("s", s["art"])
        if s.get("url"):
            md["xesam:url"] = GLib.Variant("s", s["url"])
        return md

    def props(self, iface):
        s = self.s
        if iface == ROOT_IFACE:
            return {"CanQuit": GLib.Variant("b", False), "CanRaise": GLib.Variant("b", True),
                    "HasTrackList": GLib.Variant("b", False),
                    "Identity": GLib.Variant("s", BROWSER_NAME),
                    "DesktopEntry": GLib.Variant("s", BROWSER),
                    "SupportedUriSchemes": GLib.Variant("as", []),
                    "SupportedMimeTypes": GLib.Variant("as", [])}
        rate = s.get("rate", 1.0)
        return {"PlaybackStatus": GLib.Variant("s", "Playing" if s.get("playing") else "Paused"),
                "Rate": GLib.Variant("d", rate), "MinimumRate": GLib.Variant("d", 0.25),
                "MaximumRate": GLib.Variant("d", 2.0), "Volume": GLib.Variant("d", 1.0),
                "Metadata": GLib.Variant("a{sv}", self.metadata()),
                "Position": GLib.Variant("x", self.position()),
                "CanGoNext": GLib.Variant("b", bool(s.get("canNext"))),
                "CanGoPrevious": GLib.Variant("b", bool(s.get("canPrev"))),
                "CanPlay": GLib.Variant("b", True), "CanPause": GLib.Variant("b", True),
                "CanSeek": GLib.Variant("b", s.get("duration", 0) > 0),
                "CanControl": GLib.Variant("b", True),
                # the page's shuffle / repeat (tab.js modes()); left out
                # where it has none, so the bar hides that button
                **({"Shuffle": GLib.Variant("b", s["shuffle"])}
                   if isinstance(s.get("shuffle"), bool) else {}),
                **({"LoopStatus": GLib.Variant("s", s["loop"])}
                   if s.get("loop") in ("None", "Playlist", "Track") else {})}

    def on_get(self, _conn, _sender, _path, iface, prop):
        return self.props(iface).get(prop)

    def on_set(self, _conn, _sender, _path, iface, prop, value):
        """Shuffle / LoopStatus (the bar's ⇄ ⟲ through playerctl): shown at
        once, then tab.js clicks YouTube's own buttons and reports back."""
        if iface != PLAYER_IFACE:
            return False
        v = value.unpack()
        if prop == "Shuffle" and isinstance(self.s.get("shuffle"), bool):
            change, cmd = {"shuffle": bool(v)}, {"cmd": "shuffle", "value": bool(v)}
        elif prop == "LoopStatus" and self.s.get("loop") and v in ("None", "Playlist", "Track"):
            change, cmd = {"loop": v}, {"cmd": "loop", "value": v}
        else:
            return False
        before = self.snapshot()
        self.s = dict(self.s, **change)
        send(dict(cmd, tab=self.tab))
        self.emit_changed(before)
        return True

    def snapshot(self):
        return {(i, k): v for i in (ROOT_IFACE, PLAYER_IFACE)
                for k, v in self.props(i).items() if k != "Position"}

    def emit_changed(self, before):
        for iface in (ROOT_IFACE, PLAYER_IFACE):
            now = self.props(iface)
            now.pop("Position", None)            # never signalled (MPRIS spec)
            changed = {k: v for k, v in now.items() if before.get((iface, k)) != v}
            if changed:
                self.conn.emit_signal(None, MPRIS_PATH, "org.freedesktop.DBus.Properties",
                                      "PropertiesChanged",
                                      GLib.Variant("(sa{sv}as)", (iface, changed, [])))

    def seeked(self):
        self.conn.emit_signal(None, MPRIS_PATH, PLAYER_IFACE, "Seeked",
                              GLib.Variant("(x)", (self.position(),)))

    def update(self, state):
        before = self.snapshot()
        expected = self.position() / 1e6
        jumped = (self.s.get("url") == state.get("url") and state.get("duration", 0) > 0
                  and abs(state.get("position", 0) - expected) > SEEK_JUMP)
        self.s, self.at = state, time.monotonic()
        self.publish()
        self.emit_changed(before)
        if jumped:
            self.seeked()

    def on_call(self, _conn, _sender, _path, iface, method, params, invocation):
        before = self.snapshot()
        if iface == ROOT_IFACE and method == "Raise":
            focus(self.tab)
        elif iface == PLAYER_IFACE:
            playing = self.s.get("playing")
            if method in ("PlayPause", "Play", "Pause", "Stop"):
                want = {"PlayPause": not playing, "Play": True}.get(method, False)
                if want != playing:
                    # optimistic, the content script confirms
                    self.s = dict(self.s, position=self.position() / 1e6, playing=want)
                    self.at = time.monotonic()
                    send({"cmd": "play" if want else "pause", "tab": self.tab})
            elif method in ("Next", "Previous"):
                send({"cmd": "next" if method == "Next" else "prev", "tab": self.tab})
            elif method in ("Seek", "SetPosition"):
                if method == "Seek":
                    target = self.position() + params.unpack()[0]
                else:
                    trackid, target = params.unpack()
                    if trackid != self.trackid():
                        target = None
                if target is not None and self.s.get("duration", 0) > 0:
                    target = max(0, min(target, int(self.s["duration"] * 1e6) - 500_000))
                    self.s = dict(self.s, position=target / 1e6, stalled=True)   # until the page has it
                    self.at = time.monotonic()
                    send({"cmd": "seek", "tab": self.tab, "position": target / 1e6})
                    self.seeked()
        invocation.return_value(None)
        self.emit_changed(before)


players = {}            # tab id -> TabPlayer
loop = GLib.MainLoop()
_titles = {}            # tab id -> tab title (for finding its window)


def focus(tab):
    """Switch Firefox to `tab`, then bring its window forward. Firefox can't
    raise itself on Wayland, so find the window by its title (the active
    tab's) once Firefox has switched, and let Hyprland focus it."""
    send({"cmd": "focus", "tab": tab})
    title = _titles.get(tab, "")
    if os.environ.get("FIREFOX_TABS_NO_WM"):     # tests: a headless Firefox has no window
        return

    def raise_window(tries=[0]):
        tries[0] += 1
        try:
            clients = json.loads(subprocess.run(["hyprctl", "clients", "-j"], capture_output=True,
                                                text=True, timeout=2).stdout)
        except (ValueError, subprocess.SubprocessError, OSError):
            return False
        ff = [c for c in clients if c.get("class") == BROWSER]
        hit = [c for c in ff if title and c.get("title", "").startswith(title)]
        if hit or tries[0] >= 6:
            # no title match after 0.6 s: only if there's no doubt which window
            pick = hit[0] if hit else (ff[0] if len(ff) == 1 else None)
            if pick:
                subprocess.run(["hyprctl", "dispatch", "focuswindow", f"address:{pick['address']}"],
                               capture_output=True, timeout=2)
            return False
        return True                              # title not there yet: retry
    GLib.timeout_add(100, raise_window)


def nudge_bars():
    subprocess.run(["pkill", "-USR1", "-f",
                    r"^/usr/bin/python3 .*/now-playing\.py( --cffi)?( --scope [a-z]+)?$"],
                   capture_output=True)


_current = [None]


def set_current(tab):
    name = f"{BROWSER}.tab_{tab}" if tab in players else ""
    if name == _current[0]:
        return
    _current[0] = name
    try:
        if name:
            with open(CURRENT + ".new", "w") as f:
                f.write(name + "\n")
            os.replace(CURRENT + ".new", CURRENT)
        elif os.path.exists(CURRENT):
            os.remove(CURRENT)
    except OSError:
        pass
    nudge_bars()


def apply(msg):
    if msg.get("type") != "tabs":
        return False
    if os.environ.get("FIREFOX_TABS_DEBUG"):
        log("<-", msg.get("current"), [(t["tab"], t.get("playing"), round(t.get("position", 0), 1))
                                        for t in msg.get("tabs", [])])
    seen = set()
    for t in msg.get("tabs", []):
        tab = int(t["tab"])
        seen.add(tab)
        _titles[tab] = t.get("tabTitle", "")
        if tab not in players:
            players[tab] = TabPlayer(tab)
            log("tab", tab, "appears:", t.get("title"))
        players[tab].update(t)
    for tab in list(players):
        if tab not in seen:
            log("tab", tab, "gone")
            players.pop(tab).close()
            _titles.pop(tab, None)
    set_current(msg.get("current"))
    return False


def quit_():
    for p in players.values():
        p.close()
    try:
        os.remove(CURRENT)
    except OSError:
        pass
    loop.quit()
    return False


if __name__ == "__main__":
    log("start", os.getpid())
    threading.Thread(target=reader, daemon=True).start()
    try:
        loop.run()
    finally:
        try:
            os.remove(CURRENT)
        except OSError:
            pass
        log("exit")
