// Three dots bouncing in turn — "working on it" (connecting, pairing).
import QtQuick

Row {
    id: dots
    property color color: Theme.accent
    property real size: 4
    spacing: 3
    Repeater {
        model: 3
        Rectangle {
            id: dot
            required property int index
            width: dots.size
            height: dots.size
            radius: dots.size / 2
            color: dots.color
            opacity: 0.3
            SequentialAnimation on opacity {
                running: dots.visible
                loops: Animation.Infinite
                PauseAnimation { duration: dot.index * 160 }
                NumberAnimation { to: 1; duration: 280 }
                NumberAnimation { to: 0.3; duration: 280 }
                PauseAnimation { duration: (2 - dot.index) * 160 }
            }
        }
    }
}
