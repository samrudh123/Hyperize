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
    // the panel's highlight colour — the pill's (Theme.pillTint); the shared
    // controls inside (Segmented, Slider, Toggle, IconBtn, FocusRing) pick it
    // up via Theme.tintOf. Popups with their own colour logic set it.
    property color tint: Theme.pillTint(pill)
    // the screen edge the panel may not cross (bar height + gap)
    default property alias content: body.data
    readonly property alias card: card
    readonly property Item textTarget: card.textTarget

    signal opened()
    signal closed2()                          // `closed` is FINAL on PopupWindow

    // ── keyboard ────────────────────────────────────────────────────────────
    //   Tab / Shift+Tab   next / previous SECTION (header buttons, tab bar,
    //                     list, footer… — see "sections" below); lands on
    //                     the control last used there — accent ring on it
    //   ← → ↑ ↓           move inside the section (round in a circle). On a
    //                     slider / tab bar / dropdown ← → adjust it and ↑ ↓
    //                     move on (adjust when it's alone in its section);
    //                     `navArrows: true` controls take all four (calendar)
    //   Enter / Space     press it
    //   Ctrl+Tab          the panel's own tabs (tabBar) · Esc closes
    //   Ctrl+← / →        the previous / next pill's panel on this bar
    //   Ctrl+↑ / ↓        the nearest panel on the other bar
    // Keys reach the popup itself, or (pointer over it) the BAR, which hands
    // them to navKey(). Opened from the keyboard (openByKeyboard), the first
    // control — or initialFocus — takes the focus.
    property bool navigable: true             // in Ctrl+arrow's round
    // set (a function): Enter / Space run it — PillStop's "click the pill"
    property var enterAction: null
    property string navName: ""               // e.g. "audio" (startNav picks it)
    property var initialFocus: null
    // optional function(dir): Tab / Shift+Tab jumps of its own (NewsPopup:
    // section to section); return false for the usual next control
    property var tabAction: null
    // the Dropdown whose list is open in this panel (Dropdown sets it): Esc
    // and the arrow / Enter keys go to it first
    property var dropdown: null
    function escapeKey() {
        if (dropdown && dropdown.open) { dropdown.close(); return; }
        close();
    }
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
        noteKb(it);
    }
    // ── keeping the keyboard's place ────────────────────────────────────────
    // Pressing a control often rebuilds the list it sits in (News › More:
    // + adds a category and every card is made anew; Tasks: ticking, moving,
    // deleting, editing). The focused control is destroyed with it, and the
    // keyboard fell out of the panel — the next Tab started over at the top.
    // So the control the keyboard is on is remembered with where it was:
    // its `navKey` if it has one (a stable name: "cat:tech:add"), its section
    // and place in it. When it vanishes, the same control is looked for in
    // the rebuilt list, else the control of the same kind now at the same
    // place in that section (a ticked task: the task after it, or before it
    // if it was the last). A control that still exists but is hidden gets
    // ~0.6 s for its list to come back (a helper process answers first);
    // one that was destroyed means the list is rebuilt already.
    // The same when the focused control is only hidden (an inline editor
    // closing): controls with `navTransient: true` (those editors) aren't
    // remembered, so the keyboard goes back to what opened them.
    property var kbTrack: null
    property var kbInfo: null                 // { key, sec, kind, idx }
    function kindOf(x) { return typeName(x).split("_QML")[0]; }
    // the control with the keyboard, if it's in this panel and on screen
    function focusedInside() {
        const w = card.winFocus;
        return w && w !== card && w.visible && inside(w) ? w : null;
    }
    function noteKb(it) {
        if (!it || it === card || !inside(it)) return;
        for (let x = it; x && x !== card; x = x.parent) if (x.navTransient === true) return;
        if (it === kbTrack && kbInfo) return;
        const ctx = sectionCtx(), items = focusables();
        const secs = items.map(i => sectionOf(i, ctx));
        const order = [];
        for (const x of secs) if (order.indexOf(x) < 0) order.push(x);
        const S = sectionOf(it, ctx);
        const kind = kindOf(it);
        const same = items.filter((x, i) => secs[i] === S && kindOf(x) === kind);
        kbTrack = it;
        kbInfo = { key: it.navKey || "", sec: order.indexOf(S), kind: kind, idx: same.indexOf(it) };
        kbRestore.stop();
    }
    function restoreKb(giveUp) {
        const info = kbInfo;
        if (!info) return true;
        if (focusedInside()) return true;     // back already (or moved on)
        const items = focusables();
        if (!kbTrack) giveUp = true;          // destroyed: the new list is here
        if (info.key) {
            const same = items.find(i => i.navKey === info.key);
            if (same) { kbInfo = null; kbFocus(same); return true; }
            if (!giveUp) return false;          // the list may still be on its way
        }
        if (info.sec < 0 || !items.length) return giveUp;
        const ctx = sectionCtx();
        const secs = items.map(i => sectionOf(i, ctx));
        const order = [];
        for (const x of secs) if (order.indexOf(x) < 0) order.push(x);
        if (!giveUp && order.length <= info.sec) return false;
        const S = order[Math.min(info.sec, order.length - 1)];
        const mine = items.filter((_, i) => secs[i] === S);
        if (!mine.length) return giveUp;
        // the same kind of control (task → task, ✎ → ✎), else any
        const kin = mine.filter(x => kindOf(x) === info.kind);
        const pool = kin.length ? kin : mine;
        kbInfo = null;
        kbFocus(pool[Math.max(0, Math.min(info.idx, pool.length - 1))]);
        return true;
    }
    Timer {
        // is the tracked control gone? (cheap: a null check)
        interval: 30
        repeat: true
        running: pop.isOpen && !!pop.kbInfo
        onTriggered: if (!pop.focusedInside() && !kbRestore.running) { kbRestore.tries = 0; kbRestore.start(); }
    }
    Timer {
        id: kbRestore
        property int tries: 0
        interval: 50
        repeat: true
        onTriggered: {
            tries++;
            // a keyed control gets ~0.6 s to come back; then the same place
            if (!pop.isOpen || pop.restoreKb(tries >= 12)) stop();
        }
    }
    function current() {
        const w = card.winFocus;
        if (w && w !== card && inside(w)) return w;
        return BarState.kbItem && inside(BarState.kbItem) ? BarState.kbItem : null;
    }
    // ── sections ────────────────────────────────────────────────────────────
    // A section is a top-level block of the panel's content: the first level
    // below the content holder with more than one visible child (wrappers
    // with a single child are looked through, Flickables / lists are not
    // entered). Neighbouring blocks made from the same component (a
    // Repeater's cards, two IconBtns in a row) are one section. Any item
    // with `property bool navSection: true` is a section of its own (to
    // split a block); it may define navEnter(last) → the control to land on
    // (`last` = the one used there before, may be null).
    property Item navRoot: null               // override the detected level
    property var navLast: []                  // [{ s: section, it: control }]
    function typeName(x) { return String(x).split("(")[0]; }
    function sectionCtx() {
        let r = navRoot || body;
        if (!navRoot) {
            for (let n = 0; n < 12; n++) {
                let only = null, count = 0;
                for (let i = 0; i < r.children.length; i++) {
                    const c = r.children[i];
                    if (c.visible && (c.width > 0 || c.height > 0)) { count++; only = c; }
                }
                if (count !== 1 || only.contentY !== undefined) break;     // not into Flickables
                r = only;
            }
        }
        const kids = [], lead = [];
        for (let i = 0; i < r.children.length; i++) {
            const c = r.children[i];
            if (!c.visible || (c.width <= 0 && c.height <= 0)) continue;
            const t = typeName(c), k = kids.length;
            kids.push(c);
            lead.push(k > 0 && t.indexOf("_QML") >= 0 && t === typeName(kids[k - 1]) ? lead[k - 1] : c);
        }
        return { root: r, kids: kids, lead: lead };
    }
    function sectionOf(it, ctx) {
        let prev = null;
        for (let x = it; x; x = x.parent) {
            if (x.navSection === true) return x;
            if (x === ctx.root) {
                if (!prev) return x;
                const i = ctx.kids.indexOf(prev);
                return i >= 0 ? ctx.lead[i] : prev;
            }
            prev = x;
        }
        return card;
    }
    // every focusable control in the panel, in Tab order
    function focusables() {
        const out = [], seen = [];
        let it = card;
        for (let n = 0; n < 800; n++) {
            it = it.nextItemInFocusChain(true);
            if (!it || seen.indexOf(it) >= 0) break;
            seen.push(it);
            if (it !== card && inside(it) && it.visible) out.push(it);
        }
        return out;
    }
    function remember(sec, it) {
        const l = navLast.filter(r => r.s !== sec);
        l.push({ s: sec, it: it });
        navLast = l.slice(-30);
    }
    // Tab / Shift+Tab: the next / previous section (one section: control by
    // control, as before)
    function tabSection(dir) {
        const ctx = sectionCtx(), items = focusables();
        if (!items.length) return;
        const secs = items.map(i => sectionOf(i, ctx));
        const order = [];
        for (const s of secs) if (order.indexOf(s) < 0) order.push(s);
        if (order.length < 2) { move(dir); return; }
        const cur = current();
        const k = cur ? order.indexOf(sectionOf(cur, ctx)) : -1;
        if (k >= 0) remember(order[k], cur);
        const S = order[k < 0 ? (dir > 0 ? 0 : order.length - 1) : (k + dir + order.length) % order.length];
        const mine = items.filter((_, i) => secs[i] === S);
        const rec = navLast.find(r => r.s === S);
        const last = rec && mine.indexOf(rec.it) >= 0 ? rec.it : null;
        let t = typeof S.navEnter === "function" ? S.navEnter(last) : null;
        if (!t || !t.visible || !inside(t)) t = last || mine[0];
        kbFocus(t);
    }
    function sectionMembers(it) {
        const ctx = sectionCtx(), items = focusables();
        const S = sectionOf(it, ctx);
        return items.filter(i => sectionOf(i, ctx) === S);
    }
    // arrows: the previous / next control in the current section, round in
    // a circle (past the last → the first). A ListView only has the rows
    // near the view built, so at the end of those it scrolls on to the next
    // row first, and the wrap goes to the list's real first / last row.
    function listIn(x, S) {
        for (let p = x; p; p = p.parent) {
            if (p.itemAtIndex !== undefined && p.positionViewAtIndex !== undefined && p.count !== undefined) return p;
            if (p === S) break;
        }
        return null;
    }
    function rowOf(x, lv) {
        let p = x;
        while (p && p.parent !== lv.contentItem) p = p.parent;
        return p;
    }
    // show row `idx` of list `lv`; focus its first (dir > 0) / last control
    function focusRow(lv, idx, S, dir) {
        lv.positionViewAtIndex(idx, ListView.Contain);
        const row = lv.itemAtIndex(idx);
        if (!row) return false;
        const ctx = sectionCtx();
        const mine = focusables().filter(i => sectionOf(i, ctx) === S && rowOf(i, lv) === row);
        if (!mine.length) return false;
        kbFocus(dir > 0 ? mine[0] : mine[mine.length - 1]);
        return true;
    }
    function moveInSection(dir) {
        const cur = current();
        if (!cur) { move(dir); return; }
        const ctx = sectionCtx();
        const S = sectionOf(cur, ctx);
        const list = focusables().filter(i => sectionOf(i, ctx) === S);
        if (list.indexOf(cur) < 0) { move(dir); return; }
        // in a list: the row's own controls, then the next row by INDEX (the
        // focus chain has rows in the order they were built, not list order)
        const lv = listIn(cur, S);
        if (lv) {
            const row = rowOf(cur, lv);
            const inRow = list.filter(i => listIn(i, S) === lv && rowOf(i, lv) === row);
            const k = inRow.indexOf(cur);
            if (k + dir >= 0 && k + dir < inRow.length) { kbFocus(inRow[k + dir]); return; }
            const idx = row ? lv.indexAt(row.x + 1, row.y + 1) : -1;
            if (idx >= 0 && idx + dir >= 0 && idx + dir < lv.count && focusRow(lv, idx + dir, S, dir)) return;
        }
        // the section's controls in order, each list as one stop; past the
        // last → the first (a list is entered at its first / last row)
        const slots = [];
        for (const i of list) {
            const l = listIn(i, S);
            if (!l) slots.push({ it: i });
            else if (!slots.some(x => x.lv === l)) slots.push({ lv: l });
        }
        const n = slots.length;
        const s0 = slots.findIndex(x => lv ? x.lv === lv : x.it === cur);
        for (let m = 1; m <= n; m++) {
            const t = slots[((s0 + dir * m) % n + n) % n];
            if (t.it) { kbFocus(t.it); return; }
            if (t.lv.count > 0 && focusRow(t.lv, dir > 0 ? 0 : t.lv.count - 1, S, dir)) return;
        }
    }
    // for checking the grouping: `qs ipc call panels sections`
    function describeSections() {
        const ctx = sectionCtx(), items = focusables();
        const out = [], order = [];
        const label = x => {
            const t = typeName(x).replace(/_QML(TYPE)?_\d+/, "");
            const w = x.label || x.text || (x.t && x.t.text) || x.tip || x.placeholder || x.icon || "";
            return t + (w ? " \"" + String(w).slice(0, 24) + "\"" : "");
        };
        for (const i of items) {
            const s = sectionOf(i, ctx);
            let k = order.indexOf(s);
            if (k < 0) { order.push(s); out.push([]); k = order.length - 1; }
            out[k].push(label(i));
        }
        const cur = current();
        let at = "";
        if (cur) {
            const s = sectionOf(cur, ctx), mine = items.filter(i => sectionOf(i, ctx) === s);
            at = "focus: section " + (order.indexOf(s) + 1) + ", " + (mine.indexOf(cur) + 1) + "/" + mine.length + " " + label(cur);
            const lv = listIn(cur, s), r = lv ? rowOf(cur, lv) : null;
            if (r) at += " (list row " + (lv.indexAt(r.x + 1, r.y + 1) + 1) + "/" + lv.count + ")";
            at += "\n";
        }
        return at + "root " + label(ctx.root) + " · " + order.length + " sections\n"
             + out.map((l, k) => (k + 1) + ". [" + label(order[k]) + "] " + l.length + ": "
                                 + l.slice(0, 6).join(", ") + (l.length > 6 ? ", …" : "")).join("\n");
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
        if (dropdown && dropdown.open && dropdown.ddKey(key, mods)) return true;
        // a key right after the focused control vanished: put the keyboard
        // back first (don't wait for the timers), then handle the key there
        if (kbInfo && !focusedInside()) { kbRestore.stop(); restoreKb(true); }
        const ctrl = (mods & Qt.ControlModifier) !== 0;
        if (ctrl && (key === Qt.Key_Left || key === Qt.Key_Right || key === Qt.Key_Up || key === Qt.Key_Down)) {
            BarState.navPopup(key === Qt.Key_Left ? "left" : key === Qt.Key_Right ? "right" : key === Qt.Key_Up ? "up" : "down");
            return true;
        }
        if (enterAction && !ctrl && (key === Qt.Key_Return || key === Qt.Key_Enter || key === Qt.Key_Space)) {
            enterAction();
            return true;
        }
        if (ctrl && (key === Qt.Key_Tab || key === Qt.Key_Backtab)) {
            cycleTab(key === Qt.Key_Backtab || (mods & Qt.ShiftModifier) ? -1 : 1);
            return true;
        }
        if (!ctrl && (key === Qt.Key_Tab || key === Qt.Key_Backtab)) {
            const dir = key === Qt.Key_Backtab || (mods & Qt.ShiftModifier) ? -1 : 1;
            if (!(tabAction && tabAction(dir))) tabSection(dir);
            return true;
        }
        const it = current();
        // keys of the control's own, or of what it's part of (a task and
        // its buttons: 0–3 = priority)
        for (let x = it; x && x !== card; x = x.parent)
            if (typeof x.kbKey === "function") { if (x.kbKey(key, mods)) return true; break; }
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
        if (!d) return false;
        if (typeof it.kbStep === "function") {
            // ← → adjust it; ↑ ↓ move on — unless it's alone in its section
            const vertical = key === Qt.Key_Up || key === Qt.Key_Down;
            if (it.navArrows === true || !vertical || sectionMembers(it).length < 2) it.kbStep(d, key);
            else moveInSection(d);
            return true;
        }
        moveInSection(d);                       // inside the section, round in a circle
        return true;
    }

    function open() {
        if (isOpen) return;
        closeAnim.stop();
        closing = false;
        if (alignLeft && pill) pillX = pill.mapToItem(null, 0, 0).x;
        // the other open popup goes FIRST: its focus grab must end before
        // ours starts — ending it after ours had begun dropped Hyprland's
        // grab altogether (keys, Esc included, fell through to the window)
        if (BarState.activePopup && BarState.activePopup !== pop && BarState.activePopup.isOpen)
            BarState.activePopup.close();
        isOpen = true;
        BarState.grabFor(pop);
        shown = true;
        introAnim.restart();
        openAnim.restart();
        card.forceActiveFocus();
        BarState.activePopup = pop;
        BarState.kbItem = null;
        BarState.kbMode = false;            // openByKeyboard sets it after this
        opened();
    }
    function close() {
        if (!isOpen) return;
        if (dropdown) dropdown.close();
        if (BarState.activePopup === pop) BarState.activePopup = null;
        if (BarState.kbItem && inside(BarState.kbItem)) BarState.kbItem = null;
        kbInfo = null;
        kbTrack = null;
        kbRestore.stop();
        // the content stays exactly as it is (no reverse stagger) and the
        // window keeps its size, so only the card itself fades and settles
        heldH = implicitHeight;
        closing = true;
        isOpen = false;
        BarState.releaseGrab(pop);
        introAnim.stop();
        openAnim.stop();
        closeAnim.restart();
        closed2();
    }
    function toggle() { if (isOpen) close(); else open(); }

    property bool shown: false
    property bool closing: false              // the close animation is running
    property real heldH: 0                    // the height it had when closing began

    visible: shown
    color: "transparent"
    anchor.item: pill
    anchor.rect.x: !pill ? 0 : alignLeft ? leftMargin - pillX : pill.width / 2
    anchor.rect.y: !pill ? 0 : edge === Edges.Bottom ? pill.height + 8 : -8
    anchor.gravity: alignLeft ? edge | Edges.Right : edge
    anchor.adjustment: PopupAdjustment.Slide
    implicitWidth: panelWidth
    // held while closing: content that empties on close (backends that only
    // run while open) used to resize the card mid-fade — the shake
    implicitHeight: closing ? heldH : body.childrenRect.height + 2 * pad

    // the focus grab (click outside / Esc closes us) is BarState's one
    // shared grab — see BarState.grabFor; the bars are in it too, so their
    // pills stay hoverable and clickable; a press on a bar outside our pill
    // closes us (onBarPressed below)
    Connections {
        target: BarState
        enabled: pop.isOpen
        function onEscapePressed() { pop.escapeKey(); }
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
    // Tab / Shift+Tab inside the popup: ours (move(): visible controls of
    // this popup only, wrapping), not Qt's own focus chain. Only plain Tab is
    // a Shortcut: Shift+Tab / Ctrl+Tab / Ctrl+Shift+Tab go through the card's
    // Keys → navKey (Shortcuts listing a key's several forms — "Shift+Tab",
    // "Backtab", "Shift+Backtab" — all match one press: ambiguous, none fire)
    Shortcut {
        enabled: pop.isOpen
        sequences: ["Tab"]
        context: Qt.WindowShortcut
        onActivated: pop.move(1)
    }
    Shortcut {
        enabled: pop.isOpen
        sequences: ["Escape"]
        context: Qt.WindowShortcut
        onActivated: pop.escapeKey()
    }
    Connections {
        target: BarState
        enabled: pop.isOpen
        function onBarPressed(root, x, y) {
            if (!BarState.pressedOn(pop.pill, root, x, y)) pop.close();
        }
    }

    // the content's staggered entrance (stage(k) in the panels): OutExpo
    // put most of the move in the first few frames — a jolt; OutCubic glides
    NumberAnimation {
        id: introAnim
        target: pop; property: "intro"
        from: 0; to: 1; duration: 460
        easing.type: Easing.OutCubic
    }
    // the card: in = fade + grow from 96 % out of the pill's side (no
    // overshoot — the bounce read as a wobble); out = fade + shrink a little
    // back toward the pill (transformOrigin). While either runs the card is drawn as one texture
    // (layer) — scaling live text re-hints every glyph each frame, which
    // made the edges and words wobble.
    ParallelAnimation {
        id: openAnim
        NumberAnimation { target: card; property: "opacity"; to: 1; duration: 260; easing.type: Easing.OutCubic }
        NumberAnimation { target: card; property: "scale"; to: 1; duration: 380; easing.type: Easing.OutQuint }
    }
    ParallelAnimation {
        id: closeAnim
        NumberAnimation { target: card; property: "opacity"; to: 0; duration: 200; easing.type: Easing.InOutQuad }
        NumberAnimation { target: card; property: "scale"; to: 0.96; duration: 200; easing.type: Easing.InOutCubic }
        onFinished: {
            if (pop.isOpen) return;
            pop.shown = false;
            pop.closing = false;
            pop.intro = 0;
        }
    }

    Rectangle {
        id: card
        readonly property color panelTint: pop.tint     // Theme.tintOf finds it
        readonly property var panelPopup: pop           // Dropdown finds it
        width: parent.width
        height: parent.height
        radius: 18
        color: Theme.panel(Theme.mantle)
        border.width: 1
        border.color: Theme.alpha(Theme.surface1, 0.9)
        clip: true

        opacity: 0
        scale: 0.96
        transformOrigin: pop.edge === Edges.Bottom ? Item.Top : Item.Bottom
        layer.enabled: openAnim.running || closeAnim.running
        layer.smooth: true

        focus: true
        Keys.onEscapePressed: pop.escapeKey()
        // keys the focused control didn't take (Tab, Ctrl+arrows, arrows on
        // a button…) — see navKey
        Keys.onPressed: ev => { if (pop.navKey(ev.key, ev.modifiers)) ev.accepted = true; }
        readonly property Item winFocus: Window.activeFocusItem
        // the text box being typed in (focused by a click / focusAdd / Tab),
        // for the bars to forward keys to: Hyprland gives a popup's keys to
        // a BAR (the grab's first layer surface), never the popup itself
        readonly property Item textTarget: {
            const t = BarState.typing;
            return t && t.focus && t.visible && pop.inside(t) ? t : null;
        }
        onWinFocusChanged: if (winFocus && winFocus !== card && pop.inside(winFocus)) { BarState.kbItem = winFocus; pop.noteKb(winFocus); }

        Item {
            id: body
            x: pop.pad
            y: pop.pad
            width: parent.width - 2 * pop.pad
            height: childrenRect.height
        }
    }
}
