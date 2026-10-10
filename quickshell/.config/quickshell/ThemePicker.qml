// Theme picker — SUPER+T (`qs ipc call themepicker toggle`). The wallpaper
// picker's carousel with desktop themes as the cards: each card is a little
// desktop drawn in that theme's palette (bar, a terminal with highlighted
// code, a window, the 14 accents). Enter applies it everywhere through
// hypr/set-theme.sh (shell, borders, terminal, GTK/Qt apps, notifications,
// lock screen, editors, Firefox, Spotify/Discord …; see that script).
//
//   ← → / h l / wheel   move              Enter / click centre   apply
//   1-8                 jump to a theme    click a side card      move to it
//   b                   bar style: classic ⇄ floating islands (applies at once)
//   Esc / q / right click / click outside  close
//
// Palettes come from hypr/rice-theme.py (`list`), read once.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

PanelWindow {
    id: picker

    property bool shown: false
    property var themes: []
    property int target: 0
    property real pos: 0
    property real fade: 0
    property real scrollAcc: 0
    property bool applying: false

    readonly property var sel: themes.length ? themes[Math.min(target, themes.length - 1)] : null
    readonly property string barStyle: (barFile.text() || "classic").trim() === "islands" ? "islands" : "classic"

    // ── geometry (wallpaper picker's) ──
    readonly property int ch: Math.round(height * 0.34)
    readonly property int slant: Math.round(ch * 0.30)
    readonly property int wc: Math.round(ch * 1.55)
    readonly property int wsl: Math.round(ch * 0.30)
    readonly property int gap: 12
    readonly property int cy: Math.round(height / 2 - ch / 2 + 24)
    readonly property int iw: wc + slant
    readonly property int m: 4

    function cardWidth(i) {
        const d = Math.min(1, Math.abs(i - pos));
        return wsl + (wc - wsl) * (1 - d);
    }

    readonly property var geo: {
        const n = themes.length;
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

    // the accent a switch would give: the current accent's ROLE in that theme
    function accentRole() {
        const cur = Theme.pal;
        const hex = String(Theme.accent).toLowerCase();
        const roles = ["rosewater", "flamingo", "pink", "mauve", "red", "maroon", "peach", "yellow",
                       "green", "teal", "sky", "sapphire", "blue", "lavender"];
        return roles.find(r => String(cur[r] || "").toLowerCase() === hex) || "";
    }

    function open() {
        const mon = Hyprland.focusedMonitor;
        for (const s of Quickshell.screens)
            if (mon && s.name === mon.name) screen = s;
        if (!themes.length) listProc.running = true;
        const i = themes.findIndex(t => t.id === Theme.themeId);
        target = Math.max(0, i);
        pos = target;
        fade = 0;
        applying = false;
        shown = true;
        tick.start();
        keys.forceActiveFocus();
    }

    function close() {
        shown = false;
        tick.stop();
    }

    function move(step) {
        if (!themes.length) return;
        target = Math.max(0, Math.min(themes.length - 1, target + step));
        tick.start();
    }

    function select(i) {
        target = i;
        tick.start();
    }

    function apply() {
        const t = sel;
        if (!t) return;
        if (t.id !== Theme.themeId) Theme.exec(Theme.hypr + "/set-theme.sh " + t.id);
        close();
    }

    function toggleBar() {
        barFile.setText((barStyle === "islands" ? "classic" : "islands") + "\n");
    }

    IpcHandler {
        target: "themepicker"
        function toggle(): void { picker.shown ? picker.close() : picker.open(); }
        function open(): void { if (!picker.shown) picker.open(); }
        function close(): void { picker.close(); }
    }

    Process {
        id: listProc
        command: ["/usr/bin/python3", Theme.hypr + "/rice-theme.py", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { picker.themes = JSON.parse(text); } catch (e) { return; }
                const i = picker.themes.findIndex(t => t.id === Theme.themeId);
                picker.target = Math.max(0, i);
                picker.pos = picker.target;
            }
        }
    }
    Component.onCompleted: listProc.running = true

    FileView {
        id: barFile
        path: Theme.hypr + "/theme/bar-style"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }

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
    WlrLayershell.namespace: "qs-theme-picker"
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    color: "transparent"
    visible: shown

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
            for (let i = 0; i < picker.themes.length; i++) {
                const left = picker.geo.lefts[i] + picker.geo.offset;
                const edge = left + picker.slant * (1 - ly / picker.ch);
                if (x < edge || x > edge + picker.geo.widths[i]) continue;
                const z = -Math.abs(i - picker.pos);
                if (z > bestZ) { bestZ = z; best = i; }
            }
            return best;
        }

        Repeater {
            model: picker.themes

            Item {
                id: card
                required property var modelData
                required property int index
                readonly property var t: modelData
                readonly property real w: picker.geo.widths[index] ?? picker.wsl
                readonly property real lx: (picker.geo.lefts[index] ?? 0) + picker.geo.offset
                readonly property real d: Math.min(1, Math.abs(index - picker.pos))
                readonly property bool selected: d < 0.5

                x: lx - picker.m
                y: picker.cy - picker.m
                width: w + picker.slant + 2 * picker.m
                height: picker.ch + 2 * picker.m + 18
                z: -Math.abs(index - picker.pos)
                visible: lx + w + picker.slant >= -20 && lx <= picker.width + 20

                ThemePreview {
                    id: preview
                    width: picker.iw
                    height: picker.ch
                    visible: false
                    p: card.t
                    accentRole: picker.accentRole() || card.t.accent
                }
                ShaderEffectSource {
                    id: tex
                    sourceItem: preview
                    hideSource: true
                    visible: false
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
                    property color strokeColor: card.selected ? (card.t[preview.accentRole] || Theme.accent)
                                                              : Theme.alpha(Theme.surface1, 0.8)
                    property color dimColor: Theme.crust
                    property color emptyColor: Theme.surface0
                    property var src: tex
                    fragmentShader: Qt.resolvedUrl("shaders/card.frag.qsb")
                }

                // ✓ on the theme in use, bottom-left
                Rectangle {
                    visible: card.t.id === Theme.themeId && card.w > 40
                    x: picker.m + 24 - 13
                    y: picker.m + picker.ch - 20 - 13
                    width: 26
                    height: 26
                    radius: 13
                    color: Theme.alpha(Theme.crust, 0.8)
                    opacity: picker.fade
                    Text {
                        anchors.centerIn: parent
                        text: "\u{f012c}"
                        color: Theme.green
                        font.family: Theme.font
                        font.pointSize: 11
                    }
                }
            }
        }

        Text {
            visible: picker.themes.length === 0
            x: picker.width / 2 - width / 2
            y: picker.cy + picker.ch / 2 - height / 2
            text: "Loading themes…"
            color: Theme.subtext0
            opacity: picker.fade
            font.family: Theme.font
            font.pointSize: 13
        }
    }

    // ── toolbar ──
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
                width: Math.max(150, label.implicitWidth + 24)
                height: 44
                Text {
                    id: label
                    anchors.centerIn: parent
                    text: picker.sel ? picker.sel.name : "Themes"
                    color: picker.sel ? picker.sel[picker.accentRole() || picker.sel.accent] : Theme.text
                    font.family: Theme.font
                    font.pointSize: 11
                    font.bold: true
                }
            }
            Item {
                width: 9; height: 44
                Rectangle { x: 4; y: 12; width: 1; height: 20; color: Theme.surface1 }
            }
            // one dot per theme: its base, ringed in its accent
            Repeater {
                model: picker.themes
                Item {
                    id: dot
                    required property var modelData
                    required property int index
                    readonly property bool on: index === picker.target
                    width: 30
                    height: 44
                    Rectangle {
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
                        color: dot.modelData.base
                        border.width: 3
                        border.color: dot.modelData[dot.modelData.accent]
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
                width: 9; height: 44
                Rectangle { x: 4; y: 12; width: 1; height: 20; color: Theme.surface1 }
            }
            // bar style: classic ⇄ floating islands
            Item {
                id: barBtn
                width: 34
                height: 44
                readonly property bool on: picker.barStyle === "islands"
                Rectangle {
                    visible: barBtn.on || barMouse.containsMouse
                    x: 2; y: 7
                    width: parent.width - 4
                    height: parent.height - 14
                    radius: 9
                    color: Theme.alpha(Theme.surface0, barBtn.on ? 1 : 0.7)
                }
                Text {
                    anchors.centerIn: parent
                    text: barBtn.on ? "\u{f1513}" : "\u{f056a}"   // md-dock_top (islands) / md-view_agenda (classic)
                    color: barBtn.on ? Theme.accent : barMouse.containsMouse ? Theme.text : Theme.overlay2
                    font.family: Theme.font
                    font.pointSize: 14
                }
                MouseArea {
                    id: barMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: picker.toggleBar()
                }
            }
        }
    }

    // ── caption ──
    Item {
        id: caption
        visible: picker.sel !== null
        anchors.fill: parent
        opacity: picker.fade
        readonly property real cyc: picker.cy + picker.ch + 40

        readonly property string sub: {
            const t = picker.sel;
            if (!t) return "";
            const bits = [];
            if (t.id === Theme.themeId) bits.push("\u{f05e0} current");
            const r = picker.accentRole() || t.accent;
            bits.push("accent " + r);
            bits.push("bar: " + (picker.barStyle === "islands" ? "floating islands" : "classic") + "  (b)");
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
            text: picker.sel ? picker.sel.name : ""
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
            color: picker.sel ? picker.sel[picker.accentRole() || picker.sel.accent] : Theme.subtext0
            font.family: Theme.font
            font.pointSize: 9
        }
        Text {
            x: picker.width / 2 - width / 2
            y: caption.cyc + 44 - height / 2
            text: (picker.target + 1) + " / " + picker.themes.length
            color: Theme.overlay0
            font.family: Theme.font
            font.pointSize: 9
        }
    }

    Item {
        id: keys
        focus: true
        Keys.onPressed: ev => {
            const k = ev.key;
            ev.accepted = true;
            const n = picker.themes.length;
            if (k === Qt.Key_Escape || k === Qt.Key_Q) picker.close();
            else if (k === Qt.Key_Left || k === Qt.Key_H || k === Qt.Key_Up || k === Qt.Key_K) picker.move(-1);
            else if (k === Qt.Key_Right || k === Qt.Key_L || k === Qt.Key_Down || k === Qt.Key_J) picker.move(1);
            else if (k === Qt.Key_Tab && n) picker.select((picker.target + 1) % n);
            else if (k === Qt.Key_Backtab && n) picker.select((picker.target - 1 + n) % n);
            else if (k === Qt.Key_Home) picker.move(-n);
            else if (k === Qt.Key_End) picker.move(n);
            else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) picker.apply();
            else if (k === Qt.Key_B) picker.toggleBar();
            else if (k >= Qt.Key_1 && k <= Qt.Key_9 && k - Qt.Key_1 < n) picker.select(k - Qt.Key_1);
        }
    }
}
