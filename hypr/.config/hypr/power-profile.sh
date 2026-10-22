#!/bin/bash
# Bottom-bar power profile widget (power-profiles-daemon).
#
#   power-profile.sh status   one JSON line for the bar
#   power-profile.sh watch    a JSON line now and on every profile change
#                             (the bar's pill runs this; long-running)
#   power-profile.sh next     cycle power-saver -> balanced -> performance
#
# Talks to the daemon with busctl (~10 ms) rather than powerprofilesctl,
# which is a Python script (~200 ms per call). With the old poll, a click ran
# `next` (two powerprofilesctl calls, ~0.5 s) while the pill re-polled after
# 200 ms, read the OLD profile, and showed the new one only at the next 5 s
# poll. `watch` follows the daemon's PropertiesChanged instead, so the pill
# changes as soon as the profile does, whoever changed it.

BUS=org.freedesktop.UPower.PowerProfiles
OBJ=/org/freedesktop/UPower/PowerProfiles

get() {
    busctl --system get-property "$BUS" "$OBJ" "$BUS" ActiveProfile 2>/dev/null \
        | sed -n 's/^s "\(.*\)"$/\1/p'
}

set_profile() {
    busctl --system set-property "$BUS" "$OBJ" "$BUS" ActiveProfile s "$1"
}

status() {
    local cur icon label
    cur=$(get)
    case "$cur" in
        power-saver) icon="󰌪"; label="saver" ;;
        performance) icon="󰓅"; label="performance" ;;
        balanced)    icon="󰾅"; label="balanced" ;;
        *)           icon="?"; label="unknown"; cur="unknown" ;;
    esac
    printf '{"text":"%s  %s","class":"%s","tooltip":"Power profile: %s\\nClick to switch"}\n' \
        "$icon" "$label" "$cur" "$cur"
}

case "$1" in
    next)
        case "$(get)" in
            power-saver) set_profile balanced ;;
            balanced)    set_profile performance ;;
            *)           set_profile power-saver ;;
        esac
        ;;
    watch)
        # One process, exec'd, so it is the bar's direct child and dies with
        # it (PDEATHSIG too) — no orphaned monitor pipelines.
        exec /usr/bin/python3 -c '
import ctypes, signal, subprocess, sys
ctypes.CDLL(None).prctl(1, signal.SIGTERM)          # PR_SET_PDEATHSIG
from gi.repository import Gio, GLib
script, bus, obj = sys.argv[1:4]
def show(*_):
    out = subprocess.run([script, "status"], capture_output=True, text=True).stdout
    sys.stdout.write(out); sys.stdout.flush()
def changed(_c, _s, _p, _i, _sig, params):
    if "ActiveProfile" in params.unpack()[1]:
        show()
conn = Gio.bus_get_sync(Gio.BusType.SYSTEM)
conn.signal_subscribe(bus, "org.freedesktop.DBus.Properties", "PropertiesChanged",
                      obj, None, Gio.DBusSignalFlags.NONE, changed)
show()
signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
GLib.MainLoop().run()
' "$0" "$BUS" "$OBJ"
        ;;
    status|*)
        status
        ;;
esac
