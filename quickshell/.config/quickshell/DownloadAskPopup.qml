// The "new download" panel (Serpantinum-style) above the bottom bar's
// downloads pill — what the fuzzel menu of `dl-popup add` did: the browser
// extension (Zen / Firefox) hands a download over, this asks where it goes.
//
//   header   download glyph · "New download" · name · size · site
//   preview  PDFs: "Preview in Zathura" (nothing saved)
//   form     Save to (path field, recent folders ▾, Browse… = yazi) ·
//            Filename (aria2 only — JD names files itself) · Speed ▾ ·
//            Chunks [− n +] · Parallel [− n +] (typed numbers checked
//            against dl-popup's limits, red if outside) · aria2 | JDownloader
//   footer   Download · Let Zen download it · Cancel
//
// dl-popup writes the request (JSON, 0600) to a file and calls
// `qs ipc call downloads ask PATH`; the answer goes to PATH.reply:
//   {"action": "go" | "browse" | "preview" | "browser" | "cancel", "state": {…}}
// "browse" = run yazi, then dl-popup asks again with the picked folder.
// Closing the panel any other way (Esc, a click outside) = cancel.
import QtQuick
import Quickshell
import Quickshell.Io

PanelPopup {
    id: pop
    edge: Edges.Top
    panelWidth: 470
    pad: 16
    navigable: false                          // not in Ctrl+arrow's round
    initialFocus: goBtn                       // Enter = Download

    property string reqPath: ""               // the request being answered
    property var req: ({})
    property var st: ({})                     // the form's state (sent back)
    property bool answered: false
    readonly property bool jd: st.backend === "jd"
    readonly property string browser: req.browser || "the browser"
    tint: jd ? Theme.peach : Theme.sapphire

    // ── request / reply ─────────────────────────────────────────────────────
    // (Processes, not FileViews: a FileView whose path changes kept serving
    // the PREVIOUS request's text — the second download showed the first's)
    Process {
        id: reader
        property string path: ""
        command: ["cat", path]
        stdout: StdioCollector {
            onStreamFinished: {
                let r;
                try { r = JSON.parse(text); } catch (e) { return; }
                pop.show(reader.path, r);
            }
        }
    }
    Process { id: writer }

    function ask(path) {
        if (isOpen && reqPath && reqPath !== path) answer("cancel");
        reader.running = false;
        reader.path = path;
        reader.running = true;
    }
    function show(path, r) {
        req = r;
        st = Object.assign({}, r.state);
        reqPath = path;
        answered = false;
        nameField.text = st.filename || "";
        dirField.text = st.dir || "";
        if (isOpen) close();
        Qt.callLater(openByKeyboard);
    }
    function answer(action) {
        if (!reqPath || answered) return;
        if (action === "go" && badNums) {               // fix the red number first
            (chunksSt.invalid ? chunksSt : parSt).input.forceActiveFocus();
            return;
        }
        answered = true;
        const s = Object.assign({}, st, { dir: dirField.text.trim() || st.dir, filename: nameField.text.trim() });
        writer.command = ["sh", "-c", 'umask 077; printf "%s\\n" "$2" > "$1.tmp" && mv "$1.tmp" "$1"', "sh",
                          reqPath + ".reply", JSON.stringify({ action: action, state: s })];
        writer.running = true;
        reqPath = "";
        if (isOpen) close();
    }
    function setSt(k, v) { const s = Object.assign({}, st); s[k] = v; st = s; }
    onClosed2: if (reqPath && !answered) answer("cancel")

    // the limits dl-popup applies (it clamps the reply to these too)
    readonly property int chunksMax: jd ? 20 : 16
    readonly property int parMax: 20
    readonly property var numErrors: [
        chunksSt.invalid ? "\u{f0028}  Chunks must be a whole number from 1 to " + chunksMax
                           + (jd ? " (JDownloader's limit)" : " (aria2's limit)") : "",
        parSt.invalid ? "\u{f0028}  Parallel must be a whole number from 1 to " + parMax : ""
    ].filter(m => m)
    readonly property bool badNums: numErrors.length > 0
    readonly property var speeds: req.speeds || []

    function stage(k) { return Math.max(0, Math.min(1, (pop.intro - k * 0.12) / (1 - k * 0.12))); }

    component FieldLabel: Text {
        width: 74
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        color: Theme.subtext0
        font.family: Theme.font
        font.pixelSize: 11
        font.weight: Font.DemiBold
    }

    Column {
        width: parent.width
        spacing: 12

        // ── header ──────────────────────────────────────────────────────────
        Row {
            width: parent.width
            spacing: 14
            opacity: pop.stage(0)
            transform: Translate { y: 12 * (1 - pop.stage(0)) }
            Rectangle {
                id: badge
                width: 52
                height: 52
                radius: 16
                color: Theme.alpha(pop.tint, 0.16)
                border.width: 1
                border.color: Theme.alpha(pop.tint, 0.45)
                Behavior on color { ColorAnimation { duration: Theme.fast } }
                Text {
                    anchors.centerIn: parent
                    text: pop.req.preview ? "\u{f0226}" : "\u{f01da}"
                    color: pop.tint
                    font.family: Theme.font
                    font.pixelSize: 24
                }
            }
            Column {
                width: parent.width - badge.width - parent.spacing
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3
                Text {
                    text: "New download"
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 17
                    font.weight: Font.Bold
                }
                Text {
                    width: parent.width
                    elide: Text.ElideMiddle
                    text: pop.req.name || "(name from the server)"
                    color: pop.tint
                    font.family: Theme.font
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: [pop.req.size, pop.req.host, pop.req.browser ? "from " + pop.req.browser : ""].filter(s => s).join("  ·  ")
                    color: Theme.overlay1
                    font.family: Theme.font
                    font.pixelSize: 10
                }
            }
        }

        // ── PDF preview ─────────────────────────────────────────────────────
        Rectangle {
            visible: !!pop.req.preview
            width: parent.width
            height: 46
            radius: 12
            opacity: pop.stage(1)
            color: prevMa.containsMouse || prevBtn.activeFocus ? Theme.alpha(Theme.mauve, 0.22) : Theme.alpha(Theme.mauve, 0.12)
            border.width: 1
            border.color: Theme.alpha(Theme.mauve, 0.4)
            Behavior on color { ColorAnimation { duration: Theme.fast } }
            Row {
                anchors.verticalCenter: parent.verticalCenter
                x: 14
                spacing: 10
                Text { text: "\u{f0dc8}"; color: Theme.mauve; font.family: Theme.font; font.pixelSize: 17; anchors.verticalCenter: parent.verticalCenter }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Text { text: "Preview in Zathura"; color: Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.DemiBold }
                    Text { text: "opens it in a tab, nothing is saved"; color: Theme.overlay1; font.family: Theme.font; font.pixelSize: 10 }
                }
            }
            MouseArea {
                id: prevMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: pop.answer("preview")
            }
            // keyboard stop (Tab to it, Enter)
            Item {
                id: prevBtn
                anchors.fill: parent
                activeFocusOnTab: parent.visible
                function kbActivate() { pop.answer("preview"); }
                FocusRing {}
            }
        }

        // ── form ────────────────────────────────────────────────────────────
        Rectangle {
            width: parent.width
            height: form.implicitHeight + 24
            radius: 14
            color: Theme.alpha(Theme.surface0, 0.45)
            border.width: 1
            border.color: Theme.alpha(Theme.surface1, 0.6)
            opacity: pop.stage(1)
            transform: Translate { y: 14 * (1 - pop.stage(1)) }

            Column {
                id: form
                x: 12
                y: 12
                width: parent.width - 24
                spacing: 10

                Row {
                    width: parent.width
                    spacing: 6
                    FieldLabel { text: "\u{f024b}  Save to" }
                    SettingsField {
                        id: dirField
                        width: parent.width - 74 - (recentDd.visible ? recentDd.width + parent.spacing : 0)
                               - browseBtn.width - 2 * parent.spacing
                        height: 32
                        placeholder: "folder"
                        onAccepted: pop.answer("go")
                    }
                    // recent folders (the default first)
                    Dropdown {
                        id: recentDd
                        readonly property var dirs: pop.req.dirs || []
                        visible: dirs.length > 0
                        width: 46
                        height: 32
                        showValue: false
                        icon: "\u{f02da}"
                        tip: "Recent folders"
                        elide: Text.ElideMiddle
                        maxRows: 8
                        listWidth: form.width - 80 + 12        // from the path field to the panel's edge
                        options: dirs.map((d, i) => ({ label: d.label, icon: "\u{f024b}", hint: i === 0 ? "default" : "" }))
                        currentIndex: dirs.findIndex(d => d.label === dirField.text.trim())
                        onSelected: i => dirField.text = dirs[i].label
                    }
                    IconBtn {
                        id: browseBtn
                        size: 32
                        iconSize: 14
                        icon: "\u{f0770}"
                        tip: "Pick a folder in yazi  (q = this folder, Q = cancel)"
                        tipEdge: Edges.Top
                        onClicked: pop.answer("browse")
                    }
                }

                Row {
                    visible: !pop.jd                  // JDownloader names files itself
                    width: parent.width
                    spacing: 6
                    FieldLabel { text: "\u{f0214}  Name" }
                    SettingsField {
                        id: nameField
                        width: parent.width - 74 - parent.spacing
                        height: 32
                        placeholder: "from the server"
                        onAccepted: pop.answer("go")
                    }
                }

                Row {
                    width: parent.width
                    spacing: 6
                    FieldLabel { text: "\u{f04c5}  Speed" }
                    Dropdown {
                        width: parent.width - 74 - parent.spacing
                        height: 30
                        fontSize: 11
                        accent: pop.tint
                        options: pop.speeds.map(s => s.bps
                            ? { label: s.label.replace(/^([\d.]+)\s*([KMG])$/i, (m, n, u) => n + " " + u.toUpperCase() + "B/s") }
                            : { label: "Unlimited", icon: "\u{f06e4}" })
                        currentIndex: Math.max(0, pop.speeds.findIndex(s => s.bps === pop.st.speed))
                        onSelected: i => pop.setSt("speed", pop.speeds[i].bps)
                    }
                }
                Row {
                    id: numRow
                    width: parent.width
                    spacing: 6
                    readonly property real stW: (width - 2 * 74 - 3 * spacing) / 2
                    FieldLabel { text: "\u{f00fb}  Chunks" }
                    Stepper {
                        id: chunksSt
                        width: numRow.stW
                        value: pop.st.chunks || 1
                        min: 1
                        max: pop.chunksMax
                        onEdited: v => pop.setSt("chunks", v)
                        onAccepted: pop.answer("go")
                    }
                    FieldLabel { text: "\u{f0328}  Parallel" }
                    Stepper {
                        id: parSt
                        width: numRow.stW
                        value: pop.st.parallel || 1
                        min: 1
                        max: pop.parMax
                        onEdited: v => pop.setSt("parallel", v)
                        onAccepted: pop.answer("go")
                    }
                }
                Row {
                    width: parent.width
                    spacing: 6
                    FieldLabel { text: "\u{f048b}  Using" }
                    Segmented {
                        width: parent.width - 74 - parent.spacing
                        height: 30
                        fontSize: 11
                        accent: pop.tint
                        options: ["aria2", "JDownloader"]
                        currentIndex: pop.jd ? 1 : 0
                        onSelected: i => pop.setSt("backend", i ? "jd" : "aria2")
                    }
                }
                Text {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: pop.badNums ? pop.numErrors.join("\n")
                        : pop.jd ? "JDownloader names the file itself; chunks 1–20 per file; parallel (1–20) applies to all of JD."
                                 : "Chunks = connections per file (1–16, aria2's cap); parallel = downloads at once (1–20)."
                    color: pop.badNums ? Theme.red : Theme.overlay1
                    font.weight: pop.badNums ? Font.DemiBold : Font.Normal
                    font.family: Theme.font
                    font.pixelSize: 10
                }
            }
        }

        // ── footer ──────────────────────────────────────────────────────────
        Row {
            spacing: 6
            opacity: pop.stage(2)
            IconBtn {
                id: goBtn
                size: 34
                iconSize: 15
                icon: "\u{f01da}"
                text: "Download"
                enabled: !pop.badNums
                tip: pop.badNums ? "Fix the number in red first" : ""
                tipEdge: Edges.Top
                active: true
                activeFg: pop.tint
                onClicked: pop.answer("go")
            }
            IconBtn {
                size: 34
                iconSize: 15
                icon: pop.browser === "Zen" ? "\u{f05dd}" : "\u{f0239}"
                text: "Let " + pop.browser + " download it"
                onClicked: pop.answer("browser")
            }
            IconBtn {
                size: 34
                iconSize: 15
                icon: "\u{f0156}"
                text: "Cancel"
                fg: Theme.red
                onClicked: pop.answer("cancel")
            }
        }
    }
}
