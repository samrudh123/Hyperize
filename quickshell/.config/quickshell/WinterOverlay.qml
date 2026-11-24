// Winter theme, one per screen (shell.qml): the falling snow, the snow lying
// on windows and on the bottom bar's islands, and the clumps that fall when
// something with snow on it moves, closes or collapses. See SeasonState.qml.
//
// A click-through layer on TOP (under fullscreen windows, the pickers and
// the idle cover); it exists only while a winter theme is on.
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

PanelWindow {
    id: win

    required property var modelData
    screen: modelData
    readonly property string mon: screen ? screen.name : ""
    readonly property var hmon: Hyprland.monitorFor(screen)
    readonly property bool fullscreenHere: SeasonState.fullscreenMons.indexOf(mon) >= 0
    // the idle cover fills the screen: nothing here is seen
    readonly property bool covered: SeasonState.coveredMons.indexOf(mon) >= 0

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "qs-snow"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    color: "transparent"
    mask: Region {}                            // never takes a click

    // ── falling snow ──────────────────────────────────────────────────────
    readonly property bool snowing: SeasonState.snowOn && !fullscreenHere && !covered
    // the hour, for moonlit flakes at night
    property int hour: new Date().getHours()
    Timer { interval: 300000; repeat: true; running: SeasonState.winter; onTriggered: win.hour = new Date().getHours() }
    readonly property bool night: hour >= 19 || hour < 6

    // pointer parting: ask SeasonState for the pointer while snowing
    readonly property bool wantsCursor: snowing && SeasonState.cursorOn
    onWantsCursorChanged: SeasonState.cursorUsers += wantsCursor ? 1 : -1
    // (an initial true fires no onChanged: count it here)
    Component.onCompleted: if (wantsCursor) SeasonState.cursorUsers += 1
    Component.onDestruction: if (wantsCursor) SeasonState.cursorUsers -= 1

    ShaderEffect {
        id: snow
        anchors.fill: parent
        visible: win.snowing || opacity > 0
        opacity: win.snowing ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 1200 } }
        blending: true
        fragmentShader: Qt.resolvedUrl("shaders/snowfall.frag.qsb")

        property size itemSize: Qt.size(width, height)
        property real t: 0
        property real drift: 0
        property real density: SeasonState.density
        property point cursor: {
            const c = SeasonState.cursor;
            const m = win.hmon;
            return m ? Qt.point(c.x - m.x, c.y - m.y) : Qt.point(-9999, -9999);
        }
        // eases in when the pointer moves, out when it rests (the flakes close
        // over a still pointer)
        property real push: 0
        property color flakeColor: Theme.light ? "#ffffff" : win.night ? "#e2ebff" : "#f6f9ff"
        property color rimColor: Theme.light ? Theme.alpha(Theme.overlay1, 0.75) : Theme.alpha("#ffffff", 0)

        // ~30 fps: the time and the wind step on a timer (not every frame)
        property real wind: 0
        property real gustT: 0
        property int frame: 0
        // ~30 fps; 20 on battery
        Timer {
            interval: Idle.onBattery ? 50 : 33; repeat: true
            running: snow.visible
            onTriggered: {
                const dt = interval / 1000;
                snow.t = (snow.t + dt) % 1800;
                if (++snow.frame % 3 === 0) win.clock = snow.t;     // the lights: ~10 fps is plenty
                // a slow breeze with a gust now and then
                snow.gustT += dt;
                const g = Math.sin(snow.gustT / 23) * Math.sin(snow.gustT / 7.3);
                const target = 9 + 26 * Math.max(0, g) - 6 * Math.max(0, -g);
                snow.wind += (target - snow.wind) * 0.02;
                snow.drift = (snow.drift + snow.wind * dt) % 100000;
                const moving = Date.now() - SeasonState.cursorAt < 900;
                snow.push += ((moving ? 1 : 0.25) - snow.push) * 0.08;
            }
        }
    }

    // ── snow on the windows ───────────────────────────────────────────────
    Item {
        id: caps
        anchors.fill: parent
        visible: SeasonState.capsOn && !win.fullscreenHere && !win.covered
        opacity: SeasonState.settling ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: SeasonState.settling ? 90 : 380 } }

        Repeater {
            model: SeasonState.capList.filter(c => c.mon === win.mon)
            delegate: Item {
                id: wcap
                required property var modelData
                readonly property real depth: SeasonState.depthOf(modelData.t0, SeasonState.winMax,
                                                                  SeasonState.winGrow, SeasonState.now)
                Repeater {
                    model: wcap.modelData.segs
                    delegate: SnowCap {
                        required property var modelData
                        x: modelData[0]
                        width: modelData[1] - modelData[0]
                        y: wcap.modelData.y + base - height
                        maxDepth: SeasonState.winMax
                        depth: wcap.depth
                        gx: modelData[0] - wcap.modelData.x
                        seed: (wcap.modelData.x * 7 + wcap.modelData.w * 3) % 997
                        taperL: modelData[2]
                        taperR: modelData[3]
                    }
                }
            }
        }
    }

    // ── snow on the bottom bar's islands ──────────────────────────────────
    // not faded with the window caps on a workspace switch: the bar stays put
    Item {
        anchors.fill: parent
        visible: SeasonState.capsOn && !win.fullscreenHere && !win.covered
        Repeater {
            model: SeasonState.ledgeKeys.filter(l => l.mon === win.mon)
            delegate: SnowCap {
                required property var modelData
                readonly property var l: SeasonState.ledgeMap[modelData.key] || null
                visible: l !== null && depth > 0.3
                x: l ? l.x + 2 : 0
                width: l ? l.w - 4 : 0
                y: (l ? l.y : 0) + base - height
                maxDepth: SeasonState.ledgeMax
                base: 1
                depth: l ? SeasonState.depthOf(l.t0, SeasonState.ledgeMax, SeasonState.ledgeGrow, SeasonState.now) : 0
                // the lumps belong to the island, not to where it is now
                seed: (parseInt(modelData.key.slice(1)) * 97) % 389
                taperL: l ? Math.max(8, l.r) : 8
                taperR: l ? Math.max(8, l.r) : 8
            }
        }
    }

    // ── fairy lights along the top bar's islands ──────────────────────────
    // their clock: rides the snowfall's frames when it snows, else ~12 fps
    property real clock: 0
    Timer {
        interval: 80; repeat: true
        running: lightsItem.visible && !snow.visible
        onTriggered: win.clock += 0.08
    }
    Item {
        id: lightsItem
        anchors.fill: parent
        visible: SeasonState.lightsOn && !win.fullscreenHere && !win.covered
        Repeater {
            model: SeasonState.lightsOn ? SeasonState.lightList.filter(l => l.mon === win.mon) : []
            delegate: Item {
                id: strip
                required property var modelData
                x: modelData.x
                y: modelData.y - 3                     // the hooks, just inside the edge
                width: modelData.w
                height: 16
                readonly property real inset: Math.max(7, modelData.r * 0.8)
                readonly property int spans: Math.max(1, Math.round((width - 2 * inset) / 46))
                readonly property real span: (width - 2 * inset) / spans
                readonly property real sag: 5
                Canvas {
                    id: wire
                    anchors.fill: parent
                    onWidthChanged: requestPaint()
                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.clearRect(0, 0, width, height);
                        ctx.strokeStyle = Theme.light ? Theme.alpha(Theme.overlay2, 0.9) : "rgba(36,52,46,0.95)";
                        ctx.lineWidth = 1.2;
                        ctx.beginPath();
                        for (let i = 0; i < strip.spans; i++) {
                            const x0 = strip.inset + i * strip.span;
                            ctx.moveTo(x0, 0.5);
                            ctx.quadraticCurveTo(x0 + strip.span / 2, 2 * strip.sag, x0 + strip.span, 0.5);
                        }
                        ctx.stroke();
                    }
                }
                Repeater {
                    model: strip.spans * 2
                    delegate: Item {
                        id: bulb
                        required property int index
                        readonly property real u: index % 2 ? 0.7 : 0.3
                        readonly property color c: {
                            const l = [Theme.red, Theme.yellow, Theme.green, Theme.sky, Theme.peach, Theme.mauve];
                            const k = (index + Math.floor(((strip.modelData && strip.modelData.x) || 0) / 7)) % l.length;
                            return l[k] || Theme.yellow;
                        }
                        // twinkle: each bulb breathes at its own pace, now and
                        // then dipping low — off the overlay's clock (no
                        // animations of its own: those redrew at 60 fps)
                        readonly property real rate: 0.35 + 0.9 * ((index * 7919 + ((strip.modelData && strip.modelData.x) || 0)) % 97) / 97
                        readonly property real phase: ((index * 104729) % 628) / 100
                        readonly property real glow: {
                            const w = Math.sin(win.clock * rate + phase);
                            return w > 0.55 ? 0.3 + 0.7 * (1 - (w - 0.55) / 0.45) * 0.4 : 0.75 + 0.25 * Math.sin(win.clock * rate * 1.7 + phase);
                        }
                        x: strip.inset + (Math.floor(index / 2) + u) * strip.span
                        y: 0.5 + 4 * strip.sag * u * (1 - u)
                        Rectangle {                    // the glow
                            width: 14; height: 14; radius: 7
                            x: -7; y: -2
                            color: Theme.alpha(bulb.c, (Theme.light ? 0.22 : 0.32) * bulb.glow)
                        }
                        Rectangle {                    // the socket
                            width: 2.4; height: 2; x: -1.2; y: -0.5
                            color: Theme.light ? Theme.overlay2 : "#24342e"
                        }
                        Rectangle {                    // the bulb
                            width: 4; height: 5.5; radius: 2
                            x: -2; y: 1.2
                            color: Qt.lighter(bulb.c, 0.75 + 0.45 * bulb.glow)
                            opacity: 0.55 + 0.45 * bulb.glow
                        }
                    }
                }
            }
        }
    }

    // ── clumps falling off ────────────────────────────────────────────────
    // A fixed pool of soft dots stepped by one timer (only while some fall).
    // Was QtQuick.Particles (a ParticleSystem + an Emitter made per drop):
    // that segfaulted inside libQt6QuickParticles every so often (kernel log,
    // 2026-11-24, always the same spot) and took the whole shell down —
    // bars gone until something restarted qs.
    readonly property int poolSize: 260
    property var parts: []                     // live: { i, x, y, vx, vy, age, life, dust, ph }
    property int nextSlot: 0
    Item {
        id: pool
        anchors.fill: parent
        Repeater {
            id: dots
            model: win.poolSize
            delegate: Rectangle {
                visible: false
                color: Theme.light ? "#ffffff" : "#eef4ff"
                border.width: Theme.light ? 1 : 0
                border.color: Theme.alpha(Theme.overlay1, 0.5)
            }
        }
    }
    function burst(x, y, w, h) {
        const n = Math.max(3, Math.round(Math.min(150, w / 7 * Math.min(1.4, h / 5))));
        const dust = Math.max(2, Math.round(n * 0.5));
        const add = [];
        for (let k = 0; k < n + dust; k++) {
            const isDust = k >= n;
            const i = nextSlot;
            nextSlot = (nextSlot + 1) % poolSize;
            const it = dots.itemAt(i);
            if (!it) continue;
            const sz = isDust ? 2 + Math.random() * 2 : 3 + h * 0.7 + Math.random() * 3;
            it.width = sz;
            it.height = sz;
            it.radius = sz / 2;
            it.opacity = 0;
            it.visible = true;
            const ang = (90 + (Math.random() * 2 - 1) * (isDust ? 60 : 35)) * Math.PI / 180;
            const sp = isDust ? 10 + Math.random() * 35 : 10 + Math.random() * 60;
            add.push({ i: i, x: x + Math.random() * w, y: y - Math.random() * h,
                       vx: Math.cos(ang) * sp, vy: Math.sin(ang) * sp - (isDust ? 0 : 20),
                       age: 0, life: isDust ? 1.6 + Math.random() * 1.2 : 0.9 + Math.random() * 0.8,
                       dust: isDust, ph: Math.random() * 6.28, sz: sz });
        }
        // a slot taken over by this burst stops being stepped for the old one
        const taken = {};
        for (const a of add) taken[a.i] = true;
        parts = parts.filter(p => !taken[p.i]).concat(add);
        stepper.start();
    }
    Timer {
        id: stepper
        interval: 16; repeat: true
        onTriggered: {
            const dt = 0.016;
            const keep = [];
            for (const p of win.parts) {
                const it = dots.itemAt(p.i);
                p.age += dt;
                if (!it || p.age >= p.life || p.y > win.height + 20) { if (it) it.visible = false; continue; }
                p.vy += (p.dust ? 90 : 640) * dt;
                if (p.dust) p.vx += Math.sin(p.age * 3 + p.ph) * 40 * dt;
                p.x += p.vx * dt;
                p.y += p.vy * dt;
                it.x = p.x - p.sz / 2;
                it.y = p.y - p.sz / 2;
                // fade in quickly, out over the last third
                const a = Math.min(1, p.age / 0.12) * Math.min(1, (p.life - p.age) / (p.life * 0.35));
                it.opacity = a * (p.dust ? 0.55 : 0.95);
                keep.push(p);
            }
            win.parts = keep;
            if (!keep.length) stop();
        }
    }
    Connections {
        target: SeasonState
        function onCapDropped(m, x, y, w, h) {
            if (m !== win.mon || win.fullscreenHere || !SeasonState.winter) return;
            win.burst(x, y, w, h);
        }
    }
}
