// Winter theme hook for a bar surface — an island (Island.qml) or the classic
// bar's panel. Put one inside, filling it:
//   kind "ledge"   the bottom bar: snow settles on its top edge
//   kind "lights"  the top bar: fairy lights hang along its bottom edge
// It only registers with SeasonState; WinterOverlay draws both (they reach
// outside the bar window). Not winter: does nothing.
import QtQuick
import Quickshell

Item {
    id: trim

    // from the bar it's in (TopBar / BottomBar `winterTrim`), unless set
    property string kind: ledgeWindow && ledgeWindow.winterTrim ? ledgeWindow.winterTrim : ""
    property real ledgeRadius: 12
    readonly property var ledgeWindow: QsWindow.window
    property string ledgeKey: ""
    property real ledgeT0: 0
    readonly property string trimKind: kind

    anchors.fill: parent
    readonly property bool on: visible && width > 8 && (kind === "ledge" ? SeasonState.capsOn
                                                       : kind === "lights" ? SeasonState.lightsOn : false)
    onOnChanged: on ? SeasonState.addLedge(trim) : SeasonState.removeLedge(trim)
    Component.onCompleted: if (on) SeasonState.addLedge(trim)
    Component.onDestruction: SeasonState.removeLedge(trim)
}
