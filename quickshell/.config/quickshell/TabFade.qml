// A tab switch's entrance for a popup's content: when `key` (the popup's
// tab) changes while `active`, `value` runs 0 -> 1 (220 ms, OutCubic). The
// popup multiplies its content's opacity by it and lifts it by a few px —
// the same soft swap as the sound / mic panels' cross-fade.
//
//     TabFade { id: tabFx; key: pop.tab; active: pop.isOpen }
//     opacity: pop.stage(2) * tabFx.value
//     transform: Translate { y: 14 * (1 - pop.stage(2)) + 8 * (1 - tabFx.value) }
import QtQuick

Item {
    id: tf
    property var key
    property bool active: true
    property real value: 1
    readonly property bool busy: anim.running
    visible: false
    width: 0
    height: 0
    onKeyChanged: if (active) { value = 0; anim.restart(); }
    NumberAnimation { id: anim; target: tf; property: "value"; from: 0; to: 1; duration: 220; easing.type: Easing.OutCubic }
}
