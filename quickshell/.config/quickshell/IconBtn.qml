// A square-ish icon (or icon + text) button for the panels. `active` fills
// it in `fg` with dark text (a toggled-on state); hover fills it softly.
//
//     IconBtn { icon: "\u{f04ae}"; tip: "Previous"; onClicked: … }
import QtQuick
import Quickshell

Rectangle {
    id: btn

    property string icon
    property string text
    property color fg: Theme.subtext0
    property color activeFg: Theme.accent
    property bool active: false
    property real size: 34
    property real iconSize: 16
    property string tip
    property int tipEdge: Edges.Bottom
    property bool enabled: true
    readonly property bool hovered: ma.containsMouse

    signal clicked(int button)

    // keyboard (Tab to it; Enter / Space press it) — see PanelPopup.navKey
    activeFocusOnTab: enabled && visible && opacity > 0.05
    function kbActivate() { if (enabled) clicked(Qt.LeftButton); }
    Keys.onPressed: ev => {
        if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter || ev.key === Qt.Key_Space) {
            kbActivate();
            ev.accepted = true;
        }
    }

    implicitWidth: text ? row.implicitWidth + 22 : size
    implicitHeight: size
    radius: Math.min(10, height / 2)
    opacity: enabled ? 1 : 0.4
    color: active ? (hovered ? Qt.lighter(activeFg, 1.08) : activeFg)
         : hovered ? Theme.alpha(Theme.surface1, 0.9) : Theme.alpha(Theme.surface0, 0.75)
    Behavior on color { ColorAnimation { duration: Theme.fast; easing.type: Easing.OutQuint } }

    scale: ma.pressed ? 0.92 : 1
    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 7
        Text {
            visible: btn.icon !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: btn.icon
            color: btn.active ? Theme.crust : btn.hovered ? Theme.text : btn.fg
            font.family: Theme.font
            font.pixelSize: btn.iconSize
        }
        Text {
            visible: btn.text !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: btn.text
            color: btn.active ? Theme.crust : btn.hovered ? Theme.text : btn.fg
            font.family: Theme.font
            font.pixelSize: 12
            font.weight: Font.DemiBold
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        enabled: btn.enabled
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        onClicked: ev => btn.clicked(ev.button)
    }

    Tooltip {
        target: btn
        text: btn.tip
        shown: ma.containsMouse
        edge: btn.tipEdge
    }
    FocusRing {}
}
