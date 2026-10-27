// The keyboard-focus outline for the panels' controls (IconBtn, Toggle,
// Slider, Segmented, cards): an accent ring just outside the parent, shown
// while it has keyboard focus — real focus, or BarState.kbItem (keys the bar
// forwards while the pointer is over a popup; see PanelPopup.navKey).
//
//     FocusRing {}            // as the last child
import QtQuick

Rectangle {
    readonly property Item target: parent
    readonly property bool on: !!target && (target.activeFocus || BarState.kbItem === target)
    anchors.fill: parent
    anchors.margins: -3
    radius: (target && target.radius !== undefined ? target.radius : 8) + 3
    color: "transparent"
    border.width: 2
    border.color: Theme.accent
    opacity: on ? 1 : 0
    visible: opacity > 0
    z: 1000
    Behavior on opacity { NumberAnimation { duration: 110 } }
}
