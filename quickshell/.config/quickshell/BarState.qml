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
            if (!p.pill || !p.navigable || rootOf(p.pill) !== root || !p.pill.visible || !p.pill.enabled) continue;
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
        openedAt = Date.now();
        openedPopup = p;
    }
    // when the open panel was opened (and which): one opened over Settings
    // is in front of it (see onCleared)
    property real openedAt: 0
    property var openedPopup: null
    function releaseGrab(p) {
        if (grabPopup === p || regrabFor.p === p) grabRelease.restart();
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
        // a click outside (or another grab): close the open panel — unless
        // it was a workspace switch (see below)
        onCleared: {
            const p = grabPopup || regrabFor.p;      // (regrab: bars-only for a beat)
            regrabFor.stop();
            regrabFor.p = null;
            grabRelease.stop();
            grabHeld = false;
            if (!p || !p.isOpen) { grabPopup = null; return; }
            if (Date.now() - wsSwitchAt < 400) { regrab(p); return; }
            // a picker or Settings (SUPER+Tab, SUPER+W, SUPER+I) took the keyboard: wait for it
            // — unless the panel was opened while Settings was already up (a
            // pill clicked with Settings open): then it is in front. Right
            // after it opened, the end is Settings' exclusive keyboard letting
            // go late (SettingsPanel retakes the grab); later, a real click
            // outside — close as usual.
            const inFront = pickerShown && openedPopup === p && openedAt > overlayAt;
            if (inFront && Date.now() - openedAt < 500) return;
            if (pickerShown && !inFront) { pausedPopup = p; return; }
            pendingClose = p;
            closeWait.restart();
        }
    }

    // Switching workspace (SUPER+1…, the special workspace, a swipe) focuses
    // a window there, and Hyprland ends the grab for it — that used to close
    // the open panel. A panel lives on the bar, which every workspace shows,
    // so it stays open: the grab is taken again, and Esc closes the panel
    // before any key reaches the windows of the new workspace. Which comes
    // first, the grab's end or Hyprland's workspace event, isn't fixed, so a
    // grab end waits closeWait for a switch before it closes the panel.
    property real wsSwitchAt: 0
    property var pendingClose: null
    // Take the grab back for the open panel `p`. Hyprland moves the keyboard
    // to a surface of the grab when it starts — any one, and it may pick the
    // panel's own popup surface, where Esc goes nowhere (the keys work on
    // the BAR, which forwards them; a fresh open() gets the bar because its
    // popup surface isn't mapped yet when the grab starts). So start with the
    // bars only, and add the panel once the keyboard is on a bar.
    function regrab(p) {
        pendingClose = null;
        closeWait.stop();
        grabPopup = null;
        regrabFor.p = p;
        Qt.callLater(() => {
            if (!p.isOpen || activePopup !== p) return;
            grabHeld = true;
            regrabFor.restart();
        });
    }
    // start the grab over for `p` (another surface — Settings — had the
    // keyboard while it began)
    function retake(p) {
        if (!p || !p.isOpen || activePopup !== p) return;
        pausedPopup = null;
        grabHeld = false;
        regrab(p);
    }
    Timer {
        id: regrabFor
        property var p: null
        interval: 40
        onTriggered: {
            if (p && p.isOpen && grabHeld && !grabPopup) {
                grabPopup = p;
                p.card.forceActiveFocus();
            }
            p = null;
        }
    }
    // The keyboard can slip out of a HELD grab (Hyprland 0.53): starting a
    // grab moves the keyboard to a bar with a bare seat call, so Hyprland's
    // own "focused surface" stays the window you were in. When any layer
    // surface unmaps meanwhile (a notification expiring, an OSD), Hyprland
    // hands the keyboard back to that window without asking the grab — the
    // panel stays open but Esc and typing go to the window behind. Qt sees the
    // keyboard leave (application state), so: take a surface out of the grab
    // and put it back. Hyprland then refocuses inside the grab the proper
    // way, which also makes the bar its focused surface, so later unmaps
    // leave the keyboard where it is. If that didn't bring it back, start
    // the grab over.
    Connections {
        target: Qt.application
        function onStateChanged() { kbCheck.restart(); }
    }
    function kbStray() {
        const p = activePopup;
        return Qt.application.state !== Qt.ApplicationActive
            && grabHeld && !!p && p.isOpen && grabPopup === p && !pickerShown;
    }
    Timer {
        id: kbCheck
        interval: 30                         // let a leave + enter pair settle
        onTriggered: {
            if (!kbStray()) return;
            const p = activePopup;
            console.warn("BarState: keyboard left the open panel; refocusing the grab");
            grabPopup = null;                // surface out (commit: Hyprland refocuses a bar)
            Qt.callLater(() => {
                if (!grabHeld || grabPopup || !p.isOpen || activePopup !== p) return;
                grabPopup = p;               // and back in
                p.card.forceActiveFocus();
                kbRetake.p = p;
                kbRetake.restart();
            });
        }
    }
    Timer {
        id: kbRetake
        property var p: null
        interval: 200
        onTriggered: {
            if (p && kbStray() && activePopup === p) { console.warn("BarState: keyboard still out; restarting the grab"); retake(p); }
            p = null;
        }
    }
    Timer {
        id: closeWait
        interval: 120
        onTriggered: {
            const p = pendingClose;
            pendingClose = null;
            if (grabPopup === p && !grabHeld) grabPopup = null;
            if (p && p.isOpen) p.close();
        }
    }
    // the pickers' and Settings' exclusive keyboard ends the grab too (the
    // workspace picker, SUPER+Tab; the wallpaper picker, SUPER+W; Settings,
    // SUPER+I): the panel stays open behind them and gets the grab back once
    // they close
    property bool wsPickerShown: false      // WorkspacePicker.qml sets it
    property bool wallPickerShown: false    // WallpaperPicker.qml sets it
    property bool settingsShown: false      // SettingsPanel.qml sets it
    // a screenshot's region pick / save window is up (see shotLayers below):
    // same deal — the panel stays on screen (so it's in the shot) and gets
    // the grab back after Esc
    readonly property bool shotUi: shotLayers > 0 || shotWindows.length > 0
    readonly property bool pickerShown: wsPickerShown || wallPickerShown || settingsShown || shotUi
    property real overlayAt: 0               // when pickerShown last became true
    property var pausedPopup: null
    onPickerShownChanged: {
        if (pickerShown) overlayAt = Date.now();
        if (pickerShown || !pausedPopup) return;
        const p = pausedPopup;
        pausedPopup = null;
        pickerDone.p = p;
        if (p.isOpen) pickerDone.restart();
    }
    Timer {
        id: pickerDone
        property var p: null
        interval: 60                         // the picker's layer lets go of the keyboard first
        onTriggered: if (p && p.isOpen && activePopup === p) regrab(p)
    }
    // Screenshots (SUPER+SHIFT+S → screenshot.sh, the recorder's region pick):
    // slurp's overlay (layer namespace "selection") takes the keyboard, which
    // ends the grab — that used to close the open panel (and a right-click
    // menu, MenuPopup.qml) before the overlay even showed. While it, or the
    // "Save screenshot?" window after it, is up, the panel is paused as
    // behind a picker; Esc in slurp (or closing the save window) gives the
    // grab back. Hyprland's layer/window events and the grab's end race, so
    // a grab end waits closeWait first (as for a workspace switch).
    property int shotLayers: 0
    property var shotWindows: []              // addresses of screenshot-save windows
    onShotUiChanged: if (shotUi && pendingClose) {
        pausedPopup = pendingClose;
        pendingClose = null;
        closeWait.stop();
    }
    Connections {
        target: Hyprland
        function onRawEvent(ev) {
            if (ev.name === "openlayer" || ev.name === "closelayer") {
                if (ev.data === "selection")
                    shotLayers = Math.max(0, shotLayers + (ev.name === "openlayer" ? 1 : -1));
                return;
            }
            if (ev.name === "openwindow") {
                const f = ev.data.split(",");         // ADDRESS,WORKSPACE,CLASS,TITLE
                if (f[2] === "screenshot-save") shotWindows = shotWindows.concat([f[0]]);
                return;
            }
            if (ev.name === "closewindow") {
                if (shotWindows.includes(ev.data)) shotWindows = shotWindows.filter(a => a !== ev.data);
                return;
            }
            if (ev.name !== "workspacev2" && ev.name !== "activespecialv2") return;
            wsSwitchAt = Date.now();
            if (pendingClose) regrab(pendingClose);
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
