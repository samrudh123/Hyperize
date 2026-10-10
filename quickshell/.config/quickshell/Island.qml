// A group of bar modules. In the classic bar style it is just a Row (no
// background, no padding — the bar's own panel is the background). In the
// "islands" style (theme picker `b`, theme/bar-style) it becomes a detached
// rounded glass island, the wallpaper showing between islands.
import QtQuick

Item {
    id: isl

    default property alias content: row.data
    property alias spacing: row.spacing
    readonly property bool on: Theme.islands
    readonly property int pad: on ? 6 : 0

    width: row.width + 2 * pad
    height: on ? 34 : row.height

    Rectangle {
        anchors.fill: parent
        visible: isl.on
        radius: 12
        color: Theme.alpha(Theme.base, 0.86)
        border.width: 1
        border.color: Theme.alpha(Theme.surface1, 0.8)
    }

    Row {
        id: row
        x: isl.pad
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0
    }
}
