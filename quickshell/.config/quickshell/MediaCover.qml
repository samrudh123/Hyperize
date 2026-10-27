// The music panel's record: the cover art cut round, spinning slowly like
// a vinyl while it plays (a spindle hole in the middle), inside a ring of
// spectrum bars.
//
// The ring listens to the laptop's audio (hypr/visualizer.py, the speakers'
// monitor) while `listen` is on — the panel is open and a laptop player is
// playing. A phone player's audio plays on the phone, so `fake` makes the
// bars dance to a made-up beat instead (like the bottom bar's phone spectrum).
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io

Item {
    id: rec

    property string art
    property color tint: Theme.accent
    property bool playing: false
    property bool listen: false
    property bool fake: false
    property int bars: 56
    property real coverSize: 148

    implicitWidth: coverSize + 2 * 34
    implicitHeight: implicitWidth

    property var levels: []

    // ── the ring ────────────────────────────────────────────────────────────
    Item {
        id: ring
        anchors.centerIn: parent
        width: rec.coverSize + 16
        height: width
        Repeater {
            model: rec.bars
            Item {
                required property int index
                readonly property real v: (rec.levels[index % rec.levels.length] || 0) / 100
                width: ring.width
                height: ring.height
                rotation: index * 360 / rec.bars
                Rectangle {
                    x: ring.width / 2 - width / 2
                    // grows outwards from just outside the cover
                    y: -height + 3
                    width: 3
                    height: 3 + parent.v * 22
                    radius: 1.5
                    color: rec.tint
                    opacity: 0.35 + 0.65 * parent.v
                    Behavior on height { NumberAnimation { duration: 70 } }
                }
            }
        }
    }

    // ── the record ──────────────────────────────────────────────────────────
    Rectangle {
        id: disc
        anchors.centerIn: parent
        width: rec.coverSize
        height: width
        radius: width / 2
        color: Theme.surface0
        border.width: 2
        border.color: Theme.alpha(rec.tint, 0.5)

        Text {
            anchors.centerIn: parent
            visible: img.status !== Image.Ready
            text: "\u{f075a}"                       // md-music_note
            color: Theme.alpha(rec.tint, 0.7)
            font.family: Theme.font
            font.pixelSize: 56
        }

        Item {
            id: spinner
            anchors.fill: parent
            anchors.margins: 2

            Image {
                id: img
                anchors.fill: parent
                source: rec.art
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                smooth: true
                mipmap: true
                sourceSize.width: 320
                sourceSize.height: 320
                visible: false
            }
            Rectangle {
                id: mask
                anchors.fill: parent
                radius: width / 2
                visible: false
                layer.enabled: true
            }
            MultiEffect {
                anchors.fill: parent
                source: img
                visible: img.status === Image.Ready
                maskEnabled: true
                maskSource: mask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1
            }

            // grooves
            Repeater {
                model: 3
                Rectangle {
                    required property int index
                    anchors.centerIn: parent
                    width: parent.width * (0.86 - index * 0.16)
                    height: width
                    radius: width / 2
                    color: "transparent"
                    border.width: 1
                    border.color: Qt.rgba(0, 0, 0, 0.18)
                }
            }

            NumberAnimation on rotation {
                from: 0; to: 360
                duration: 16000
                loops: Animation.Infinite
                running: rec.listen
                paused: running && !rec.playing
            }
        }

        // the label and spindle hole
        Rectangle {
            anchors.centerIn: parent
            width: 34
            height: 34
            radius: 17
            color: Theme.alpha(Theme.mantle, 0.92)
            border.width: 2
            border.color: Theme.alpha(rec.tint, 0.8)
            Rectangle {
                anchors.centerIn: parent
                width: 8
                height: 8
                radius: 4
                color: rec.tint
            }
        }
    }

    // ── levels ──────────────────────────────────────────────────────────────
    // the real thing: 28 bands, mirrored round the ring (low at the top)
    readonly property int half: Math.floor(bars / 2)
    Process {
        id: feed
        running: rec.listen && !rec.fake && rec.playing
        command: ["/usr/bin/python3", Theme.hypr + "/visualizer.py", String(rec.half)]
        stdout: SplitParser {
            onRead: line => {
                const v = line.trim().split(" ").map(Number);
                rec.levels = v.concat(v.slice().reverse());
            }
        }
        onRunningChanged: if (!running) decay.start()
    }

    // made-up beat (phone players): ~120 bpm, low bands on the kick
    property real beat: 0
    property var walk: []
    Timer {
        interval: 40
        repeat: true
        running: rec.listen && rec.fake && rec.playing
        onRunningChanged: if (!running) decay.start()
        onTriggered: {
            const n = rec.half;
            const w = rec.walk.length === n ? rec.walk : Array.from({ length: n }, () => Math.random());
            rec.beat = (rec.beat + 0.04 / 0.5) % 1;
            const kick = Math.exp(-rec.beat * 7);
            const out = [];
            for (let i = 0; i < n; i++) {
                w[i] = Math.min(1, Math.max(0.05, w[i] + (Math.random() - 0.5) * 0.25));
                const low = 1 - i / (n - 1);
                out.push(Math.round(100 * Math.min(1, 0.1 + 0.4 * w[i] * Math.random() + 0.6 * kick * low)));
            }
            rec.walk = w;
            rec.levels = out.concat(out.slice().reverse());
        }
    }

    // stop: bars fall back down
    Timer {
        id: decay
        interval: 40
        repeat: true
        onTriggered: {
            const lv = rec.levels.map(v => Math.floor(v * 0.7));
            rec.levels = lv;
            if (lv.every(v => v < 2)) { rec.levels = []; stop(); }
        }
    }
}
