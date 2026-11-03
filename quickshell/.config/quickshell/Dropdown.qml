// A Serpantinum-style dropdown (a select) for the panels: a field showing
// the choice + a chevron; a click drops a list card over the panel (it pops
// in under the field — or above it when there's more room there), the
// chosen row is the accent pill, long lists scroll. A click anywhere else in
// the panel, Esc, Tab or a pick closes it.
//
//     Dropdown {
//         options: ["1", "2", { label: "Tue 3 Nov", hint: "2 ✓", hintColor: Theme.green, icon: "…" }]
//         currentIndex: i
//         onSelected: i => …
//     }
//
// The list is drawn inside the panel's own window (PanelPopup's card), not a
// popup of its own: a nested popup isn't in the shell's focus grab, and keys
// reach the panels through the bars (PanelPopup.navKey → ddKey here).
//
// Keyboard: Tab to it · Enter / Space open it · ↑ ↓ move · Enter picks ·
// Esc closes just the list. Closed, ← → ↑ ↓ step the choice directly.
//
// `showValue: false` = a compact trigger (icon + chevron, no value text) —
// e.g. "recent folders" next to a path field; `listWidth` lets the list be
// wider than its field (it's kept inside the panel).
import QtQuick
import Quickshell

Rectangle {
    id: dd

    property var options: []              // strings, or { label, hint, hintColor, icon }
    property int currentIndex: -1
    property string placeholder: "Choose…"
    property string icon: ""              // leading glyph in the field
    property bool showValue: true
    property color accent: Theme.tintOf(parent)     // the popup's tint
    property real fontSize: 12
    property int maxRows: 7
    property real rowHeight: 30
    property real listWidth: 0            // 0 = the field's width
    property int elide: Text.ElideRight   // ElideMiddle for paths
    property string tip: ""
    property int tipEdge: Edges.Top
    property bool enabled: true
    property bool open: false
    readonly property bool hovered: ma.containsMouse

    signal selected(int index)

    function opt(i) {
        const o = options[i];
        return o === undefined || o === null ? null : typeof o === "object" ? o : { label: String(o) };
    }
    readonly property var cur: opt(currentIndex)

    // ── open / close ────────────────────────────────────────────────────────
    property var card_: null
    property int hi: -1                   // the row under the pointer / keyboard
    property bool up: false
    property real lx: 0
    property real ly: 0
    property real lw: 0
    property real lh: 0

    function findCard() {
        for (let x = dd.parent; x; x = x.parent) if (x.panelPopup !== undefined) return x;
        return null;
    }
    function place() {
        if (!card_) return;
        const p = dd.mapToItem(card_, 0, 0);
        const m = 8, gap = 6;
        const need = Math.min(options.length, maxRows) * rowHeight + 8;
        const below = card_.height - (p.y + dd.height + gap) - m;
        const above = p.y - gap - m;
        up = below < need && above > below;
        lh = Math.max(Math.min(rowHeight + 8, need), Math.min(need, up ? above : below));
        ly = up ? p.y - gap - lh : p.y + dd.height + gap;
        lw = Math.min(card_.width - 2 * m, Math.max(dd.width, listWidth));
        lx = Math.max(m, Math.min(p.x, card_.width - m - lw));
    }
    function openList() {
        if (!enabled || !options.length || open) return;
        if (!card_) card_ = findCard();
        if (!card_) return;
        const pp = card_.panelPopup;
        if (pp.dropdown && pp.dropdown !== dd) pp.dropdown.close();
        pp.dropdown = dd;
        // a text box being typed in would keep the arrows / Enter (the bars
        // hand keys to it) — the list takes them while it's open
        if (!dd.activeFocus && BarState.typing && pp.inside(BarState.typing)) card_.forceActiveFocus();
        layer.parent = card_;
        place();
        hi = currentIndex >= 0 ? currentIndex : 0;
        open = true;
        revealAnim.restart();
        Qt.callLater(() => lv.positionViewAtIndex(dd.hi, ListView.Contain));
    }
    function close() {
        if (!open) return;
        open = false;
        if (card_ && card_.panelPopup.dropdown === dd) card_.panelPopup.dropdown = null;
    }
    function toggle() { if (open) close(); else openList(); }
    function pick(i) {
        close();
        if (i >= 0 && i < options.length && i !== currentIndex) selected(i);
    }
    function moveHi(d) {
        if (!options.length) return;
        hi = Math.max(0, Math.min(options.length - 1, (hi < 0 ? currentIndex : hi) + d));
        lv.positionViewAtIndex(hi, ListView.Contain);
    }
    onVisibleChanged: if (!visible) close()
    onOptionsChanged: if (open) place()
    Connections {
        target: dd.card_
        enabled: dd.open
        function onHeightChanged() { dd.place(); }
    }

    // keys while the list is open (PanelPopup.navKey asks first): true = taken
    function ddKey(key, mods) {
        if (!open || (mods & Qt.ControlModifier)) return false;
        if (key === Qt.Key_Up || key === Qt.Key_Left) moveHi(-1);
        else if (key === Qt.Key_Down || key === Qt.Key_Right) moveHi(1);
        else if (key === Qt.Key_Return || key === Qt.Key_Enter || key === Qt.Key_Space) pick(hi);
        else if (key === Qt.Key_Home) { hi = 0; lv.positionViewAtBeginning(); }
        else if (key === Qt.Key_End) { hi = options.length - 1; lv.positionViewAtEnd(); }
        else if (key === Qt.Key_Escape) close();
        else { if (key === Qt.Key_Tab || key === Qt.Key_Backtab) close(); return false; }
        return true;
    }

    // keyboard (Tab to it) — see PanelPopup.navKey
    activeFocusOnTab: enabled && visible && opacity > 0.05
    function kbActivate() { if (open) pick(hi); else openList(); }
    function kbStep(d) {
        if (open) { moveHi(d); return; }
        if (!options.length || !showValue) return;
        const i = currentIndex < 0 ? (d > 0 ? 0 : options.length - 1)
                                   : Math.max(0, Math.min(options.length - 1, currentIndex + d));
        if (i !== currentIndex) selected(i);
    }
    Keys.onShortcutOverride: ev => { if (ev.key === Qt.Key_Escape && dd.open) ev.accepted = true; }
    Keys.onPressed: ev => {
        if (dd.open && dd.ddKey(ev.key, ev.modifiers)) { ev.accepted = true; return; }
        if (ev.modifiers & Qt.ControlModifier) return;
        if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter || ev.key === Qt.Key_Space) { kbActivate(); ev.accepted = true; }
        else if (ev.key === Qt.Key_Up || ev.key === Qt.Key_Left) { kbStep(-1); ev.accepted = true; }
        else if (ev.key === Qt.Key_Down || ev.key === Qt.Key_Right) { kbStep(1); ev.accepted = true; }
    }

    // ── the field ───────────────────────────────────────────────────────────
    implicitWidth: showValue ? 180 : 46
    implicitHeight: 32
    radius: 10
    opacity: enabled ? 1 : 0.4
    color: open || hovered ? Theme.alpha(Theme.surface1, 0.9) : Theme.alpha(Theme.surface0, 0.75)
    border.width: 1
    border.color: open ? Theme.alpha(accent, 0.75) : Theme.alpha(Theme.surface1, 0.5)
    Behavior on color { ColorAnimation { duration: Theme.fast; easing.type: Easing.OutQuint } }
    Behavior on border.color { ColorAnimation { duration: Theme.fast } }
    scale: ma.pressed ? 0.97 : 1
    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }

    Text {
        id: ico
        readonly property string glyph: dd.icon || (dd.cur && dd.cur.icon ? dd.cur.icon : "")
        visible: glyph !== "" && dd.showValue
        x: 11
        anchors.verticalCenter: parent.verticalCenter
        text: glyph
        color: dd.open ? dd.accent : Theme.subtext0
        font.family: Theme.font
        font.pixelSize: dd.fontSize + 1
        Behavior on color { ColorAnimation { duration: Theme.fast } }
    }
    Text {
        id: chev
        visible: dd.showValue
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        text: "\u{f0140}"
        color: dd.open ? dd.accent : dd.hovered ? Theme.text : Theme.overlay1
        font.family: Theme.font
        font.pixelSize: dd.fontSize + 2
        rotation: dd.open ? 180 : 0
        Behavior on rotation { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
        Behavior on color { ColorAnimation { duration: Theme.fast } }
    }
    Text {
        id: hintT
        visible: dd.showValue && !!dd.cur && !!dd.cur.hint
        anchors.right: chev.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        text: dd.cur && dd.cur.hint ? dd.cur.hint : ""
        color: dd.cur && dd.cur.hintColor ? dd.cur.hintColor : Theme.overlay1
        font.family: Theme.font
        font.pixelSize: dd.fontSize - 1
        font.weight: Font.DemiBold
    }
    Text {
        visible: dd.showValue
        anchors.left: ico.visible ? ico.right : parent.left
        anchors.leftMargin: ico.visible ? 8 : 11
        anchors.right: hintT.visible ? hintT.left : chev.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        elide: dd.elide
        text: dd.cur ? dd.cur.label : dd.placeholder
        color: dd.cur ? Theme.text : Theme.overlay1
        font.family: Theme.font
        font.pixelSize: dd.fontSize
        font.weight: dd.cur ? Font.DemiBold : Font.Normal
    }
    // compact: icon + small chevron, centred
    Row {
        visible: !dd.showValue
        anchors.centerIn: parent
        spacing: 3
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: dd.icon
            color: dd.open ? dd.accent : dd.hovered ? Theme.text : Theme.subtext0
            font.family: Theme.font
            font.pixelSize: dd.fontSize + 2
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "\u{f0140}"
            color: dd.open ? dd.accent : Theme.overlay1
            font.family: Theme.font
            font.pixelSize: dd.fontSize
            rotation: dd.open ? 180 : 0
            Behavior on rotation { NumberAnimation { duration: 260; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        enabled: dd.enabled
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: dd.toggle()
    }
    Tooltip {
        target: dd
        text: dd.tip
        shown: ma.containsMouse && !dd.open
        edge: dd.tipEdge
    }
    FocusRing {}

    // ── the list (moved into the panel's card on first open) ────────────────
    property real reveal: 0
    NumberAnimation { id: revealAnim; target: dd; property: "reveal"; from: 0; to: 1; duration: 320; easing.type: Easing.OutCubic }

    Item {
        id: layer
        anchors.fill: parent
        z: 950
        visible: dd.open || box.opacity > 0.01

        // a press anywhere else in the panel closes the list (and is eaten)
        MouseArea {
            anchors.fill: parent
            enabled: dd.open
            acceptedButtons: Qt.AllButtons
            onPressed: dd.close()
            onWheel: w => w.accepted = true
        }

        Rectangle {
            id: box
            x: dd.lx
            y: dd.ly + (dd.open ? 0 : dd.up ? 6 : -6)
            width: dd.lw
            height: dd.lh
            radius: 12
            color: Theme.base
            border.width: 1
            border.color: Theme.alpha(dd.accent, 0.5)
            opacity: dd.open ? 1 : 0
            scale: dd.open ? 1 : 0.94
            transformOrigin: dd.up ? Item.Bottom : Item.Top
            Behavior on opacity { NumberAnimation { duration: dd.open ? 180 : 120; easing.type: Easing.OutCubic } }
            Behavior on scale { NumberAnimation { duration: dd.open ? 300 : 120; easing.type: dd.open ? Easing.OutBack : Easing.InCubic; easing.overshoot: 1.2 } }
            Behavior on y { NumberAnimation { duration: dd.open ? 260 : 120; easing.type: Easing.OutCubic } }

            // soft shadow under it
            Rectangle {
                z: -1
                x: -2
                y: 3
                width: parent.width + 4
                height: parent.height + 4
                radius: parent.radius + 2
                color: Theme.alpha(Theme.crust, 0.6)
            }
            MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }   // a press on the card's edge stays here

            ListView {
                id: lv
                anchors.fill: parent
                anchors.margins: 4
                clip: true
                model: dd.options.length
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height

                delegate: Rectangle {
                    id: row
                    required property int index
                    readonly property var o: dd.opt(index)
                    readonly property bool sel: index === dd.currentIndex
                    readonly property bool hot: index === dd.hi
                    width: lv.width - (lv.interactive ? 7 : 0)
                    height: dd.rowHeight
                    radius: 8
                    color: sel ? dd.accent : hot ? Theme.alpha(Theme.surface1, 0.9) : "transparent"
                    Behavior on color { ColorAnimation { duration: 90 } }
                    // rows drift in one after another on open
                    opacity: Math.max(0, Math.min(1, dd.reveal * 2.2 - Math.min(index, 8) * 0.12))
                    transform: Translate { y: (1 - dd.reveal) * (dd.up ? 4 : -4) * (1 + Math.min(row.index, 8) * 0.35) }

                    Text {
                        id: rIco
                        visible: !!row.o && !!row.o.icon
                        x: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.o && row.o.icon ? row.o.icon : ""
                        color: row.sel ? Theme.crust : Theme.subtext0
                        font.family: Theme.font
                        font.pixelSize: dd.fontSize + 1
                    }
                    Text {
                        id: rHint
                        visible: text !== ""
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.o && row.o.hint ? row.o.hint : ""
                        color: row.sel ? Theme.crust : row.o && row.o.hintColor ? row.o.hintColor : Theme.overlay1
                        font.family: Theme.font
                        font.pixelSize: dd.fontSize - 1
                        font.weight: Font.DemiBold
                    }
                    Text {
                        anchors.left: rIco.visible ? rIco.right : parent.left
                        anchors.leftMargin: rIco.visible ? 8 : 10
                        anchors.right: rHint.visible ? rHint.left : parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        elide: dd.elide
                        text: row.o ? row.o.label : ""
                        color: row.sel ? Theme.crust : row.hot ? Theme.text : Theme.subtext1
                        font.family: Theme.font
                        font.pixelSize: dd.fontSize
                        font.weight: row.sel ? Font.Bold : Font.Normal
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: dd.hi = row.index
                        onClicked: dd.pick(row.index)
                    }
                }
            }
            // scroll thumb
            Rectangle {
                visible: lv.interactive
                x: box.width - 7
                y: 4 + lv.visibleArea.yPosition * (box.height - 8)
                width: 3
                height: Math.max(16, lv.visibleArea.heightRatio * (box.height - 8))
                radius: 2
                color: Theme.alpha(dd.accent, 0.55)
            }
        }
    }
}
