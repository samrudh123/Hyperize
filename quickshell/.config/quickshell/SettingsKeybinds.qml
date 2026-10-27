// Settings › Keybindings — every Hyprland bind (hyprland.conf) and every
// Neovim keymap, searchable, each one movable to another key — plus bindings
// of your own: "+ Add" opens a form (name, keys, a command or a Hyprland
// action / a Neovim action); they list under "Your own …" with edit/delete.
// The same form edits ANY binding's name and what it runs (✎ on a row): for
// hyprland.conf's binds that is an override (Reset puts it back); for an
// existing Neovim mapping, a replacement on the same keys (LSP buffer maps
// excluded — they are re-made per buffer).
// 🗑 deletes: your own bindings for good; hyprland.conf's / Neovim's are
// unbound (listed struck through; Restore brings them back).
//
// Hyprland: hypr/settings-keybinds.py. Changes go to keybinds-user.conf
// (unbind + bind, sourced last by hyprland.conf), applied with a reload.
// While a new combo is being recorded Hyprland sits in the empty
// `kbcapture` submap, so combos that are already bound reach this panel
// instead of firing (Escape leaves it = cancel).
//
// Neovim: hypr/settings-nvim.py dumps the keymaps from a headless nvim and
// writes ~/.config/nvim/keymap-overrides.json, which the config's
// lua/keymap-overrides.lua applies at startup (new nvims only).
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

SettingsPage {
    id: page
    title: "Keybindings"
    subtitle: mode === 0
        ? "Hyprland binds from hyprland.conf. Change one and press the new combo — your changes live in keybinds-user.conf and apply at once."
        : "Neovim's keymaps (your config, plugins, LSP, defaults). Moved keys apply to Neovim windows opened from now on."

    property int mode: 0                      // 0 Hyprland, 1 Neovim
    property var hypr: []
    property var nvim: []
    property bool loading: false
    property bool nvimLoaded: false

    // the row being changed: hypr bind id, or "mode|orig" for nvim
    property string capId: ""
    property var capEntry: null
    property string held: ""                  // modifiers held right now (hypr)
    property var pendMods: ""
    property string pendKey: ""
    property var tokens: []                   // nvim key sequence
    property var conflict: []
    property string note: ""

    readonly property string leader: " "

    // ── the add / edit form ─────────────────────────────────────────────────
    property bool adding: false
    property var editing: null                // the custom entry being edited
    property string fName: ""
    property int fKind: 0                     // hypr: 0 run a command, 1 Hyprland action
    property string fCmd: ""
    property string fDisp: ""
    property string fArg: ""
    property string fMods: ""
    property string fKey: ""
    property string fMode: "n"                // nvim
    property string fLhs: ""
    property string fRhs: ""
    property var fConflict: []
    property string fError: ""
    property bool fBusy: false
    property string delArmed: ""              // a custom row's id, armed for delete
    Timer { id: disarm; interval: 4000; onTriggered: page.delArmed = "" }
    readonly property var nvimModes: [["n", "Normal"], ["i", "Insert"], ["x", "Visual"], ["t", "Terminal"]]
    readonly property var quickActions: [
        ["killactive", "", "Close window"], ["togglefloating", "", "Float"], ["fullscreen", "0", "Fullscreen"],
        ["fullscreen", "1", "Maximise"], ["pin", "", "Pin"], ["workspace", "e+1", "Next workspace"],
        ["movetoworkspace", "e+1", "Move to next ws"], ["togglespecialworkspace", "", "Scratchpad"],
        ["centerwindow", "", "Centre window"], ["togglesplit", "", "Toggle split"]
    ]

    function openForm(e) {
        use(e);
        cancelCapture();
        editing = e || null;
        fConflict = []; fError = ""; fBusy = false;
        if (mode === 0) {
            const arg = e ? (e.argEdit !== undefined ? e.argEdit : e.arg) : "";
            fName = e ? (e.name || e.desc || "") : "";
            fKind = e && e.dispatcher !== "exec" ? 1 : 0;
            fCmd = e && e.dispatcher === "exec" ? arg : "";
            fDisp = e && e.dispatcher !== "exec" ? e.dispatcher : "";
            fArg = e && e.dispatcher !== "exec" ? arg : "";
            fMods = e ? e.curMods : ""; fKey = e ? e.curKey : "";
        } else {
            fName = e ? (e.desc || "") : "";
            fMode = e ? (e.mode === "v" ? "x" : e.mode) : "n";
            fLhs = e ? e.lhs : "";
            fRhs = e && e.rhs !== "<Lua function>" ? e.rhs : "";
        }
        adding = true;
    }
    // editing one of Neovim's existing mappings: keys and mode stay
    readonly property bool nvimEditExisting: mode === 1 && !!editing && editing.custom !== true
    function closeForm() { cancelCapture(); adding = false; editing = null; fConflict = []; fError = ""; }
    readonly property bool formReady: mode === 0
        ? fKey !== "" && (fKind === 0 ? fCmd.trim() !== "" : /^[a-z]+$/.test(fDisp.trim()))
        : fLhs.trim() !== "" && fRhs.trim() !== ""
    function saveForm(force) {
        if (!formReady || fBusy) return;
        fError = "";
        if (mode === 0) {
            const disp = fKind === 0 ? "exec" : fDisp.trim();
            const arg = fKind === 0 ? fCmd.trim() : fArg.trim();
            const args = editing ? ["edit", editing.id] : ["add"];
            fBusy = true;
            run([Theme.hypr + "/settings-keybinds.py"].concat(args, [fMods, fKey, disp, arg, fName.trim()], force ? ["--force"] : []), r => {
                page.fBusy = false;
                if (r.conflict) { page.fConflict = r.conflict; return; }
                if (!r.ok) { page.fError = r.error || r.hyprctl || "Hyprland didn't take it"; return; }
                page.closeForm();
                hyprProc.running = true;
            });
        } else {
            const lhs = fLhs.trim();
            if (!force && !nvimEditExisting) {
                const clash = nvim.filter(x => x.mode === fMode && canon(x.lhs) === canon(lhs)
                                          && !(editing && x.mode === editing.mode && canon(x.lhs) === canon(editing.lhs)));
                if (clash.length) { fConflict = clash.map(x => x.desc || x.rhs || x.lhs); return; }
            }
            if (nvimEditExisting) {                // same keys, new action / description
                fBusy = true;
                run([Theme.hypr + "/settings-nvim.py", "add", editing.mode, editing.lhs, fRhs.trim(), fName.trim(),
                     "--edit", editing.group], r => {
                    page.fBusy = false;
                    if (!r.ok) { page.fError = r.error || "couldn't save it"; return; }
                    page.closeForm();
                    page.loading = true;
                    nvimProc.running = true;
                });
                return;
            }
            const add = () => run([Theme.hypr + "/settings-nvim.py", "add", fMode, lhs, fRhs.trim(), fName.trim()], r => {
                page.fBusy = false;
                if (!r.ok) { page.fError = r.error || "couldn't save it"; return; }
                page.closeForm();
                page.loading = true;
                nvimProc.running = true;
            });
            fBusy = true;
            if (editing && (editing.mode !== fMode || canon(editing.lhs) !== canon(lhs)))
                run([Theme.hypr + "/settings-nvim.py", "remove", editing.mode, editing.lhs], add);
            else add();
        }
    }
    function removeCustom(e) {
        use(e);
        if (delArmed !== (mode === 0 ? e.id : e.mode + "|" + e.lhs)) {
            delArmed = mode === 0 ? e.id : e.mode + "|" + e.lhs;
            disarm.restart();
            return;
        }
        delArmed = "";
        // your own: gone; an existing one: unbound / freed (Reset restores it)
        if (mode === 0) run([Theme.hypr + "/settings-keybinds.py", "delete", e.id], r => {
            page.note = r.ok === false ? "Hyprland said: " + (r.error || r.hyprctl || "?") : "";
            hyprProc.running = true;
        });
        else if (e.custom) run([Theme.hypr + "/settings-nvim.py", "remove", e.mode, e.lhs], () => { page.loading = true; nvimProc.running = true; });
        else run([Theme.hypr + "/settings-nvim.py", "delete", e.mode, e.lhs, e.group, e.desc || "",
                  e.rhs === "<Lua function>" ? "" : (e.rhs || "")], () => { page.loading = true; nvimProc.running = true; });
    }
    // recording the form's keys: a capture with a pseudo entry
    function recordForm() {
        startCapture({ id: "__form__", mode: fMode, orig: "__form__", form: true });
        tokens = [];
    }
    readonly property bool formCapturing: capEntry !== null && capEntry.form === true

    // evdev keycode → Hyprland / xkb key name (US layout)
    readonly property var keyNames: ({
        1: "Escape", 2: "1", 3: "2", 4: "3", 5: "4", 6: "5", 7: "6", 8: "7", 9: "8", 10: "9", 11: "0",
        12: "minus", 13: "equal", 14: "BackSpace", 15: "Tab",
        16: "Q", 17: "W", 18: "E", 19: "R", 20: "T", 21: "Y", 22: "U", 23: "I", 24: "O", 25: "P",
        26: "bracketleft", 27: "bracketright", 28: "Return",
        30: "A", 31: "S", 32: "D", 33: "F", 34: "G", 35: "H", 36: "J", 37: "K", 38: "L",
        39: "semicolon", 40: "apostrophe", 41: "grave", 43: "backslash",
        44: "Z", 45: "X", 46: "C", 47: "V", 48: "B", 49: "N", 50: "M",
        51: "comma", 52: "period", 53: "slash", 55: "KP_Multiply", 57: "space",
        59: "F1", 60: "F2", 61: "F3", 62: "F4", 63: "F5", 64: "F6", 65: "F7", 66: "F8", 67: "F9", 68: "F10",
        87: "F11", 88: "F12", 96: "KP_Enter", 99: "Print", 102: "Home", 103: "up", 104: "Prior",
        105: "left", 106: "right", 107: "End", 108: "down", 109: "Next", 110: "Insert", 111: "Delete",
        113: "XF86AudioMute", 114: "XF86AudioLowerVolume", 115: "XF86AudioRaiseVolume", 119: "Pause",
        163: "XF86AudioNext", 164: "XF86AudioPlay", 165: "XF86AudioPrev",
        224: "XF86MonBrightnessDown", 225: "XF86MonBrightnessUp"
    })
    // xkb names → Vim notation, for the keys Vim writes as <…>
    readonly property var vimNames: ({
        Return: "CR", Tab: "Tab", space: "Space", BackSpace: "BS", Delete: "Del", Escape: "Esc",
        left: "Left", right: "Right", up: "Up", down: "Down", Home: "Home", End: "End",
        Prior: "PageUp", Next: "PageDown", Insert: "Insert", KP_Enter: "kEnter"
    })
    readonly property var modeNames: ({ n: "Normal", i: "Insert", x: "Visual", s: "Select", o: "Operator", t: "Terminal", c: "Command", v: "Visual" })

    function modsOf(ev) {
        const m = [];
        if (ev.modifiers & Qt.MetaModifier) m.push("SUPER");
        if (ev.modifiers & Qt.ShiftModifier) m.push("SHIFT");
        if (ev.modifiers & Qt.ControlModifier) m.push("CTRL");
        if (ev.modifiers & Qt.AltModifier) m.push("ALT");
        return m.join(" ");
    }
    function isModKey(k) {
        return [Qt.Key_Meta, Qt.Key_Super_L, Qt.Key_Super_R, Qt.Key_Shift, Qt.Key_Control, Qt.Key_Alt,
                Qt.Key_AltGr, Qt.Key_Hyper_L, Qt.Key_Hyper_R, Qt.Key_CapsLock].includes(k);
    }
    function canon(lhs) {
        return (lhs || "").replace(/<[^>]+>/g, s => s.toLowerCase()).replace(/^<space>/, "<leader>");
    }

    // ── loading ─────────────────────────────────────────────────────────────
    function reload() {
        if (mode === 0) { hyprProc.running = true; }
        else { loading = true; nvimProc.running = true; }
    }
    Process {
        id: hyprProc
        running: true
        command: ["/usr/bin/python3", Theme.hypr + "/settings-keybinds.py", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { const d = JSON.parse(text); d.forEach(e => e._hy = true); page.hypr = d; } catch (e) {}
            }
        }
    }
    Process {
        id: nvimProc
        command: ["/usr/bin/python3", Theme.hypr + "/settings-nvim.py", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { page.nvim = JSON.parse(text); } catch (e) {}
                page.loading = false;
                page.nvimLoaded = true;
            }
        }
    }
    // one-off commands (set / reset); `then` runs with the parsed JSON
    Process {
        id: act
        property var then: null
        stdout: StdioCollector {
            onStreamFinished: {
                let r = {};
                try { r = JSON.parse(text); } catch (e) {}
                const f = act.then;
                act.then = null;
                if (f) f(r);
            }
        }
    }
    function run(args, then) {
        act.then = then || null;
        act.command = ["/usr/bin/python3"].concat(args);
        act.running = true;
    }

    // ── capturing a new combo ───────────────────────────────────────────────
    function startCapture(entry) {
        use(entry);
        if (capId) cancelCapture();
        capEntry = entry;
        capId = mode === 0 ? entry.id : entry.mode + "|" + entry.orig;
        pendMods = ""; pendKey = ""; tokens = []; held = ""; conflict = []; note = "";
        if (mode === 0) Hyprland.dispatch("submap kbcapture");
        catcher.forceActiveFocus();
    }
    function cancelCapture() {
        const was = capId !== "" && mode === 0;
        capId = ""; capEntry = null; conflict = []; held = "";
        if (was) Hyprland.dispatch("submap reset");
    }
    Component.onDestruction: if (capId && mode === 0) Hyprland.dispatch("submap reset")

    // Escape inside the capture submap is Hyprland's (it leaves the submap):
    // treat leaving it as cancel
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "submap" && event.data !== "kbcapture" && page.capId && page.mode === 0 && !act.running)
                page.cancelCapture();
        }
    }

    function confirm(force) {
        if (!capEntry) return;
        if (capEntry.form) {                       // the form's keys: just keep them
            if (mode === 0) { if (!pendKey) return; fMods = pendMods; fKey = pendKey; }
            else { if (!tokens.length) return; fLhs = tokens.join(""); }
            fConflict = [];
            cancelCapture();
            return;
        }
        if (mode === 0) {
            if (!pendKey) return;
            const id = capEntry.id;
            run([Theme.hypr + "/settings-keybinds.py", "set", id, pendMods, pendKey].concat(force ? ["--force"] : []), r => {
                if (r.conflict) { page.conflict = r.conflict; return; }
                page.note = r.ok ? "" : "Hyprland said: " + (r.hyprctl || r.error || "?");
                page.capId = ""; page.capEntry = null; page.conflict = [];
                Hyprland.dispatch("submap reset");
                hyprProc.running = true;
            });
        } else {
            if (!tokens.length) return;
            const lhs = tokens.join("");
            const e = capEntry;
            if (!force) {
                const clash = nvim.filter(x => x.mode === e.mode && canon(x.lhs) === canon(lhs) && x !== e);
                if (clash.length) { conflict = clash.map(x => x.desc || x.rhs || x.lhs); return; }
            }
            run([Theme.hypr + "/settings-nvim.py", "set", e.mode, e.orig, lhs], r => {
                page.capId = ""; page.capEntry = null; page.conflict = [];
                page.loading = true;
                nvimProc.running = true;
            });
        }
    }
    function resetEntry(e) {
        use(e);
        if (mode === 0) run([Theme.hypr + "/settings-keybinds.py", "reset", e.id], () => hyprProc.running = true);
        else run([Theme.hypr + "/settings-nvim.py", "reset", e.mode, e.orig], () => { page.loading = true; nvimProc.running = true; });
    }
    function resetAll() {
        if (mode === 0) run([Theme.hypr + "/settings-keybinds.py", "reset-all"], () => hyprProc.running = true);
        else run([Theme.hypr + "/settings-nvim.py", "reset-all"], () => { page.loading = true; nvimProc.running = true; });
    }

    // invisible key catcher, focused while capturing
    Item {
        id: catcher
        width: 0
        height: 0
        Keys.onPressed: ev => {
            if (!page.capId) return;
            ev.accepted = true;
            const name = page.keyNames[ev.nativeScanCode - 8] || "";
            if (page.mode === 0) {
                if (page.isModKey(ev.key)) { page.held = page.modsOf(ev); return; }
                if ((ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) && !ev.modifiers && page.pendKey) { page.confirm(page.conflict.length > 0); return; }
                if (ev.key === Qt.Key_Escape && !ev.modifiers) { page.cancelCapture(); return; }
                if (!name) { page.note = "That key can't be bound from here"; return; }
                page.note = "";
                page.conflict = [];
                page.pendMods = page.modsOf(ev);
                page.pendKey = name;
                if (page.capEntry && page.capEntry.form) page.confirm(false);
            } else {
                if (page.isModKey(ev.key)) return;
                const mods = ev.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier);
                if ((ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) && !ev.modifiers) { page.confirm(page.conflict.length > 0); return; }
                if (ev.key === Qt.Key_Escape && !ev.modifiers) { page.cancelCapture(); return; }
                if (ev.key === Qt.Key_Backspace && !ev.modifiers) { page.tokens = page.tokens.slice(0, -1); page.conflict = []; return; }
                let t;
                const special = page.vimNames[name];
                if (special || mods || /^F\d+$/.test(name)) {
                    let base = special || (/^F\d+$/.test(name) ? name : (name.length === 1 ? name.toLowerCase() : (ev.text || name)));
                    let p = "";
                    if (ev.modifiers & Qt.ControlModifier) p += "C-";
                    if (ev.modifiers & (Qt.AltModifier | Qt.MetaModifier)) p += "M-";
                    if ((ev.modifiers & Qt.ShiftModifier) && (special || /^F\d+$/.test(name))) p += "S-";
                    t = (special === "Space" && !p && page.tokens.length === 0 && page.leader === " ") ? "<leader>" : "<" + p + base + ">";
                } else {
                    t = ev.text;
                    if (t === "<") t = "<lt>";
                }
                if (!t) return;
                page.conflict = [];
                page.tokens = page.tokens.concat([t]);
            }
        }
        Keys.onReleased: ev => { if (page.capId && page.mode === 0) page.held = page.modsOf(ev); }
    }

    // ── the list ────────────────────────────────────────────────────────────
    readonly property var groupOrder: ["Your own mappings", "Your config", "Plugins (load on first use)", "LSP (when a language server attaches)"]
    // While searching, the list holds BOTH Hyprland's and Neovim's matches
    // (the current tab's first, headings say which), each row with all its
    // buttons: acting on a row of the other kind switches the tab to it
    // first (use()), so the page's per-mode logic stays as it is.
    readonly property bool searching: SettingsState.query.trim() !== ""
    onSearchingChanged: if (searching && !nvimLoaded && !nvimProc.running) { loading = true; nvimProc.running = true; }
    Component.onCompleted: if (searching && !nvimLoaded) { loading = true; nvimProc.running = true; }
    function use(e) {
        if (!e || e.form) return;
        const m = e._hy === true ? 0 : 1;
        if (mode !== m) { cancelCapture(); adding = false; editing = null; mode = m; }
    }
    readonly property var nvimSorted: nvim.slice().sort((a, b) => {
        const ga = groupOrder.indexOf(a.group), gb = groupOrder.indexOf(b.group);
        const ra = ga < 0 ? (a.group === "Neovim defaults" ? 99 : 50) : ga;
        const rb = gb < 0 ? (b.group === "Neovim defaults" ? 99 : 50) : gb;
        return ra - rb || a.group.localeCompare(b.group);
    })
    function matches(list, hy, q, tag) {
        const out = [];
        let g = null;
        for (const e of list) {
            const hay = hy
                ? (e.desc + " " + e.curMods + " " + e.curKey + " " + e.group + " " + e.dispatcher + " " + e.argExpanded).toLowerCase()
                : (e.desc + " " + e.lhs + " " + e.rhs + " " + e.group + " " + (modeNames[e.mode] || "") + " neovim nvim").toLowerCase();
            if (q && !hay.includes(q)) continue;
            if (e.group !== g) { g = e.group; out.push({ header: tag + g, hy: hy }); }
            out.push(e);
        }
        return out;
    }
    readonly property var rows: {
        const q = SettingsState.query.trim().toLowerCase();
        if (!q) return mode === 0 ? matches(hypr, true, "", "") : matches(nvimSorted, false, "", "");
        const h = matches(hypr, true, q, "Hyprland · "), n = matches(nvimSorted, false, q, "Neovim · ");
        return mode === 0 ? h.concat(n) : n.concat(h);
    }
    readonly property int changedCount: (mode === 0 ? hypr : nvim).filter(e => e.changed).length

    // toolbar
    Item {
        width: parent.width
        height: 38
        Segmented {
            id: seg
            width: 260
            height: 36
            options: ["\u{f359}  Hyprland", "\u{e62b}  Neovim"]
            currentIndex: page.mode
            onSelected: i => {
                page.closeForm();
                page.mode = i;
                if (i === 1 && !page.nvimLoaded && !nvimProc.running) { page.loading = true; nvimProc.running = true; }
            }
        }
        Text {
            anchors.left: seg.right
            anchors.leftMargin: 14
            anchors.verticalCenter: parent.verticalCenter
            text: page.searching ? page.rows.filter(r => r.header === undefined).length + " matches in Hyprland & Neovim"
                                   + (page.loading ? "  ·  reading Neovim's keymaps…" : "")
                : page.mode === 1 && page.loading ? "Reading Neovim's keymaps…"
                : (page.mode === 0 ? page.hypr.length : page.nvim.length) + " bindings"
                  + (page.changedCount ? "  ·  " + page.changedCount + " changed" : "")
            color: Theme.overlay1
            font.family: Theme.font
            font.pixelSize: 12
        }
        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            IconBtn {
                visible: page.changedCount > 0
                icon: "\u{f0450}"
                text: "Reset all"
                fg: Theme.peach
                tip: "Put every moved key back (your own bindings stay)"
                onClicked: page.resetAll()
            }
            IconBtn {
                icon: "\u{f0415}"
                text: page.mode === 0 ? "Add binding" : "Add mapping"
                active: page.adding
                onClicked: page.adding ? page.closeForm() : page.openForm(null)
            }
        }
    }

    // ── the add / edit form ─────────────────────────────────────────────────
    Rectangle {
        id: form
        visible: page.adding
        width: parent.width
        height: visible ? formCol.implicitHeight + 32 : 0
        radius: 14
        color: Theme.alpha(Theme.accent, 0.07)
        border.width: 1
        border.color: Theme.alpha(Theme.accent, 0.45)

        Column {
            id: formCol
            x: 16
            y: 16
            width: parent.width - 32
            spacing: 12

            Text {
                text: (page.editing ? "Edit " : "New ") + (page.mode === 0 ? "Hyprland binding" : "Neovim mapping")
                    + (page.editing && page.editing.custom !== true ? "  ·  " + (page.mode === 0 ? page.editing.origDesc || page.editing.desc : page.editing.lhs) : "")
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 15
                font.weight: Font.Bold
            }

            // name
            Row {
                spacing: 12
                width: parent.width
                Text { width: 90; anchors.verticalCenter: parent.verticalCenter; text: page.mode === 0 ? "Name" : "Description"; color: Theme.subtext0; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold }
                SettingsField {
                    width: parent.width - 102
                    placeholder: page.mode === 0 ? "What it does, e.g. “System monitor”" : "e.g. “Save file”"
                    text: page.fName
                    onEdited: t => page.fName = t
                    onEscaped: page.closeForm()
                    onAccepted: page.saveForm(false)
                }
            }

            // Neovim: which mode
            Row {
                visible: page.mode === 1 && !page.nvimEditExisting
                spacing: 12
                Text { width: 90; anchors.verticalCenter: parent.verticalCenter; text: "Mode"; color: Theme.subtext0; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold }
                Segmented {
                    width: 380
                    height: 32
                    options: page.nvimModes.map(m => m[1])
                    currentIndex: Math.max(0, page.nvimModes.findIndex(m => m[0] === page.fMode))
                    onSelected: i => { page.fMode = page.nvimModes[i][0]; page.fConflict = []; }
                }
            }

            // keys
            Row {
                visible: !page.nvimEditExisting
                spacing: 12
                width: parent.width
                Text { width: 90; anchors.verticalCenter: parent.verticalCenter; text: "Keys"; color: Theme.subtext0; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold }
                // Hyprland: recorded combo as chips
                Row {
                    visible: page.mode === 0
                    spacing: 6
                    anchors.verticalCenter: parent.verticalCenter
                    Repeater {
                        model: {
                            if (page.formCapturing) {
                                const m = page.held;
                                return (m ? m.split(" ") : []).concat(["…"]);
                            }
                            return page.fKey ? (page.fMods ? page.fMods.split(" ") : []).concat([page.fKey]) : [];
                        }
                        delegate: SettingsChip {
                            required property var modelData
                            text: modelData
                            fg: page.formCapturing ? Theme.crust : Theme.text
                            bg: page.formCapturing ? Theme.accent : Theme.alpha(Theme.surface1, 0.8)
                        }
                    }
                }
                // Neovim: typed or recorded key notation
                SettingsField {
                    visible: page.mode === 1
                    width: 220
                    mono: true
                    placeholder: "<leader>w  ·  <C-s>  ·  gx"
                    text: page.formCapturing ? page.tokens.join("") : page.fLhs
                    onEdited: t => { page.fLhs = t; page.fConflict = []; }
                    onEscaped: page.closeForm()
                }
                IconBtn {
                    anchors.verticalCenter: parent.verticalCenter
                    size: 32
                    icon: page.formCapturing ? "\u{f0ec2}" : "\u{f097b}"
                    text: page.formCapturing ? (page.mode === 0 ? "Press the combo…" : "Type keys · Enter done")
                        : (page.mode === 0 ? (page.fKey ? "Record again" : "Record keys") : "Record")
                    active: page.formCapturing
                    tip: page.mode === 0 ? "Press the key combination (Esc cancels)" : "Type the keys; Space first = <leader>; Enter to finish, Esc cancels"
                    onClicked: page.formCapturing ? page.cancelCapture() : page.recordForm()
                }
            }

            // Hyprland: what it does
            Row {
                visible: page.mode === 0
                spacing: 12
                Text { width: 90; anchors.verticalCenter: parent.verticalCenter; text: "Does"; color: Theme.subtext0; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold }
                Segmented {
                    width: 320
                    height: 32
                    options: ["Run a command", "Hyprland action"]
                    currentIndex: page.fKind
                    onSelected: i => page.fKind = i
                }
            }
            Row {
                visible: page.mode === 0 && page.fKind === 0
                spacing: 12
                width: parent.width
                Item { width: 90; height: 1 }
                SettingsField {
                    width: parent.width - 102
                    mono: true
                    placeholder: "e.g.  ghostty -e btop   ·   ~/.local/bin/qs ipc call players toggle"
                    text: page.fCmd
                    onEdited: t => page.fCmd = t
                    onEscaped: page.closeForm()
                    onAccepted: page.saveForm(false)
                }
            }
            Column {
                visible: page.mode === 0 && page.fKind === 1
                spacing: 8
                width: parent.width
                Flow {
                    x: 102
                    width: parent.width - 102
                    spacing: 6
                    Repeater {
                        model: page.quickActions
                        delegate: IconBtn {
                            required property var modelData
                            size: 26
                            text: modelData[2]
                            active: page.fDisp === modelData[0] && page.fArg === modelData[1]
                            onClicked: { page.fDisp = modelData[0]; page.fArg = modelData[1]; }
                        }
                    }
                }
                Row {
                    x: 102
                    spacing: 8
                    SettingsField {
                        width: 200
                        mono: true
                        placeholder: "dispatcher, e.g. workspace"
                        text: page.fDisp
                        onEdited: t => page.fDisp = t
                        onEscaped: page.closeForm()
                    }
                    SettingsField {
                        width: formCol.width - 102 - 208
                        mono: true
                        placeholder: "argument (optional), e.g. 3"
                        text: page.fArg
                        onEdited: t => page.fArg = t
                        onEscaped: page.closeForm()
                        onAccepted: page.saveForm(false)
                    }
                }
            }

            // Neovim: what it does
            Row {
                visible: page.mode === 1
                spacing: 12
                width: parent.width
                Text { width: 90; anchors.verticalCenter: parent.verticalCenter; text: "Does"; color: Theme.subtext0; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold }
                SettingsField {
                    width: parent.width - 102
                    mono: true
                    placeholder: ":w<CR>   ·   <cmd>Telescope find_files<CR>   ·   \"+y"
                    text: page.fRhs
                    onEdited: t => page.fRhs = t
                    onEscaped: page.closeForm()
                    onAccepted: page.saveForm(false)
                }
            }

            Text {
                visible: page.nvimEditExisting && page.editing.rhs === "<Lua function>"
                width: parent.width
                wrapMode: Text.Wrap
                text: "\u{f02fc}  It runs a Lua function now — type an action to replace it (Reset brings the function back)."
                color: Theme.overlay1
                font.family: Theme.font
                font.pixelSize: 11
            }
            Text {
                visible: page.fConflict.length > 0
                width: parent.width
                wrapMode: Text.Wrap
                text: "\u{f0026}  Already used by: " + page.fConflict.join(", ") + " — “Save anyway” keeps both (both will fire)"
                color: Theme.peach
                font.family: Theme.font
                font.pixelSize: 11
            }
            Text {
                visible: page.fError !== ""
                width: parent.width
                wrapMode: Text.Wrap
                text: "\u{f0026}  " + page.fError
                color: Theme.red
                font.family: Theme.font
                font.pixelSize: 11
            }

            Row {
                spacing: 8
                IconBtn {
                    icon: "\u{f012c}"
                    text: page.fBusy ? "Saving…" : page.fConflict.length ? "Save anyway" : "Save"
                    active: page.formReady
                    enabled: page.formReady && !page.fBusy
                    onClicked: page.saveForm(page.fConflict.length > 0)
                }
                IconBtn {
                    icon: "\u{f0156}"
                    text: "Cancel"
                    onClicked: page.closeForm()
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: page.mode === 0 ? (page.editing && page.editing.custom !== true
                                             ? "hyprland.conf stays as is · Reset on the row puts it back"
                                             : "Saved to keybinds-user.conf · works at once")
                                          : "Saved to keymap-overrides.json · Neovim windows opened from now on"
                    color: Theme.overlay0
                    font.family: Theme.font
                    font.pixelSize: 11
                }
            }
        }
    }

    Text {
        visible: page.note !== ""
        text: page.note
        color: Theme.red
        font.family: Theme.font
        font.pixelSize: 12
    }

    Column {
        width: parent.width
        spacing: 0

        Repeater {
            model: page.rows
            delegate: Item {
                id: rowItem
                required property var modelData
                readonly property bool isHeader: modelData.header !== undefined
                // Hyprland row or Neovim row (both show up while searching)
                readonly property bool hy: isHeader ? modelData.hy === true : modelData._hy === true
                readonly property var e: modelData
                readonly property string rid: isHeader ? "" : hy ? e.id : e.mode + "|" + e.orig
                readonly property bool capturing: !isHeader && rid === page.capId
                readonly property bool isDeleted: !isHeader && e.deleted === true
                readonly property bool canChange: !isHeader && !isDeleted && (!rowItem.hy || !e.mouse)
                readonly property bool isCustom: !isHeader && e.custom === true
                readonly property bool canEdit: !isHeader && !isDeleted && (rowItem.hy ? !e.mouse : !e.buffer)
                width: parent.width
                height: isHeader ? 40 : capturing ? (page.conflict.length ? 96 : 72) : 50
                Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                // group heading
                Text {
                    visible: rowItem.isHeader
                    x: 4
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 8
                    text: rowItem.isHeader ? rowItem.modelData.header : ""
                    color: Theme.accent
                    font.family: Theme.font
                    font.pixelSize: 12
                    font.weight: Font.Bold
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 1
                }

                Rectangle {
                    visible: !rowItem.isHeader
                    anchors.fill: parent
                    anchors.topMargin: 2
                    anchors.bottomMargin: 2
                    radius: 12
                    color: rowItem.capturing ? Theme.alpha(Theme.accent, 0.12)
                         : rowMa.containsMouse ? Theme.alpha(Theme.surface0, 0.75) : Theme.alpha(Theme.surface0, 0.35)
                    border.width: rowItem.capturing ? 1 : 0
                    border.color: Theme.alpha(Theme.accent, 0.6)
                    Behavior on color { ColorAnimation { duration: Theme.fast } }

                    MouseArea {
                        id: rowMa
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: if (rowItem.canChange && !rowItem.capturing) page.startCapture(rowItem.e)
                    }

                    // description + action
                    Column {
                        x: 14
                        y: 9
                        width: parent.width - 14 - rightSide.width - 20
                        spacing: 2
                        Row {
                            spacing: 8
                            width: parent.width
                            Rectangle {
                                visible: !rowItem.isHeader && rowItem.e.changed === true
                                width: 7; height: 7; radius: 4
                                color: Theme.peach
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                width: parent.width - 20
                                text: rowItem.isHeader ? "" : (rowItem.e.desc || rowItem.e.rhs || rowItem.e.lhs)
                                color: rowItem.isDeleted ? Theme.overlay1 : Theme.text
                                font.strikeout: rowItem.isDeleted
                                elide: Text.ElideRight
                                font.family: Theme.font
                                font.pixelSize: 13
                                font.weight: Font.DemiBold
                            }
                        }
                        Text {
                            width: parent.width
                            text: rowItem.isHeader ? ""
                                : rowItem.isDeleted ? "deleted  ·  Restore brings it back"
                                : rowItem.hy ? rowItem.e.dispatcher + (rowItem.e.argExpanded ? "  " + rowItem.e.argExpanded : "")
                                : (page.modeNames[rowItem.e.mode] || rowItem.e.mode) + " mode"
                                  + (rowItem.e.rhs && rowItem.e.rhs !== "<Lua function>" ? "  ·  " + rowItem.e.rhs : "")
                                  + (rowItem.e.changed && rowItem.e.orig !== rowItem.e.lhs ? "  ·  was " + rowItem.e.orig : "")
                            color: Theme.overlay1
                            elide: Text.ElideRight
                            font.family: Theme.font
                            font.pixelSize: 11
                        }
                        // capture hint / conflict
                        Text {
                            visible: rowItem.capturing
                            topPadding: 6
                            width: parent.width
                            text: rowItem.hy
                                ? (page.pendKey ? "Enter to save  ·  Esc to cancel  ·  press another combo to change it"
                                                : "Press the new key combination…  (Esc cancels)")
                                : (page.tokens.length ? "Enter to save  ·  Backspace removes a key  ·  Esc cancels"
                                                      : "Type the new keys (Space first = <leader>)…  Esc cancels")
                            color: Theme.accent
                            font.family: Theme.font
                            font.pixelSize: 11
                            SequentialAnimation on opacity {
                                running: rowItem.capturing && !page.pendKey && !page.tokens.length
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.4; duration: 600 }
                                NumberAnimation { to: 1; duration: 600 }
                            }
                        }
                        Text {
                            visible: rowItem.capturing && page.conflict.length > 0
                            width: parent.width
                            text: "\u{f0026}  Already used by: " + page.conflict.join(", ") + " — Enter again to bind anyway (both will fire)"
                            color: Theme.peach
                            wrapMode: Text.Wrap
                            font.family: Theme.font
                            font.pixelSize: 11
                        }
                    }

                    // combo chips + buttons
                    Row {
                        id: rightSide
                        opacity: rowItem.isDeleted ? 0.85 : 1
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        y: 13
                        spacing: 6

                        Repeater {
                            model: {
                                if (rowItem.isHeader) return [];
                                if (rowItem.capturing) {
                                    if (rowItem.hy) {
                                        const m = page.pendKey ? page.pendMods : page.held;
                                        return (m ? m.split(" ") : []).concat(page.pendKey ? [page.pendKey] : ["…"]);
                                    }
                                    return page.tokens.length ? page.tokens : ["…"];
                                }
                                if (rowItem.hy) return (rowItem.e.curMods ? rowItem.e.curMods.split(" ") : []).concat([rowItem.e.curKey]);
                                return [rowItem.e.lhs];
                            }
                            delegate: SettingsChip {
                                required property var modelData
                                text: modelData === " " ? "Space" : modelData
                                fg: rowItem.capturing ? Theme.crust : rowItem.isDeleted ? Theme.overlay0 : Theme.text
                                bg: rowItem.capturing ? Theme.accent : Theme.alpha(Theme.surface1, rowItem.isDeleted ? 0.35 : 0.8)
                            }
                        }

                        Item { width: 4; height: 1 }

                        IconBtn {
                            visible: !rowItem.isHeader && !rowItem.capturing && rowItem.e.changed === true
                            size: 26
                            iconSize: 13
                            icon: "\u{f0450}"
                            fg: Theme.peach
                            text: rowItem.isDeleted ? "Restore" : ""
                            tip: rowItem.isDeleted ? "Bring it back" : rowItem.hy ? "Back to hyprland.conf's: " + (rowItem.e.mods ? rowItem.e.mods + " + " : "") + rowItem.e.key
                                                   + (rowItem.e.edited ? "  ·  " + rowItem.e.origDesc : "")
                                 : "Back to " + rowItem.e.orig + (rowItem.e.edited ? " and its own action" : "")
                            onClicked: page.resetEntry(rowItem.e)
                        }
                        IconBtn {
                            visible: rowItem.canChange && !rowItem.capturing
                            size: 26
                            iconSize: 13
                            icon: "\u{f097b}"
                            tip: "Change the keys"
                            onClicked: page.startCapture(rowItem.e)
                        }
                        IconBtn {
                            visible: rowItem.canEdit && !rowItem.capturing
                            size: 26
                            iconSize: 13
                            icon: "\u{f03eb}"
                            tip: "Edit the name and what it runs"
                            onClicked: page.openForm(rowItem.e)
                        }
                        IconBtn {
                            readonly property bool armed: rowItem.canEdit && page.delArmed === (rowItem.hy ? rowItem.e.id : rowItem.e.mode + "|" + rowItem.e.lhs)
                            visible: rowItem.canEdit && !rowItem.capturing
                            size: 26
                            iconSize: 13
                            icon: "\u{f0a7a}"
                            text: armed ? "Delete?" : ""
                            fg: Theme.red
                            active: armed
                            activeFg: Theme.red
                            tip: armed ? "Click again to delete"
                               : rowItem.isCustom ? "Delete" : "Delete (Reset on the row brings it back)"
                            onClicked: page.removeCustom(rowItem.e)
                        }
                        IconBtn {
                            visible: rowItem.capturing
                            size: 26
                            iconSize: 13
                            icon: "\u{f012c}"
                            active: true
                            enabled: rowItem.hy ? page.pendKey !== "" : page.tokens.length > 0
                            tip: "Save"
                            onClicked: page.confirm(page.conflict.length > 0)
                        }
                        IconBtn {
                            visible: rowItem.capturing
                            size: 26
                            iconSize: 13
                            icon: "\u{f0156}"
                            tip: "Cancel"
                            onClicked: page.cancelCapture()
                        }
                        Text {
                            visible: !rowItem.isHeader && !rowItem.canChange && !rowItem.isDeleted
                            anchors.verticalCenter: parent.verticalCenter
                            text: "mouse"
                            color: Theme.overlay0
                            font.family: Theme.font
                            font.pixelSize: 10
                        }
                    }
                }
            }
        }

        Text {
            visible: page.rows.length === 0 && !page.loading
            topPadding: 30
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: "No bindings match “" + SettingsState.query + "”"
            color: Theme.overlay0
            font.family: Theme.font
            font.pixelSize: 13
        }
    }
}
