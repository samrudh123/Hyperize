// One bar module: a 32px rounded pill with a label, hover state, tooltip and
// mouse handling. Everything on both bars is built from this (waybar's
// `padding: 0 9px; margin: 4px 1px; border-radius: 8px` look).
//
// Children are placed inside, after the label; set `label: ""` to draw
// something else entirely.
import QtQuick
import Quickshell

Item {
    id: pill

    property string label
    property color fg: Theme.text
    property color bg: "transparent"
    // Hover: a quiet surface fill by default. With `fillHover` the pill
    // fills in its text colour and the text goes dark; a pill that is
    // already filled (bg set, dark text) just lightens.
    property bool fillHover: false
    readonly property bool filled: bg.a > 0.5
    property color hoverFg: fillHover && !filled ? Theme.crust : fg
    property color hoverBg: !fillHover ? Theme.alpha(Theme.surface0, 0.9)
                          : filled ? Qt.lighter(bg, 1.08) : fg
    property bool interactive: true
    property real fontSize: 13
    property int fontWeight: Font.DemiBold
    property int padLeft: 9
    property int padRight: 9
    property int marginH: 1
    property string tip
    property int tipEdge: Edges.Bottom
    property bool shown: true
    // 0–1 draws a thin progress line along the pill's bottom edge (downloads)
    property real progress: -1
    property color progressColor: fg
    default property alias content: inner.data

    readonly property bool hovered: mouse.containsMouse
    // keyboard navigation is on this pill's popup: look hovered
    readonly property bool navHot: BarState.kbMode && !!BarState.activePopup && BarState.activePopup.isOpen
                                   && BarState.activePopup.pill === pill
    readonly property alias pressed: mouse.pressed
    readonly property alias labelItem: text

    // set -> the wheel does what Settings › Pills says (PillClicks.scroll);
    // scrollTable: this pill's own scroll actions (id -> function(dir))
    property string pillId: ""
    property var scrollTable: ({})

    signal clicked(int button)
    signal scrolled(int dir)

    visible: shown
    implicitHeight: 32
    implicitWidth: shown ? body.width + 2 * marginH : 0

    Rectangle {
        id: body
        x: pill.marginH
        height: 32
        width: Math.max(text.visible ? text.implicitWidth : 0, inner.childrenRect.width) + pill.padLeft + pill.padRight
        radius: 8
        color: pill.interactive && (mouse.containsMouse || pill.navHot) ? pill.hoverBg : pill.bg
        Behavior on color { ColorAnimation { duration: Theme.fast; easing.type: Easing.OutQuint } }
        Behavior on width { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }

        Text {
            id: text
            visible: pill.label !== ""
            x: pill.padLeft
            anchors.verticalCenter: parent.verticalCenter
            text: pill.label
            textFormat: Text.StyledText
            color: pill.interactive && (mouse.containsMouse || pill.navHot) ? pill.hoverFg : pill.fg
            font.family: Theme.font
            font.pixelSize: pill.fontSize
            font.weight: pill.fontWeight
            Behavior on color { ColorAnimation { duration: Theme.fast; easing.type: Easing.OutQuint } }
        }

        Rectangle {
            visible: pill.progress >= 0
            x: 7
            y: parent.height - 4
            width: parent.width - 14
            height: 2
            radius: 1
            color: Theme.alpha(Theme.surface1, 0.9)
            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, pill.progress))
                height: parent.height
                radius: 1
                color: pill.progressColor
                Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
            }
        }

        Item {
            id: inner
            x: pill.padLeft
            height: parent.height
            width: childrenRect.width
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: body
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        cursorShape: pill.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
        // tell open popups (BarState.barPressed): one not anchored here
        // closes, then this pill's own action runs (and may open its popup).
        // On the CLICK, not the press: closing a popup drops its focus grab,
        // and Hyprland then re-enters the bar — which cancelled a held press,
        // so the click (and the new popup) never came.
        onClicked: ev => {
            const p = mapToItem(null, ev.x, ev.y);
            BarState.barPressed(BarState.rootOf(pill), p.x, p.y);
            pill.clicked(ev.button);
        }
        // One step per wheel notch; a touchpad's many small deltas add up.
        property real acc: 0
        onWheel: wheel => {
            acc += Theme.wheelDelta(wheel);
            while (Math.abs(acc) >= 120) {
                if (pill.pillId) PillClicks.scroll(pill.pillId, acc > 0 ? 1 : -1, pill.scrollTable);
                else pill.scrolled(acc > 0 ? 1 : -1);
                acc -= acc > 0 ? 120 : -120;
            }
        }
    }

    Tooltip {
        target: body
        text: pill.tip
        shown: mouse.containsMouse
        edge: pill.tipEdge
    }
}
