// What the per-screen bars share. shell.qml makes one top bar and one bottom
// bar for every screen (a duplicated screen isn't one: Hyprland withdraws
// its output while it mirrors).
//
//   primary  the laptop panel (else the first screen): side effects that
//            must happen once (the focus timer's phase change) run there
//   active   the focused monitor's screen (else the primary): its bars own
//            the IPC targets, so `qs ipc call …` opens menus where you are
//
// The bottom bar's shown state and keep-awake live here so every screen
// follows one switch; both survive config reloads.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland

Singleton {
    readonly property string primary: {
        const s = Quickshell.screens;
        const main = s.find(x => /^(eDP|LVDS|DSI)/.test(x.name)) || s[0];
        return main ? main.name : "";
    }
    readonly property string active: {
        const f = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        return Quickshell.screens.some(x => x.name === f) ? f : primary;
    }

    // Open a panel from anywhere (another bar, another screen, a keybind's
    // IPC): the active screen's bars / shell.qml pick it up.
    //   "settings" TAB · "notifications" system|phone · "audio" · "network" wifi|bluetooth
    signal panelRequested(string name, string arg)

    // The bars stay live while a popup is open: every popup's focus grab
    // includes them (bars), so hovering and clicking other pills works. A
    // click on a bar (a Pill, or the bar's empty background) is announced here; each
    // open popup closes unless the press was on its own pill (whose click
    // then toggles it as usual) — so clicking another pill swaps popups.
    property var bars: []
    function addBar(w) { if (!bars.includes(w)) bars = bars.concat([w]); }
    function removeBar(w) { bars = bars.filter(b => b !== w); }
    // `root`: the top of the pressed bar's item tree (rootOf), which tells
    // windows apart (a popup's anchor.window is a different object than the
    // bar's own id); x, y in that window
    signal barPressed(var root, real x, real y)
    // Esc anywhere while a popup is open: with the pointer over a popup,
    // Hyprland gives the keys to the BAR (the popup's parent layer surface),
    // not the popup — so the bars forward Esc here and every open popup closes
    signal escapePressed()
    // Ctrl+Tab / Ctrl+Shift+Tab reaching a bar (same reason): the open popup's menu tabs
    signal tabPressed(int dir)

    // ── keyboard navigation (PanelPopup.navKey, FocusRing) ──────────────────
    //   activePopup  the bar popup open now (one at a time), or null
    //   kbItem       the control the keyboard is on inside it (for the ring,
    //                and for keys the BAR forwards: with the pointer over a
    //                popup Hyprland gives the keys to the bar)
    //   popups       every PanelPopup on every bar (they register themselves),
    //                for Ctrl+← / → (along the bar) and Ctrl+↑ / ↓ (other bar)
    property var activePopup: null
    property var kbItem: null
    // the open popup came from the keyboard (SUPER+. / Ctrl+arrows): its
    // pill shows the hover highlight so you can see where you are
    property bool kbMode: false
    // the text box last focused in a bar popup (a click or forceActiveFocus
    // sets its `focus` even while Hyprland keeps the keyboard on a bar); the
    // bars forward typing to it (TopBar / BottomBar key sink)
    property var typing: null
    property var popups: []
    function addPopup(p) { if (!popups.includes(p)) popups = popups.concat([p]); }
    function removePopup(p) {
        popups = popups.filter(x => x !== p);
        if (activePopup === p) activePopup = null;
    }
    // the popups of the bar `root` (a bar window's item root), left to right,
    // whose pill is on screen now
    function barPopups(root) {
        const out = [];
        for (const p of popups) {
            if (!p.pill || !p.navigable || rootOf(p.pill) !== root || !p.pill.visible) continue;
            // a hidden ancestor (the island of a pill that is shown: false…)
            let ok = true;
            for (let it = p.pill; it; it = it.parent) if (!it.visible) { ok = false; break; }
            if (!ok || p.pill.width <= 0) continue;
            out.push({ pop: p, x: p.pill.mapToItem(null, 0, 0).x + p.pill.width / 2 });
        }
        out.sort((a, b) => a.x - b.x);
        return out;
    }
    // ONE focus grab for every bar panel, kept while you switch between them
    // (Ctrl+arrows, or a click on another pill). Each popup used to have its
    // own: a switch destroyed one grab and made the next, and every time
    // Hyprland sent the bar's keyboard a leave + enter — Qt's key repeat dies
    // at a leave, so a HELD Ctrl+arrow moved one pill and stopped. Now only
    // the popup in it changes (add/remove surface, same grab); it ends a beat
    // after the last popup closes, unless another opens meanwhile.
    property var grabPopup: null
    property bool grabHeld: false
    function grabFor(p) {
        grabRelease.stop();
        grabPopup = p;
        grabHeld = true;
    }
    function releaseGrab(p) {
        if (grabPopup === p) grabRelease.restart();
    }
    Timer {
        id: grabRelease
        interval: 80
        onTriggered: {
            if (activePopup && activePopup.isOpen) return;
            grabHeld = false;
            grabPopup = null;
        }
    }
    HyprlandFocusGrab {
        active: grabHeld
        windows: (grabPopup ? [grabPopup] : []).concat(bars)
        // a click outside (or another grab): close the open panel
        onCleared: {
            const p = grabPopup;
            grabRelease.stop();
            grabHeld = false;
            grabPopup = null;
            if (p && p.isOpen) p.close();
        }
    }

    // Ctrl+arrow from the open popup: left / right along its bar, up / down to
    // the other bar (the popup whose pill is nearest in x). A held Ctrl+arrow
    // repeats ~25×/s; it walks at most one pill per 120 ms (each step opens a
    // panel, some start a helper process)
    property real lastNav: 0
    function navPopup(dir) {
        const cur = activePopup;
        if (!cur || !cur.pill) return;
        const t = Date.now();
        if (t - lastNav < 120) return;
        lastNav = t;
        const root = rootOf(cur.pill);
        let next = null;
        if (dir === "left" || dir === "right") {
            const list = barPopups(root);
            const i = list.findIndex(e => e.pop === cur);
            if (list.length < 2 || i < 0) return;
            next = list[(i + (dir === "right" ? 1 : -1) + list.length) % list.length].pop;
        } else {
            const x = cur.pill.mapToItem(null, 0, 0).x + cur.pill.width / 2;
            const cand = [];
            for (const r of bars.map(b => b.navRoot ? b.navRoot() : null).filter((v, k, a) => v && a.indexOf(v) === k)) {
                if (r === root) continue;
                for (const e of barPopups(r)) cand.push(e);
            }
            if (!cand.length) return;
            cand.sort((a, b) => Math.abs(a.x - x) - Math.abs(b.x - x));
            next = cand[0].pop;
        }
        if (!next || next === cur) return;
        cur.close();
        next.openByKeyboard();
    }
    // start keyboard mode from nothing (the keybind): the sound panel of the
    // focused screen's top bar, else the leftmost one there
    function startNav() {
        // open one: SUPER+. again closes it (a stale reference — a popup that
        // is no longer open — must not block the start)
        if (activePopup && activePopup.isOpen) { activePopup.close(); return; }
        activePopup = null;
        const tops = bars.filter(b => b.screen && b.screen.name === active && b.isTopBar);
        const root = tops.length && tops[0].navRoot ? tops[0].navRoot() : null;
        const list = root ? barPopups(root) : [];
        if (!list.length) return;
        const snd = list.find(e => e.pop.navName === "audio");
        (snd || list[0]).pop.openByKeyboard();
    }
    function rootOfItem(i) { return rootOf(i); }
    function rootOf(item) {
        while (item && item.parent) item = item.parent;
        return item;
    }
    // was that press on `item`?
    function pressedOn(item, root, x, y) {
        if (!item || !item.visible || rootOf(item) !== root) return false;
        const p = item.mapToItem(null, 0, 0);
        return x >= p.x && x < p.x + item.width && y >= p.y && y < p.y + item.height;
    }

    property alias bottomShown: state.bottomShown
    property alias keepAwake: state.keepAwake
    PersistentProperties {
        id: state
        reloadableId: "barState"
        property bool bottomShown: true
        property bool keepAwake: false
    }
}
