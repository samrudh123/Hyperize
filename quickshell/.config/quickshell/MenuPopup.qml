// A themed popup card for menus. Put MenuRows inside; call open(item) to
// show it beside `item` and close() to hide it. Clicking anywhere outside
// closes it (Hyprland focus grab), as does Escape.
import QtQuick
import Quickshell
import Quickshell.Hyprland

PopupWindow {
    id: menu

    property int edge: Edges.Bottom
    property int minWidth: 190
    default property alias rows: column.data
    property bool isOpen: false

    signal dismissed()

    function open(item) {
        anchor.item = item;
        isOpen = true;
    }

    function close() {
        if (!isOpen) return;
        isOpen = false;
        dismissed();
    }

    visible: isOpen
    color: "transparent"

    anchor.rect.x: !anchor.item ? 0 : edge === Edges.Right ? anchor.item.width + 8 : anchor.item.width / 2
    anchor.rect.y: !anchor.item ? 0 : edge === Edges.Bottom ? anchor.item.height + 6
                 : edge === Edges.Top ? -6 : anchor.item.height / 2
    anchor.gravity: edge

    implicitWidth: Math.max(minWidth, column.naturalWidth) + 2 * 5
    implicitHeight: column.implicitHeight + 2 * 5

    HyprlandFocusGrab {
        active: menu.isOpen
        windows: [menu]
        onCleared: menu.close()
    }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: 12
        color: Theme.alpha(Theme.mantle, 0.97)
        border.width: 1
        border.color: Theme.surface1

        // a quick fade + slide in
        opacity: menu.isOpen ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }

        focus: true
        Keys.onEscapePressed: menu.close()

        Column {
            id: column
            x: 5
            y: 5
            width: parent.width - 10
            spacing: 1
            readonly property real naturalWidth: {
                let w = 0;
                for (const c of children) w = Math.max(w, c.implicitWidth || 0);
                return w;
            }
        }
    }
}
