// The network panel's "core" (Serpantinum's orb): a round glowing badge for
// the current link. Ripples breathe out of it while connected, a ring shows
// the signal, an arc spins while something is connecting, and holding the
// mouse on it sweeps the ring red — let go early to cancel, hold through to
// disconnect (`held()`).
import QtQuick

Item {
    id: orb

    property string icon: "\u{f0928}"
    property string hoverIcon: ""                 // shown while hovered (holdable)
    property color tint: Theme.accent
    property bool active: false                   // connected: lit core + ripples
    property bool busy: false                     // connecting: spinning arc
    property real level: -1                       // 0–1 signal ring, <0 = none
    property bool holdable: false
    property real hold: 0                         // 0–1 while held
    readonly property bool hovered: ma.containsMouse

    signal held()

    implicitWidth: 112
    implicitHeight: 112

    // ripples
    Repeater {
        model: 3
        Rectangle {
            id: ripple
            required property int index
            anchors.centerIn: parent
            width: core.width
            height: width
            radius: width / 2
            color: "transparent"
            border.width: 2
            border.color: orb.tint
            opacity: 0
            SequentialAnimation on scale {
                running: orb.active && orb.visible && orb.hold === 0
                loops: Animation.Infinite
                PauseAnimation { duration: index * 700 }
                NumberAnimation { from: 1; to: 1.42; duration: 2100; easing.type: Easing.OutSine }
            }
            SequentialAnimation on opacity {
                running: orb.active && orb.visible && orb.hold === 0
                loops: Animation.Infinite
                onRunningChanged: if (!running) ripple.opacity = 0
                PauseAnimation { duration: index * 700 }
                NumberAnimation { from: 0.45; to: 0; duration: 2100; easing.type: Easing.OutSine }
            }
        }
    }

    // signal ring / hold sweep
    Canvas {
        id: ring
        anchors.centerIn: parent
        width: core.width + 14
        height: width
        readonly property real lvl: orb.level
        readonly property real hld: orb.hold
        readonly property color tint: orb.tint
        onLvlChanged: requestPaint()
        onHldChanged: requestPaint()
        onTintChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const c = width / 2, r = c - 3;
            ctx.lineCap = "round";
            ctx.lineWidth = 3;
            if (orb.level >= 0 || orb.hold > 0) {
                ctx.strokeStyle = Qt.rgba(Theme.surface1.r, Theme.surface1.g, Theme.surface1.b, 0.8);
                ctx.beginPath(); ctx.arc(c, c, r, 0, 2 * Math.PI); ctx.stroke();
            }
            if (orb.hold > 0) {
                ctx.strokeStyle = Theme.red;
                ctx.beginPath(); ctx.arc(c, c, r, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * orb.hold); ctx.stroke();
            } else if (orb.level > 0) {
                ctx.strokeStyle = orb.tint;
                ctx.beginPath(); ctx.arc(c, c, r, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * Math.min(1, orb.level)); ctx.stroke();
            }
        }
    }

    // connecting: a short arc going round
    Canvas {
        anchors.centerIn: parent
        width: core.width + 14
        height: width
        visible: orb.busy
        onVisibleChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const c = width / 2;
            ctx.lineCap = "round";
            ctx.lineWidth = 3;
            ctx.strokeStyle = orb.tint;
            ctx.beginPath(); ctx.arc(c, c, c - 3, 0, Math.PI * 0.55); ctx.stroke();
        }
        RotationAnimation on rotation {
            running: orb.busy && orb.visible
            from: 0; to: 360; duration: 900
            loops: Animation.Infinite
        }
    }

    Rectangle {
        id: core
        anchors.centerIn: parent
        width: 80
        height: 80
        radius: 40
        gradient: Gradient {
            GradientStop { position: 0; color: orb.active ? Qt.lighter(orb.tint, 1.12) : Theme.alpha(Theme.surface1, 0.9) }
            GradientStop { position: 1; color: orb.active ? Qt.darker(orb.tint, 1.25) : Theme.alpha(Theme.surface0, 0.9) }
        }
        border.width: orb.active ? 0 : 1
        border.color: Theme.alpha(Theme.surface2, 0.8)
        scale: ma.pressed ? 0.94 : orb.hovered ? 1.04 : 1
        Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }

        // a soft breathing glow while connected
        SequentialAnimation on opacity {
            running: orb.active && orb.visible
            loops: Animation.Infinite
            onRunningChanged: if (!running) core.opacity = 1
            NumberAnimation { to: 0.88; duration: 1800; easing.type: Easing.InOutSine }
            NumberAnimation { to: 1; duration: 1800; easing.type: Easing.InOutSine }
        }

        Text {
            anchors.centerIn: parent
            text: orb.hold > 0 || (orb.holdable && orb.hovered && orb.hoverIcon) ? orb.hoverIcon : orb.icon
            color: orb.active ? Theme.crust : orb.hold > 0 ? Theme.red : Theme.overlay1
            font.family: Theme.font
            font.pixelSize: 32
        }
    }

    NumberAnimation {
        id: holdAnim
        target: orb; property: "hold"
        from: 0; to: 1; duration: 1000
        onFinished: { orb.hold = 0; orb.held(); }
    }
    NumberAnimation { id: unhold; target: orb; property: "hold"; to: 0; duration: 220; easing.type: Easing.OutCubic }

    MouseArea {
        id: ma
        anchors.centerIn: parent
        width: core.width
        height: core.height
        hoverEnabled: true
        enabled: orb.holdable
        cursorShape: orb.holdable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onPressed: { unhold.stop(); holdAnim.restart(); }
        onReleased: if (holdAnim.running) { holdAnim.stop(); unhold.restart(); }
        onCanceled: if (holdAnim.running) { holdAnim.stop(); unhold.restart(); }
    }
}
