// A horizontal slider: dim track, accent fill, a knob that grows on hover.
// `value` 0–1 follows the outside unless the user is dragging; `moved(v)`
// fires while dragging / on click / on scroll (one 5 % step per notch).
//
//     Slider { value: sink.audio.volume; onMoved: v => sink.audio.volume = v }
import QtQuick

Item {
    id: sl

    property real value: 0
    property color color: Theme.accent
    property color trackColor: Theme.alpha(Theme.surface1, 0.9)
    property real step: 0.05
    property bool enabled: true
    readonly property bool dragging: mouse.pressed
    readonly property real shown: dragging ? dragValue : Math.max(0, Math.min(1, value))
    property real dragValue: 0
    property real thickness: 6
    // wheel travel per step (120 = one mouse notch); lower = faster
    property real wheelUnit: 120

    signal moved(real v)

    // keyboard: Tab to it, ← / ↓ lower, → / ↑ raise by `step`
    activeFocusOnTab: enabled && visible
    function kbStep(d) {
        const from = wheelAt >= 0 ? wheelAt : value;
        wheelAt = Math.max(0, Math.min(1, Math.round((from + d * step) / step) * step));
        moved(wheelAt);
        wheelIdle.restart();
    }
    Keys.onPressed: ev => {
        if (ev.modifiers & Qt.ControlModifier) return;
        if (ev.key === Qt.Key_Left || ev.key === Qt.Key_Down) { kbStep(-1); ev.accepted = true; }
        else if (ev.key === Qt.Key_Right || ev.key === Qt.Key_Up) { kbStep(1); ev.accepted = true; }
    }
    property real wheelAt: -1
    Timer { id: wheelIdle; interval: 600; onTriggered: sl.wheelAt = -1 }

    implicitWidth: 200
    implicitHeight: 22
    opacity: enabled ? 1 : 0.45

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: mouse.containsMouse || sl.dragging ? sl.thickness + 2 : sl.thickness
        radius: height / 2
        color: sl.trackColor
        Behavior on height { NumberAnimation { duration: 120 } }

        Rectangle {
            width: Math.max(height, parent.width * sl.shown)
            height: parent.height
            radius: height / 2
            color: sl.color
            Behavior on width { enabled: !sl.dragging; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        }
    }

    Rectangle {
        property real d: mouse.containsMouse || sl.dragging ? 16 : 12
        width: d
        height: d
        radius: d / 2
        x: (sl.width - d) * sl.shown
        anchors.verticalCenter: parent.verticalCenter
        color: sl.color
        border.width: 3
        border.color: Theme.mantle
        Behavior on d { NumberAnimation { duration: 120 } }
        Behavior on x { enabled: !sl.dragging; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        anchors.margins: -4
        enabled: sl.enabled
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        function at(x) { return Math.max(0, Math.min(1, (x - 4) / sl.width)); }
        onPressed: ev => { sl.dragValue = at(ev.x); sl.moved(sl.dragValue); }
        onPositionChanged: ev => { if (pressed) { sl.dragValue = at(ev.x); sl.moved(sl.dragValue); } }
        property real acc: 0
        onWheel: wheel => {
            acc += Theme.wheelDelta(wheel);
            while (Math.abs(acc) >= sl.wheelUnit) {
                // from where the last step put it (value lags while a change is on its way)
                const from = sl.wheelAt >= 0 ? sl.wheelAt : sl.value;
                sl.wheelAt = Math.max(0, Math.min(1, Math.round((from + (acc > 0 ? sl.step : -sl.step)) / sl.step) * sl.step));
                sl.moved(sl.wheelAt);
                wheelIdle.restart();
                acc -= acc > 0 ? sl.wheelUnit : -sl.wheelUnit;
            }
        }
    }
    FocusRing { radius: 8 }
}
