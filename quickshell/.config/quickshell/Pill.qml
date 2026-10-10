// One bar module: a 32px rounded pill with a label, hover state, tooltip and
// mouse handling. Everything on both bars is built from this (waybar's
// `padding: 0 9px; margin: 4px 1px; border-radius: 8px` look).
//
// Children are placed inside, after the label; set `label: ""` to draw
// something else entirely.
import QtQuick
import Quickshell

Item {
    id: pill

    property string label
    property color fg: Theme.text
    property color bg: "transparent"
    // Hover: either a quiet surface fill (default) or a filled accent pill
    // (`hoverFill`, the "button" modules: power, tasks, wallpaper…).
    property color hoverFg: fg
    property color hoverBg: Theme.alpha(Theme.surface0, 0.9)
    property bool interactive: true
    property real fontSize: 13
    property int fontWeight: Font.DemiBold
    property int padLeft: 9
    property int padRight: 9
    property int marginH: 1
    property string tip
    property int tipEdge: Edges.Bottom
    property bool shown: true
    // 0–1 draws a thin progress line along the pill's bottom edge (downloads)
    property real progress: -1
    property color progressColor: fg
    default property alias content: inner.data

    readonly property bool hovered: mouse.containsMouse
    readonly property alias pressed: mouse.pressed
    readonly property alias labelItem: text

    signal clicked(int button)
    signal scrolled(int dir)

    visible: shown
    implicitHeight: 32
    implicitWidth: shown ? body.width + 2 * marginH : 0

    Rectangle {
        id: body
        x: pill.marginH
        height: 32
        width: Math.max(text.visible ? text.implicitWidth : 0, inner.childrenRect.width) + pill.padLeft + pill.padRight
        radius: 8
        color: pill.interactive && mouse.containsMouse ? pill.hoverBg : pill.bg
        Behavior on color { ColorAnimation { duration: Theme.fast; easing.type: Easing.OutQuint } }
        Behavior on width { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }

        Text {
            id: text
            visible: pill.label !== ""
            x: pill.padLeft
            anchors.verticalCenter: parent.verticalCenter
            text: pill.label
            textFormat: Text.StyledText
            color: pill.interactive && mouse.containsMouse ? pill.hoverFg : pill.fg
            font.family: Theme.font
            font.pixelSize: pill.fontSize
            font.weight: pill.fontWeight
            Behavior on color { ColorAnimation { duration: Theme.fast; easing.type: Easing.OutQuint } }
        }

        Rectangle {
            visible: pill.progress >= 0
            x: 7
            y: parent.height - 4
            width: parent.width - 14
            height: 2
            radius: 1
            color: Theme.alpha(Theme.surface1, 0.9)
            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, pill.progress))
                height: parent.height
                radius: 1
                color: pill.progressColor
                Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
            }
        }

        Item {
            id: inner
            x: pill.padLeft
            height: parent.height
            width: childrenRect.width
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: body
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        cursorShape: pill.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: ev => pill.clicked(ev.button)
        // One step per wheel notch; a touchpad's many small deltas add up.
        property real acc: 0
        onWheel: wheel => {
            acc += Theme.wheelDelta(wheel);
            while (Math.abs(acc) >= 120) {
                pill.scrolled(acc > 0 ? 1 : -1);
                acc -= acc > 0 ? 120 : -120;
            }
        }
    }

    Tooltip {
        target: body
        text: pill.tip
        shown: mouse.containsMouse
        edge: pill.tipEdge
    }
}
