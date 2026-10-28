// The capture panel (Serpantinum-style) under the top bar's camera pill
// (RecordPill.qml) — right-click it. Screenshots (screenshot.sh) and
// recording (screen-record.py: wf-recorder, or OBS while OBS is open).
//
//   header   camera orb (red and pulsing while recording) · state · time
//   stop     while recording: a big stop card with the running time
//   shoot    Region · Window · Screen
//   record   Screen · Region · Window (wf-recorder) · In OBS (when OBS is open)
//   sound    Desktop · Microphone · None (wf-recorder; OBS has its own mixer)
//   footer   Open OBS · Recordings folder
import QtQuick
import Quickshell

PanelPopup {
    id: pop

    property var rec: null                    // the RecordPill (st, run(), shot(), clock())
    edge: Edges.Bottom
    panelWidth: 440
    pad: 16

    readonly property bool recording: !!rec && rec.recording
    readonly property var st: rec ? rec.st : ({})
    readonly property color tint: recording ? (st.state === "paused" ? Theme.yellow : Theme.red) : Theme.flamingo

    function shot(mode) { close(); rec.shot(mode); }
    function record(args) { close(); rec.run(args); }

    function stage(k) { return Math.max(0, Math.min(1, (pop.intro - k * 0.12) / (1 - k * 0.12))); }

    component Tile: Rectangle {
        id: tile
        property string glyph
        property string label
        property color tint: Theme.flamingo
        property bool enabled_: true
        signal activated()
        readonly property bool lit: enabled_ && (tma.containsMouse || activeFocus || BarState.kbItem === tile)
        activeFocusOnTab: enabled_ && visible
        function kbActivate() { if (enabled_) activated(); }
        Keys.onPressed: ev => {
            if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter || ev.key === Qt.Key_Space) { kbActivate(); ev.accepted = true; }
        }
        height: 74
        radius: 14
        opacity: enabled_ ? 1 : 0.4
        color: lit ? Theme.alpha(tint, 0.2) : Theme.alpha(Theme.surface1, 0.45)
        border.width: 1
        border.color: Theme.alpha(tint, lit ? 0.6 : 0.15)
        Behavior on color { ColorAnimation { duration: Theme.fast } }
        scale: tma.pressed ? 0.95 : 1
        Behavior on scale { NumberAnimation { duration: 110 } }
        Column {
            anchors.centerIn: parent
            spacing: 5
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: tile.glyph; color: tile.tint; font.family: Theme.font; font.pixelSize: 22 }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: tile.label; color: Theme.text; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold }
        }
        MouseArea {
            id: tma
            anchors.fill: parent
            hoverEnabled: true
            enabled: tile.enabled_
            cursorShape: Qt.PointingHandCursor
            onClicked: tile.activated()
        }
        FocusRing {}
    }

    Column {
        width: parent.width
        spacing: 14

        // ── header ──────────────────────────────────────────────────────────
        Row {
            spacing: 12
            opacity: pop.stage(0)
            Item {
                width: 48
                height: 48
                Rectangle {
                    anchors.fill: parent
                    radius: 24
                    color: Theme.alpha(pop.tint, 0.18)
                    border.width: 2
                    border.color: Theme.alpha(pop.tint, 0.5)
                    SequentialAnimation on scale {
                        running: pop.isOpen && pop.recording && pop.st.state !== "paused"
                        loops: Animation.Infinite
                        NumberAnimation { to: 1.1; duration: 700; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1.0; duration: 700; easing.type: Easing.InOutSine }
                    }
                }
                Text {
                    anchors.centerIn: parent
                    text: pop.recording ? "\u{f044a}" : "\u{f0d5d}"
                    color: pop.tint
                    font.family: Theme.font
                    font.pixelSize: 22
                }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    text: pop.recording ? "Recording" + (pop.st.backend === "obs" ? " in OBS" : "") : "Capture"
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 17
                    font.weight: Font.Bold
                }
                Text {
                    text: pop.recording ? (pop.st.state === "paused" ? "paused · " : "") + (pop.rec ? pop.rec.clock(pop.st.elapsed || 0) : "")
                        : "screenshots ask where to save · videos go to Videos/Recordings"
                    color: pop.recording ? pop.tint : Theme.overlay1
                    font.family: Theme.font
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
            }
        }

        // ── recording: stop ─────────────────────────────────────────────────
        Rectangle {
            id: stopCard
            visible: pop.recording
            width: parent.width
            height: 64
            radius: 16
            readonly property bool lit: sma.containsMouse || activeFocus || BarState.kbItem === stopCard
            activeFocusOnTab: visible
            function kbActivate() { pop.record("stop"); }
            Keys.onPressed: ev => {
                if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter || ev.key === Qt.Key_Space) { kbActivate(); ev.accepted = true; }
            }
            color: lit ? pop.tint : Theme.alpha(pop.tint, 0.22)
            Behavior on color { ColorAnimation { duration: Theme.fast } }
            Row {
                anchors.centerIn: parent
                spacing: 12
                Text { anchors.verticalCenter: parent.verticalCenter; text: "\u{f04db}"; color: stopCard.lit ? Theme.crust : pop.tint; font.family: Theme.font; font.pixelSize: 24 }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Stop recording  ·  " + (pop.rec ? pop.rec.clock(pop.st.elapsed || 0) : "")
                    color: stopCard.lit ? Theme.crust : Theme.text
                    font.family: Theme.font
                    font.pixelSize: 14
                    font.weight: Font.Bold
                }
            }
            MouseArea {
                id: sma
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: pop.record("stop")
            }
            FocusRing {}
        }

        // ── screenshot ──────────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 6
            opacity: pop.stage(1)
            transform: Translate { y: 12 * (1 - pop.stage(1)) }
            Text { text: "SCREENSHOT"; color: Theme.overlay1; font.family: Theme.font; font.pixelSize: 10; font.weight: Font.Bold; font.letterSpacing: 1.2 }
            Row {
                id: shotRow
                width: parent.width
                spacing: 8
                Tile { width: (shotRow.width - 16) / 3; glyph: "\u{f019f}"; label: "Region"; onActivated: pop.shot("region") }
                Tile { width: (shotRow.width - 16) / 3; glyph: "\u{f05b2}"; label: "Window"; onActivated: pop.shot("window") }
                Tile { width: (shotRow.width - 16) / 3; glyph: "\u{f0379}"; label: "Screen"; onActivated: pop.shot("screen") }
            }
        }

        // ── record ──────────────────────────────────────────────────────────
        Column {
            visible: !pop.recording
            width: parent.width
            spacing: 6
            opacity: pop.stage(2)
            transform: Translate { y: 12 * (1 - pop.stage(2)) }
            Text { text: "RECORD"; color: Theme.overlay1; font.family: Theme.font; font.pixelSize: 10; font.weight: Font.Bold; font.letterSpacing: 1.2 }
            Row {
                id: recRow
                width: parent.width
                spacing: 8
                readonly property int n: pop.st.obs ? 4 : 3
                Tile { width: (recRow.width - (recRow.n - 1) * 8) / recRow.n; tint: Theme.red; glyph: "\u{f0379}"; label: "Screen"; enabled_: pop.st.wf !== false; onActivated: pop.record("start screen") }
                Tile { width: (recRow.width - (recRow.n - 1) * 8) / recRow.n; tint: Theme.red; glyph: "\u{f019f}"; label: "Region"; enabled_: pop.st.wf !== false; onActivated: pop.record("start region") }
                Tile { width: (recRow.width - (recRow.n - 1) * 8) / recRow.n; tint: Theme.red; glyph: "\u{f05b2}"; label: "Window"; enabled_: pop.st.wf !== false; onActivated: pop.record("start window") }
                Tile {
                    visible: pop.st.obs === true
                    width: (recRow.width - (recRow.n - 1) * 8) / recRow.n
                    tint: Theme.red
                    glyph: "\u{f0bdc}"
                    label: "In OBS"
                    enabled_: pop.st.obsReachable === true
                    onActivated: pop.record("obs start")
                }
            }
            // wf-recorder's sound (OBS uses its own mixer)
            Item {
                width: parent.width
                height: 32
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u{f057e}  Sound"
                    color: Theme.subtext0
                    font.family: Theme.font
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
                Segmented {
                    anchors.right: parent.right
                    width: 290
                    height: 30
                    readonly property var ids: ["desktop", "mic", "none"]
                    options: ["Desktop", "Microphone", "None"]
                    currentIndex: Math.max(0, ids.indexOf(pop.st.audio || "desktop"))
                    accent: Theme.red
                    onSelected: i => {
                        pop.rec.st = Object.assign({}, pop.rec.st, { audio: ids[i] });
                        pop.rec.run("audio " + ids[i]);
                    }
                }
            }
        }

        // ── footer ──────────────────────────────────────────────────────────
        Row {
            spacing: 8
            opacity: pop.stage(3)
            IconBtn {
                visible: !pop.st.obs
                icon: "\u{f0bdc}"
                text: "Open OBS"
                onClicked: { pop.close(); Theme.exec(Theme.hypr + "/focus-or-launch.sh obsproject /usr/bin/obs"); }
            }
            IconBtn {
                icon: "\u{f19fb}"
                text: "Recordings folder"
                // yazi in grid view (thumbnails)
                onClicked: { pop.close(); Theme.exec(Theme.home + "/.config/yazi/grid-open.sh " + Theme.home + "/Videos/Recordings"); }
            }
        }
    }
}
