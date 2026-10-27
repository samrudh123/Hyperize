// A key-cap chip (keybinding combos) or a small status chip.
import QtQuick

Rectangle {
    id: chip
    property string text
    property color fg: Theme.text
    property color bg: Theme.alpha(Theme.surface1, 0.8)
    property bool mono: true
    implicitWidth: Math.max(26, label.implicitWidth + 16)
    implicitHeight: 24
    radius: 7
    color: bg
    border.width: 1
    border.color: Theme.alpha(Theme.surface2, 0.6)
    Text {
        id: label
        anchors.centerIn: parent
        text: chip.text
        color: chip.fg
        font.family: Theme.font
        font.pixelSize: 11
        font.weight: Font.Bold
    }
}
