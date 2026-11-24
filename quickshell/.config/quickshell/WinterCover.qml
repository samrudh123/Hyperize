// Winter theme: left alone, the screen snows in (one per screen, shell.qml).
// After SeasonState.idleAfter s with no input (and nothing inhibiting idle —
// a playing video never gets snowed in) frost creeps in from the edges and a
// drift rises from the bottom until snow fills the screen (~3 min).
// Back at the desk, moving the pointer wipes it away like a frosted window;
// once most of it is wiped (or ~10 s after any other input) the rest melts.
// A drawing (Shift was used) fades out slowly 15 s after the last move; if
// idleness comes first, the drawing stays and fresh snow fills its strokes in.
// Holding Shift: the pointer moves without wiping and it stays "idle" — the
// snow keeps piling up (draw in the snow: wipe = pen down, Shift = pen up).
//
// A click-through OVERLAY layer above everything (bars too), mapped only
// while there is snow on it.
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

PanelWindow {
    id: win

    required property var modelData
    screen: modelData
    readonly property var hmon: Hyprland.monitorFor(screen)

    property real level: 0                     // drift height 0..1
    property real frost: 0                     // frost reach 0..1
    readonly property bool snowy: level > 0 || frost > 0
    onSnowyChanged: SeasonState.setCoverUp(screen ? screen.name : "", snowy)
    Component.onCompleted: SeasonState.setCoverUp(screen ? screen.name : "", snowy)
    // seconds of idleness so far (Shift holding it up counts): the snow's age
    property real idleSecs: 0
    // the overlay's falling snow can stop under a full cover
    readonly property bool full: level >= 1 && fadeOut.opacity >= 1 && !wiping
    onFullChanged: SeasonState.setCovered(screen ? screen.name : "", full)

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-snow-cover"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    color: "transparent"
    mask: Region {}
    visible: SeasonState.idleOn && snowy

    function reset() {
        level = 0;
        frost = 0;
        idleSecs = 0;
        fadeOut.opacity = 1;
        wiped = 0;
        grid = ({});
        wiping = false;
        drawing = false;
        refilling = false;
        refillSteps = 0;
        mask.clearReq = true;
        mask.requestPaint();
    }

    // grow while idle, in steps (a still screen draws nothing in between);
    // wiped parts (a drawing) slowly fill back in while idle — Shift holding
    // it up, or a new spell of idleness — ~10 s before a stroke starts to
    // frost over, gone in ~20 s
    property bool refilling: false            // a new idle spell is snowing the strokes over
    property int refillSteps: 0
    Timer {
        interval: 500; repeat: true
        running: SeasonState.idleOn && SeasonState.idle
        triggeredOnStart: true
        onTriggered: {
            win.idleSecs += 0.5;
            const s = win.idleSecs;
            win.frost = Math.max(win.frost, Math.min(1, s / 70));
            win.level = Math.max(win.level, Math.min(1, Math.max(0, (s - 20) / 150)));
            if ((SeasonState.lifted || win.refilling) && win.wiped > 0) {
                mask.refill = true;
                mask.requestPaint();
                // filled in for good: forget the strokes
                if (++win.refillSteps >= 44) {
                    mask.clearReq = true;
                    win.wiped = 0;
                    win.grid = ({});
                    win.refilling = false;
                    win.drawing = false;
                    win.refillSteps = 0;
                }
            }
        }
    }
    Connections {
        target: SeasonState
        function onIdleBegan(preview) {
            // a new spell of idleness: the drawing stays, and fresh snow
            // settles into its strokes gradually (the growth timer)
            if (preview) win.idleSecs = Math.max(win.idleSecs, 60);
            win.refilling = win.wiped > 0;
        }
        function onIdleChanged() {
            if (SeasonState.idle) {
                // idle (or held up by Shift): nothing wipes. A drawing already
                // fading away keeps fading if you've walked off; holding
                // Shift (back at it) brings it back.
                if (melt.running && SeasonState.lifted) { melt.stop(); unmelt.restart(); }
                meltLater.stop();
                win.wiping = false;
            } else if (win.snowy) {
                win.last = Qt.point(-1, -1);       // no stroke from where it was
                win.wiping = true;
                meltLater.restart();
            }
        }
        function onLiftedChanged() {
            // Shift used on the snow: it's a drawing, give it time
            if (SeasonState.lifted && win.snowy) win.drawing = true;
        }
        function onIdleOnChanged() { if (!SeasonState.idleOn) win.reset(); }
        function onMeltAll() { win.meltNow(); }
    }

    // ── wiping ────────────────────────────────────────────────────────────
    property bool wiping: false
    onWipingChanged: SeasonState.cursorUsers += wiping ? 1 : -1
    Component.onDestruction: if (wiping) SeasonState.cursorUsers -= 1
    property point last: Qt.point(-1, -1)
    property var grid: ({})                    // wiped cells (48×30)
    property int wiped: 0
    readonly property int brush: 95            // px
    Connections {
        target: SeasonState
        enabled: win.wiping
        function onCursorChanged() {
            const m = win.hmon;
            if (!m) return;
            const p = Qt.point(SeasonState.cursor.x - m.x, SeasonState.cursor.y - m.y);
            if (p.x < 0 || p.y < 0 || p.x > win.width || p.y > win.height) { win.last = Qt.point(-1, -1); return; }
            const a = win.last.x < 0 ? p : win.last;
            win.last = p;
            // Shift held: moving over the snow without touching it (between
            // strokes of a drawing) — it counts as activity, nothing melts
            if (SeasonState.lifted) {
                win.drawing = true;
                if (melt.running) { melt.stop(); unmelt.restart(); }
                meltLater.restart();
                return;
            }
            // drawing again while it fades: it comes back
            if (melt.running) { melt.stop(); unmelt.restart(); }
            win.refilling = false;
            win.refillSteps = 0;
            const dx = p.x - a.x, dy = p.y - a.y;
            const steps = Math.max(1, Math.ceil(Math.hypot(dx, dy) / (win.brush * 0.35)));
            for (let i = 1; i <= steps; i++) {
                const x = a.x + dx * i / steps, y = a.y + dy * i / steps;
                mask.stamps.push([x / 4, y / 4]);
                win.mark(x, y);
            }
            mask.requestPaint();
            meltLater.restart();
            // most of it wiped: the rest melts — unless it's a drawing
            if (!win.drawing && win.wiped > 48 * 30 * 0.55) win.meltNow();
        }
    }
    function mark(x, y) {
        const cw = width / 48, chh = height / 30, r = brush * 0.8;
        for (let gx = Math.floor((x - r) / cw); gx <= Math.floor((x + r) / cw); gx++)
            for (let gy = Math.floor((y - r) / chh); gy <= Math.floor((y + r) / chh); gy++) {
                if (gx < 0 || gy < 0 || gx >= 48 || gy >= 30) continue;
                const cx = (gx + 0.5) * cw, cy = (gy + 0.5) * chh;
                if (Math.hypot(cx - x, cy - y) > r) continue;
                const k = gx + "," + gy;
                if (!grid[k]) { grid[k] = true; wiped++; }
            }
    }
    // the rest melts: after enough wiping, or a while after other input
    // (15 s once Shift has been used: a drawing gets time to be seen)
    property bool drawing: false
    Timer { id: meltLater; interval: win.drawing ? 15000 : 10000; onTriggered: win.meltNow() }
    // A plain wipe's leftovers melt quickly; a drawing fades away slowly
    // (~12 s) — move the mouse or hold Shift meanwhile and it comes back.
    function meltNow() {
        if (!melt.running && snowy) {
            unmelt.stop();
            melt.duration = drawing ? 12000 : 1600;
            melt.easing.type = drawing ? Easing.InOutSine : Easing.InOutQuad;
            melt.start();
        }
    }
    NumberAnimation {
        id: melt
        target: fadeOut; property: "opacity"; to: 0; duration: 1600
        easing.type: Easing.InOutQuad
        onFinished: win.reset()
    }
    NumberAnimation {
        id: unmelt
        target: fadeOut; property: "opacity"; to: 1; duration: 700
        easing.type: Easing.OutCubic
    }

    Item {
        id: fadeOut
        anchors.fill: parent

        // what the pointer swept, at quarter size: alpha = wiped
        Canvas {
            id: mask
            width: Math.ceil(win.width / 4)
            height: Math.ceil(win.height / 4)
            property var stamps: []
            property bool clearReq: false
            property bool refill: false
            onPaint: {
                const ctx = getContext("2d");
                if (clearReq) { ctx.clearRect(0, 0, width, height); clearReq = false; }
                if (refill) {
                    // snow settling back into the wiped parts
                    ctx.globalCompositeOperation = "destination-out";
                    ctx.fillStyle = "rgba(0,0,0,0.035)";
                    ctx.fillRect(0, 0, width, height);
                    ctx.globalCompositeOperation = "source-over";
                    refill = false;
                }
                const r = win.brush / 4;
                for (const s of stamps) {
                    const g = ctx.createRadialGradient(s[0], s[1], 0, s[0], s[1], r);
                    g.addColorStop(0, "rgba(255,255,255,1)");
                    g.addColorStop(0.55, "rgba(255,255,255,0.9)");
                    g.addColorStop(1, "rgba(255,255,255,0)");
                    ctx.fillStyle = g;
                    ctx.beginPath();
                    ctx.arc(s[0], s[1], r, 0, 2 * Math.PI);
                    ctx.fill();
                }
                stamps = [];
            }
        }
        ShaderEffectSource {
            id: wipeSrc
            sourceItem: mask
            hideSource: true
            live: true
            visible: false
            smooth: true
        }

        // the picture: redrawn only when level / frost step
        ShaderEffect {
            id: picture
            anchors.fill: parent
            blending: true
            fragmentShader: Qt.resolvedUrl("shaders/snowcover.frag.qsb")
            property size itemSize: Qt.size(width, height)
            property real level: win.level
            property real frost: win.frost
            property real seed: 17.3
            property color snowColor: Theme.light ? "#fbfdff" : "#eef4fc"
            property color shadeColor: Theme.light ? "#cfdbea" : "#a9b9d3"
            property color frostColor: Theme.light ? "#ffffff" : "#e8f1ff"
        }
        ShaderEffectSource {
            id: pictureSrc
            sourceItem: picture
            hideSource: true
            live: true
            visible: false
        }
        // on screen: the picture minus the wiped parts
        ShaderEffect {
            anchors.fill: parent
            blending: true
            fragmentShader: Qt.resolvedUrl("shaders/snowwipe.frag.qsb")
            property var src: pictureSrc
            property var wipe: wipeSrc
            property color bankColor: Theme.light ? "#ffffff" : "#f4f8ff"
        }
    }
}
