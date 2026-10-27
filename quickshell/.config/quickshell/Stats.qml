// CPU / memory / temperature / backlight / network numbers for the top bar,
// read straight from /proc and /sys (what waybar's built-in modules did), so
// no helper process runs for them.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking

Singleton {
    id: root

    // ── CPU (every 3 s, like waybar's interval) ─────────────────────────────
    property real cpu: 0                 // 0–100
    property var cores: []               // per-core 0–100
    property string load: ""
    property var _prev: null

    function _readCpu() {
        statFile.reload();
        const lines = statFile.text().split("\n").filter(l => l.startsWith("cpu"));
        const now = lines.map(l => {
            const f = l.trim().split(/\s+/).slice(1).map(Number);
            const idle = f[3] + (f[4] || 0);
            const total = f.reduce((a, b) => a + b, 0);
            return { idle, total };
        });
        if (_prev && _prev.length === now.length) {
            const pct = (i) => {
                const dt = now[i].total - _prev[i].total;
                return dt > 0 ? 100 * (1 - (now[i].idle - _prev[i].idle) / dt) : 0;
            };
            cpu = Math.round(pct(0));
            const c = [];
            for (let i = 1; i < now.length; i++) c.push(Math.round(pct(i)));
            cores = c;
        }
        _prev = now;
        loadFile.reload();
        load = loadFile.text().split(" ").slice(0, 3).join("  ");
    }

    FileView { id: statFile; path: "/proc/stat"; blockLoading: true }
    FileView { id: loadFile; path: "/proc/loadavg"; blockLoading: true }

    // ── memory (5 s) ────────────────────────────────────────────────────────
    property real memPct: 0
    property real memUsedGiB: 0
    property real memTotalGiB: 0

    function _readMem() {
        memFile.reload();
        const m = {};
        for (const l of memFile.text().split("\n")) {
            const r = /^(\w+):\s+(\d+)/.exec(l);
            if (r) m[r[1]] = Number(r[2]);
        }
        if (!m.MemTotal) return;
        const used = m.MemTotal - m.MemAvailable;
        memPct = Math.round(100 * used / m.MemTotal);
        memUsedGiB = used / 1048576;
        memTotalGiB = m.MemTotal / 1048576;
    }

    FileView { id: memFile; path: "/proc/meminfo"; blockLoading: true }

    // ── temperature (5 s): thermal_zone0, as waybar's default ───────────────
    property int tempC: 0
    readonly property int tempCritical: 82
    // one heat scale for the temperature pill and its panel (SysPopup)
    // sapphire · yellow ≥60 · peach ≥70 · red ≥ tempCritical
    function tempColor(c) { return c >= tempCritical ? Theme.red : c >= 70 ? Theme.peach : c >= 60 ? Theme.yellow : Theme.sapphire; }

    function _readTemp() {
        tempFile.reload();
        tempC = Math.round(Number(tempFile.text().trim()) / 1000);
    }

    FileView { id: tempFile; path: "/sys/class/thermal/thermal_zone0/temp"; blockLoading: true }

    // ── backlight (1 s; sysfs has no change events) ─────────────────────────
    property int brightness: 0           // percent

    function _readBacklight() {
        blFile.reload();
        blMax.reload();
        const max = Number(blMax.text().trim());
        if (max > 0) brightness = Math.round(100 * Number(blFile.text().trim()) / max);
    }

    FileView { id: blFile; path: "/sys/class/backlight/intel_backlight/brightness"; blockLoading: true }
    FileView { id: blMax; path: "/sys/class/backlight/intel_backlight/max_brightness"; blockLoading: true }

    // ── network ─────────────────────────────────────────────────────────────
    // State from NetworkManager (Quickshell.Networking); address and rates
    // from `ip` and /proc/net/dev every 5 s.
    readonly property var wifiDev: Networking.devices.values.find(d => d.type === DeviceType.Wifi) || null
    readonly property var wiredDev: Networking.devices.values.find(d => d.type === DeviceType.Wired && d.connected) || null
    readonly property var wifiNet: wifiDev ? wifiDev.networks.values.find(n => n.connected) || null : null
    readonly property string netKind: wiredDev ? "wired" : wifiNet ? "wifi" : wifiDev && wifiDev.connected ? "linked" : "offline"
    readonly property string ifname: wiredDev ? wiredDev.name : wifiDev ? wifiDev.name : ""
    readonly property string essid: wifiNet ? wifiNet.name : ""
    readonly property int signal: wifiNet ? Math.round(wifiNet.signalStrength * 100) : 0
    property string ipaddr: ""
    property real rxBps: 0               // bits per second
    property real txBps: 0
    property var _netPrev: null

    function _readNet() {
        if (!ifname) return;
        netDev.reload();
        const line = netDev.text().split("\n").find(l => l.trim().startsWith(ifname + ":"));
        if (line) {
            const f = line.split(":")[1].trim().split(/\s+/).map(Number);
            const now = { rx: f[0], tx: f[8], t: Date.now() };
            if (_netPrev && _netPrev.ifname === ifname) {
                const dt = (now.t - _netPrev.t) / 1000;
                rxBps = Math.max(0, (now.rx - _netPrev.rx) * 8 / dt);
                txBps = Math.max(0, (now.tx - _netPrev.tx) * 8 / dt);
            }
            now.ifname = ifname;
            _netPrev = now;
        }
        if (!ipProc.running) ipProc.running = true;
    }

    function bits(b) {
        const u = ["b/s", "kb/s", "Mb/s", "Gb/s"];
        let i = 0;
        while (b >= 1000 && i < u.length - 1) { b /= 1000; i++; }
        return (i === 0 ? Math.round(b) : b.toFixed(1)) + " " + u[i];
    }

    FileView { id: netDev; path: "/proc/net/dev"; blockLoading: true }

    Process {
        id: ipProc
        command: ["ip", "-4", "-o", "addr", "show", "dev", root.ifname]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = /inet (\S+)/.exec(text);
                root.ipaddr = m ? m[1].split("/")[0] : "";
            }
        }
    }

    // ── timers ──────────────────────────────────────────────────────────────
    Timer { interval: 3000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root._readCpu() }
    Timer { interval: 5000; running: true; repeat: true; triggeredOnStart: true; onTriggered: { root._readMem(); root._readTemp(); root._readNet(); } }
    Timer { interval: 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root._readBacklight() }

    // Re-read now (after a brightness keypress / scroll on the bar).
    function refreshBacklight() { blTimer.restart(); }
    Timer { id: blTimer; interval: 150; onTriggered: root._readBacklight() }
}
