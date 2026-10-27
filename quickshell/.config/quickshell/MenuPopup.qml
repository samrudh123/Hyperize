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

    // bars included: see PanelPopup.qml
    HyprlandFocusGrab {
        active: menu.isOpen
        windows: [menu].concat(BarState.bars)
        onCleared: menu.close()
    }
    Connections {
        target: BarState
        enabled: menu.isOpen
        function onEscapePressed() { menu.close(); }
    }
    Shortcut {
        enabled: menu.isOpen
        sequences: ["Escape"]
        context: Qt.WindowShortcut
        onActivated: menu.close()
    }
    Connections {
        target: BarState
        enabled: menu.isOpen
        function onBarPressed(root, x, y) {
            if (!BarState.pressedOn(menu.anchor.item, root, x, y)) menu.close();
        }
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
        // keyboard: Tab / ↓ next row, Shift+Tab / ↑ previous (MenuRow: Enter picks)
        Keys.onPressed: ev => {
            const fwd = ev.key === Qt.Key_Down || (ev.key === Qt.Key_Tab && !(ev.modifiers & Qt.ShiftModifier));
            const back = ev.key === Qt.Key_Up || ev.key === Qt.Key_Backtab || (ev.key === Qt.Key_Tab && (ev.modifiers & Qt.ShiftModifier));
            if (!fwd && !back) return;
            let it = Window.activeFocusItem || card;
            for (let n = 0; n < 200; n++) {
                it = it.nextItemInFocusChain(fwd);
                if (it && it !== card && it.visible) { it.forceActiveFocus(); break; }
            }
            ev.accepted = true;
        }

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
