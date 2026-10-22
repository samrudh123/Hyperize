// Wallpaper picker — SUPER+W (desktop), SUPER+SHIFT+W (lock screen):
// `qs ipc call wallpicker toggle desktop|lock`. Pressing a mode's key again
// closes it; the other mode's key swaps to that mode.
//
// The GTK picker (hypr/wallpaper-picker.py, still there as a standalone
// fallback) rebuilt inside the shell: same carousel, filters, keys and
// behaviour, but it is up the moment the key is pressed — no Python + GTK
// start-up, no card decoding on open (cards are only loaded near the
// selection, and the decoded ones stay cached in the shell between opens).
//
//   [ Green ]  󰕰  󰐊   ● ● ● ● ● ● ● ●   󰏘 󰤕 󰍉
//    filter   all video  colour filters  accent transitions search
//
//   ← → / h l / wheel   move              Enter / click centre   set it
//   Tab / Shift+Tab     next filter        click a side card      move to it
//   a  v  1-8           All / Video / colour
//   c                   accent follows wallpaper on/off
//   t                   transitions strip: ← → pick (saved, and previewed on
//                       the real wallpaper), p replays, Enter / Esc / t close
//   /  then type        search names       Esc   clear search, else close
//   wheel: mouse up = next card; the touchpad the other way round
//
// The list comes from hypr/wallpaper-index.py (colour buckets, cached card
// pictures; ~40 ms). The last list is shown at once and refreshed as the
// picker opens. Setting goes through set-wallpaper.sh / set-lockscreen.sh,
// then set-accent.sh with the bucket's colour when accent sync is on — for a
// Mono wallpaper its own grey, from the index (files hypr/wallpaper-accent-
// sync[-lock]). Transitions: hypr/
// wallpaper-transition, previewed with `set-wallpaper.sh --preview`.
//
// LOCK MODE: images only, plus a first card "Live screen" (hyprlock's
// `screenshot`): its preview is a blurred capture of the screen taken just
// before the picker maps. Accent sync starts OFF there.
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

PanelWindow {
    id: picker

    // ── constants (wallpaper-picker.py's) ──
    // the colour filters, each in the CURRENT theme's colour for its role —
    // also the accent a wallpaper of that bucket sets (accent sync)
    readonly property var colours: [
        { name: "Red", hex: String(Theme.red) }, { name: "Orange", hex: String(Theme.peach) },
        { name: "Yellow", hex: String(Theme.yellow) }, { name: "Green", hex: String(Theme.green) },
        { name: "Blue", hex: String(Theme.blue) }, { name: "Purple", hex: String(Theme.mauve) },
        { name: "Pink", hex: String(Theme.pink) }, { name: "Mono", hex: String(Theme.overlay2) }
    ]
    function swatch(name) {
        const c = colours.find(c => c.name === name);
        return c ? c.hex : null;
    }
    // the accent a wallpaper sets: its bucket's colour, or for a black-and-
    // white one the grey wallpaper-index.py measured in it
    function accentOf(e) {
        if (!e || e.bucket === "Live") return null;
        return e.bucket === "Mono" ? (e.accent || null) : swatch(e.bucket);
    }
    // kinds are WallpaperTransition.qml's (+ random / none); keep in step
    readonly property var transitions: [
        { kind: "circle", label: "Circle zoom", glyph: "\u{f0e96}" },
        { kind: "cursor", label: "From cursor", glyph: "\u{f0cfd}" },
        { kind: "iris", label: "Iris", glyph: "\u{f0104}" },
        { kind: "fade", label: "Fade", glyph: "\u{f1853}" },
        { kind: "wipe", label: "Wipe", glyph: "\u{f174a}" },
        { kind: "wave", label: "Wave", glyph: "\u{f078d}" },
        { kind: "slide", label: "Slide", glyph: "\u{f04e1}" },
        { kind: "zoom", label: "Zoom", glyph: "\u{f034b}" },
        { kind: "dissolve", label: "Dissolve", glyph: "\u{f0d7c}" },
        { kind: "pixelate", label: "Pixelate", glyph: "\u{f013a}" },
        { kind: "diamond", label: "Diamond", glyph: "\u{f070c}" },
        { kind: "random", label: "Random", glyph: "\u{f049f}" },
        { kind: "none", label: "Instant", glyph: "\u{f0243}" }
    ]
    readonly property string iGrid: "\u{f0570}"
    readonly property string iPlay: "\u{f040a}"
    readonly property string iPalette: "\u{f03d8}"
    readonly property string iSearch: "\u{f0349}"
    readonly property string iCheck: "\u{f05e0}"
    readonly property string iTransition: "\u{f0915}"
    readonly property string screenshotWord: "screenshot"   // hyprlock: blur the live screen

    // ── state ──
    property bool shown: false
    property string mode: "desktop"
    readonly property bool lock: mode === "lock"
    property var lists: ({})          // last index per mode: {items, current, raw}
    property bool freshOpen: false
    property var all: []
    property var items: []
    property string current: ""
    property string filter: "All"
    property bool searching: false
    property string query: ""
    property bool sync: true
    property string transition: "circle"
    property bool tstrip: false
    property bool loading: false
    property real pos: 0
    property int target: 0
    property real fade: 0
    property real scrollAcc: 0
    property bool waitingLive: false

    readonly property var filters: lock ? ["All"].concat(colours.map(c => c.name))
                                        : ["All", "Video"].concat(colours.map(c => c.name))
    readonly property var sel: items.length ? items[Math.min(target, items.length - 1)] : null

    // ── geometry: layout() ──
    // From the SCREEN, not the window: on the first open after the shell
    // starts, the window has not been mapped yet and its height is a 100 px
    // placeholder — the index was then asked for 63×34 cards, which were
    // cached and stretched over the big cards (the "blurry first open").
    readonly property real screenH: screen ? screen.height : height
    readonly property int ch: Math.round(screenH * 0.34)
    readonly property int slant: Math.round(ch * 0.30)
    readonly property int wc: Math.round(ch * 1.55)
    readonly property int wsl: Math.round(ch * 0.30)
    readonly property int gap: 12
    readonly property int cy: Math.round(screenH / 2 - ch / 2 + 24)
    readonly property int iw: wc + slant
    readonly property int m: 4

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
        const c0 = lefts[f] + widths[f] / 2;
        const c1 = lefts[f1] + widths[f1] / 2;
        return { lefts: lefts, widths: widths, offset: width / 2 - slant / 2 - (c0 + (c1 - c0) * (pos - f)) };
    }

    // ── helpers ──
    function q(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'"; }

    function stateOn(file, dflt) {
        const t = (file.text() || "").trim();
        return t === "" ? dflt : t === "on";
    }

    // ── open / close ──
    function toggle(m) {
        if (shown && mode === m) { close(); return; }
        open(m);
    }

    function open(m) {
        const mon = Hyprland.focusedMonitor;
        for (const s of Quickshell.screens)
            if (mon && s.name === mon.name) screen = s;
        mode = m;
        filter = "All";
        searching = false;
        query = "";
        tstrip = false;
        syncFile.path = Theme.hypr + (lock ? "/wallpaper-accent-sync-lock" : "/wallpaper-accent-sync");
        syncFile.reload();
        sync = stateOn(syncFile, !lock);
        transFile.reload();
        const t = (transFile.text() || "").trim();
        transition = transitions.some(x => x.kind === t) ? t : "circle";
        const last = lists[m] || { items: [], current: "" };
        current = last.current;
        all = withLive(last.items);
        loading = last.items.length === 0;
        freshOpen = true;
        refilter(current);
        indexProc.command = ["/usr/bin/python3", Theme.hypr + "/wallpaper-index.py", m,
                             "--card", iw + "x" + ch];
        indexProc.running = true;
        if (lock) {
            // grab the screen BEFORE the picker covers it — and if the
            // desktop picker is up, after it has faded away
            const wasShown = shown;
            shown = false;
            tick.stop();
            waitingLive = true;
            liveView.captureSource = null;
            if (wasShown) liveDelay.restart();
            else captureLive();
        } else {
            reveal();
        }
    }

    function captureLive() {
        liveView.captureSource = picker.screen;
        liveTimeout.restart();
    }

    function reveal() {
        waitingLive = false;
        fade = 0;
        shown = true;
        tick.start();
        keys.forceActiveFocus();
    }

    function close() {
        shown = false;
        waitingLive = false;
        tick.stop();
    }

    function withLive(list) {
        if (!lock) return list;
        return [{ path: screenshotWord, name: "Live screen", bucket: "Live", video: false,
                  card: "", still: "", live: true }].concat(list);
    }

    function indexed(text) {
        let d;
        try { d = JSON.parse(text); } catch (e) { loading = false; return; }
        const raw = JSON.stringify(d.items);
        const prev = lists[d.mode];
        const l = Object.assign({}, lists);
        l[d.mode] = { items: d.items, current: d.current, raw: raw };
        lists = l;
        if (d.mode !== mode) return;
        loading = false;
        // unchanged: leave the cards alone (no rebuild, no reload)
        if (prev && prev.raw === raw && prev.current === d.current) { freshOpen = false; return; }
        const keep = freshOpen ? d.current : (sel ? sel.path : d.current);
        freshOpen = false;
        current = d.current;
        all = withLive(d.items);
        refilter(keep);
    }

    function refilter(keep) {
        keep = keep || current;
        const ql = query.toLowerCase();
        items = all.filter(e => {
            if (filter === "Video" && !e.video) return false;
            if (filter !== "All" && filter !== "Video" && e.bucket !== filter) return false;
            return !ql || e.name.toLowerCase().includes(ql);
        });
        const idx = Math.max(0, items.findIndex(e => e.path === keep));
        target = idx;
        pos = idx;
    }

    function setFilter(name) {
        filter = name;
        refilter(sel ? sel.path : null);
    }

    function cycleFilter(step) {
        const i = filters.indexOf(filter);
        setFilter(filters[(i + step + filters.length) % filters.length]);
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

    function toggleSync() {
        sync = !sync;
        syncFile.setText(sync ? "on\n" : "off\n");
    }

    function toggleSearch() {
        searching = !searching;
        query = "";
        refilter(sel ? sel.path : null);
    }

    function transitionOf(kind) {
        return transitions.find(t => t.kind === kind) || { label: "", glyph: iTransition };
    }

    function setTransition(kind) {
        transition = kind;
        transFile.setText(kind + "\n");
        preview();
    }

    // Play the chosen transition on the real wallpaper: from the current one
    // to the selected card (or the next one, if that IS the current).
    function preview() {
        if (lock || transition === "none" || !items.length) return;
        const cands = [items[target]].concat(items.slice(target + 1), items.slice(0, target));
        const e = cands.find(c => c.path !== current && c.path !== screenshotWord);
        if (!e) return;
        Theme.exec(q(Theme.hypr + "/set-wallpaper.sh") + " --preview " + q(e.path) + " " + q(transition));
    }

    function apply() {
        const e = sel;
        if (!e) return;
        let hex = sync ? accentOf(e) : null;
        if (hex && hex.toLowerCase() === String(Theme.accent).toLowerCase()) hex = null;
        // the wallpaper first (instant), then the accent; detached, through
        // Hyprland, like a keybind
        const setter = Theme.hypr + (lock ? "/set-lockscreen.sh" : "/set-wallpaper.sh");
        const tgt = e.path === screenshotWord ? "--screenshot" : e.path;
        let script = '"$0" "$1"';
        const argv = [setter, tgt];
        if (hex) {
            script += ' && "$2" "$3"';
            argv.push(Theme.hypr + "/set-accent.sh", hex.slice(1));
        }
        Theme.exec("sh -c " + q(script) + " " + argv.map(q).join(" "));
        close();
    }

    // ── IPC ──
    IpcHandler {
        target: "wallpicker"
        function toggle(mode: string): void { picker.toggle(mode === "lock" ? "lock" : "desktop"); }
        function open(mode: string): void { picker.open(mode === "lock" ? "lock" : "desktop"); }
        function close(): void { picker.close(); }
        function status(): string {
            return JSON.stringify({ shown: picker.shown, mode: picker.mode, items: picker.items.length,
                                    all: picker.all.length, target: picker.target, filter: picker.filter,
                                    current: picker.current, sel: picker.sel ? picker.sel.path : null });
        }
    }

    Process {
        id: indexProc
        stdout: StdioCollector { onStreamFinished: picker.indexed(text) }
    }

    FileView { id: syncFile; blockLoading: true; printErrors: false }
    FileView { id: transFile; path: Theme.hypr + "/wallpaper-transition"; blockLoading: true; printErrors: false }

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

    Timer {                       // the desktop picker's fade-out (layersOut)
        id: liveDelay
        interval: 220
        onTriggered: if (picker.waitingLive) picker.captureLive()
    }

    Timer {                       // never hang on a capture that doesn't come
        id: liveTimeout
        interval: 400
        onTriggered: if (picker.waitingLive) picker.reveal()
    }

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-wallpaper-picker"
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    color: "transparent"
    visible: shown

    // ── the live screen (lock mode's first card) ──
    Item {
        id: liveSrc
        width: picker.iw
        height: picker.ch
        visible: false
        ScreencopyView {
            id: liveView
            anchors.fill: parent
            live: false
            onHasContentChanged: if (hasContent && picker.waitingLive) picker.reveal()
        }
    }
    MultiEffect {
        id: liveBlur
        width: picker.iw
        height: picker.ch
        visible: false
        source: liveSrc
        blurEnabled: true
        blur: 1.0
        blurMax: 24
    }
    ShaderEffectSource {
        id: liveTex
        sourceItem: liveBlur
        hideSource: true
        visible: false
    }

    // backdrop
    Rectangle {
        anchors.fill: parent
        color: Theme.alpha(Theme.crust, 0.45 * picker.fade)
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: mouse => {
            if (mouse.button === Qt.RightButton) { picker.close(); return; }
            const i = band.hit(mouse.x, mouse.y);
            if (i < 0) picker.close();
            else if (i === picker.target) picker.apply();
            else picker.select(i);
        }
        onWheel: wheel => {
            // mouse wheel up = next card; the touchpad the opposite way
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

        function hit(x, y) {
            let best = -1, bestZ = -1e9;
            const ly = y - picker.cy;
            if (ly < 0 || ly > picker.ch) return -1;
            for (let i = 0; i < picker.items.length; i++) {
                const left = picker.geo.lefts[i] + picker.geo.offset;
                const edge = left + picker.slant * (1 - ly / picker.ch);
                if (x < edge || x > edge + picker.geo.widths[i]) continue;
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
                readonly property bool near: Math.abs(index - picker.target) <= 12

                x: lx - picker.m
                y: picker.cy - picker.m
                width: w + picker.slant + 2 * picker.m
                height: picker.ch + 2 * picker.m + 18
                z: -Math.abs(index - picker.pos)
                visible: lx + w + picker.slant >= -20 && lx <= picker.width + 20

                Image {
                    id: img
                    width: picker.iw
                    height: picker.ch
                    visible: false
                    asynchronous: true
                    fillMode: Image.PreserveAspectCrop
                    sourceSize: Qt.size(picker.iw, picker.ch)
                    readonly property string file: card.e.card || card.e.still || ""
                    source: card.near && file ? "file://" + file : ""
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
                    property real hasTex: card.e.live ? (liveView.hasContent ? 1 : 0)
                                                      : (img.status === Image.Ready ? 1 : 0)
                    property color strokeColor: card.selected ? Theme.accent : Theme.alpha(Theme.surface1, 0.8)
                    property color dimColor: Theme.crust
                    property color emptyColor: Theme.alpha(Theme.surface0, 0.9)
                    property var src: card.e.live ? liveTex : img
                    fragmentShader: Qt.resolvedUrl("shaders/card.frag.qsb")
                }

                // ▶ badge on animated wallpapers, bottom-left
                Rectangle {
                    visible: card.e.video && card.w > 40
                    x: picker.m + 24 - 13
                    y: picker.m + picker.ch - 20 - 13
                    width: 26
                    height: 26
                    radius: 13
                    color: Theme.alpha(Theme.crust, 0.75)
                    opacity: picker.fade
                    Text {
                        anchors.centerIn: parent
                        text: picker.iPlay
                        color: Theme.text
                        font.family: Theme.font
                        font.pointSize: 11
                    }
                }
            }
        }

        Text {
            visible: picker.items.length === 0
            x: picker.width / 2 - width / 2
            y: picker.cy + picker.ch / 2 - height / 2
            text: picker.loading ? "Indexing wallpapers…"
                : picker.searching && picker.query ? "No wallpapers match “" + picker.query + "”"
                : "No " + picker.filter.toLowerCase() + " wallpapers"
            color: Theme.subtext0
            opacity: picker.fade
            font.family: Theme.font
            font.pointSize: 13
        }
    }

    // ── toolbar ──
    Text {
        visible: picker.lock
        x: picker.width / 2 - width / 2
        y: toolbar.y - 22 - height / 2
        text: "\u{f033e}  Lock screen"
        color: Theme.subtext0
        opacity: picker.fade
        font.family: Theme.font
        font.pointSize: 11
        font.bold: true
    }

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

        component Sep: Item {
            width: 9
            height: 44
            Rectangle { x: 4; y: 12; width: 1; height: 20; color: Theme.surface1 }
        }

        component IconButton: Item {
            id: ib
            property string icon
            property bool on: false
            signal clicked()
            width: 34
            height: 44
            Rectangle {
                visible: ib.on || ibMouse.containsMouse
                x: 2; y: 7
                width: parent.width - 4
                height: parent.height - 14
                radius: 9
                color: Theme.alpha(Theme.surface0, ib.on ? 1 : 0.7)
            }
            Text {
                anchors.centerIn: parent
                text: ib.icon
                color: ib.on ? Theme.accent : ibMouse.containsMouse ? Theme.text : Theme.overlay2
                font.family: Theme.font
                font.pointSize: 14
            }
            MouseArea {
                id: ibMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: ib.clicked()
            }
        }

        Row {
            id: row
            x: toolbar.pad
            height: parent.height

            Item {
                width: 110
                height: 44
                Text {
                    anchors.centerIn: parent
                    text: picker.searching ? "/" + picker.query + "▏" : picker.filter
                    color: picker.searching ? Theme.text : (picker.swatch(picker.filter) || Theme.text)
                    font.family: Theme.font
                    font.pointSize: 11
                    font.bold: true
                }
            }
            Sep {}
            IconButton {
                icon: picker.iGrid
                on: picker.filter === "All"
                onClicked: picker.setFilter("All")
            }
            IconButton {
                visible: !picker.lock
                icon: picker.iPlay
                on: picker.filter === "Video"
                onClicked: picker.setFilter("Video")
            }
            Sep {}
            Repeater {
                model: picker.colours
                Item {
                    id: sw
                    required property var modelData
                    readonly property bool on: picker.filter === modelData.name
                    width: 30
                    height: 44
                    Rectangle {
                        visible: sw.on
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
                        readonly property int r: sw.on || swMouse.containsMouse ? 9 : 8
                        width: 2 * r
                        height: width
                        radius: r
                        color: sw.modelData.hex
                    }
                    MouseArea {
                        id: swMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: picker.setFilter(sw.modelData.name)
                    }
                }
            }
            Sep {}
            IconButton {
                icon: picker.iPalette
                on: picker.sync
                onClicked: picker.toggleSync()
            }
            IconButton {
                visible: !picker.lock
                icon: picker.transitionOf(picker.transition).glyph
                on: picker.tstrip
                onClicked: picker.tstrip = !picker.tstrip
            }
            IconButton {
                icon: picker.iSearch
                on: picker.searching
                onClicked: picker.toggleSearch()
            }
        }
    }

    // ── transitions strip (`t`) ──
    Rectangle {
        id: strip
        visible: picker.tstrip && !picker.lock
        readonly property int pad: 6
        width: chips.width + 2 * pad
        height: 36
        radius: 18
        x: picker.width / 2 - width / 2
        y: toolbar.y - 52
        color: Theme.alpha(Theme.crust, 0.92)
        border.width: 1
        border.color: Theme.alpha(Theme.surface1, 0.9)
        opacity: picker.fade

        Row {
            id: chips
            x: strip.pad
            height: parent.height
            Repeater {
                model: picker.transitions
                Item {
                    id: chip
                    required property var modelData
                    readonly property bool on: modelData.kind === picker.transition
                    width: 34 + modelData.label.length * 8
                    height: 36
                    Rectangle {
                        visible: chip.on || chipMouse.containsMouse
                        x: 1; y: 5
                        width: parent.width - 2
                        height: parent.height - 10
                        radius: height / 2
                        color: chip.on ? Theme.accent : Theme.alpha(Theme.surface0, 0.8)
                    }
                    Text {
                        anchors.centerIn: parent
                        text: chip.modelData.glyph + " " + chip.modelData.label
                        color: chip.on ? Theme.crust : chipMouse.containsMouse ? Theme.text : Theme.subtext0
                        font.family: Theme.font
                        font.pointSize: 9
                        font.bold: chip.on
                    }
                    MouseArea {
                        id: chipMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: picker.setTransition(chip.modelData.kind)
                    }
                }
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: -14 - height / 2
            text: "← →  choose   ·   p  preview   ·   Enter  done"
            color: Theme.overlay0
            font.family: Theme.font
            font.pointSize: 8
        }
    }

    // ── caption ──
    Item {
        id: caption
        visible: picker.sel !== null
        anchors.fill: parent
        opacity: picker.fade
        readonly property real cyc: picker.cy + picker.ch + 40

        readonly property string name: {
            const e = picker.sel;
            if (!e) return "";
            return e.name.length <= 60 ? e.name : e.name.slice(0, 59) + "…";
        }
        readonly property string sub: {
            const e = picker.sel;
            if (!e) return "";
            const bits = e.live ? ["blurs whatever is on screen when it locks"]
                                : [e.bucket].concat(e.video ? ["animated"] : []);
            if (e.path === picker.current) bits.push(picker.iCheck + " current");
            if (picker.sync && picker.accentOf(e)) bits.push("sets accent");
            if (!picker.lock) {
                const t = picker.transitionOf(picker.transition);
                bits.push(t.glyph + " " + t.label);
            }
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
            text: caption.name
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
            color: picker.accentOf(picker.sel) || (picker.sel && picker.swatch(picker.sel.bucket)) || Theme.subtext0
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
            if (picker.searching) {                          // typing a search
                if (k === Qt.Key_Escape) picker.toggleSearch();
                else if (k === Qt.Key_Backspace) {
                    picker.query = picker.query.slice(0, -1);
                    picker.refilter(picker.sel ? picker.sel.path : null);
                } else if (k === Qt.Key_Return || k === Qt.Key_Enter) picker.apply();
                else if (k === Qt.Key_Left || k === Qt.Key_Right) picker.move(k === Qt.Key_Left ? -1 : 1);
                else if (ev.text && ev.text.length === 1 && ev.text >= " ") {
                    picker.query += ev.text;
                    picker.refilter(picker.sel ? picker.sel.path : null);
                }
                return;
            }
            if (picker.tstrip) {                             // choosing a transition
                const kinds = picker.transitions.map(t => t.kind);
                const i = kinds.indexOf(picker.transition);
                if (k === Qt.Key_Left || k === Qt.Key_H || k === Qt.Key_Up || k === Qt.Key_K)
                    picker.setTransition(kinds[(i - 1 + kinds.length) % kinds.length]);
                else if (k === Qt.Key_Right || k === Qt.Key_L || k === Qt.Key_Down || k === Qt.Key_J || k === Qt.Key_Tab)
                    picker.setTransition(kinds[(i + 1) % kinds.length]);
                else if (k === Qt.Key_P) picker.preview();
                else if (k === Qt.Key_Escape || k === Qt.Key_Return || k === Qt.Key_Enter
                         || k === Qt.Key_T || k === Qt.Key_Space)
                    picker.tstrip = false;
                return;
            }
            const n = picker.items.length;
            if (k === Qt.Key_Escape || k === Qt.Key_Q) picker.close();
            else if (k === Qt.Key_Left || k === Qt.Key_H || k === Qt.Key_Up || k === Qt.Key_K) picker.move(-1);
            else if (k === Qt.Key_Right || k === Qt.Key_L || k === Qt.Key_Down || k === Qt.Key_J) picker.move(1);
            else if (k === Qt.Key_Home) picker.move(-n);
            else if (k === Qt.Key_End) picker.move(n);
            else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) picker.apply();
            else if (k === Qt.Key_Tab) picker.cycleFilter(1);
            else if (k === Qt.Key_Backtab) picker.cycleFilter(-1);
            else if (k === Qt.Key_A) picker.setFilter("All");
            else if (k === Qt.Key_V && !picker.lock) picker.setFilter("Video");
            else if (k === Qt.Key_C) picker.toggleSync();
            else if (k === Qt.Key_T && !picker.lock) picker.tstrip = !picker.tstrip;
            else if (k === Qt.Key_Slash || (k === Qt.Key_F && (ev.modifiers & Qt.ControlModifier))) {
                picker.searching = true;
                picker.query = "";
            } else if (k >= Qt.Key_1 && k <= Qt.Key_8) picker.setFilter(picker.colours[k - Qt.Key_1].name);
        }
    }
}
