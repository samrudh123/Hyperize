// A big popup panel under (top bar) or above (bottom bar) a pill — the base
// of the Serpantinum-style panels: audio, network, notifications, media.
//
//     PanelPopup {
//         id: pop
//         pill: somePill            // anchor; the panel centres on it
//         edge: Edges.Bottom        // Edges.Top on the bottom bar
//         panelWidth: 420
//         Column { … }              // content, laid out inside the padding
//     }
//     pop.toggle()
//
// `alignLeft: true` puts it at the bar window's left edge (+ leftMargin)
// instead of centring it on the pill (the players deck, bottom-left).
//
// Clicking outside (Hyprland focus grab) or Esc closes it. Opening plays a
// staggered intro: the card scales/fades in, then `intro` (0→1, delayed)
// can drive the content's own fade/slide (`opacity: pop.intro`).
import QtQuick
import Quickshell
import Quickshell.Hyprland

PopupWindow {
    id: pop

    property Item pill: null
    property int edge: Edges.Bottom
    property real panelWidth: 420
    property real pad: 14
    property bool isOpen: false
    property bool alignLeft: false
    property real leftMargin: 8
    // the pill's x in its window, measured on open (mapToItem isn't a binding)
    property real pillX: 0
    // 0→1 shortly after opening, for the content's entrance
    property real intro: 0
    // the screen edge the panel may not cross (bar height + gap)
    default property alias content: body.data
    readonly property alias card: card

    signal opened()
    signal closed2()                          // `closed` is FINAL on PopupWindow

    // ── keyboard ────────────────────────────────────────────────────────────
    //   Tab / Shift+Tab   next / previous control (IconBtn, Toggle, Slider,
    //                     Segmented, text fields, cards) — accent ring on it
    //   Enter / Space     press it · ← → ↑ ↓ adjust a slider / move a switch
    //   Ctrl+Tab          the panel's own tabs (tabBar) · Esc closes
    //   Ctrl+← / →        the previous / next pill's panel on this bar
    //   Ctrl+↑ / ↓        the nearest panel on the other bar
    // Keys reach the popup itself, or (pointer over it) the BAR, which hands
    // them to navKey(). Opened from the keyboard (openByKeyboard), the first
    // control — or initialFocus — takes the focus.
    property bool navigable: true             // in Ctrl+arrow's round
    property string navName: ""               // e.g. "audio" (startNav picks it)
    property var initialFocus: null
    Component.onCompleted: BarState.addPopup(pop)
    Component.onDestruction: BarState.removePopup(pop)

    function inside(it) {
        for (let x = it; x; x = x.parent) if (x === card) return true;
        return false;
    }
    function kbFocus(it) {
        if (!it) return;
        it.forceActiveFocus();
        BarState.kbItem = it;
    }
    function current() {
        const w = card.winFocus;
        if (w && w !== card && inside(w)) return w;
        return BarState.kbItem && inside(BarState.kbItem) ? BarState.kbItem : null;
    }
    // next / previous focusable control inside this panel (wraps)
    function move(dir) {
        let it = current() || card;
        for (let n = 0; n < 400; n++) {
            it = it.nextItemInFocusChain(dir > 0);
            if (!it || it === card) { it = card; continue; }
            if (inside(it) && it.visible) { kbFocus(it); return; }
        }
    }
    function openByKeyboard() {
        open();
        BarState.kbMode = true;
        Qt.callLater(() => {
            if (initialFocus && initialFocus.visible) kbFocus(initialFocus);
            else move(1);
        });
    }
    // a key: from the popup itself (card's Keys) or forwarded by a bar
    function navKey(key, mods) {
        const ctrl = (mods & Qt.ControlModifier) !== 0;
        if (ctrl && (key === Qt.Key_Left || key === Qt.Key_Right || key === Qt.Key_Up || key === Qt.Key_Down)) {
            BarState.navPopup(key === Qt.Key_Left ? "left" : key === Qt.Key_Right ? "right" : key === Qt.Key_Up ? "up" : "down");
            return true;
        }
        if (key === Qt.Key_Tab && !ctrl) { move((mods & Qt.ShiftModifier) ? -1 : 1); return true; }
        if (key === Qt.Key_Backtab && !ctrl) { move(-1); return true; }
        const it = current();
        if (!it) {
            // nothing focused yet: arrows / Enter start at the first control
            if (key === Qt.Key_Down || key === Qt.Key_Right || key === Qt.Key_Return || key === Qt.Key_Enter) { move(1); return true; }
            return false;
        }
        if (key === Qt.Key_Return || key === Qt.Key_Enter || key === Qt.Key_Space) {
            if (typeof it.kbActivate === "function") { it.kbActivate(); return true; }
            if (key !== Qt.Key_Space && it.parent && typeof it.parent.accepted === "function") { it.parent.accepted(); return true; }
            return false;
        }
        const d = key === Qt.Key_Left || key === Qt.Key_Up ? -1 : key === Qt.Key_Right || key === Qt.Key_Down ? 1 : 0;
        if (d && typeof it.kbStep === "function") { it.kbStep(d); return true; }
        if (d) { move(d); return true; }       // on a button: arrows walk like Tab
        return false;
    }

    function open() {
        if (isOpen) return;
        hideTimer.stop();
        if (alignLeft && pill) pillX = pill.mapToItem(null, 0, 0).x;
        isOpen = true;
        shown = true;
        introAnim.restart();
        card.forceActiveFocus();
        if (BarState.activePopup && BarState.activePopup !== pop && BarState.activePopup.isOpen)
            BarState.activePopup.close();
        BarState.activePopup = pop;
        BarState.kbItem = null;
        BarState.kbMode = false;            // openByKeyboard sets it after this
        opened();
    }
    function close() {
        if (!isOpen) return;
        if (BarState.activePopup === pop) BarState.activePopup = null;
        if (BarState.kbItem && inside(BarState.kbItem)) BarState.kbItem = null;
        isOpen = false;
        introAnim.stop();
        outAnim.restart();
        hideTimer.restart();
        closed2();
    }
    function toggle() { if (isOpen) close(); else open(); }

    property bool shown: false
    Timer { id: hideTimer; interval: 170; onTriggered: pop.shown = false }

    visible: shown
    color: "transparent"
    anchor.item: pill
    anchor.rect.x: !pill ? 0 : alignLeft ? leftMargin - pillX : pill.width / 2
    anchor.rect.y: !pill ? 0 : edge === Edges.Bottom ? pill.height + 8 : -8
    anchor.gravity: alignLeft ? edge | Edges.Right : edge
    anchor.adjustment: PopupAdjustment.Slide
    implicitWidth: panelWidth
    implicitHeight: body.childrenRect.height + 2 * pad

    // the bars are in the grab too, so their pills stay hoverable and
    // clickable; a press on a bar outside our pill closes us (BarState)
    HyprlandFocusGrab {
        active: pop.isOpen
        windows: [pop].concat(BarState.bars)
        onCleared: pop.close()
    }
    Connections {
        target: BarState
        enabled: pop.isOpen
        function onEscapePressed() { pop.close(); }
        function onTabPressed(dir) { pop.cycleTab(dir); }
    }
    // the panel's menu (a Segmented of pages, if it has one): Ctrl+Tab /
    // Ctrl+Shift+Tab step through it, as if its next / previous tab was clicked
    property var tabBar: null
    function cycleTab(dir) {
        if (!tabBar || !tabBar.visible || !tabBar.options || tabBar.options.length < 2) return;
        const n = tabBar.options.length;
        const at = tabBar.shownIndex !== undefined ? tabBar.shownIndex : tabBar.currentIndex;
        if (typeof tabBar.pick === "function") tabBar.pick(at + dir);
        else tabBar.selected((at + dir + n) % n);
    }
    Shortcut {
        enabled: pop.isOpen
        sequences: ["Ctrl+Tab"]
        context: Qt.WindowShortcut
        onActivated: pop.cycleTab(1)
    }
    Shortcut {
        enabled: pop.isOpen
        sequences: ["Ctrl+Shift+Tab", "Ctrl+Backtab", "Ctrl+Shift+Backtab"]
        context: Qt.WindowShortcut
        onActivated: pop.cycleTab(-1)
    }
    Shortcut {
        enabled: pop.isOpen
        sequences: ["Escape"]
        context: Qt.WindowShortcut
        onActivated: pop.close()
    }
    Connections {
        target: BarState
        enabled: pop.isOpen
        function onBarPressed(root, x, y) {
            if (!BarState.pressedOn(pop.pill, root, x, y)) pop.close();
        }
    }

    NumberAnimation {
        id: introAnim
        target: pop; property: "intro"
        from: 0; to: 1; duration: 420
        easing.type: Easing.OutExpo
    }
    NumberAnimation {
        id: outAnim
        target: pop; property: "intro"
        to: 0; duration: 140
        easing.type: Easing.InCubic
    }

    Rectangle {
        id: card
        width: parent.width
        height: parent.height
        radius: 18
        color: Theme.panel(Theme.mantle)
        border.width: 1
        border.color: Theme.alpha(Theme.surface1, 0.9)
        clip: true

        opacity: pop.isOpen ? 1 : 0
        scale: pop.isOpen ? 1 : 0.94
        transformOrigin: pop.edge === Edges.Bottom ? Item.Top : Item.Bottom
        Behavior on opacity { NumberAnimation { duration: pop.isOpen ? 220 : 140; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: pop.isOpen ? 380 : 140; easing.type: pop.isOpen ? Easing.OutBack : Easing.InCubic; easing.overshoot: 1.1 } }

        focus: true
        Keys.onEscapePressed: pop.close()
        // keys the focused control didn't take (Tab, Ctrl+arrows, arrows on
        // a button…) — see navKey
        Keys.onPressed: ev => { if (pop.navKey(ev.key, ev.modifiers)) ev.accepted = true; }
        readonly property Item winFocus: Window.activeFocusItem
        onWinFocusChanged: if (winFocus && winFocus !== card && pop.inside(winFocus)) BarState.kbItem = winFocus

        Item {
            id: body
            x: pop.pad
            y: pop.pad
            width: parent.width - 2 * pop.pad
            height: childrenRect.height
        }
    }
}
