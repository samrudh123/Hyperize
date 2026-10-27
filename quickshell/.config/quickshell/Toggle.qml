// An on/off switch: accent track + white-ish knob when on, dim when off.
//
//     Toggle { checked: x; onToggled: v => … }
import QtQuick

Rectangle {
    id: tg

    property bool checked: false
    property color accent: Theme.accent
    property bool busy: false

    signal toggled(bool value)

    // keyboard: Tab to it, Enter / Space flips it
    activeFocusOnTab: visible
    function kbActivate() { toggled(!checked); }
    Keys.onPressed: ev => {
        if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter || ev.key === Qt.Key_Space) {
            kbActivate();
            ev.accepted = true;
        }
    }

    implicitWidth: 44
    implicitHeight: 24
    radius: height / 2
    color: checked ? accent : Theme.alpha(Theme.surface1, 0.9)
    Behavior on color { ColorAnimation { duration: Theme.fast } }

    Rectangle {
        id: knob
        width: parent.height - 6
        height: width
        radius: width / 2
        y: 3
        x: tg.checked ? parent.width - width - 3 : 3
        color: tg.checked ? Theme.crust : Theme.overlay2
        Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
        Behavior on color { ColorAnimation { duration: Theme.fast } }

        // pulses while the change is on its way
        SequentialAnimation on opacity {
            running: tg.busy
            loops: Animation.Infinite
            onRunningChanged: if (!running) knob.opacity = 1
            NumberAnimation { to: 0.35; duration: 400 }
            NumberAnimation { to: 1; duration: 400 }
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: tg.toggled(!tg.checked)
    }
    FocusRing {}
}
