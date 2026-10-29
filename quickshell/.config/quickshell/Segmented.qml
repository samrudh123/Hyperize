// A segmented tab switch (Serpantinum's "Outputs | Inputs | Streams"): the
// selected segment is an accent pill that slides between options.
//
//     Segmented { options: ["Wi-Fi", "Bluetooth"]; onSelected: i => … }
import QtQuick

Rectangle {
    id: seg

    property var options: []
    property int currentIndex: 0
    property color accent: Theme.tintOf(parent)       // the popup's tint
    property real fontSize: 12

    signal selected(int index)

    // pick one as a click would (also the keyboard and Ctrl+Tab)
    function pick(i) {
        if (!options.length) return;
        i = (i + options.length) % options.length;
        optimistic = i;
        settle.restart();
        selected(i);
    }
    // keyboard: Tab to it, ← / → move the selection
    activeFocusOnTab: visible && options.length > 1
    function kbStep(d) { pick(shownIndex + d); }
    function kbActivate() {}
    Keys.onPressed: ev => {
        if (ev.modifiers & Qt.ControlModifier) return;
        if (ev.key === Qt.Key_Left || ev.key === Qt.Key_Up) { kbStep(-1); ev.accepted = true; }
        else if (ev.key === Qt.Key_Right || ev.key === Qt.Key_Down) { kbStep(1); ev.accepted = true; }
    }

    // A click shows at once (optimistic) but does NOT assign currentIndex —
    // that broke the owner's binding, so a later change made elsewhere (the
    // theme picker, the power-profile pill, another panel) left a stale
    // highlight. The owner's binding catches up (or after 2.5 s it shows the
    // real value again, if the change didn't take).
    property int optimistic: -1
    readonly property int shownIndex: optimistic >= 0 ? optimistic : currentIndex
    onCurrentIndexChanged: optimistic = -1
    Timer { id: settle; interval: 2500; onTriggered: seg.optimistic = -1 }

    implicitWidth: 300
    implicitHeight: 34
    radius: 10
    color: Theme.alpha(Theme.surface0, 0.8)

    readonly property real segW: options.length ? (width - 6) / options.length : 0

    Rectangle {
        x: 3 + seg.segW * seg.shownIndex
        y: 3
        width: seg.segW
        height: seg.height - 6
        radius: seg.radius - 3
        color: seg.accent
        Behavior on x { NumberAnimation { duration: 280; easing.type: Easing.OutBack; easing.overshoot: 0.9 } }
    }

    Row {
        x: 3
        y: 3
        Repeater {
            model: seg.options
            delegate: Item {
                required property var modelData
                required property int index
                width: seg.segW
                height: seg.height - 6
                Text {
                    anchors.centerIn: parent
                    text: parent.modelData
                    color: parent.index === seg.shownIndex ? Theme.crust
                         : ma.containsMouse ? Theme.text : Theme.subtext0
                    font.family: Theme.font
                    font.pixelSize: seg.fontSize
                    font.weight: Font.DemiBold
                    Behavior on color { ColorAnimation { duration: Theme.fast } }
                }
                MouseArea {
                    id: ma
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: seg.pick(parent.index)
                }
            }
        }
    }
    FocusRing {}
}
