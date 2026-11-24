// Seasonal effects — what the season's pieces share. A SEASONAL theme
// (rice-theme.py: "winter") puts `season` in palette.json (Theme.season);
// picking any normal theme turns every effect off again.
//
// Winter (Winter*.qml, SnowCap.qml, shaders/snow*.frag):
//   * snow falling over the desktop (WinterOverlay) — flakes part around
//     the pointer, the wind gusts now and then
//   * snow settling on the top edges of windows, bar popups (PanelPopup) and
//     the bottom bar's islands, growing slowly; it falls off when the thing
//     under it moves, closes or collapses (capDropped → the overlay's
//     falling clumps)
//   * left idle, the screen frosts over and fills with snow (WinterCover);
//     moving the pointer wipes it away
//   * frosted panel corners, fairy lights along the top bar's islands
//
// Settings › Appearance › Season writes theme/season-fx.json:
//   snow caps idle frost lights cursor wallpaper   true/false
//   density   0.5 light · 1 normal · 1.7 heavy
//   idleAfter seconds before the idle cover starts (45)
// Low battery (battery-saver.py's flag) stops the snowfall; the rest stays.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Singleton {
    id: root

    readonly property bool winter: Theme.season === "winter"

    // ── settings ──────────────────────────────────────────────────────────
    readonly property var fx: {
        try { return JSON.parse(fxFile.text() || "{}"); } catch (e) { return {}; }
    }
    function opt(k, d) {
        const v = fx[k];
        return v === undefined || v === null ? d : v;
    }
    function set(k, v) {
        const o = Object.assign({}, fx);
        o[k] = v;
        fxFile.setText(JSON.stringify(o, null, 1) + "\n");
    }
    property bool saver: false                // battery-saver.py: ≤20 % unplugged
    readonly property bool snowOn: winter && opt("snow", true) && !saver
    readonly property bool capsOn: winter && opt("caps", true)
    readonly property bool idleOn: winter && opt("idle", true)
    readonly property bool frostOn: winter && opt("frost", true)
    readonly property bool lightsOn: winter && opt("lights", true)
    readonly property bool cursorOn: winter && opt("cursor", true)
    readonly property real density: {
        const d = Number(opt("density", 1));
        return isNaN(d) ? 1 : Math.max(0.3, Math.min(2.5, d));
    }
    readonly property int idleAfter: Math.max(15, Number(opt("idleAfter", 45)) || 45)

    // the theme the season replaced (set-theme.sh), for "Back to …"
    readonly property string prevTheme: {
        const t = (prevFile.text() || "").trim().replace(/-light$/, "");
        return t && t !== "winter" ? t : "mocha";
    }
    FileView {
        id: prevFile
        path: Theme.hypr + "/theme/season-prev-theme"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }
    FileView {
        id: fxFile
        path: Theme.hypr + "/theme/season-fx.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }
    FileView {
        id: saverFile
        path: (Quickshell.env("XDG_STATE_HOME") || Theme.home + "/.local/state") + "/battery-saver/low"
        printErrors: false
        onLoaded: root.saver = true
        onLoadFailed: root.saver = false
    }
    Timer {
        interval: 30000; repeat: true; running: root.winter; triggeredOnStart: true
        onTriggered: saverFile.reload()
    }

    // ── clock (cap growth) ───────────────────────────────────────────────
    property real now: Date.now()
    Timer {
        interval: 1000; repeat: true; running: root.capsOn
        onTriggered: root.now = Date.now()
    }

    // ── idle ──────────────────────────────────────────────────────────────
    // respectInhibitors: a playing video (or anything holding an idle
    // inhibitor) never gets snowed in
    // Idle for the snow cover. Holding Shift UPHOLDS it while there's snow on
    // screen: the pointer can move (draw, or just look) and the snow keeps
    // piling up. The compositor's idle ends on the Shift press itself, so its
    // end is held back a moment (idleRaw) for the Shift bind to land first.
    readonly property bool idle: idleRaw || previewIdle || (lifted && coverUpMons.length > 0)
    property bool idleRaw: false
    property real idleStart: 0
    // a NEW spell of idleness (not Shift holding one up): the cover snows
    // over what was wiped
    signal idleBegan(bool preview)
    Timer { id: idleGrace; interval: 300; onTriggered: root.idleRaw = false }
    // screens with snow on them (WinterCover)
    property var coverUpMons: []
    function setCoverUp(mon, on) {
        if ((coverUpMons.indexOf(mon) >= 0) === on) return;
        const l = coverUpMons.filter(m => m !== mon);
        if (on) l.push(mon);
        coverUpMons = l;
    }
    // `qs ipc call winter snowin`: snow the screen in now (a preview — as if
    // idle for a while); moving the pointer ends it like real idleness
    property bool previewIdle: false
    function snowIn() {
        if (!idleOn) return;
        idleStart = Date.now() - 60000;
        previewIdle = true;
        idleBegan(true);
        previewArm.restart();
    }
    // the pointer is read for a moment first: where it rests then is home
    Timer { id: previewArm; interval: 1500; onTriggered: root.previewFrom = root.cursor }
    property point previewFrom: Qt.point(0, 0)
    onCursorChanged: if (previewIdle && !previewArm.running && !lifted
                         && Math.hypot(cursor.x - previewFrom.x, cursor.y - previewFrom.y) > 4) previewIdle = false
    IpcHandler {
        target: "winter"
        function snowin(): void { root.snowIn(); }
        function melt(): void { root.previewIdle = false; root.meltAll(); }
        function state(): string {
            return JSON.stringify({ winter: root.winter, idle: root.idle, lifted: root.lifted,
                                    saver: root.saver, caps: root.capList.length, ledges: root.ledgeList.length });
        }
    }
    signal meltAll()
    IdleMonitor {
        id: idleMon
        enabled: root.idleOn
        timeout: root.idleAfter
        respectInhibitors: true
        onIsIdleChanged: {
            if (isIdle) {
                idleGrace.stop();
                root.idleStart = Date.now();
                const was = root.idle;
                root.idleRaw = true;
                if (!was) root.idleBegan(false);
            } else {
                idleGrace.restart();
            }
        }
    }

    // screens a full idle cover hides (WinterCover): their snowfall rests
    property var coveredMons: []
    function setCovered(mon, on) {
        const l = coveredMons.filter(m => m !== mon);
        if (on) l.push(mon);
        coveredMons = l;
    }

    // ── Shift held: the pointer is "lifted" off the snow cover ────────────
    // hyprland.conf binds Shift_L/R (non-consuming: apps still get Shift) to
    // `global, quickshell:snowlift`; Hyprland sends that shortcut "pressed"
    // on key-down and "released" on key-up. WinterCover doesn't wipe while
    // lifted, and while there's snow on screen idleness is upheld (`idle`):
    // the snow keeps piling up. Release Shift and the pointer wipes again.
    // Two binds can match one key (with / without SHIFT in the mask): the
    // events come in pairs, both edges are idempotent.
    property bool lifted: false
    GlobalShortcut {
        appid: "quickshell"
        name: "snowlift"
        description: "Winter: hold to move over the snow without wiping it"
        onPressed: { root.liftLog("shift down"); root.lifted = true; liftTimeout.restart(); }
        onReleased: { root.liftLog("shift up"); root.lifted = false; }
    }
    // Shift events while there's snow on screen go to `qs log` (debugging
    // the binds: grep "winter:")
    function liftLog(what) {
        if (coverUpMons.length) console.info("winter:", what, "idle", idle, "lifted", lifted);
    }
    // (a key-up that never arrives: let go after a few minutes)
    Timer { id: liftTimeout; interval: 300000; onTriggered: root.lifted = false }

    // ── the pointer (Hyprland j/cursorpos), polled while someone wants it ──
    // `cursorUsers` counts the wanters (the snowfall parting, a cover being
    // wiped); global layout px.
    property int cursorUsers: 0
    property point cursor: Qt.point(-9999, -9999)
    property real cursorAt: 0                 // when it last moved
    Timer {
        interval: 33; repeat: true
        running: (root.cursorUsers > 0 || root.previewIdle) && root.winter
        onTriggered: if (!cursorSock.connected) { cursorSock.buf = ""; cursorSock.connected = true; }
    }
    Socket {
        id: cursorSock
        property string buf: ""
        path: Hyprland.requestSocketPath
        parser: SplitParser {
            splitMarker: ""
            onRead: d => {
                cursorSock.buf += d;
                try {
                    const o = JSON.parse(cursorSock.buf);
                    if (o.x !== root.cursor.x || o.y !== root.cursor.y) {
                        root.cursor = Qt.point(o.x, o.y);
                        root.cursorAt = Date.now();
                    }
                    cursorSock.connected = false;
                } catch (e) {}
            }
        }
        onConnectedChanged: if (connected) { write("j/cursorpos"); flush(); }
    }

    // ── windows (Hyprland j/clients) → snow caps ──────────────────────────
    // Hyprland's general:border_size / decoration:rounding (hyprland.conf)
    readonly property int borderPx: 2
    readonly property int roundingPx: 18
    readonly property int winMax: 10          // px of snow on a window, fully grown
    readonly property real winGrow: 200000    // ms to grow it
    // what the overlays draw: [{ key, mon, x, y, segs: [[x0, x1, taperL, taperR]], t0 }]
    // y = the ledge (window's top border); monitor-local px
    property var capList: []
    property string capSig: ""
    // monitors with a fullscreen window up (everything hides there)
    property var fullscreenMons: []
    // a workspace switch is animating: caps hide for a moment
    property bool settling: false
    Timer { id: settleTimer; interval: 520; onTriggered: root.settling = false }

    signal capDropped(string mon, real x, real y, real w, real h)
    function drop(mon, x, y, w, h) {
        // (not while the season is going away: the overlays are being torn down)
        if (winter && w > 2 && h > 0.6) capDropped(mon, x, y, w, h);
    }

    property var recs: ({})                   // addr → { t0, x, y, w, h, ws, mon, shown }
    property var lastActive: ({})             // monitor → workspace id at the last poll

    Timer {
        interval: 700; repeat: true; running: root.capsOn
        triggeredOnStart: true
        onTriggered: root.pollClients()
    }
    Timer { id: soonPoll; interval: 90; onTriggered: root.pollClients() }
    function pollClients() {
        if (!clientSock.connected) { clientSock.buf = ""; clientSock.connected = true; }
    }
    Socket {
        id: clientSock
        property string buf: ""
        path: Hyprland.requestSocketPath
        parser: SplitParser {
            splitMarker: ""
            onRead: d => {
                clientSock.buf += d;
                let list;
                try { list = JSON.parse(clientSock.buf); } catch (e) { return; }
                clientSock.connected = false;
                root.onClients(list);
            }
        }
        onConnectedChanged: if (connected) { write("j/clients"); flush(); }
    }
    Connections {
        target: Hyprland
        enabled: root.capsOn
        function onRawEvent(ev) {
            const n = ev.name;
            if (n === "workspacev2" || n === "focusedmonv2" || n === "activespecialv2") {
                if (n === "activespecialv2") Hyprland.refreshMonitors();
                root.settling = true;
                settleTimer.restart();
                soonPoll.restart();
            } else if (n === "openwindow" || n === "closewindow" || n === "movewindowv2"
                       || n === "changefloatingmode" || n === "fullscreen" || n === "activewindowv2") {
                soonPoll.restart();
            }
        }
    }
    // the bar popups that are open, as occluders: [{ mon, x, y, w, h }]
    property var popupRects: []
    function setPopupRect(pop, r) {
        const out = popupRects.filter(p => p.pop !== pop);
        if (r) out.push(Object.assign({ pop: pop }, r));
        popupRects = out;
        rebuildCaps();
    }

    property var lastClients: []
    function onClients(list) {
        lastClients = list;
        const mons = {};
        const active = {};
        for (const m of Hyprland.monitors.values) {
            mons[m.id] = m;
            active[m.name] = m.activeWorkspace ? m.activeWorkspace.id : null;
            // a special workspace shown over it: no caps on that monitor
            const sp = m.lastIpcObject && m.lastIpcObject.specialWorkspace;
            if (sp && sp.id) active[m.name] = null;
        }
        const now = Date.now();
        const seen = {};
        const fs = [];
        for (const c of list) {
            seen[c.address] = true;
            const m = mons[c.monitor];
            if (!m) continue;
            const visible = c.mapped && !c.hidden && c.workspace && c.workspace.id === active[m.name];
            if (visible && c.fullscreen >= 2) fs.push(m.name);
            const g = { x: c.at[0] - m.x, y: c.at[1] - m.y, w: c.size[0], h: c.size[1],
                        ws: c.workspace ? c.workspace.id : 0, mon: m.name,
                        floating: c.floating, fh: c.focusHistoryID };
            let r = recs[c.address];
            if (!r) {
                recs[c.address] = Object.assign({ t0: now, shown: visible }, g);
                continue;
            }
            const moved = Math.abs(r.x - g.x) > 3 || Math.abs(r.y - g.y) > 3 || Math.abs(r.w - g.w) > 3;
            if (moved || r.ws !== g.ws) {
                // shaken off (moved, resized, sent to another workspace)
                if (r.shown) dropRec(r, now);
                r.t0 = now;
            } else if (r.shown && !visible) {
                // its workspace was switched away from (SUPER+N, a swipe):
                // the snow falls off as it leaves; it starts afresh when back
                dropRec(r, now);
                r.t0 = now;
            }
            Object.assign(r, g);
            r.shown = visible;
        }
        for (const a in recs) {
            if (seen[a]) continue;
            const r = recs[a];
            if (r.shown && lastActive[r.mon] === active[r.mon]) dropRec(r, now);   // closed
            delete recs[a];
        }
        const la = {};
        for (const k in active) la[k] = active[k];
        lastActive = la;
        if (JSON.stringify(fs) !== JSON.stringify(fullscreenMons)) fullscreenMons = fs;
        rebuildCaps();
    }
    function depthOf(t0, max, grow, nowMs) {
        return max * Math.min(1, Math.max(0, (nowMs - t0) / grow));
    }
    function dropRec(r, nowMs) {
        const h = depthOf(r.t0, winMax, winGrow, nowMs);
        drop(r.mon, r.x, r.y - root.borderPx, r.w, h);
    }

    // the caps' visible parts: what's above a window covers its cap
    function rebuildCaps() {
        const vis = [];
        for (const a in recs) if (recs[a].shown) vis.push(Object.assign({ key: a }, recs[a]));
        const out = [];
        for (const w of vis) {
            const top = w.y - root.borderPx;
            const band0 = top - winMax - 2, band1 = top + 1;
            let segs = [[w.x, w.x + w.w]];
            const cut = (x0, x1) => {
                const n = [];
                for (const s of segs) {
                    if (x1 <= s[0] || x0 >= s[1]) { n.push(s); continue; }
                    if (x0 > s[0]) n.push([s[0], x0]);
                    if (x1 < s[1]) n.push([x1, s[1]]);
                }
                segs = n;
            };
            for (const o of vis) {
                if (o === w || o.mon !== w.mon) continue;
                const above = (o.floating && !w.floating) || (o.floating && w.floating && o.fh < w.fh);
                if (!above) continue;
                const b = root.borderPx;
                if (o.y - b < band1 && o.y + o.h + b > band0) cut(o.x - b, o.x + o.w + b);
            }
            for (const p of popupRects) {
                if (p.mon !== w.mon) continue;
                if (p.y < band1 && p.y + p.h > band0) cut(p.x, p.x + p.w);
            }
            const r = root.roundingPx;
            const out2 = segs.filter(s => s[1] - s[0] > 6).map(s => [
                s[0], s[1],
                s[0] <= w.x + 0.5 ? Math.max(8, r) : 0,
                s[1] >= w.x + w.w - 0.5 ? Math.max(8, r) : 0
            ]);
            if (out2.length) out.push({ key: w.key, mon: w.mon, x: w.x, y: top, w: w.w, segs: out2, t0: w.t0 });
        }
        const sig = JSON.stringify(out);
        if (sig !== capSig) { capSig = sig; capList = out; }
    }

    // ── bar trims (WinterTrim.qml): the bottom bar's islands are ledges
    // snow settles on; the top bar's islands carry fairy lights ──────────
    readonly property int ledgeMax: 7
    readonly property real ledgeGrow: 150000
    property var ledgeItems: []
    property var ledgeList: []                // [{ key, mon, x, y, w, t0, r }] snow (y = top edge)
    // for the overlay's Repeater: the keys change only when an island comes
    // or goes (re-creating every cap whenever one island moved made them
    // blink, e.g. on a workspace switch); each cap reads its place from ledgeMap
    property var ledgeKeys: []                // [{ key, mon }]
    property var ledgeMap: ({})               // key → entry
    property var lightList: []                // [{ key, mon, x, y, w, r }] lights (y = bottom edge)
    property int ledgeSeq: 0
    function addLedge(it) {
        if (ledgeItems.indexOf(it) >= 0) return;
        it.ledgeKey = "l" + (++ledgeSeq);
        it.ledgeT0 = Date.now();
        ledgeItems = ledgeItems.concat([it]);
        measureLedges();
    }
    function removeLedge(it) {
        const i = ledgeItems.indexOf(it);
        if (i < 0) return;
        const l = ledgeList.find(x => x.key === it.ledgeKey);
        if (l) drop(l.mon, l.x, l.y, l.w, depthOf(l.t0, ledgeMax, ledgeGrow, Date.now()));
        ledgeItems = ledgeItems.filter(x => x !== it);
        measureLedges();
    }
    // islands move as their neighbours grow (player titles …): re-measured
    // every second (mapToItem isn't a binding)
    Timer {
        interval: 1000; repeat: true; running: root.winter && root.ledgeItems.length > 0
        onTriggered: root.measureLedges()
    }
    function measureLedges() {
        const snow = [], lights = [];
        const now = Date.now();
        for (const it of ledgeItems) {
            const w = it.ledgeWindow;
            if (!w || !w.screen || !it.visible || it.width < 8) continue;
            const p = it.mapToItem(null, 0, 0);
            if (it.trimKind === "lights") {
                if (!w.visible) continue;
                lights.push({ key: it.ledgeKey, mon: w.screen.name, x: Math.round(p.x),
                              y: Math.round(p.y + it.height), w: Math.round(it.width), r: it.ledgeRadius || 0 });
                continue;
            }
            const y0 = w.screen.height - w.height;     // the bottom bar
            const l = { key: it.ledgeKey, mon: w.screen.name, x: Math.round(p.x),
                        y: Math.round(y0 + p.y), w: Math.round(it.width), t0: it.ledgeT0,
                        r: it.ledgeRadius || 0 };
            // gone from view (the bar hid): what lay there falls
            if (!w.visible) {
                const old = ledgeList.find(x => x.key === l.key);
                if (old) drop(old.mon, old.x, old.y, old.w, depthOf(old.t0, ledgeMax, ledgeGrow, now));
                it.ledgeT0 = now;
                continue;
            }
            snow.push(l);
        }
        if (JSON.stringify(snow) !== JSON.stringify(ledgeList)) {
            ledgeList = snow;
            const map = {};
            for (const l of snow) map[l.key] = l;
            ledgeMap = map;
            const keys = snow.map(l => ({ key: l.key, mon: l.mon }));
            if (JSON.stringify(keys) !== JSON.stringify(ledgeKeys)) ledgeKeys = keys;
        }
        if (JSON.stringify(lights) !== JSON.stringify(lightList)) lightList = lights;
    }

    // ── bar popups (PanelPopup) ───────────────────────────────────────────
    readonly property int popMax: 11
    readonly property real popGrow: 50000
}
