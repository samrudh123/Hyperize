// The music panel's equalizer: presets, ten band sliders (±12 dB) over a
// smooth response curve, on/off. Drives hypr/eq.py (`serve` on stdin while
// the panel is open), which sets the PipeWire filter-chain rice-eq
// (~/.config/pipewire/rice-eq.conf, rice-eq.service) and saves the state.
//
//   drag a band    set it          scroll    ±0.5 dB
//   double-click   back to 0 dB    preset    all ten at once
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: eq

    property bool active: false            // the panel is open
    property color tint: Theme.accent

    property var bands: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
    property var freqs: [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    property var presets: ["Flat", "Bass", "Treble", "Vocal", "Pop", "Rock", "Jazz", "Classic"]
    property string preset: "Flat"
    property bool eqOn: true
    property bool live: true
    readonly property real headroom: Math.max(0, Math.max.apply(null, bands))
    property int dragging: -1               // a band being dragged: ignore echoes for it

    function send(line) { if (srv.running) srv.write(line + "\n"); }
    function setBand(i, db) {
        db = Math.round(Math.max(-12, Math.min(12, db)) * 2) / 2;
        if (bands[i] === db) return;
        const b = bands.slice();
        b[i] = db;
        bands = b;
        pending[i] = db;
        flush.restart();
    }
    property var pending: ({})
    // at most one write per 40 ms while dragging
    Timer {
        id: flush
        interval: 40
        onTriggered: {
            for (const k in eq.pending) eq.send("set " + (Number(k) + 1) + " " + eq.pending[k]);
            eq.pending = {};
        }
    }

    Process {
        id: srv
        running: eq.active
        stdinEnabled: true
        command: ["/usr/bin/python3", Theme.hypr + "/eq.py", "serve"]
        stdout: SplitParser {
            onRead: line => {
                let s;
                try { s = JSON.parse(line); } catch (e) { return; }
                if (eq.dragging < 0 && Object.keys(eq.pending).length === 0) eq.bands = s.bands;
                eq.preset = s.preset;
                eq.eqOn = s.enabled;
                eq.live = s.live;
                if (s.freqs) eq.freqs = s.freqs;
                if (s.presets) eq.presets = s.presets;
            }
        }
    }

    function fmtF(f) { return f >= 1000 ? (f / 1000) + "k" : String(f); }
    function fmtDb(v) { return (v > 0 ? "+" : v < 0 ? "−" : "") + Math.abs(v).toFixed(Math.abs(v) % 1 ? 1 : 0); }

    Column {
        anchors.fill: parent
        spacing: 12

        // presets
        Row {
            spacing: 6
            anchors.horizontalCenter: parent.horizontalCenter
            Repeater {
                model: eq.presets.concat(eq.preset === "Custom" ? ["Custom"] : [])
                Rectangle {
                    required property string modelData
                    readonly property bool on: eq.preset === modelData
                    width: lbl.implicitWidth + 18
                    height: 26
                    radius: 8
                    color: on ? eq.tint : pma.containsMouse ? Theme.alpha(Theme.surface1, 0.9) : Theme.alpha(Theme.surface0, 0.75)
                    Behavior on color { ColorAnimation { duration: Theme.fast } }
                    Text {
                        id: lbl
                        anchors.centerIn: parent
                        text: parent.modelData
                        color: parent.on ? Theme.crust : pma.containsMouse ? Theme.text : Theme.subtext0
                        font.family: Theme.font
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }
                    MouseArea {
                        id: pma
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: parent.modelData === "Custom" ? Qt.ArrowCursor : Qt.PointingHandCursor
                        onClicked: if (parent.modelData !== "Custom") {
                            eq.send("preset " + parent.modelData);
                            eq.preset = parent.modelData;
                        }
                    }
                }
            }
        }

        // the bands
        Item {
            id: graph
            width: parent.width
            height: 196
            opacity: eq.eqOn ? 1 : 0.4
            Behavior on opacity { NumberAnimation { duration: Theme.normal } }

            readonly property real colW: width / 10
            readonly property real topPad: 22               // dB label above
            readonly property real trackH: height - topPad - 26
            function yOf(db) { return topPad + trackH * (1 - (db + 12) / 24); }

            // 0 dB line
            Rectangle {
                x: 6
                width: parent.width - 12
                y: graph.yOf(0)
                height: 1
                color: Theme.alpha(Theme.overlay0, 0.35)
            }

            // the response, through the band knobs
            Canvas {
                id: curve
                anchors.fill: parent
                property var pts: eq.bands
                property color col: eq.tint
                onPtsChanged: requestPaint()
                onColChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d");
                    ctx.reset();
                    const p = pts.map((v, i) => [graph.colW * (i + 0.5), graph.yOf(v)]);
                    const path = () => {
                        ctx.moveTo(0, p[0][1]);
                        ctx.lineTo(p[0][0], p[0][1]);
                        for (let i = 0; i < p.length - 1; i++) {
                            const mx = (p[i][0] + p[i + 1][0]) / 2;
                            ctx.bezierCurveTo(mx, p[i][1], mx, p[i + 1][1], p[i + 1][0], p[i + 1][1]);
                        }
                        ctx.lineTo(width, p[p.length - 1][1]);
                    };
                    // soft fill down to 0 dB
                    ctx.beginPath();
                    path();
                    ctx.lineTo(width, graph.yOf(0));
                    ctx.lineTo(0, graph.yOf(0));
                    ctx.closePath();
                    ctx.fillStyle = Qt.rgba(col.r, col.g, col.b, 0.13);
                    ctx.fill();
                    ctx.beginPath();
                    path();
                    ctx.lineWidth = 2;
                    ctx.strokeStyle = Qt.rgba(col.r, col.g, col.b, 0.85);
                    ctx.stroke();
                }
            }

            Repeater {
                model: 10
                Item {
                    id: col
                    required property int index
                    readonly property real v: eq.bands[index] || 0
                    x: graph.colW * index
                    width: graph.colW
                    height: graph.height

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: 0
                        text: eq.fmtDb(col.v)
                        color: col.v !== 0 ? eq.tint : Theme.overlay1
                        font.family: Theme.font
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }
                    // track
                    Rectangle {
                        id: tr
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: graph.topPad
                        width: bma.containsMouse || bma.pressed ? 8 : 6
                        height: graph.trackH
                        radius: width / 2
                        color: Theme.alpha(Theme.surface1, 0.55)
                        Behavior on width { NumberAnimation { duration: 120 } }
                        // filled from 0 dB to the value
                        Rectangle {
                            width: parent.width
                            radius: width / 2
                            readonly property real y0: graph.yOf(0) - graph.topPad
                            readonly property real y1: graph.yOf(col.v) - graph.topPad
                            y: Math.min(y0, y1)
                            height: Math.max(2, Math.abs(y1 - y0))
                            color: Theme.alpha(eq.tint, 0.55)
                        }
                    }
                    // knob
                    Rectangle {
                        property real d: bma.containsMouse || bma.pressed ? 18 : 14
                        width: d
                        height: d
                        radius: d / 2
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: graph.yOf(col.v) - d / 2
                        color: eq.tint
                        border.width: 3
                        border.color: Theme.mantle
                        Behavior on d { NumberAnimation { duration: 120 } }
                        Behavior on y { enabled: eq.dragging !== col.index; NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        text: eq.fmtF(eq.freqs[col.index])
                        color: bma.containsMouse ? Theme.text : Theme.subtext0
                        font.family: Theme.font
                        font.pixelSize: 11
                    }

                    MouseArea {
                        id: bma
                        anchors.fill: parent
                        anchors.topMargin: graph.topPad - 10
                        anchors.bottomMargin: 16
                        hoverEnabled: true
                        enabled: eq.eqOn
                        cursorShape: Qt.SizeVerCursor
                        function dbAt(y) {
                            return 12 - 24 * (y + bma.anchors.topMargin - graph.topPad) / graph.trackH;
                        }
                        onPressed: ev => { eq.dragging = col.index; eq.setBand(col.index, dbAt(ev.y)); }
                        onPositionChanged: ev => { if (pressed) eq.setBand(col.index, dbAt(ev.y)); }
                        onReleased: eq.dragging = -1
                        onDoubleClicked: eq.setBand(col.index, 0)
                        property real acc: 0
                        onWheel: wheel => {
                            acc += Theme.wheelDelta(wheel);
                            while (Math.abs(acc) >= 120) {
                                eq.setBand(col.index, col.v + (acc > 0 ? 0.5 : -0.5));
                                acc -= acc > 0 ? 120 : -120;
                            }
                        }
                    }
                }
            }
        }

        // on/off · preamp · reset
        Item {
            width: parent.width
            height: 28
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                Toggle {
                    anchors.verticalCenter: parent.verticalCenter
                    checked: eq.eqOn
                    accent: eq.tint
                    onToggled: v => { eq.eqOn = v; eq.send(v ? "on" : "off"); }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: !eq.live ? "Equalizer service not running"
                        : !eq.eqOn ? "Bypassed"
                        : eq.headroom > 0 ? "On  ·  preamp −" + eq.headroom.toFixed(1) + " dB" : "On"
                    color: eq.live ? Theme.subtext0 : Theme.red
                    font.family: Theme.font
                    font.pixelSize: 12
                }
            }
            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                IconBtn {
                    visible: !eq.live
                    size: 28
                    icon: "\u{f040a}"
                    text: "Start"
                    tip: "systemctl --user start rice-eq.service"
                    tipEdge: Edges.Top
                    onClicked: {
                        Theme.exec("systemctl --user start rice-eq.service");
                        retry.start();
                    }
                }
                IconBtn {
                    size: 28
                    icon: "\u{f0450}"                 // md-restore
                    text: "Reset"
                    tip: "All bands back to 0 dB"
                    tipEdge: Edges.Top
                    onClicked: { eq.send("preset Flat"); eq.preset = "Flat"; }
                }
            }
        }
    }

    // after "Start": ask again once the service is up
    Timer { id: retry; interval: 1500; onTriggered: eq.send("apply") }
}
