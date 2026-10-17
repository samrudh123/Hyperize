// One row of a themed popup menu (tray menus, the dock's right-click menu).
import QtQuick
import Quickshell
import Quickshell.Widgets

Item {
    id: row

    property string text
    property string glyph              // Nerd Font glyph, or…
    property string iconSource         // …an image (tray menus)
    property color glyphColor: Theme.subtext0
    property bool separator: false
    property bool enabled: true
    property bool header: false        // a non-clickable title row
    property int check: -1             // -1 none, 0 unchecked, 1 checked (checkbox / radio)
    property bool submenu: false
    property bool danger: false
    property bool removable: false     // a trash button at the end, on hover

    signal activated()
    signal removed()

    width: parent ? parent.width : 200
    implicitWidth: (separator ? 0 : label.implicitWidth) + 30 + 28 + (submenu ? 18 : 0)
    implicitHeight: separator ? 9 : header ? 30 : 32

    Rectangle {
        visible: row.separator
        anchors.centerIn: parent
        width: parent.width - 16
        height: 1
        color: Theme.alpha(Theme.surface1, 0.9)
    }

    Rectangle {
        visible: !row.separator
        anchors.fill: parent
        radius: 8
        color: mouse.containsMouse && row.enabled && !row.header
               ? (row.danger ? Theme.alpha(Theme.red, 0.18) : Theme.alpha(Theme.surface0, 0.95))
               : Theme.alpha(Theme.surface0, 0)
        Behavior on color { ColorAnimation { duration: 120; easing.type: Easing.OutQuint } }

        // check mark / radio dot, else the icon
        Item {
            id: lead
            x: 8
            width: 18
            height: parent.height

            Text {
                anchors.centerIn: parent
                visible: row.check >= 0 || (row.glyph !== "" && row.iconSource === "")
                text: row.check === 1 ? "\u{f012c}" : row.check === 0 ? "" : row.glyph
                color: row.check >= 0 ? Theme.accent : row.danger ? Theme.red : row.glyphColor
                font.family: Theme.font
                font.pixelSize: 15
            }
            IconImage {
                anchors.centerIn: parent
                visible: row.check < 0 && row.iconSource !== ""
                implicitSize: 16
                source: row.iconSource
            }
        }

        Text {
            id: label
            x: 34
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - x - (row.submenu ? 28 : row.removable ? 34 : 10)
            elide: Text.ElideRight
            text: row.text
            color: !row.enabled ? Theme.overlay0
                 : row.header ? Theme.subtext0
                 : row.danger && mouse.containsMouse ? Theme.red : Theme.text
            font.family: row.header ? Theme.font : Theme.uiFont
            font.pixelSize: row.header ? 12 : 13
            font.weight: row.header ? Font.Bold : Font.Medium
        }

        Text {
            visible: row.submenu
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: "\u{f0142}"          // md-chevron_right
            color: Theme.overlay2
            font.family: Theme.font
            font.pixelSize: 14
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        enabled: !row.separator && !row.header
        hoverEnabled: true
        cursorShape: row.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (row.enabled) row.activated()

        // a child of the row's MouseArea: on top of it (a click here doesn't
        // activate the row), and the row keeps its hover while over it
        MouseArea {
            id: del
            visible: row.removable && !row.separator && !row.header
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            width: 26
            height: 24
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: row.removed()

            Rectangle {
                anchors.fill: parent
                radius: 6
                color: Theme.alpha(Theme.red, del.containsMouse ? 0.2 : 0)
                Behavior on color { ColorAnimation { duration: 120; easing.type: Easing.OutQuint } }
            }
            Text {
                anchors.centerIn: parent
                text: "\u{f0a7a}"         // md-trash_can_outline
                color: del.containsMouse ? Theme.red : Theme.overlay2
                opacity: mouse.containsMouse || del.containsMouse ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 120 } }
                font.family: Theme.font
                font.pixelSize: 14
            }
        }
    }
}
