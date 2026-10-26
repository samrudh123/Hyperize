// A small audio spectrum beside the laptop's player (hypr/visualizer.py:
// the speakers' monitor through pw-record, ~30 lines a second).
//
// Runs only while `active` (a laptop player is playing), in the player's
// colour. Bars grow from the middle, and fold away when the music stops.
//
// `fake: true` (the phone pill): the phone's audio plays on the phone, so
// there is nothing to listen to — the bars dance to a made-up beat instead.
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: vis

    property bool active: false
    property color tint: Theme.accent
    property int bars: 12
    property int barWidth: 3
    property int gap: 2
    property int maxHeight: 18

    property bool fake: false
    property var levels: []
    readonly property bool shown: active

    visible: width > 0.5
    implicitHeight: 32
    // where implicitWidth is heading (BottomBar.qml's title room)
    readonly property real targetWidth: shown ? bars * barWidth + (bars - 1) * gap + 12 : 0
    implicitWidth: targetWidth
    width: implicitWidth
    clip: true
    Behavior on implicitWidth { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }

    Row {
        x: 6
        anchors.verticalCenter: parent.verticalCenter
        spacing: vis.gap
        Repeater {
            model: vis.bars
            Rectangle {
                required property int index
                readonly property real v: (vis.levels[index] || 0) / 100
                anchors.verticalCenter: parent.verticalCenter
                width: vis.barWidth
                height: Math.max(vis.barWidth, v * vis.maxHeight)
                radius: vis.barWidth / 2
                color: vis.tint
                opacity: 0.55 + 0.45 * v
                Behavior on height { NumberAnimation { duration: 60 } }
            }
        }
    }

    // made-up music: a ~120 bpm kick that hits the low bars, a softer
    // off-beat for the mids, and a random walk per bar so it never repeats
    property real beat: 0
    property var walk: []
    property var fakeLv: []
    Timer {
        interval: 33
        repeat: true
        running: vis.active && vis.fake
        onRunningChanged: if (!running) { vis.levels = []; vis.fakeLv = []; }
        onTriggered: {
            const n = vis.bars;
            let walk = vis.walk.length === n ? vis.walk : Array.from({ length: n }, () => Math.random());
            let lv = vis.fakeLv.length === n ? vis.fakeLv : new Array(n).fill(0);
            vis.beat = (vis.beat + 0.033 / 0.5) % 1;
            const kick = Math.exp(-vis.beat * 7);
            const snare = Math.exp(-((vis.beat + 0.5) % 1) * 9) * (Math.random() < 0.85 ? 1 : 0);
            for (let i = 0; i < n; i++) {
                walk[i] = Math.min(1, Math.max(0.1, walk[i] + (Math.random() - 0.5) * 0.3));
                const low = 1 - i / (n - 1);
                const mid = 1 - Math.abs(i / (n - 1) - 0.5) * 2;
                const target = Math.min(1, 0.15 + 0.45 * walk[i] * (0.6 + 0.4 * Math.random())
                                           + 0.55 * kick * low + 0.35 * snare * mid);
                lv[i] = target > lv[i] ? target : lv[i] * 0.82;
            }
            vis.walk = walk;
            vis.fakeLv = lv;
            vis.levels = lv.map(v => Math.round(v * 100));
        }
    }

    Process {
        id: feed
        running: vis.active && !vis.fake
        command: ["/usr/bin/python3", Theme.hypr + "/visualizer.py", String(vis.bars)]
        stdout: SplitParser {
            onRead: line => { vis.levels = line.trim().split(" ").map(Number); }
        }
        onRunningChanged: if (!running) vis.levels = []
    }
}
