// Settings › Terminal: the greeting a new terminal prints (zsh fortunefetch):
// fastfetch's logo, the cowsay cow + fortune under it, and which fastfetch
// details show. ~/.config/fastfetch/greeting.py does the work (state / set /
// preview); the preview stays pinned above the options and redraws after
// every pick, with the same fortune until "New fortune".
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: page

    readonly property string script: Quickshell.env("HOME") + "/.config/fastfetch/greeting.py"
    readonly property string termFont: "JetBrainsMono Nerd Font"   // ghostty's
    readonly property int halfCols: 91                              // a half-screen ghostty

    property var st: null                 // greeting.py state
    property string logo: st ? st.logo : ""
    property string cow: st ? st.cow : ""
    property var on: ({})                 // module / extra id → bool
    property var pv: null                 // greeting.py preview
    property string fortune: ""
    property bool big: false              // the preview takes the whole page

    // SettingsPanel's keyboard scrolling + Tab-reveal go to the options
    readonly property real keyStep: opts.keyStep
    readonly property real contentHeight: opts.contentHeight
    function scrollBy(dy) { opts.scrollBy(dy); }
    function scrollTo(y) { opts.scrollTo(y); }
    function reveal(it) { opts.reveal(it); }

    // ── greeting.py ─────────────────────────────────────────────────────────
    Process {
        id: stateProc
        running: true
        command: ["/usr/bin/python3", page.script, "state"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const s = JSON.parse(text);
                    const o = {};
                    for (const m of s.modules.concat(s.extras)) o[m.id] = m.on;
                    page.on = o;
                    page.st = s;
                } catch (e) {}
                page.refresh();
            }
        }
    }

    // picks run one after another (a quick run of clicks queues), then the
    // preview redraws once
    property var queue: []
    function set(args) {
        queue = queue.concat([args]);
        if (!setProc.running) next();
    }
    function next() {
        if (!queue.length) { refresh(); return; }
        const a = queue[0];
        queue = queue.slice(1);
        setProc.command = ["/usr/bin/python3", page.script, "set"].concat(a);
        setProc.running = true;
    }
    Process {
        id: setProc
        onExited: page.next()
    }

    function pickLogo(id) { if (id !== logo) { logo = id; set(["logo", id]); } }
    function pickCow(id) { if (id !== cow) { cow = id; set(["cow", id]); } }
    function flip(id) {
        const o = Object.assign({}, on);
        o[id] = !o[id];
        on = o;
        set(["module", id, o[id] ? "1" : "0"]);
    }

    property bool again: false
    property bool loading: false
    function refresh() {
        if (previewProc.running) { again = true; return; }
        loading = true;
        previewProc.command = ["/usr/bin/python3", page.script, "preview"].concat(fortune ? [fortune] : []);
        previewProc.running = true;
    }
    function newFortune() { fortune = ""; refresh(); }
    Process {
        id: previewProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const p = JSON.parse(text);
                    page.pv = p;
                    page.fortune = p.fortune;
                } catch (e) {}
            }
        }
        onExited: {
            page.loading = false;
            if (page.again) { page.again = false; page.refresh(); }
        }
    }

    TextMetrics { id: cell; font.family: page.termFont; font.pixelSize: 11; text: "M" }

    // ── title + the pinned preview ──────────────────────────────────────────
    Column {
        id: top
        x: 28
        y: 24
        width: page.width - 56
        spacing: 4
        Text {
            text: "Terminal"
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: 22
            font.weight: Font.Bold
        }
        Text {
            width: parent.width
            text: "The greeting a new terminal prints (and `ff`): the logo, the cow with a fortune, and fastfetch's details."
            color: Theme.overlay1
            wrapMode: Text.Wrap
            font.family: Theme.font
            font.pixelSize: 12
        }
        Item { width: 1; height: 10 }

        Rectangle {
            id: term
            width: parent.width
            // click it (or the fullscreen button) for the whole page; again for the options
            height: page.big ? page.height - y - top.y - 16
                             : Math.round(Math.min(400, Math.max(220, page.height * 0.5)))
            Behavior on height { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
            radius: 14
            color: page.pv && page.pv.bg ? page.pv.bg : Theme.crust
            border.width: 1
            border.color: Theme.alpha(Theme.surface1, 0.7)
            clip: true

            // window-ish strip: dots · what it needs · new fortune
            Item {
                id: strip
                width: parent.width
                height: 34
                Row {
                    x: 14
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    Repeater {
                        model: [Theme.red, Theme.yellow, Theme.green]
                        delegate: Rectangle {
                            required property var modelData
                            width: 10; height: 10; radius: 5
                            color: Theme.alpha(modelData, 0.8)
                        }
                    }
                }
                Text {
                    anchors.centerIn: parent
                    readonly property int cols: page.pv ? page.pv.cols : 0
                    text: !page.pv ? "drawing…"
                        : cols + " columns wide  ·  " + (cols <= page.halfCols ? "fits a half-screen terminal"
                                                                              : "cut off in a half-screen terminal (" + page.halfCols + ")")
                    color: !page.pv || cols <= page.halfCols ? Theme.overlay1 : Theme.peach
                    font.family: Theme.font
                    font.pixelSize: 11
                }
                Row {
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4
                    IconBtn {
                        size: 26
                        iconSize: 13
                        icon: "\u{f0450}"
                        text: "New fortune"
                        enabled: page.cow !== "none"
                        tip: "Same logo and cow, another fortune"
                        onClicked: page.newFortune()
                    }
                    IconBtn {
                        size: 26
                        iconSize: 13
                        icon: page.big ? "\u{f0294}" : "\u{f0293}"
                        active: page.big
                        tip: page.big ? "Back to the options" : "Bigger preview"
                        onClicked: page.big = !page.big
                    }
                }
            }
            Rectangle {
                y: strip.height
                width: parent.width
                height: 1
                color: Theme.alpha(Theme.surface1, 0.5)
            }

            MouseArea {
                anchors.fill: screen
                cursorShape: Qt.PointingHandCursor
                onClicked: page.big = !page.big
            }
            Item {
                id: screen
                x: 16
                y: strip.height + 10
                width: parent.width - 32
                height: parent.height - y - 10
                clip: true

                Text {
                    id: out
                    textFormat: Text.RichText
                    text: page.pv ? page.pv.html : ""
                    color: page.pv ? page.pv.fg : Theme.text
                    font.family: page.termFont
                    font.pixelSize: 11
                    transformOrigin: Item.TopLeft
                    scale: implicitWidth > 0 ? Math.min(1, screen.width / implicitWidth, screen.height / implicitHeight) : 1
                    opacity: page.loading ? 0.55 : 1
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                }

                // where a half-screen terminal ends
                Rectangle {
                    visible: page.pv && page.pv.cols > page.halfCols
                    x: page.halfCols * cell.advanceWidth * out.scale
                    width: 1
                    height: Math.min(parent.height, out.implicitHeight * out.scale)
                    color: Theme.alpha(Theme.peach, 0.55)
                }
            }
        }
    }

    // ── the options (scroll under the preview) ──────────────────────────────
    SettingsPage {
        id: opts
        showHead: false
        width: page.width
        y: top.y + top.height + 4
        height: Math.max(0, page.height - y)

        // logo
        SettingsCard {
            title: "Logo"
            icon: "\u{f31b}"
            Item {
                width: parent.width
                height: logoGrid.height + 24
                Grid {
                    id: logoGrid
                    x: 12
                    y: 12
                    width: parent.width - 24
                    columns: 4
                    spacing: 8
                    Repeater {
                        model: page.st ? page.st.logos : []
                        delegate: Rectangle {
                            id: tile
                            required property var modelData
                            readonly property bool cur: modelData.id === page.logo
                            width: (logoGrid.width - 3 * logoGrid.spacing) / 4
                            height: 150
                            radius: 12
                            color: page.pv && page.pv.bg ? page.pv.bg : Theme.crust
                            border.width: cur ? 2 : 1
                            border.color: cur ? Theme.accent : tma.containsMouse || activeFocus ? Theme.overlay0 : Theme.alpha(Theme.surface1, 0.7)
                            Behavior on border.color { ColorAnimation { duration: Theme.fast } }
                            scale: tma.pressed ? 0.96 : 1
                            Behavior on scale { NumberAnimation { duration: 120 } }

                            activeFocusOnTab: true
                            Keys.onPressed: ev => {
                                if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter || ev.key === Qt.Key_Space) {
                                    page.pickLogo(tile.modelData.id);
                                    ev.accepted = true;
                                }
                            }

                            Item {
                                id: art
                                x: 8
                                y: 8
                                width: parent.width - 16
                                height: parent.height - 34
                                clip: true
                                Text {
                                    visible: tile.modelData.html !== ""
                                    textFormat: Text.RichText
                                    text: tile.modelData.html
                                    font.family: page.termFont
                                    font.pixelSize: 9
                                    transformOrigin: Item.Center
                                    anchors.centerIn: parent
                                    scale: implicitWidth > 0 ? Math.min(1, art.width / implicitWidth, art.height / implicitHeight) : 1
                                }
                                Text {
                                    visible: tile.modelData.html === ""
                                    anchors.centerIn: parent
                                    text: "\u{f0156}"
                                    color: Theme.overlay0
                                    font.family: Theme.font
                                    font.pixelSize: 22
                                }
                            }
                            Text {
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 8
                                x: 8
                                width: parent.width - 16
                                horizontalAlignment: Text.AlignHCenter
                                text: tile.modelData.name
                                elide: Text.ElideRight
                                color: tile.cur ? Theme.accent : Theme.subtext0
                                font.family: Theme.font
                                font.pixelSize: 11
                                font.weight: tile.cur ? Font.Bold : Font.Medium
                            }
                            MouseArea {
                                id: tma
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: page.pickLogo(tile.modelData.id)
                            }
                            FocusRing {}
                        }
                    }
                }
            }
        }

        // cow
        SettingsCard {
            title: "Cow"
            icon: "\u{f019a}"
            Item {
                width: parent.width
                height: cowFlow.height + 24
                Flow {
                    id: cowFlow
                    x: 12
                    y: 12
                    width: parent.width - 24
                    spacing: 6
                    Repeater {
                        model: page.st ? [{ id: "none", name: "No fortune", icon: "\u{f0156}" },
                                          { id: "random", name: "Random", icon: "\u{f049d}" }]
                                         .concat(page.st.cows.map(c => ({ id: c, name: c, icon: "" }))) : []
                        delegate: Chip {
                            required property var modelData
                            label: modelData.name
                            glyph: modelData.icon
                            checked: modelData.id === page.cow
                            onActivated: page.pickCow(modelData.id)
                        }
                    }
                }
            }
        }

        // fastfetch details, per box section
        SettingsCard {
            title: "Details"
            icon: "\u{f0279}"
            Column {
                width: parent.width
                topPadding: 6
                bottomPadding: 12
                spacing: 4
                Repeater {
                    model: page.st ? page.st.sections.concat([{ id: "_extra", name: "Around the box" }]) : []
                    delegate: Column {
                        id: sec
                        required property var modelData
                        x: 12
                        width: parent.width - 24
                        spacing: 8
                        Text {
                            topPadding: 6
                            leftPadding: 4
                            text: sec.modelData.name
                            color: Theme.overlay1
                            font.family: Theme.font
                            font.pixelSize: 11
                            font.weight: Font.Bold
                        }
                        Flow {
                            width: parent.width
                            spacing: 6
                            Repeater {
                                model: sec.modelData.id === "_extra" ? page.st.extras
                                     : page.st.modules.filter(m => m.section === sec.modelData.id)
                                delegate: Chip {
                                    required property var modelData
                                    label: modelData.name
                                    glyph: modelData.icon || (modelData.id === "title" ? "\u{f0004}" : "\u{f03d8}")
                                    toggle: true
                                    checked: !!page.on[modelData.id]
                                    onActivated: page.flip(modelData.id)
                                }
                            }
                        }
                    }
                }
            }
        }

        Text {
            width: parent.width
            leftPadding: 4
            text: "Applies to new terminals. greeting.py writes ~/.config/fastfetch/greeting.env (logo + cow) and config.jsonc's modules (so plain `fastfetch` shows the same details)."
            wrapMode: Text.Wrap
            color: Theme.overlay0
            font.family: Theme.font
            font.pixelSize: 11
        }
    }

    // a pill to pick: a cow, or a detail (toggle: ✓ / dim)
    component Chip: Rectangle {
        id: chip
        property string label
        property string glyph
        property bool checked
        property bool toggle: false
        signal activated()

        implicitWidth: row.implicitWidth + 22
        implicitHeight: 28
        radius: 9
        color: checked ? (toggle ? Theme.alpha(Theme.accent, 0.2) : Theme.accent)
             : cma.containsMouse ? Theme.alpha(Theme.surface1, 0.9) : Theme.alpha(Theme.surface0, 0.75)
        border.width: 1
        border.color: checked ? Theme.alpha(Theme.accent, toggle ? 0.7 : 1) : Theme.alpha(Theme.surface1, 0.5)
        Behavior on color { ColorAnimation { duration: Theme.fast; easing.type: Easing.OutQuint } }
        scale: cma.pressed ? 0.94 : 1
        Behavior on scale { NumberAnimation { duration: 110 } }

        readonly property color fg: checked ? (toggle ? Theme.accent : Theme.crust)
                                  : cma.containsMouse ? Theme.text : Theme.subtext0

        activeFocusOnTab: true
        Keys.onPressed: ev => {
            if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter || ev.key === Qt.Key_Space) {
                chip.activated();
                ev.accepted = true;
            }
        }

        Row {
            id: row
            anchors.centerIn: parent
            spacing: 6
            Text {
                visible: chip.glyph !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: chip.glyph
                color: chip.toggle && !chip.checked ? Theme.overlay1 : chip.fg
                font.family: Theme.font
                font.pixelSize: 13
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: chip.label
                color: chip.fg
                font.family: Theme.font
                font.pixelSize: 12
                font.weight: chip.checked ? Font.DemiBold : Font.Normal
            }
        }
        MouseArea {
            id: cma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.activated()
        }
        FocusRing {}
    }
}
