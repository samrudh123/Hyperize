// Idle timeouts (screen off / sleep), separate for battery and plugged in —
// shared by Settings › Power and the power panel (PowerPopup). The values
// live in hypr/idle.json; hypr/idle.sh saves a change, regenerates
// hypridle.conf and restarts hypridle. Seconds, 0 = never.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

Singleton {
    id: root

    readonly property var screenOpts: [60, 120, 300, 600, 900, 1800, 0]
    readonly property var screenLabels: ["1m", "2m", "5m", "10m", "15m", "30m", "Never"]
    readonly property var sleepOpts: [300, 900, 1800, 3600, 7200, 0]
    readonly property var sleepLabels: ["5m", "15m", "30m", "1h", "2h", "Never"]
    // idle.sh's defaults, for a missing file / value
    readonly property var defaults: ({ battery: { screen: 300, sleep: 1800 }, ac: { screen: 600, sleep: 1800 } })

    readonly property bool onBattery: UPower.onBattery
    readonly property string current: onBattery ? "battery" : "ac"

    readonly property var data: {
        try { return JSON.parse(file.text() || "{}"); } catch (e) { return {}; }
    }
    function get(src, key) {
        const v = data[src] ? data[src][key] : undefined;
        return typeof v === "number" ? v : defaults[src][key];
    }
    // the option closest to `secs` (a hand-edited 390 s shows as 5m), never = 0
    function index(opts, secs) {
        let best = 0, bd = Infinity;
        for (let i = 0; i < opts.length; i++) {
            const a = opts[i] || 1e9, b = secs || 1e9;
            const d = Math.abs(a - b);
            if (d < bd) { bd = d; best = i; }
        }
        return best;
    }
    function set(src, key, secs) {
        Theme.exec(Theme.hypr + "/idle.sh set " + src + " " + key + " " + secs);
    }
    function label(secs) {
        if (!secs) return "never";
        return secs >= 3600 ? (secs / 3600) + " h" : Math.round(secs / 60) + " min";
    }

    FileView {
        id: file
        path: Theme.hypr + "/idle.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }
}
