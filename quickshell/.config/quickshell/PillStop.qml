// A keyboard stop on a pill that has no popup (keep-awake, power profile,
// wallpaper): an invisible 1 px PanelPopup, so Ctrl+← / → / ↑ / ↓ can land
// on the pill like on any other. While it is "open" the pill shows the hover
// highlight (Pill.navHot), Enter / Space do what a left click does, Esc
// leaves keyboard mode, and the focus grab keeps the keys on the bars.
//
//     PillStop { pill: awake }
import QtQuick

PanelPopup {
    id: stop
    panelWidth: 1
    pad: 0
    implicitHeight: 1
    enterAction: () => { if (stop.pill) stop.pill.clicked(Qt.LeftButton); }
    // only the keyboard opens it; it draws nothing
    Component.onCompleted: {
        card.color = "transparent";
        card.border.width = 0;
    }
}
