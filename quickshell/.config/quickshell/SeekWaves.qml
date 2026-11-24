// Waves above a seek line: the line stays straight; over its played part
// (start → playhead) translucent waves rise from it and sweep slowly, at an
// even pace, from the start to the playhead and back again, full height
// wherever the playhead is. Paused, they sink back into the line.
//
//   level   laptop loudness 0..1 (NowPlaying's visualizer feed): louder =
//           taller and quicker. -1 = no audio here (the phone's plays on the
//           phone): a gentle rolling loop instead.
//
// Put it right above the line — bottom edge on the line's top — and as wide
// as the line, e.g. inside a Slider:
//     SeekWaves { anchors.bottom: parent.verticalCenter; width: parent.width
//                 height: 16; frac: seek.shown; playing: np.playing; color: tint }
//
// Used by the bottom-bar player (NowPlaying.qml), the music panel
// (MediaPopup.qml) and the players deck (PlayersColumn.qml). Drawn by
// shaders/seekwaves.frag. One 30 fps timer, running only while its window
// is up (`active`) and it plays or is still settling: paused costs nothing.
import QtQuick

ShaderEffect {
    id: sw

    property real frac: 0
    property bool playing: false
    property real level: -1
    property color color: Theme.accent
    property bool active: true                // its window is open (Item.visible doesn't know)
    property real scale: 1                    // wavelength scale (bar: smaller)
    property real crest: 0.85
    // the second layer: wavelength (px at scale 1) and how far its pattern
    // sits from the front one's (radians). The bar uses the front's own
    // wavelength half a wave off (π), so the two counter-moving layers
    // interleave crest-in-trough and read apart even in 8 px
    property real lambda1: 40
    property real gap: 2.8
    property real third: 1                    // the faint back layer (0 = off)
    // how much height each layer keeps in its troughs (lower = separate
    // bumps with dips down to the line)
    property real floorH: 0.3

    property real amp: 0
    property real t: 0                        // seconds, for the phone's breathing
    // the sweep: each layer's phase (cycles) and position 0..1 for the shader
    property real p0: 0
    property real p1: 0.5                     // always half a cycle behind p0
    property real p2: 0.25
    property real s0: 0
    property real s1: 0
    property real s2: 0

    // 0 → 1 → 0 over one cycle at an even pace, easing only at the two
    // turns (a triangle with rounded tips — a plain cosine would rush
    // through the middle and dawdle at the ends)
    function pace(ph) {
        const k = 0.88;                       // closer to 1 = sharper turns
        const v = 1 - 2 * Math.acos(k * Math.sin(2 * Math.PI * ph)) / Math.PI;
        const vmax = 1 - 2 * Math.acos(k) / Math.PI;
        return 0.5 + 0.5 * v / vmax;
    }

    Timer {
        interval: 33
        repeat: true
        running: sw.active && sw.visible && sw.width > 0 && (sw.playing || sw.amp > 0.01)
        onTriggered: {
            const dt = interval / 1000;
            const listen = sw.level >= 0;
            const lv = listen ? sw.level : 0;
            sw.t = (sw.t + dt) % 3600;
            // slow, even travel: about 28 px a second (× scale) along the
            // played part, never quicker than one round trip in 8 s; the
            // second layer mirrors the first (half a cycle apart), the faint
            // back one drifts on its own, slower. Louder music: a little quicker
            const xs = Math.max(1, sw.width * sw.frac);
            const boost = listen ? 0.9 + 0.3 * lv : 1;
            const rate = (v, pmin) => boost / Math.max(pmin, 2 * xs / (v * sw.scale));
            sw.p0 = (sw.p0 + dt * rate(28, 8)) % 1;
            sw.p1 = (sw.p0 + 0.5) % 1;      // opposite: one heads out while the other comes back
            sw.p2 = (sw.p2 + dt * rate(16, 13)) % 1;
            sw.s0 = sw.pace(sw.p0);
            sw.s1 = sw.pace(sw.p1);
            sw.s2 = sw.pace(sw.p2);
            const target = !sw.playing ? 0
                         : listen ? 0.75 + 0.25 * lv
                         : 0.85 + 0.1 * Math.sin(sw.t * Math.PI / 2);    // 4 s breath
            sw.amp += (target - sw.amp) * (target > sw.amp ? 0.3 : 0.12);
            if (!sw.playing && sw.amp < 0.01) sw.amp = 0;      // settled: the timer stops
        }
    }

    property vector2d itemSize: Qt.vector2d(width, height)
    property color waveColor: color
    Behavior on waveColor { ColorAnimation { duration: Theme.fast } }
    fragmentShader: Qt.resolvedUrl("shaders/seekwaves.frag.qsb")
}
