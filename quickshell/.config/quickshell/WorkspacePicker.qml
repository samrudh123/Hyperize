// Workspace picker — SUPER+Tab (`qs ipc call wspicker toggle`). The wallpaper
// picker's design (wallpaper-picker.py: the band of slanted cards, the pill
// toolbar above, the caption below) with workspaces as the cards.
//
// The cards are the same stops as SUPER+Scroll (workspace-scroll.sh): the
// workspaces that have windows, workspace 1, and ONE empty workspace after
// the last — plus the one you are on, should that be some other empty one.
// The set is taken when the picker opens and does not shuffle while it is up.
//
// Each card is a little picture of the workspace: the wallpaper (a video's
// first frame — set-wallpaper.sh's cache), the bars' strips, and every window
// at its real place and stacking order, as a still captured from the window
// itself (hyprland-toplevel-export — see "window stills" below for why the
// frames are cached). A window with no good frame yet shows its app icon.
//
//   ← → / h l / wheel   move              Enter / click centre   go there
//   Tab / Shift+Tab     move (wraps)      click a side card       move to it
//   1-9                 select that workspace
//   m                   carry the focused window along (󰶭); Shift+Enter once
//   /  then type        search window titles / apps   Esc  clear, else close
//   Esc / q / right click / click outside             close
//
// The cards themselves are one shader (shaders/card.frag): the cairo
// parallelogram, shadow and outline of the wallpaper picker, antialiased.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

PanelWindow {
    id: picker

    property bool shown: false
    property var items: []            // the cards on screen (after search)
    property var all: []              // every stop, frozen at open
    property int curId: 1
    property bool searching: false
    property string query: ""
    property bool carry: false
    property real pos: 0              // animated selection (fractional index)
    property int target: 0
    property real fade: 0
    property real scrollAcc: 0
    property string wallStill: ""

    // ── geometry: wallpaper-picker.py's layout() ──
    readonly property int ch: Math.round(height * 0.34)
    readonly property int slant: Math.round(ch * 0.30)
    readonly property int wc: Math.round(ch * 1.55)          // selected card
    readonly property int wsl: Math.round(ch * 0.30)         // the slices either side
    readonly property int gap: 12
    readonly property int cy: Math.round(height / 2 - ch / 2 + 24)
    readonly property int iw: wc + slant                     // preview width
    readonly property int m: 4                               // shader margin

    function cardWidth(i) {
        const d = Math.min(1, Math.abs(i - pos));
        return wsl + (wc - wsl) * (1 - d);
    }

    readonly property var geo: {
        const n = items.length;
        const lefts = [], widths = [];
        let x = 0;
        for (let i = 0; i < n; i++) {
            const w = cardWidth(i);
            lefts.push(x);
            widths.push(w);
            x += w + gap;
        }
        if (!n) return { lefts: [], widths: [], offset: 0 };
        const f = Math.max(0, Math.min(n - 1, Math.floor(pos)));
        const f1 = Math.min(f + 1, n - 1);
        const frac = pos - f;
        const c0 = lefts[f] + widths[f] / 2;
        const c1 = lefts[f1] + widths[f1] / 2;
        return { lefts: lefts, widths: widths, offset: width / 2 - slant / 2 - (c0 + (c1 - c0) * frac) };
    }

    readonly property var sel: items.length ? items[Math.min(target, items.length - 1)] : null

    // ── data ──
    function windowsOn(id) {
        return Hyprland.toplevels.values.filter(t => t.workspace && t.workspace.id === id);
    }

    function appName(t) {
        const cls = t.lastIpcObject["class"] || (t.wayland ? t.wayland.appId : "") || "";
        DesktopEntries.applications.values;
        const e = cls ? DesktopEntries.heuristicLookup(cls) : null;
        if (e && e.name) return e.name;
        const tail = cls.split(".").pop() || cls;
        return tail.charAt(0).toUpperCase() + tail.slice(1);
    }

    function collect() {
        curId = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1;
        const occ = Hyprland.workspaces.values
            .filter(w => w.id > 0 && windowsOn(w.id).length > 0)
            .map(w => w.id).sort((a, b) => a - b);
        const ids = new Set([1, ...occ]);
        const next = occ.length ? occ[occ.length - 1] + 1 : -1;
        if (next > 0) ids.add(next);
        if (curId > 0) ids.add(curId);
        all = Array.from(ids).sort((a, b) => a - b).map(id => {
            const ws = Hyprland.workspaces.values.find(w => w.id === id) || null;
            const wins = windowsOn(id);
            return { id: id, ws: ws, wins: wins, empty: wins.length === 0,
                     current: id === curId, next: id === next && wins.length === 0 };
        });
    }

    function refilter(keepId) {
        const q = query.toLowerCase();
        items = all.filter(e => !q || e.wins.some(t =>
            (t.title || "").toLowerCase().includes(q) || appName(t).toLowerCase().includes(q)));
        const idx = Math.max(0, items.findIndex(e => e.id === keepId));
        target = idx;
        pos = idx;
    }

    function openPicker() {
        const mon = Hyprland.focusedMonitor;
        for (const s of Quickshell.screens)
            if (mon && s.name === mon.name) screen = s;
        Hyprland.refreshToplevels();      // fresh at/size/stacking for the previews
        Hyprland.refreshMonitors();
        stillProc.running = true;
        captureVisible();
        collect();
        query = "";
        searching = false;
        carry = false;
        refilter(curId);
        fade = 0;
        shown = true;
        tick.start();
        keys.forceActiveFocus();
    }

    function close() {
        shown = false;
        tick.stop();
    }

    function move(step) {
        if (!items.length) return;
        target = Math.max(0, Math.min(items.length - 1, target + step));
        tick.start();
    }

    function select(i) {
        target = i;
        tick.start();
    }

    function apply(carryNow) {
        const e = sel;
        if (!e) return;
        if ((carry || carryNow) && Hyprland.activeToplevel) Hyprland.dispatch("movetoworkspace " + e.id);
        else if (e.id !== curId) Hyprland.dispatch("workspace " + e.id);
        close();
    }

    IpcHandler {
        target: "wspicker"
        function toggle(): void { picker.shown ? picker.close() : picker.openPicker(); }
        function open(): void { if (!picker.shown) picker.openPicker(); }
        function close(): void { picker.close(); }
        // for debugging: qs ipc call wspicker status
        function status(): string {
            return JSON.stringify({ shown: picker.shown, still: picker.wallStill, cards: picker.items.map(e => ({
                id: e.id, empty: e.empty, current: e.current, next: e.next,
                wins: e.wins.map(t => ({ cls: t.lastIpcObject["class"], at: t.lastIpcObject.at,
                                         wayland: t.wayland !== null,
                                         good: (picker.viewFor(t.address) || {}).good === true })) })) });
        }
    }

    // The wallpaper as a still: itself, or a video's first frame (the same
    // cache set-wallpaper.sh's first_frame() fills).
    Process {
        id: stillProc
        command: ["sh", "-c", 'p=$(cat "$HOME/.config/hypr/wallpaper" 2>/dev/null)
            case "$p" in
            *.mp4|*.webm|*.mkv|*.mov|*.gif)
                k=$(printf %s "$p" | md5sum | cut -c1-16)-$(stat -c %Y "$p")
                f="$HOME/.cache/wallpaper-thumbs/first-frame/$k.png"
                [ -s "$f" ] || { mkdir -p "${f%/*}"; ffmpeg -v error -y -i "$p" -frames:v 1 "$f" </dev/null; }
                echo "$f" ;;
            *) echo "$p" ;;
            esac']
        stdout: StdioCollector { onStreamFinished: picker.wallStill = text.trim() }
    }

    // wallpaper-picker.py's tick(): ease the band, fade in.
    Timer {
        id: tick
        interval: 16
        repeat: true
        onTriggered: {
            picker.pos += (picker.target - picker.pos) * 0.24;
            picker.fade = Math.min(1, picker.fade + 0.12);
            if (Math.abs(picker.target - picker.pos) < 0.002) picker.pos = picker.target;
            if (picker.pos === picker.target && picker.fade >= 1) stop();
        }
    }

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-workspace-picker"
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    color: "transparent"
    visible: shown

    // ── window stills ──
    // Hyprland draws a window for toplevel-export with its WORKSPACE's alpha,
    // and the workspace animation here is `fade`: a window on a hidden
    // workspace comes back fully transparent. So every window is captured
    // while its workspace is on screen — on arriving there and on focus /
    // title / move events (once the fade is over), every few seconds, and as
    // the picker opens — and the last good frame is kept here (a
    // ScreencopyView holds its last buffer), for the cards to sample.
    function viewFor(addr) {
        for (let i = 0; i < cache.count; i++) {
            const v = cache.itemAt(i);
            if (v && v.addr === addr) return v;
        }
        return null;
    }

    function onScreen(t) {
        return t.workspace !== null && t.workspace.id > 0 && t.workspace.active;
    }

    function captureVisible() {
        for (let i = 0; i < cache.count; i++) {
            const v = cache.itemAt(i);
            if (v && v.ready && onScreen(v.modelData)) {
                v.captureFrame();
                v.good = true;
            }
        }
    }

    Item {
        visible: false
        Repeater {
            id: cache
            model: Hyprland.toplevels
            ScreencopyView {
                required property var modelData
                readonly property string addr: modelData.address
                readonly property bool ready: captureSource !== null
                property bool good: false
                readonly property var sz: modelData.lastIpcObject.size || [960, 600]
                width: Math.max(1, sz[0] * 0.5)
                height: Math.max(1, sz[1] * 0.5)
                captureSource: modelData.wayland
                live: false
                // the frame taken on creation is only good if it was on screen
                Component.onCompleted: good = picker.onScreen(modelData)
            }
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(ev) {
            if (["workspacev2", "activewindowv2", "windowtitlev2", "movewindowv2",
                 "openwindow", "changefloatingmode", "fullscreen"].includes(ev.name))
                settle.restart();
        }
    }
    Timer {                     // past the workspace fade (≈180 ms)
        id: settle
        interval: 450
        onTriggered: picker.captureVisible()
    }
    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: picker.captureVisible()
    }

    // backdrop
    Rectangle {
        anchors.fill: parent
        color: Theme.alpha(Theme.crust, 0.45 * picker.fade)
    }

    // clicks on the band / empty space, and the wheel
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: mouse => {
            if (mouse.button === Qt.RightButton) { picker.close(); return; }
            const i = band.hit(mouse.x, mouse.y);
            if (i < 0) picker.close();
            else if (i === picker.target) picker.apply(false);
            else picker.select(i);
        }
        onWheel: wheel => {
            // mouse wheel up = next card (right); the touchpad the opposite
            // way — like wallpaper-picker.py. Touchpad = pixelDelta or a
            // scroll phase (see Theme.wheelDelta).
            const touchpad = wheel.pixelDelta.y !== 0 || wheel.pixelDelta.x !== 0
                          || wheel.phase !== Qt.NoScrollPhase;
            const d = (wheel.angleDelta.y + wheel.angleDelta.x) / 120;
            picker.scrollAcc += touchpad ? -d : d;
            while (Math.abs(picker.scrollAcc) >= 1) {
                const step = picker.scrollAcc > 0 ? 1 : -1;
                picker.scrollAcc -= step;
                picker.move(step);
            }
        }
    }

    // ── the band ──
    Item {
        id: band
        anchors.fill: parent

        // index of the card under (x, y): the selected card is on top
        function hit(x, y) {
            let best = -1, bestZ = -1e9;
            for (let i = 0; i < picker.items.length; i++) {
                const left = picker.geo.lefts[i] + picker.geo.offset;
                const w = picker.geo.widths[i];
                const ly = y - picker.cy;
                if (ly < 0 || ly > picker.ch) continue;
                const edge = left + picker.slant * (1 - ly / picker.ch);
                if (x < edge || x > edge + w) continue;
                const z = -Math.abs(i - picker.pos);
                if (z > bestZ) { bestZ = z; best = i; }
            }
            return best;
        }

        Repeater {
            model: picker.items

            Item {
                id: card
                required property var modelData
                required property int index
                readonly property var e: modelData
                readonly property real w: picker.geo.widths[index] ?? picker.wsl
                readonly property real lx: (picker.geo.lefts[index] ?? 0) + picker.geo.offset
                readonly property real d: Math.min(1, Math.abs(index - picker.pos))
                readonly property bool selected: d < 0.5

                x: lx - picker.m
                y: picker.cy - picker.m
                width: w + picker.slant + 2 * picker.m
                height: picker.ch + 2 * picker.m + 18          // + the shadow below
                z: -Math.abs(index - picker.pos)
                visible: lx + w + picker.slant >= -20 && lx <= picker.width + 20

                // the workspace in miniature, rendered into `tex`
                Item {
                    id: preview
                    width: picker.iw
                    height: picker.ch
                    clip: true
                    visible: false

                    readonly property var mon: (card.e.ws && card.e.ws.monitor) || Hyprland.focusedMonitor
                    readonly property real monS: mon && mon.scale > 0 ? mon.scale : 1
                    readonly property real monX: mon ? mon.x : 0
                    readonly property real monY: mon ? mon.y : 0
                    readonly property real monW: mon && mon.width > 0 ? mon.width / monS : picker.width
                    readonly property real monH: mon && mon.height > 0 ? mon.height / monS : picker.height
                    readonly property var reserved: (mon && mon.lastIpcObject.reserved) || [0, 0, 0, 0]
                    readonly property real sc: Math.max(width / monW, height / monH)

                    Rectangle { anchors.fill: parent; color: Theme.base }

                    Item {
                        id: desk
                        width: preview.monW * preview.sc
                        height: preview.monH * preview.sc
                        anchors.centerIn: parent

                        Image {
                            anchors.fill: parent
                            source: picker.wallStill ? "file://" + picker.wallStill : ""
                            fillMode: Image.PreserveAspectCrop
                            sourceSize: Qt.size(Math.round(desk.width), Math.round(desk.height))
                            asynchronous: true
                        }

                        // the bars' strips (Hyprland's reserved area)
                        Rectangle {
                            width: parent.width
                            height: preview.reserved[1] * preview.sc
                            color: Theme.alpha(Theme.crust, 0.55)
                        }
                        Rectangle {
                            y: parent.height - height
                            width: parent.width
                            height: preview.reserved[3] * preview.sc
                            color: Theme.alpha(Theme.crust, 0.55)
                        }

                        // windows above the wallpaper; z (stacking) is relative in here
                        Item {
                            anchors.fill: parent

                            Repeater {
                                model: card.e.wins

                                Item {
                                    id: win
                                    required property var modelData
                                    readonly property var o: modelData.lastIpcObject
                                    readonly property var at: o.at || [0, 0]
                                    readonly property var size: o.size || [0, 0]
                                    readonly property bool focusedWin: card.e.current && modelData.activated

                                    visible: o.at !== undefined && !o.hidden
                                    x: (at[0] - preview.monX) * preview.sc
                                    y: (at[1] - preview.monY) * preview.sc
                                    width: size[0] * preview.sc
                                    height: size[1] * preview.sc
                                    z: (o.fullscreen ? 2000 : 0) + (o.floating ? 1000 : 0) - (o.focusHistoryID || 0)

                                    readonly property var view: picker.viewFor(modelData.address)
                                    readonly property bool shot: view !== null && view.good && view.hasContent

                                    Rectangle {
                                        anchors.fill: parent
                                        color: Theme.alpha(Theme.mantle, 0.92)
                                        visible: !win.shot
                                    }
                                    Image {
                                        anchors.centerIn: parent
                                        visible: !win.shot
                                        readonly property int s: Math.max(12, Math.min(48, Math.min(win.width, win.height) * 0.4))
                                        width: s
                                        height: s
                                        sourceSize: Qt.size(s, s)
                                        source: {
                                            const cls = win.o["class"] || "";
                                            DesktopEntries.applications.values;
                                            const de = cls ? DesktopEntries.heuristicLookup(cls) : null;
                                            return Quickshell.iconPath(de ? de.icon : cls, "application-x-executable");
                                        }
                                    }
                                    ShaderEffectSource {
                                        anchors.fill: parent
                                        visible: win.shot
                                        sourceItem: win.shot ? win.view : null
                                    }
                                    Rectangle {
                                        anchors.fill: parent
                                        color: "transparent"
                                        border.width: win.focusedWin ? 2 : 1
                                        border.color: win.focusedWin ? Theme.accent : Theme.alpha(Theme.surface1, 0.8)
                                    }
                                }
                            }
                        }
                    }

                    // the empty workspace: a big plus
                    Rectangle {
                        anchors.fill: parent
                        visible: card.e.empty
                        color: Theme.alpha(Theme.crust, 0.35)
                        Text {
                            anchors.centerIn: parent
                            text: "\u{f0415}"                           // md-plus
                            color: Theme.alpha(Theme.text, 0.85)
                            font.family: Theme.font
                            font.pointSize: 30
                        }
                    }
                }

                ShaderEffectSource {
                    id: tex
                    sourceItem: preview
                    hideSource: true
                }

                ShaderEffect {
                    anchors.fill: parent
                    opacity: picker.fade
                    property vector2d itemSize: Qt.vector2d(width, height)
                    property real margin: picker.m
                    property real cardW: card.w
                    property real cardH: picker.ch
                    property real slant: picker.slant
                    property real imgW: picker.iw
                    property real dim: 0.45 * card.d
                    property real lineW: card.selected ? 3 : 1.2
                    property real shadowA: 0.35 * (1 - 0.5 * card.d)
                    property real hasTex: 1
                    property color strokeColor: card.selected ? Theme.accent : Theme.alpha(Theme.surface1, 0.8)
                    property color dimColor: Theme.crust
                    property color emptyColor: Theme.surface0
                    property var src: tex
                    fragmentShader: Qt.resolvedUrl("shaders/card.frag.qsb")
                }

                // badge, bottom-left like the ▶ on video wallpapers: the number
                Rectangle {
                    visible: card.w > 40
                    x: picker.m + 14
                    y: picker.m + picker.ch - 36
                    width: 26
                    height: 26
                    radius: 13
                    color: card.e.current ? Theme.accent : Theme.alpha(Theme.crust, 0.75)
                    opacity: picker.fade
                    Text {
                        anchors.centerIn: parent
                        text: card.e.id
                        color: card.e.current ? Theme.crust : Theme.text
                        font.family: Theme.font
                        font.pointSize: 9
                        font.bold: true
                    }
                }
            }
        }

        Text {
            visible: picker.items.length === 0
            x: picker.width / 2 - width / 2
            y: picker.cy + picker.ch / 2 - height / 2
            text: "No workspace has a window matching “" + picker.query + "”"
            color: Theme.subtext0
            opacity: picker.fade
            font.family: Theme.font
            font.pointSize: 13
        }
    }

    // ── toolbar: [ Workspace 2 ] | ① ② ③ | 󰶭 󰍉 ──
    Rectangle {
        id: toolbar
        readonly property int pad: 10
        width: row.width + 2 * pad
        height: 44
        radius: 22
        x: picker.width / 2 - width / 2
        y: picker.cy - height - 26
        color: Theme.alpha(Theme.crust, 0.92)
        border.width: 1
        border.color: Theme.alpha(Theme.surface1, 0.9)
        opacity: picker.fade

        Row {
            id: row
            x: toolbar.pad
            height: parent.height

            Item {
                width: Math.max(130, label.implicitWidth + 20)
                height: parent.height
                Text {
                    id: label
                    anchors.centerIn: parent
                    text: picker.searching ? "/" + picker.query + "▏"
                        : picker.sel ? "Workspace " + picker.sel.id : "Workspaces"
                    color: picker.searching ? Theme.text : Theme.accent
                    font.family: Theme.font
                    font.pointSize: 11
                    font.bold: true
                }
            }

            Item {                                          // separator
                width: 9
                height: parent.height
                Rectangle { x: 4; y: 12; width: 1; height: parent.height - 24; color: Theme.surface1 }
            }

            Repeater {
                model: picker.items
                Item {
                    id: dot
                    required property var modelData
                    required property int index
                    readonly property bool on: index === picker.target
                    width: 30
                    height: parent.height

                    Rectangle {                              // selection ring
                        visible: dot.on
                        anchors.centerIn: parent
                        width: 2 * (9 + 4) + 2
                        height: width
                        radius: width / 2
                        color: "transparent"
                        border.width: 2
                        border.color: Theme.alpha(Theme.text, 0.9)
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        readonly property int r: dot.on || dotMouse.containsMouse ? 9 : 8
                        width: 2 * r
                        height: width
                        radius: r
                        color: dot.modelData.current ? Theme.accent
                             : dot.modelData.empty ? "transparent" : Theme.surface1
                        border.width: dot.modelData.empty && !dot.modelData.current ? 1.5 : 0
                        border.color: Theme.overlay2
                        Text {
                            anchors.centerIn: parent
                            text: dot.modelData.empty && !dot.modelData.current ? "+" : dot.modelData.id
                            color: dot.modelData.current ? Theme.crust : Theme.text
                            font.family: Theme.font
                            font.pointSize: 7
                            font.bold: true
                        }
                    }
                    MouseArea {
                        id: dotMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: picker.select(dot.index)
                    }
                }
            }

            Item {
                width: 9
                height: parent.height
                Rectangle { x: 4; y: 12; width: 1; height: parent.height - 24; color: Theme.surface1 }
            }

            Repeater {
                model: [
                    { kind: "carry", icon: "\u{f0dad}" },     // md-application_export
                    { kind: "search", icon: "\u{f0349}" }     // md-magnify
                ]
                Item {
                    id: btn
                    required property var modelData
                    readonly property bool on: modelData.kind === "carry" ? picker.carry : picker.searching
                    width: 34
                    height: parent.height
                    Rectangle {
                        visible: btn.on || btnMouse.containsMouse
                        x: 2
                        y: 7
                        width: parent.width - 4
                        height: parent.height - 14
                        radius: 9
                        color: Theme.alpha(Theme.surface0, btn.on ? 1 : 0.7)
                    }
                    Text {
                        anchors.centerIn: parent
                        text: btn.modelData.icon
                        color: btn.on ? Theme.accent : btnMouse.containsMouse ? Theme.text : Theme.overlay2
                        font.family: Theme.font
                        font.pointSize: 14
                    }
                    MouseArea {
                        id: btnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            if (btn.modelData.kind === "carry") picker.carry = !picker.carry;
                            else {
                                picker.searching = !picker.searching;
                                picker.query = "";
                                picker.refilter(picker.sel ? picker.sel.id : picker.curId);
                            }
                        }
                    }
                }
            }
        }
    }

    // ── caption ──
    Item {
        id: caption
        visible: picker.sel !== null
        readonly property real cyc: picker.cy + picker.ch + 40
        opacity: picker.fade
        anchors.fill: parent

        readonly property string title: {
            const e = picker.sel;
            if (!e) return "";
            if (e.empty) return "Workspace " + e.id;
            const names = [];
            for (const t of e.wins) {
                const n = picker.appName(t);
                if (!names.includes(n)) names.push(n);
            }
            const s = "Workspace " + e.id + "  ·  " + names.join(", ");
            return s.length <= 60 ? s : s.slice(0, 59) + "…";
        }
        readonly property string sub: {
            const e = picker.sel;
            if (!e) return "";
            const bits = [];
            bits.push(e.empty ? (e.next ? "empty · the next free one" : "empty")
                              : e.wins.length + (e.wins.length === 1 ? " window" : " windows"));
            if (e.current) bits.push("\u{f05e0} current");
            const a = Hyprland.activeToplevel;
            if (picker.carry && a) bits.push("\u{f0dad} brings " + picker.appName(a));
            return bits.join("  ·  ");
        }

        Rectangle {
            readonly property real lw: Math.max(nameText.implicitWidth, subText.implicitWidth) + 48
            x: picker.width / 2 - lw / 2
            y: caption.cyc - 24
            width: lw
            height: 50
            radius: 16
            color: Theme.alpha(Theme.crust, 0.88)
        }
        Text {
            id: nameText
            x: picker.width / 2 - width / 2
            y: caption.cyc - 7 - height / 2
            text: caption.title
            color: Theme.text
            font.family: Theme.font
            font.pointSize: 11
            font.bold: true
        }
        Text {
            id: subText
            x: picker.width / 2 - width / 2
            y: caption.cyc + 12 - height / 2
            text: caption.sub
            color: Theme.accent
            font.family: Theme.font
            font.pointSize: 9
        }
        Text {
            x: picker.width / 2 - width / 2
            y: caption.cyc + 44 - height / 2
            text: (picker.target + 1) + " / " + picker.items.length
            color: Theme.overlay0
            font.family: Theme.font
            font.pointSize: 9
        }
    }

    // ── keys ──
    Item {
        id: keys
        focus: true
        Keys.onPressed: ev => {
            const k = ev.key;
            ev.accepted = true;
            if (picker.searching) {
                if (k === Qt.Key_Escape) {
                    picker.searching = false;
                    picker.query = "";
                    picker.refilter(picker.sel ? picker.sel.id : picker.curId);
                } else if (k === Qt.Key_Backspace) {
                    picker.query = picker.query.slice(0, -1);
                    picker.refilter(picker.sel ? picker.sel.id : picker.curId);
                } else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
                    picker.apply(ev.modifiers & Qt.ShiftModifier);
                } else if (k === Qt.Key_Left || k === Qt.Key_Right) {
                    picker.move(k === Qt.Key_Left ? -1 : 1);
                } else if (ev.text && ev.text.length === 1 && ev.text >= " ") {
                    picker.query += ev.text;
                    picker.refilter(picker.sel ? picker.sel.id : picker.curId);
                }
                return;
            }
            const n = picker.items.length;
            if (k === Qt.Key_Escape || k === Qt.Key_Q) picker.close();
            else if (k === Qt.Key_Left || k === Qt.Key_H || k === Qt.Key_Up || k === Qt.Key_K) picker.move(-1);
            else if (k === Qt.Key_Right || k === Qt.Key_L || k === Qt.Key_Down || k === Qt.Key_J) picker.move(1);
            else if (k === Qt.Key_Home) picker.move(-n);
            else if (k === Qt.Key_End) picker.move(n);
            else if (k === Qt.Key_Tab && n) picker.select((picker.target + 1) % n);
            else if (k === Qt.Key_Backtab && n) picker.select((picker.target - 1 + n) % n);
            else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space)
                picker.apply(ev.modifiers & Qt.ShiftModifier);
            else if (k === Qt.Key_M) picker.carry = !picker.carry;
            else if (k === Qt.Key_Slash || (k === Qt.Key_F && (ev.modifiers & Qt.ControlModifier))) {
                picker.searching = true;
                picker.query = "";
            } else if (k >= Qt.Key_1 && k <= Qt.Key_9) {
                const i = picker.items.findIndex(e => e.id === k - Qt.Key_0);
                if (i >= 0) picker.select(i);
            }
        }
    }
}
