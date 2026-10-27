// The audio panel's orb: a round glass with liquid rising to `level`
// (0–1), a sine wave on its surface, the percentage in the middle — dark
// where the liquid covers it. Muted: grey and "Mute". Animates only while
// `running` (the panel is open).
import QtQuick

Item {
    id: orb

    property real level: 0
    property bool muted: false
    property color tint: Theme.pink
    property bool running: false
    property string label: Math.round(level * 100) + "%"

    signal clicked()
    signal scrolled(int dir)

    implicitWidth: 112
    implicitHeight: 112

    // eased level and colour, so the liquid sloshes up/down
    property real shownLevel: muted ? 0.08 : Math.max(0.04, Math.min(1, level))
    Behavior on shownLevel { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
    readonly property color fill: muted ? Theme.overlay0 : tint
    property real phase: 0
    property real amp: mouse.containsMouse ? 4.5 : 3

    Behavior on amp { NumberAnimation { duration: 300 } }

    NumberAnimation on phase {
        running: orb.running && orb.visible
        from: 0; to: 2 * Math.PI
        duration: 2400
        loops: Animation.Infinite
    }
    onPhaseChanged: canvas.requestPaint()
    onShownLevelChanged: canvas.requestPaint()
    onFillChanged: canvas.requestPaint()
    onLabelChanged: canvas.requestPaint()

    // soft glow behind
    Rectangle {
        anchors.centerIn: parent
        width: parent.width + 10
        height: width
        radius: width / 2
        color: "transparent"
        border.width: 5
        border.color: Theme.alpha(orb.fill, mouse.containsMouse ? 0.22 : 0.12)
        Behavior on border.color { ColorAnimation { duration: Theme.normal } }
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        renderStrategy: Canvas.Cooperative
        onPaint: {
            const ctx = getContext("2d");
            const w = width, h = height, r = w / 2;
            ctx.reset();
            // glass
            ctx.save();
            ctx.beginPath();
            ctx.arc(r, r, r - 1, 0, 2 * Math.PI);
            ctx.closePath();
            ctx.fillStyle = Theme.alpha(Theme.surface0, 0.85);
            ctx.fill();
            ctx.clip();

            const top = h * (1 - orb.shownLevel);
            const wave = (off, a, k) => {
                ctx.beginPath();
                ctx.moveTo(0, h);
                for (let x = 0; x <= w; x += 3)
                    ctx.lineTo(x, top + Math.sin(x / w * k * Math.PI + orb.phase + off) * a);
                ctx.lineTo(w, h);
                ctx.closePath();
            };
            // back wave, dimmer
            wave(1.6, orb.amp * 0.8, 2.4);
            ctx.fillStyle = Theme.alpha(orb.fill, 0.35);
            ctx.fill();
            // front wave
            wave(0, orb.amp, 2);
            ctx.fillStyle = orb.fill;
            ctx.fill();

            // the label: light above the liquid, dark inside it
            ctx.font = "bold " + (orb.muted ? 20 : 24) + "px '" + Theme.font + "'";
            ctx.textAlign = "center";
            ctx.textBaseline = "middle";
            ctx.fillStyle = Theme.text;
            ctx.fillText(orb.label, r, r);
            wave(0, orb.amp, 2);
            ctx.clip();
            ctx.fillStyle = Theme.crust;
            ctx.fillText(orb.label, r, r);
            ctx.restore();

            // rim
            ctx.beginPath();
            ctx.arc(r, r, r - 1, 0, 2 * Math.PI);
            ctx.lineWidth = 1.5;
            ctx.strokeStyle = Theme.alpha(orb.fill, 0.55);
            ctx.stroke();
        }
    }

    scale: mouse.pressed ? 0.95 : mouse.containsMouse ? 1.03 : 1
    Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: orb.clicked()
        property real acc: 0
        onWheel: wheel => {
            acc += Theme.wheelDelta(wheel);
            while (Math.abs(acc) >= 120) {
                orb.scrolled(acc > 0 ? 1 : -1);
                acc -= acc > 0 ? 120 : -120;
            }
        }
    }
}
