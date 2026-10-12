// A small audio spectrum beside the laptop's player (hypr/visualizer.py:
// the speakers' monitor through pw-record, ~30 lines a second).
//
// Runs only while `active` (a laptop player is playing), in the player's
// colour; the phone's audio plays on the phone, so it has none. Bars grow
// from the middle, and fold away when the music stops.
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

    property var levels: []
    readonly property bool shown: active

    visible: width > 0.5
    implicitHeight: 32
    implicitWidth: shown ? bars * barWidth + (bars - 1) * gap + 12 : 0
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

    Process {
        id: feed
        running: vis.active
        command: ["/usr/bin/python3", Theme.hypr + "/visualizer.py", String(vis.bars)]
        stdout: SplitParser {
            onRead: line => { vis.levels = line.trim().split(" ").map(Number); }
        }
        onRunningChanged: if (!running) vis.levels = []
    }
}
