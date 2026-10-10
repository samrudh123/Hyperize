// A styled tooltip for one item. Drop it inside the item:
//
//     Tooltip { target: parent; text: "…"; shown: mouse.containsMouse }
//
// `text` is StyledText (Theme.pango() converts script markup). `edge` is the
// side of the target it opens on: Edges.Bottom (top bar), Edges.Top (bottom
// bar), Edges.Right (dock).
import QtQuick
import Quickshell

PopupWindow {
    id: tip

    required property Item target
    property string text
    property bool shown: false
    property int edge: Edges.Bottom
    property int delay: 450

    // Waits `delay` before opening; closes at once.
    property bool open: false
    onShownChanged: {
        if (shown && text) timer.restart();
        else { timer.stop(); open = false; }
    }
    onTextChanged: if (!text) open = false

    Timer {
        id: timer
        interval: tip.delay
        onTriggered: tip.open = tip.shown && tip.text !== ""
    }

    visible: open && target.visible
    color: "transparent"

    anchor.item: target
    anchor.rect.x: edge === Edges.Right ? target.width + 10 : target.width / 2
    anchor.rect.y: edge === Edges.Bottom ? target.height + 6
                 : edge === Edges.Top ? -6 : target.height / 2
    anchor.gravity: edge

    implicitWidth: Math.min(label.implicitWidth, 460) + 2 * 11
    implicitHeight: label.implicitHeight + 2 * 7

    Rectangle {
        anchors.fill: parent
        radius: 10
        color: Theme.alpha(Theme.mantle, 0.97)
        border.width: 1
        border.color: Theme.surface1

        Text {
            id: label
            x: 11
            y: 7
            width: Math.min(implicitWidth, 460)
            text: tip.text
            textFormat: Text.StyledText
            wrapMode: Text.Wrap
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: 12
            lineHeight: 1.15
        }
    }
}
