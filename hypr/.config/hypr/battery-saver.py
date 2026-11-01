#!/usr/bin/python3
"""Low-battery mode: power saver + pause the animated wallpaper behind windows.

    battery-saver.py           the watcher (exec-once in hyprland.conf)
    battery-saver.py status    what it sees right now

"Low" = running on battery AND the charge is at or below LOW_PCT (rounded
the same way the bar's battery pill shows it). The watcher acts only when
that changes, so a power mode picked by hand in between is left alone:

  * becomes low (drained to 20 %, or unplugged while at <= 20 %)
      -> power profile "power-saver", and the flag file ~/.local/state/battery-saver/low
         exists; wallpaper-fullscreen.py sees it and also pauses the animated
         wallpaper whenever the active workspace has a tiled window on it;
         blur goes off if it is on (blur.sh lowbat on — not saved)
  * stops being low (plugged in, or charged above 20 %)
      -> power profile "balanced", flag removed (wallpaper plays again),
         blur back to the saved choice (Settings › Appearance)

At start-up (login, Hyprland restart) a low battery counts as "becoming low";
a leftover flag with the battery no longer low counts as "stopping" (the flag
lives in ~/.local/state, so this works after a reboot too), and starting
plugged in at <= 20 % with power-saver on switches to balanced.
UPower's PropertiesChanged drives it; a slow re-check catches anything missed.
"""

import fcntl
import os
import subprocess
import sys

from gi.repository import Gio, GLib

LOW_PCT = 20
RECHECK_S = 60

RUN = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
# In ~/.local/state, not $XDG_RUNTIME_DIR: it must outlive a reboot. When the
# battery dies in low mode, power-profiles-daemon keeps "power-saver" across
# the reboot, and the leftover flag is what tells the next start that low mode
# was on — so it switches back to balanced once the laptop is plugged in.
STATE = os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"), "battery-saver")
FLAG = f"{STATE}/low"
DEBUG = os.environ.get("BATTERY_SAVER_DEBUG") == "1"
BLUR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "blur.sh")

UPOWER = "org.freedesktop.UPower"
UPOWER_OBJ = "/org/freedesktop/UPower"
DISPLAY_OBJ = "/org/freedesktop/UPower/devices/DisplayDevice"
PPD = "org.freedesktop.UPower.PowerProfiles"
PPD_OBJ = "/org/freedesktop/UPower/PowerProfiles"


def log(*a):
    if DEBUG:
        print("[battery-saver]", *a, file=sys.stderr, flush=True)


class Watcher:
    def __init__(self):
        self.bus = Gio.bus_get_sync(Gio.BusType.SYSTEM)
        self.low = os.path.exists(FLAG)     # what we last acted on

    def prop(self, obj, iface, name):
        v = self.bus.call_sync(UPOWER, obj, "org.freedesktop.DBus.Properties", "Get",
                               GLib.Variant("(ss)", (iface, name)), GLib.VariantType("(v)"),
                               Gio.DBusCallFlags.NONE, 2000, None)
        return v.unpack()[0]

    def reading(self):
        on_battery = self.prop(UPOWER_OBJ, UPOWER, "OnBattery")
        pct = round(self.prop(DISPLAY_OBJ, f"{UPOWER}.Device", "Percentage"))
        return on_battery, pct

    def set_profile(self, name):
        try:
            self.bus.call_sync(PPD, PPD_OBJ, "org.freedesktop.DBus.Properties", "Set",
                               GLib.Variant("(ssv)", (PPD, "ActiveProfile", GLib.Variant("s", name))),
                               None, Gio.DBusCallFlags.NONE, 2000, None)
        except GLib.Error as e:
            log("set profile failed:", e.message)

    @staticmethod
    def blur(lowbat):
        subprocess.run([BLUR, "lowbat", lowbat], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    @staticmethod
    def notify(title, body):
        subprocess.Popen(["notify-send", "-a", "Battery", "-i", "battery-caution", title, body],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    def check(self, *_):
        try:
            on_battery, pct = self.reading()
        except GLib.Error as e:
            log("UPower read failed:", e.message)
            return True
        low = on_battery and pct <= LOW_PCT
        log(f"on_battery={on_battery} pct={pct} low={low} (was {self.low})")
        if low and not self.low:
            os.makedirs(STATE, exist_ok=True)
            open(FLAG, "w").close()
            self.set_profile("power-saver")
            self.blur("on")
            self.notify(f"Battery at {pct} %",
                        "Power saver on. The animated wallpaper pauses behind windows.")
        elif not low and self.low:
            try:
                os.remove(FLAG)
            except FileNotFoundError:
                pass
            self.set_profile("balanced")
            self.blur("off")
            why = "Plugged in" if not on_battery else f"Battery at {pct} %"
            self.notify("Battery saver off", f"{why}. Back to Balanced; the wallpaper plays again.")
        self.low = low
        return True                          # keep the GLib timeout alive

    def run(self):
        for obj in (UPOWER_OBJ, DISPLAY_OBJ):
            self.bus.signal_subscribe(UPOWER, "org.freedesktop.DBus.Properties", "PropertiesChanged",
                                      obj, None, Gio.DBusSignalFlags.NONE,
                                      lambda *_: GLib.idle_add(self.check_once))
        self.startup_plugged_low()
        self.check()
        GLib.timeout_add_seconds(RECHECK_S, self.check)
        GLib.MainLoop().run()

    def startup_plugged_low(self):
        """Logging in plugged in at <= 20 % counts as "plugged in while low":
        balanced. Something else can leave power-saver on before this starts
        (the login screen's GNOME power manager switches to it on a low
        battery — seen 2026-11-01 after the battery ran flat)."""
        try:
            on_battery, pct = self.reading()
            prof = self.bus.call_sync(PPD, PPD_OBJ, "org.freedesktop.DBus.Properties", "Get",
                                      GLib.Variant("(ss)", (PPD, "ActiveProfile")), GLib.VariantType("(v)"),
                                      Gio.DBusCallFlags.NONE, 2000, None).unpack()[0]
        except GLib.Error as e:
            log("startup read failed:", e.message)
            return
        if not on_battery and pct <= LOW_PCT and prof == "power-saver":
            log("plugged in at", pct, "% with power-saver on: balanced")
            self.set_profile("balanced")

    def check_once(self):
        self.check()
        return False


def main():
    if sys.argv[1:] == ["status"]:
        w = Watcher()
        on_battery, pct = w.reading()
        print(f"on battery: {on_battery}, charge: {pct} %, low: {on_battery and pct <= LOW_PCT}, "
              f"flag: {os.path.exists(FLAG)}")
        return 0
    lock = open(f"{RUN}/battery-saver.lock", "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        print("battery-saver: already running", file=sys.stderr)
        return 1
    Watcher().run()
    return 0


if __name__ == "__main__":
    sys.exit(main())
