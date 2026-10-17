#!/usr/bin/python3
"""Network panel — opened by clicking the Wi-Fi icon in the bar.

Two tabs, because nm-connection-editor only ever did half the job:

  Available   what is on the air right now — scan, connect, disconnect.
              This is the half that was missing.
  Saved       the stored profiles nm-connection-editor showed you: connect,
              forget, and add/edit, which hand off to the real editor.

WHY A CUSTOM PANEL, WHEN nm-applet IS ALREADY RUNNING

nm-applet's own menu can do all of this, but it hangs off the tray icon's
StatusNotifierItem, not the bar's `network` module. Clicking the module ran
`nm-connection-editor`, which by design only edits stored profiles and never
scans — hence "previous connections, but no way to join a new one". Keeping
one obvious click target and giving it both halves beats teaching the hands
that two different icons do two different halves of one job.

Deliberately a normal toplevel window, like accent-picker.py and
wallpaper-grid.py: layer surfaces on this setup have cost real time, and a
plain window gets Hyprland's focus handling for free. Its app_id comes from
GLib.set_prgname(), which the windowrules in hyprland.conf match on.

NO PASSPHRASE EVER REACHES argv
/proc is world-readable, so `nmcli ... password <secret>` would expose a
Wi-Fi passphrase to every local user for the lifetime of the call — and to
anything sampling `ps`. Secrets go to nmcli's stdin under `--ask` instead.

ENTERPRISE (802.1X) NETWORKS ARE HANDED OFF
Networks like eduroam are WPA-Enterprise: they need an EAP method, an
identity, sometimes a CA certificate. That is a whole form, not a password
box, so a first-time connection to one opens nm-connection-editor rather than
pretending a single entry field is enough. Once saved, they connect from
either tab like anything else.
"""

import fcntl
import os
import re
import signal
import subprocess
import threading

import gi

gi.require_version("Gtk", "3.0")
# Gdk must be pinned too, and BEFORE it is pulled in. Same landmine as
# accent-picker.py: importing Gdk in the same statement as Gtk resolves Gdk
# first, picks up 4.0 where it exists, and dies with "Requiring namespace
# 'Gdk' version '3.0', but '4.0' is already loaded".
gi.require_version("Gdk", "3.0")

# app_id comes from prgname on Wayland and the windowrules match on it, so it
# has to be set before any of Gtk/Gdk is imported — importing Gdk eagerly locks
# the app_id in first and the window comes up as GTK's argv[0] fallback.
from gi.repository import GLib  # noqa: E402

GLib.set_prgname("network-panel")

from gi.repository import Gdk, GObject, Gtk, Pango  # noqa: E402

ACCENT_FILE = os.path.expanduser("~/.config/hypr/theme/accent")

# Catppuccin Mocha, matching waybar/style.css. Only the accent is dynamic.
BASE, MANTLE, SURFACE0, SURFACE1 = "#1e1e2e", "#181825", "#313244", "#45475a"
TEXT, SUBTEXT, OVERLAY = "#cdd6f4", "#a6adc8", "#6c7086"
GREEN, RED, YELLOW = "#a6e3a1", "#f38ba8", "#f9e2af"

# Same glyph family as the bar's format-wifi, so signal strength reads the same
# in both places. JetBrainsMono Nerd Font.
SIGNAL_GLYPHS = ["\U000f092f", "\U000f091f", "\U000f0922", "\U000f0925", "\U000f0928"]

# Profiles the user never manages by hand. docker/podman create a bridge per
# network and NM stores one of these for each, which buried the three real
# Wi-Fi entries in nm-connection-editor's list.
HIDDEN_TYPES = {"bridge", "loopback", "tun", "veth"}

# NetworkManager device states (NMDeviceState) -> what a connecting row says,
# and how far along its progress line is. Polled from `nmcli dev show` twice a
# second while a connect / disconnect runs, so a slow join shows WHERE it is
# (a password check, DHCP, the captive-portal probe) instead of sitting still.
NM_STAGES = {
    30: ("starting", 0.05),
    40: ("preparing", 0.15),
    50: ("configuring", 0.30),
    60: ("authenticating", 0.45),
    70: ("getting an IP address", 0.65),
    80: ("checking connectivity", 0.85),
    90: ("finishing", 0.95),
    100: ("connected", 1.0),
    110: ("disconnecting", None),
}

RUNTIME = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
NOTIF_LOCK = os.path.join(RUNTIME, "notif-center.lock")
# mako/config: [mode=netpanel-open] invisible=1 — popups (top right, overlay
# layer) would sit on top of this dropdown, as they would on notif-center's.
MAKO_MODE = "netpanel-open"



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

def read_accent():
    """The live accent, read at RUNTIME rather than templated in.

    set-accent.sh keeps the current value in theme/accent, so reading it here
    means this file never joins the twelve-file template manifest: no snapshot,
    no --resync after editing it, and no chance of the render overwriting a
    later edit (the trap documented at length in set-accent.sh's header).
    """
    try:
        with open(ACCENT_FILE) as fh:
            hexval = fh.read().strip().lstrip("#")
        if re.fullmatch(r"[0-9a-fA-F]{6}", hexval):
            return "#" + hexval
    except OSError:
        pass
    return "#89b4fa"


ACCENT = read_accent()


def split_terse(row):
    r"""Split one `nmcli -t` row into fields.

    nmcli escapes a literal ':' inside a value as '\:', so a plain
    row.split(':') corrupts every BSSID (54\:F0\:B1\:...) and every
    TIMESTAMP-REAL (01\:59\:24 PM). Verified against this machine's output —
    not defensive coding.
    """
    fields, cur, esc = [], [], False
    for ch in row:
        if esc:
            cur.append(ch)
            esc = False
        elif ch == "\\":
            esc = True
        elif ch == ":":
            fields.append("".join(cur))
            cur = []
        else:
            cur.append(ch)
    fields.append("".join(cur))
    return fields


def nmcli(args, stdin_text=None, timeout=120):
    """Run nmcli and return (rc, stdout, stderr). Never raises."""
    try:
        proc = subprocess.run(
            ["nmcli", *args],
            capture_output=True,
            text=True,
            input=stdin_text,
            timeout=timeout,
        )
        return proc.returncode, proc.stdout, proc.stderr.strip()
    except subprocess.TimeoutExpired:
        return 124, "", "nmcli timed out"
    except FileNotFoundError:
        return 127, "", "nmcli not found"


def run_bg(work, done):
    """Run `work` off the main loop, deliver its result to `done` on it.

    Every nmcli call here can block for seconds — a rescan especially — and
    doing that on the GTK thread freezes the window mid-click.
    """

    def worker():
        try:
            result = work()
        except Exception as exc:  # noqa: BLE001 - surfaced in the status line
            result = exc
        GLib.idle_add(done, result)

    threading.Thread(target=worker, daemon=True).start()


def wifi_device():
    """The first managed wifi device, or None."""
    rc, out, _ = nmcli(["-t", "-f", "DEVICE,TYPE,STATE", "dev"])
    if rc != 0:
        return None
    for row in out.splitlines():
        parts = split_terse(row)
        if len(parts) >= 3 and parts[1] == "wifi":
            return parts[0]
    return None


def scan_aps(rescan):
    """Access points on the air, strongest-first, one row per SSID.

    The raw list has one row per BSSID, so a dual-band router shows up twice
    (2.4GHz and 5GHz) with different signal. Collapsing to the strongest per
    SSID is what makes this a list of *networks* rather than of radios.
    """
    rc, out, err = nmcli(
        [
            "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY,FREQ",
            "dev", "wifi", "list",
            "--rescan", "yes" if rescan else "no",
        ]
    )
    if rc != 0:
        raise RuntimeError(err or "scan failed")

    best = {}
    for row in out.splitlines():
        if not row.strip():
            continue
        parts = split_terse(row)
        if len(parts) < 5:
            continue
        in_use, ssid, signal, security, freq = parts[0], parts[1], parts[2], parts[3], parts[4]
        if not ssid:
            continue                      # hidden SSID: nothing to show or click
        try:
            signal = int(signal)
        except ValueError:
            signal = 0
        band = "5GHz" if freq and freq.split()[0].isdigit() and int(freq.split()[0]) > 4000 else "2.4GHz"
        entry = {
            "ssid": ssid,
            "signal": signal,
            "security": security.strip(),
            "band": band,
            "active": in_use.strip() == "*",
        }
        prev = best.get(ssid)
        # Keep the strongest radio, but never let it drop the active flag: you
        # can be joined to the weaker band of a network you also see stronger.
        if prev is None or signal > prev["signal"]:
            if prev and prev["active"]:
                entry["active"] = True
            best[ssid] = entry
        elif entry["active"]:
            prev["active"] = True

    return sorted(best.values(), key=lambda a: (not a["active"], -a["signal"]))


def saved_connections(wifi_only=False):
    """Stored profiles, most recently used first."""
    rc, out, err = nmcli(
        ["-t", "-f", "UUID,NAME,TYPE,AUTOCONNECT,TIMESTAMP-REAL,ACTIVE", "con", "show"]
    )
    if rc != 0:
        raise RuntimeError(err or "could not list saved connections")

    rows = []
    for row in out.splitlines():
        if not row.strip():
            continue
        parts = split_terse(row)
        if len(parts) < 6:
            continue
        uuid, name, ctype, autoconnect, last, active = parts[:6]
        short = ctype.replace("802-11-wireless", "wifi").replace("802-3-ethernet", "ethernet")
        if short in HIDDEN_TYPES:
            continue
        if wifi_only and short != "wifi":
            continue
        rows.append(
            {
                "uuid": uuid,
                "name": name,
                "type": short,
                "autoconnect": autoconnect == "yes",
                "last": "never" if last == "never" else last,
                "active": active == "yes",
            }
        )
    rows.sort(key=lambda c: (not c["active"], c["last"] == "never"))
    return rows


def saved_by_ssid():
    """SSID -> uuid, so the Available tab knows what it already has a key for."""
    try:
        return {c["name"]: c["uuid"] for c in saved_connections(wifi_only=True)}
    except RuntimeError:
        return {}


def short_date(stamp):
    """`Fri 18 Sep 2026 01:59:24 PM UTC` -> `18 Sep 2026`.

    The full nmcli timestamp does not fit a row and ellipsised into
    `last used Mon 14 Sep 2026 02:52:...`, which spends the width on the
    weekday and the seconds and then cuts off the part you were reading.
    """
    if stamp == "never":
        return "never"
    match = re.search(r"(\d{1,2} \w{3} \d{4})", stamp)
    return match.group(1) if match else stamp


def signal_glyph(signal):
    return SIGNAL_GLYPHS[min(4, max(0, signal * 5 // 101))]


def is_enterprise(security):
    return "802.1X" in security


def is_open(security):
    return security == "" or security == "--"


CSS = f"""
window, .panel {{ background: {BASE}; color: {TEXT}; }}
notebook header {{ background: {MANTLE}; border: none; }}
notebook header tab {{
    color: {OVERLAY}; padding: 8px 18px; border: none;
    background: transparent; font-weight: 600;
}}
notebook header tab:checked {{
    color: {ACCENT};
    box-shadow: inset 0 -2px 0 {ACCENT};
}}
notebook > stack {{ background: {BASE}; }}
list, row {{ background: transparent; }}
row {{ padding: 2px 4px; border-bottom: 1px solid {MANTLE}; }}
row:selected {{ background: {SURFACE0}; }}
.ssid {{ font-size: 11pt; color: {TEXT}; }}
.ssid-active {{ font-size: 11pt; color: {ACCENT}; font-weight: 700; }}
.meta {{ font-size: 9pt; color: {OVERLAY}; }}
.glyph {{ font-size: 14pt; color: {SUBTEXT}; }}
.glyph-active {{ font-size: 14pt; color: {ACCENT}; }}
.status {{ font-size: 9pt; color: {SUBTEXT}; padding: 6px 10px; background: {MANTLE}; }}
.status-err {{ color: {RED}; }}
.status-ok {{ color: {GREEN}; }}
.status-busy {{ color: {YELLOW}; }}
.meta-busy {{ font-size: 9pt; color: {ACCENT}; }}
row.pending {{ background: alpha({ACCENT}, 0.07); }}
progressbar trough {{ background: {SURFACE0}; min-height: 3px; border: none; border-radius: 2px; }}
progressbar progress {{ background: {ACCENT}; min-height: 3px; border: none; border-radius: 2px; }}
spinner {{ color: {ACCENT}; }}
button {{
    background: {SURFACE0}; color: {TEXT}; border: none;
    border-radius: 6px; padding: 5px 12px; font-size: 9pt;
}}
button:hover {{ background: {SURFACE1}; }}
button.suggested-action {{ background: {ACCENT}; color: {BASE}; font-weight: 700; }}
button.destructive-action {{ background: {RED}; color: {BASE}; }}
headerbar, .toolbar {{ background: {MANTLE}; padding: 8px; }}
entry {{
    background: {SURFACE0}; color: {TEXT}; border: none;
    border-radius: 6px; padding: 7px 10px;
}}
entry:focus {{ box-shadow: inset 0 0 0 2px {ACCENT}; }}
/* Yaru draws the switch with an ORANGE border, which is its brand colour and
   is nowhere in this palette. Setting only the background left that ring
   visible, so border and box-shadow have to be overridden too. */
switch {{ background: {SURFACE1}; border: 1px solid {SURFACE1}; box-shadow: none; }}
switch:checked {{ background: {ACCENT}; border: 1px solid {ACCENT}; box-shadow: none; }}
switch slider {{ background: {TEXT}; border: none; box-shadow: none; }}
switch:checked slider {{ background: {BASE}; }}
.dim {{ color: {OVERLAY}; font-size: 9pt; }}
"""


class PasswordDialog(Gtk.Dialog):
    """Ask for a Wi-Fi passphrase. Returns it only via .passphrase."""

    def __init__(self, parent, ssid):
        super().__init__(title="", transient_for=parent, modal=True)
        self.set_default_size(380, -1)
        self.passphrase = None

        box = self.get_content_area()
        box.set_spacing(10)
        box.set_border_width(16)

        label = Gtk.Label(xalign=0)
        label.set_markup(f"Passphrase for <b>{GLib.markup_escape_text(ssid)}</b>")
        box.add(label)

        self.entry = Gtk.Entry()
        self.entry.set_visibility(False)
        self.entry.set_input_purpose(Gtk.InputPurpose.PASSWORD)
        self.entry.set_activates_default(True)
        box.add(self.entry)

        show = Gtk.CheckButton(label="Show passphrase")
        show.get_style_context().add_class("dim")
        show.connect("toggled", lambda b: self.entry.set_visibility(b.get_active()))
        box.add(show)

        self.add_button("Cancel", Gtk.ResponseType.CANCEL)
        join = self.add_button("Join", Gtk.ResponseType.OK)
        join.get_style_context().add_class("suggested-action")
        self.set_default_response(Gtk.ResponseType.OK)
        self.show_all()

    def run_get(self):
        response = self.run()
        if response == Gtk.ResponseType.OK:
            self.passphrase = self.entry.get_text()
        self.destroy()
        return self.passphrase


class NetworkPanel(Gtk.Window):
    def __init__(self):
        super().__init__(title="Network")
        # Placed by hyprland.conf: a dropdown under the bar's Wi-Fi icon.
        self.set_default_size(420, 400)
        self.get_style_context().add_class("panel")
        # Two independent kinds of "busy". A scan used to block every button
        # behind one flag, so clicking Connect while the opening rescan ran
        # (several seconds) did NOTHING — the "slow, only says Scanning…"
        # panel. Scans and actions now run side by side.
        self.scanning = False
        self.refresh_queued = False
        self.pending = None        # the action running: {kind, ssid, uuid, name, since}
        self.anim = {}             # widgets of the row being animated
        self.anim_id = None
        self.frame = 0
        self.stage_frac = None     # progress-line target; None = pulse
        self.polling = False
        self.last_available = None
        self.last_saved = None
        self.device = None
        self.counts = {"aps": 0, "saved": 0}

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.add(outer)

        self.notebook = Gtk.Notebook()
        outer.pack_start(self.notebook, True, True, 0)

        self.notebook.append_page(self._build_available(), Gtk.Label(label="Available"))
        self.notebook.append_page(self._build_saved(), Gtk.Label(label="Saved"))

        self.status = Gtk.Label(xalign=0, label="")
        self.status.get_style_context().add_class("status")
        self.status.set_ellipsize(Pango.EllipsizeMode.END)
        outer.pack_end(self.status, False, False, 0)

        # Connected only now that self.status exists: switch-page also fires
        # while the pages are being appended, before there is a label to write.
        self.notebook.connect("switch-page", self.on_tab_switch)

        self.connect("key-press-event", self.on_key)
        self.connect("destroy", Gtk.main_quit)

        # Two-phase on purpose. NetworkManager ages entries out of its scan
        # cache, so the cached list can be down to the one or two strongest APs
        # — measured here: 7 networks cached, 2 left by the time the window
        # opened a couple of minutes later, which looks like a broken panel.
        # Render the cache first so the window is never blank, then scan for
        # real, once. `did_initial_rescan` keeps it to once: refresh_available
        # is also what every action calls when it finishes, and rescanning on
        # each of those would make every connect take seconds longer.
        self.did_initial_rescan = False
        self.refresh_available(rescan=False)
        self.refresh_saved()

    # ── tab 1: what is on the air ──────────────────────────────────────────
    def _build_available(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)

        bar = Gtk.Box(spacing=8)
        bar.get_style_context().add_class("toolbar")
        bar.set_border_width(8)

        self.wifi_switch = Gtk.Switch()
        self.wifi_switch.set_valign(Gtk.Align.CENTER)
        self.wifi_switch_handler = self.wifi_switch.connect("notify::active", self.on_wifi_toggled)
        bar.pack_start(Gtk.Label(label="Wi-Fi"), False, False, 0)
        bar.pack_start(self.wifi_switch, False, False, 0)

        self.rescan_btn = Gtk.Button(label="Rescan")
        self.rescan_btn.connect("clicked", lambda _b: self.refresh_available(rescan=True))
        bar.pack_end(self.rescan_btn, False, False, 0)
        self.scan_spinner = Gtk.Spinner()
        self.scan_spinner.set_no_show_all(True)
        bar.pack_end(self.scan_spinner, False, False, 0)

        box.pack_start(bar, False, False, 0)

        self.ap_list = Gtk.ListBox()
        self.ap_list.set_selection_mode(Gtk.SelectionMode.NONE)
        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.add(self.ap_list)
        box.pack_start(scroll, True, True, 0)
        return box

    # ── tab 2: what is stored (what the old click gave you) ────────────────
    def _build_saved(self):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)

        self.saved_list = Gtk.ListBox()
        self.saved_list.set_selection_mode(Gtk.SelectionMode.NONE)
        scroll = Gtk.ScrolledWindow()
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroll.add(self.saved_list)
        box.pack_start(scroll, True, True, 0)

        bar = Gtk.Box(spacing=8)
        bar.get_style_context().add_class("toolbar")
        bar.set_border_width(8)
        add = Gtk.Button(label="Add…")
        add.connect("clicked", lambda _b: self.open_editor(create=True))
        bar.pack_start(add, False, False, 0)
        hint = Gtk.Label(label="Add / Edit open the full connection editor", xalign=0)
        hint.get_style_context().add_class("dim")
        bar.pack_start(hint, True, True, 0)
        box.pack_end(bar, False, False, 0)
        return box

    # ── status line ────────────────────────────────────────────────────────
    def say(self, text, kind=""):
        ctx = self.status.get_style_context()
        for cls in ("status-err", "status-ok", "status-busy"):
            ctx.remove_class(cls)
        if kind:
            ctx.add_class(f"status-{kind}")
        self.status.set_text(text)

    def set_scanning(self, on, text=None):
        self.scanning = on
        self.rescan_btn.set_sensitive(not on)
        if on:
            self.scan_spinner.show()
            self.scan_spinner.start()
        else:
            self.scan_spinner.stop()
            self.scan_spinner.hide()
        if text and not self.pending:          # an action's text wins
            self.say(text, "busy")

    # ── refresh: available ─────────────────────────────────────────────────
    def refresh_available(self, rescan):
        if self.scanning:
            # Don't drop it: an action finishing mid-scan still wants a fresh
            # list (the scan in flight may predate the change).
            self.refresh_queued = True
            return
        self.set_scanning(True, "Scanning…" if rescan else "Reading networks…")

        def work():
            self.device = wifi_device()
            rc, out, _ = nmcli(["-t", "-f", "WIFI", "radio"])
            enabled = out.strip() == "enabled" if rc == 0 else False
            if not enabled:
                return {"enabled": False, "aps": [], "saved": {}}
            return {"enabled": True, "aps": scan_aps(rescan), "saved": saved_by_ssid()}

        run_bg(work, self.on_available)

    def on_available(self, result):
        self.set_scanning(False)
        self.last_available = result
        self.render_available(result)
        if self.refresh_queued:
            self.refresh_queued = False
            GLib.idle_add(lambda: self.refresh_available(rescan=False) and False)
            return
        if not isinstance(result, Exception) and result["enabled"] \
                and not self.did_initial_rescan:
            self.did_initial_rescan = True
            GLib.timeout_add(120, self._initial_rescan)

    def render_available(self, result):
        if self.notebook.get_current_page() == 0:
            self.anim.clear()            # its old widgets are about to go
        for child in self.ap_list.get_children():
            self.ap_list.remove(child)

        if isinstance(result, Exception):
            self.say(str(result), "err")
            self.ap_list.show_all()
            return

        # Block the handler: setting the switch programmatically would otherwise
        # fire notify::active and toggle the radio we are only reporting on.
        with GObject.signal_handler_block(self.wifi_switch, self.wifi_switch_handler):
            self.wifi_switch.set_active(result["enabled"])

        if not result["enabled"]:
            if not self.pending:
                self.say("Wi-Fi is off")
            self.ap_list.add(self._message_row("Wi-Fi is off — turn it on to scan."))
            self.ap_list.show_all()
            return

        aps, saved = result["aps"], result["saved"]
        if not aps:
            self.ap_list.add(self._message_row("No networks found. Try Rescan."))
        for ap in aps:
            self.ap_list.add(self._ap_row(ap, saved.get(ap["ssid"])))
        self.ap_list.show_all()
        self.counts["aps"] = len(aps)
        if not self.pending:
            self.show_counts()

    def _initial_rescan(self):
        self.refresh_available(rescan=True)
        return GLib.SOURCE_REMOVE

    def _message_row(self, text):
        row = Gtk.ListBoxRow()
        row.set_selectable(False)
        label = Gtk.Label(label=text, xalign=0)
        label.get_style_context().add_class("dim")
        # margins, not set_border_width: a Label is not a Container, and that
        # call raised whenever a list was empty ("No saved connections.").
        for side in ("top", "bottom", "start", "end"):
            getattr(label, f"set_margin_{side}")(14)
        row.add(label)
        return row

    def is_pending_row(self, ssid=None, uuid=None):
        """Is this row the network the running connect/disconnect is about?
        Only on the tab you are looking at, and the first match only — one
        row animates (on_tab_switch moves it)."""
        p = self.pending
        if not p or p["kind"] not in ("connect", "disconnect") or "glyph" in self.anim \
                or self.notebook.get_current_page() != 0:
            return False
        return bool((ssid and p.get("ssid") == ssid) or (uuid and p.get("uuid") == uuid))

    def _pending_parts(self, row, text, glyph=None):
        """Turn a row into the "working on it" version: tinted, the meta line
        replaced by the live stage, a progress line under it, a spinner (and
        Cancel while connecting) instead of the button. Widgets go in
        self.anim for tick() / on_stage() to drive."""
        row.get_style_context().add_class("pending")
        verb = "Connecting" if self.pending["kind"] == "connect" else "Disconnecting"
        meta = Gtk.Label(label=f"{verb}…", xalign=0)
        meta.get_style_context().add_class("meta-busy")
        meta.set_ellipsize(Pango.EllipsizeMode.END)
        bar = Gtk.ProgressBar()
        bar.set_pulse_step(0.12)
        bar.set_margin_top(5)
        if self.stage_frac is not None:
            bar.set_fraction(self.stage_frac)
        self.anim.update({"meta": meta, "bar": bar, "glyph": glyph or Gtk.Label()})
        spin = Gtk.Spinner()
        spin.start()
        spin.set_valign(Gtk.Align.CENTER)
        right = Gtk.Box(spacing=8)
        right.pack_end(spin, False, False, 0)
        if self.pending["kind"] == "connect" and self.device:
            cancel = Gtk.Button(label="Cancel")
            cancel.set_valign(Gtk.Align.CENTER)
            cancel.connect("clicked", lambda _b: self.do_cancel())
            right.pack_start(cancel, False, False, 0)
        return meta, bar, right

    def _ap_row(self, ap, uuid):
        row = Gtk.ListBoxRow()
        row.set_selectable(False)
        line = Gtk.Box(spacing=10)
        line.set_border_width(8)

        glyph = Gtk.Label(label=signal_glyph(ap["signal"]))
        pending = self.is_pending_row(ssid=ap["ssid"], uuid=uuid)
        glyph.get_style_context().add_class(
            "glyph-active" if ap["active"] or pending else "glyph")
        line.pack_start(glyph, False, False, 0)
        if pending:
            text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            name = Gtk.Label(label=ap["ssid"], xalign=0)
            name.get_style_context().add_class("ssid-active")
            name.set_ellipsize(Pango.EllipsizeMode.END)
            text.pack_start(name, False, False, 0)
            meta, bar, right = self._pending_parts(row, ap["ssid"], glyph)
            text.pack_start(meta, False, False, 0)
            text.pack_start(bar, False, False, 0)
            line.pack_start(text, True, True, 0)
            line.pack_end(right, False, False, 0)
            row.add(line)
            return row

        text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        name = Gtk.Label(label=ap["ssid"], xalign=0)
        name.get_style_context().add_class("ssid-active" if ap["active"] else "ssid")
        name.set_ellipsize(Pango.EllipsizeMode.END)
        text.pack_start(name, False, False, 0)

        bits = [f"{ap['signal']}%", ap["band"]]
        if ap["active"]:
            bits.append("connected")
        if is_open(ap["security"]):
            bits.append("open")
        elif is_enterprise(ap["security"]):
            bits.append("enterprise")
        else:
            bits.append(ap["security"])
        if uuid and not ap["active"]:
            bits.append("saved")
        meta = Gtk.Label(label="  ·  ".join(bits), xalign=0)
        meta.get_style_context().add_class("meta")
        meta.set_ellipsize(Pango.EllipsizeMode.END)
        text.pack_start(meta, False, False, 0)
        line.pack_start(text, True, True, 0)

        if ap["active"]:
            btn = Gtk.Button(label="Disconnect")
            btn.connect("clicked", lambda _b, a=ap: self.do_disconnect(a["ssid"]))
        else:
            btn = Gtk.Button(label="Connect")
            btn.get_style_context().add_class("suggested-action")
            btn.connect("clicked", lambda _b, a=ap, u=uuid: self.do_connect(a, u))
        btn.set_valign(Gtk.Align.CENTER)
        line.pack_end(btn, False, False, 0)

        row.add(line)
        return row

    # ── refresh: saved ─────────────────────────────────────────────────────
    def refresh_saved(self):
        run_bg(saved_connections, self.on_saved)

    def on_saved(self, result):
        self.last_saved = result
        self.render_saved(result)

    def render_saved(self, result):
        if self.notebook.get_current_page() == 1:
            self.anim.clear()
        for child in self.saved_list.get_children():
            self.saved_list.remove(child)
        if isinstance(result, Exception):
            self.saved_list.add(self._message_row(str(result)))
            self.saved_list.show_all()
            return
        if not result:
            self.saved_list.add(self._message_row("No saved connections."))
        for conn in result:
            self.saved_list.add(self._saved_row(conn))
        self.saved_list.show_all()
        self.counts["saved"] = len(result)
        if not self.pending:
            self.show_counts()

    def _saved_row(self, conn):
        row = Gtk.ListBoxRow()
        row.set_selectable(False)
        line = Gtk.Box(spacing=8)
        line.set_border_width(8)

        text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        name = Gtk.Label(label=conn["name"], xalign=0)
        name.get_style_context().add_class("ssid-active" if conn["active"] else "ssid")
        name.set_ellipsize(Pango.EllipsizeMode.END)
        text.pack_start(name, False, False, 0)

        # The row of the profile being brought up / down, when this is the tab
        # you are looking at (see is_pending_row).
        p = self.pending
        if p and p["kind"] in ("connect", "disconnect") and \
                (p.get("uuid") == conn["uuid"] or (not p.get("uuid") and p.get("ssid") == conn["name"])) \
                and self.notebook.get_current_page() == 1:
            meta, bar, right = self._pending_parts(row, conn["name"])
            text.pack_start(meta, False, False, 0)
            text.pack_start(bar, False, False, 0)
            line.pack_start(text, True, True, 0)
            line.pack_end(right, False, False, 0)
            row.add(line)
            return row

        bits = [conn["type"]]
        bits.append("connected" if conn["active"] else f"last used {short_date(conn['last'])}")
        if not conn["autoconnect"]:
            bits.append("manual")
        meta = Gtk.Label(label="  ·  ".join(bits), xalign=0)
        meta.get_style_context().add_class("meta")
        meta.set_ellipsize(Pango.EllipsizeMode.END)
        text.pack_start(meta, False, False, 0)
        line.pack_start(text, True, True, 0)

        if conn["active"]:
            updown = Gtk.Button(label="Disconnect")
            updown.connect("clicked", lambda _b, c=conn: self.do_conn_down(c))
        else:
            updown = Gtk.Button(label="Connect")
            updown.get_style_context().add_class("suggested-action")
            updown.connect("clicked", lambda _b, c=conn: self.do_conn_up(c))
        updown.set_valign(Gtk.Align.CENTER)
        line.pack_end(updown, False, False, 0)

        edit = Gtk.Button(label="Edit")
        edit.set_valign(Gtk.Align.CENTER)
        edit.connect("clicked", lambda _b, c=conn: self.open_editor(uuid=c["uuid"]))
        line.pack_end(edit, False, False, 0)

        forget = Gtk.Button(label="Forget")
        forget.get_style_context().add_class("destructive-action")
        forget.set_valign(Gtk.Align.CENTER)
        forget.connect("clicked", lambda _b, c=conn: self.do_forget(c))
        line.pack_end(forget, False, False, 0)

        row.add(line)
        return row

    # ── actions ────────────────────────────────────────────────────────────
    # ── the running action + its animation ──────────────────────────────────
    def begin(self, kind, text, ssid=None, uuid=None):
        """Start an action. False if one is already running (one at a time —
        two nmcli activations on one radio just cancel each other)."""
        if self.pending:
            return False
        self.pending = {"kind": kind, "ssid": ssid, "uuid": uuid, "text": text,
                        "since": GLib.get_monotonic_time()}
        self.stage_frac = 0.02 if kind == "connect" else None
        self.say(text, "busy")
        # Redraw the visible list from what it last showed, now with the
        # animated row.
        self.anim.clear()
        if self.notebook.get_current_page() == 0:
            if self.last_available is not None:
                self.render_available(self.last_available)
        elif self.last_saved is not None:
            self.render_saved(self.last_saved)
        if self.anim_id is None:
            self.anim_id = GLib.timeout_add(110, self.tick)
        return True

    def tick(self):
        if not self.pending:
            self.anim_id = None
            return GLib.SOURCE_REMOVE
        self.frame += 1
        glyph = self.anim.get("glyph")
        if glyph is not None and self.pending["kind"] in ("connect", "disconnect"):
            # the Wi-Fi bars filling up (emptying, for a disconnect)
            i = (self.frame // 2) % len(SIGNAL_GLYPHS)
            if self.pending["kind"] == "disconnect":
                i = len(SIGNAL_GLYPHS) - 1 - i
            glyph.set_text(SIGNAL_GLYPHS[i])
        bar = self.anim.get("bar")
        if bar is not None:
            if self.stage_frac is None:
                bar.pulse()
            else:
                cur = bar.get_fraction()
                bar.set_fraction(cur + (self.stage_frac - cur) * 0.25)
        if self.frame % 8 == 0:                       # ~1 s: elapsed time
            secs = (GLib.get_monotonic_time() - self.pending["since"]) // 1_000_000
            if secs >= 2:
                self.say(f"{self.pending['text']}  {secs}s", "busy")
        if self.frame % 4 == 0:                       # ~0.5 s: where is NM at?
            self.poll_stage()
        return GLib.SOURCE_CONTINUE

    def poll_stage(self):
        if self.polling or not self.device or not self.pending \
                or self.pending["kind"] not in ("connect", "disconnect"):
            return
        self.polling = True
        dev = self.device
        run_bg(lambda: nmcli(["-t", "-f", "GENERAL.STATE", "dev", "show", dev], timeout=5),
               self.on_stage)

    def on_stage(self, result):
        self.polling = False
        if not self.pending or isinstance(result, Exception) or result[0] != 0:
            return
        m = re.search(r"GENERAL\.STATE:(\d+)", result[1])
        if not m:
            return
        code = int(m.group(1))
        verb = "Connecting" if self.pending["kind"] == "connect" else "Disconnecting"
        if self.pending["kind"] == "connect" and code in NM_STAGES:
            stage, frac = NM_STAGES[code]
            self.stage_frac = frac
        elif self.pending["kind"] == "disconnect":
            stage, self.stage_frac = "disconnecting", None
        else:
            return
        meta = self.anim.get("meta")
        if meta is not None:
            meta.set_text(f"{verb}  ·  {stage}…")

    def after_action(self, result, ok_text):
        self.pending = None
        self.anim.clear()
        self.stage_frac = None
        if isinstance(result, Exception):
            self.say(str(result), "err")
        elif result[0] != 0:
            self.say(result[1] or "failed", "err")
        else:
            self.say(ok_text, "ok")
        self.refresh_available(rescan=False)
        self.refresh_saved()

    def do_cancel(self):
        """Abort a join that is taking too long: disconnecting the device
        stops the activation; the pending nmcli then returns with an error."""
        if self.device:
            self.say("Cancelling…", "busy")
            run_bg(lambda: nmcli(["dev", "disconnect", self.device], timeout=15), lambda _r: None)

    def do_connect(self, ap, uuid):
        if self.pending:
            return
        ssid, security = ap["ssid"], ap["security"]

        if uuid:                                  # already have a profile + key
            self.begin("connect", f"Connecting to {ssid}…", ssid=ssid, uuid=uuid)
            run_bg(
                lambda: nmcli(["con", "up", "uuid", uuid])[0:3:2],
                lambda r: self.after_action(r, f"Connected to {ssid}"),
            )
            return

        if is_enterprise(security):
            # A form, not a password box — see the module docstring.
            self.say("Enterprise network: opening the editor to set it up.", "busy")
            self.open_editor(create=True)
            return

        passphrase = None
        if not is_open(security):
            passphrase = PasswordDialog(self, ssid).run_get()
            if passphrase is None:
                self.say("Cancelled")
                return

        self.begin("connect", f"Connecting to {ssid}…", ssid=ssid)

        def work():
            if passphrase is None:
                rc, _out, err = nmcli(["dev", "wifi", "connect", ssid])
            else:
                # --ask + stdin, never argv: see the module docstring.
                rc, _out, err = nmcli(
                    ["--ask", "dev", "wifi", "connect", ssid],
                    stdin_text=passphrase + "\n",
                )
            return rc, err

        run_bg(work, lambda r: self.after_action(r, f"Connected to {ssid}"))

    def do_disconnect(self, ssid=None):
        if self.pending or not self.device:
            return
        self.begin("disconnect", f"Disconnecting from {ssid}…" if ssid else "Disconnecting…",
                   ssid=ssid)
        run_bg(
            lambda: nmcli(["dev", "disconnect", self.device])[0:3:2],
            lambda r: self.after_action(r, "Disconnected"),
        )

    def do_conn_up(self, conn):
        if self.pending:
            return
        self.begin("connect", f"Connecting to {conn['name']}…", ssid=conn["name"],
                   uuid=conn["uuid"])
        run_bg(
            lambda: nmcli(["con", "up", "uuid", conn["uuid"]])[0:3:2],
            lambda r: self.after_action(r, f"Connected to {conn['name']}"),
        )

    def do_conn_down(self, conn):
        if self.pending:
            return
        self.begin("disconnect", f"Disconnecting {conn['name']}…", ssid=conn["name"],
                   uuid=conn["uuid"])
        run_bg(
            lambda: nmcli(["con", "down", "uuid", conn["uuid"]])[0:3:2],
            lambda r: self.after_action(r, f"Disconnected {conn['name']}"),
        )

    def do_forget(self, conn):
        if self.pending:
            return
        dialog = Gtk.MessageDialog(
            transient_for=self,
            modal=True,
            message_type=Gtk.MessageType.QUESTION,
            buttons=Gtk.ButtonsType.OK_CANCEL,
            text=f"Forget “{conn['name']}”?",
        )
        dialog.format_secondary_text("The stored passphrase is deleted too. This cannot be undone.")
        confirmed = dialog.run() == Gtk.ResponseType.OK
        dialog.destroy()
        if not confirmed:
            return
        self.begin("forget", f"Forgetting {conn['name']}…")
        run_bg(
            lambda: nmcli(["con", "delete", "uuid", conn["uuid"]])[0:3:2],
            lambda r: self.after_action(r, f"Forgot {conn['name']}"),
        )

    def on_wifi_toggled(self, switch, _param):
        if self.pending:
            return
        want = switch.get_active()
        self.begin("radio", "Turning Wi-Fi " + ("on…" if want else "off…"))
        run_bg(
            lambda: nmcli(["radio", "wifi", "on" if want else "off"])[0:3:2],
            lambda r: self.after_action(r, "Wi-Fi " + ("on" if want else "off")),
        )

    def open_editor(self, uuid=None, create=False):
        """Hand off to nm-connection-editor — the thing the click used to do.

        Everything it does well (per-type forms, 802.1X, IPv4/IPv6, routes) is
        a large amount of UI that would be worse if reimplemented here.
        """
        argv = ["nm-connection-editor"]
        if create:
            argv += ["--create", "--type", "802-11-wireless"]
        elif uuid:
            argv += ["--edit", uuid]
        try:
            subprocess.Popen(argv, start_new_session=True)
        except FileNotFoundError:
            self.say("nm-connection-editor is not installed", "err")

    def show_counts(self, index=None):
        """Write the count for the tab you can actually see.

        One status line serves both tabs, so whoever finished last must not
        write its OWN number: an Available refresh completing while you read
        the Saved tab would leave "8 networks" under a list of saved profiles.
        It reports on the visible tab instead, whichever list just reloaded.

        Note this must always write something. An earlier version skipped the
        write when the finishing tab was not visible, which left the "Scanning…"
        busy text stuck on screen forever — set_busy(False) does not clear it.
        """
        if index is None:
            index = self.notebook.get_current_page()
        if index == 0:
            n = self.counts["aps"]
            self.say(f"{n} network{'s' if n != 1 else ''}")
        else:
            n = self.counts["saved"]
            self.say(f"{n} saved connection{'s' if n != 1 else ''}")

    def on_tab_switch(self, _notebook, _page, index):
        if self.pending:
            # move the animation to the tab you are now looking at (idle: during
            # switch-page get_current_page() still answers the OLD tab)
            result, render = (self.last_available, self.render_available) if index == 0 \
                else (self.last_saved, self.render_saved)
            if result is not None:
                GLib.idle_add(lambda: render(result) and False)
            return
        self.show_counts(index=index)

    def on_key(self, _widget, event):
        if event.keyval in (Gdk.KEY_Escape, Gdk.KEY_q):
            Gtk.main_quit()
            return True
        if event.keyval == Gdk.KEY_F5:
            self.refresh_available(rescan=True)
            return True
        return False


LOCK = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "network-panel.lock")


def toggle_or_claim():
    """One panel only: clicking the Wi-Fi icon while it is open closes it.

    Every click used to start another copy, so a second click stacked a
    duplicate panel instead of dismissing the first. Hold an flock for our
    lifetime; if another launch already holds it, signal that one to close
    and report True so this launch exits. A lock rather than `pgrep -f`, which
    matches any shell that merely mentions the name (landmine in
    dock-toggle.sh). The fd is opened O_CLOEXEC (Python's default), so
    nm-connection-editor started from here never inherits the lock.
    """
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
    toggle_or_claim.fd = fd            # keep it open (and locked) until exit
    return False


def close_notif_center():
    """The bell's panel drops down in the same top-right corner: close it, so
    the two never stack (notif-center.py does the same for this one)."""
    try:
        fd = os.open(NOTIF_LOCK, os.O_RDWR)
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


def set_mako_mode(on):
    subprocess.run(["makoctl", "mode", "-a" if on else "-r", MAKO_MODE],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def main():
    if toggle_or_claim():
        return
    close_notif_center()
    # SIGTERM = closed by a second click; quit through GTK, not mid-callback.
    GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, Gtk.main_quit)
    provider = Gtk.CssProvider()
    provider.load_from_data(_rice_subst(CSS).encode())
    Gtk.StyleContext.add_provider_for_screen(
        Gdk.Screen.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
    )
    win = NetworkPanel()
    win.show_all()
    # The Wi-Fi switch is the first focusable widget, so it takes focus on open
    # and a stray Space turns the radio off. Start with nothing focused.
    win.set_focus(None)
    set_mako_mode(True)
    try:
        Gtk.main()
    finally:
        set_mako_mode(False)


if __name__ == "__main__":
    main()
