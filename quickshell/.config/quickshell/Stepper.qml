// A number stepper for the panels: [ − ][ 8 ][ + ]. The buttons step by 1
// within min…max; the box takes a typed number too. A typed number outside
// the limits (or an empty box) isn't sent on: `invalid` turns true, the box
// goes red, and the owner shows why (see DownloadAskPopup).
//
//     Stepper { value: n; min: 1; max: 16; onEdited: v => n = v }
import QtQuick
import Quickshell

Row {
    id: sp

    property int value: 0
    property int min: 1
    property int max: 99
    property real size: 30
    signal edited(int value)
    signal accepted()                     // Enter in the box

    readonly property int typed: /^\d+$/.test(field.text.trim()) ? parseInt(field.text.trim()) : NaN
    readonly property bool invalid: isNaN(typed) || typed < min || typed > max
    readonly property alias input: field.input

    spacing: 4

    function clamp(v) { return Math.max(min, Math.min(max, v)); }
    function step(d) {
        const from = isNaN(typed) ? value : clamp(typed);
        const v = clamp(from + d);
        field.text = String(v);
        if (v !== value) edited(v);
    }
    // the value changed elsewhere (a step, the owner): show it — but not over
    // what's being typed when that already is the value
    onValueChanged: if (typed !== value) field.text = String(value)
    Component.onCompleted: field.text = String(value)

    IconBtn {
        size: sp.size
        iconSize: 13
        icon: "\u{f0374}"
        enabled: sp.invalid || sp.value > sp.min
        tip: "Fewer (min " + sp.min + ")"
        tipEdge: Edges.Top
        onClicked: sp.step(-1)
    }
    SettingsField {
        id: field
        width: parent.width - 2 * (sp.size + sp.spacing)
        height: sp.size
        placeholder: sp.min + "–" + sp.max
        border.color: sp.invalid ? Theme.red
                    : input.activeFocus ? Theme.alpha(Theme.tintOf(sp), 0.8) : Theme.alpha(Theme.surface1, 0.8)
        color: sp.invalid ? Theme.alpha(Theme.red, 0.12) : Theme.alpha(Theme.surface0, 0.8)
        input.horizontalAlignment: TextInput.AlignHCenter
        input.color: sp.invalid ? Theme.red : Theme.text
        input.font.weight: Font.DemiBold
        input.validator: RegularExpressionValidator { regularExpression: /\d{0,3}/ }
        onEdited: if (!sp.invalid && sp.typed !== sp.value) sp.edited(sp.typed)
        onAccepted: sp.accepted()
    }
    IconBtn {
        size: sp.size
        iconSize: 13
        icon: "\u{f0415}"
        enabled: sp.invalid || sp.value < sp.max
        tip: "More (max " + sp.max + ")"
        tipEdge: Edges.Top
        onClicked: sp.step(1)
    }
}
