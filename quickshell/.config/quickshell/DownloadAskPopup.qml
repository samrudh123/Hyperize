// The "new download" panel (Serpantinum-style) above the bottom bar's
// downloads pill — what the fuzzel menu of `dl-popup add` did: the browser
// extension (Zen / Firefox) hands a download over, this asks where it goes.
//
//   header   download glyph · "New download" · name · size · site
//   preview  PDFs: "Preview in Zathura" (nothing saved)
//   form     Save to (path field, Browse… = yazi, recent folders) · Filename
//            (aria2 only — JD names files itself) · Speed · Chunks ·
//            Parallel · aria2 | JDownloader
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

    // a number list with the current value in it (it may be a typed one)
    function withCurrent(list, cur) {
        const l = (list || []).slice();
        if (cur !== undefined && !l.includes(cur)) { l.push(cur); l.sort((a, b) => a - b); }
        return l;
    }
    readonly property var chunkOpts: withCurrent(req.chunks, st.chunks)
    readonly property var parOpts: withCurrent(req.parallel, st.parallel)
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
                        width: parent.width - 74 - browseBtn.width - 2 * parent.spacing
                        height: 32
                        placeholder: "folder"
                        onAccepted: pop.answer("go")
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
                // recent folders
                Flow {
                    id: recentFlow
                    visible: recents.count > 0
                    x: 80
                    width: parent.width - 80
                    spacing: 5
                    Repeater {
                        id: recents
                        model: (pop.req.dirs || []).filter(d => d.label !== dirField.text.trim()).slice(0, 4)
                        // a folder chip, elided in the middle when long
                        delegate: Rectangle {
                            id: chip
                            required property var modelData
                            width: Math.min(chipRow.implicitWidth + 18, recentFlow.width)
                            height: 24
                            radius: 8
                            color: chipMa.containsMouse ? Theme.alpha(Theme.surface1, 0.9) : Theme.alpha(Theme.surface0, 0.75)
                            Behavior on color { ColorAnimation { duration: Theme.fast } }
                            activeFocusOnTab: visible
                            function kbActivate() { dirField.text = modelData.label; }
                            Row {
                                id: chipRow
                                x: 9
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6
                                Text {
                                    id: chipIcon
                                    text: "\u{f024b}"
                                    color: Theme.overlay1
                                    font.family: Theme.font
                                    font.pixelSize: 11
                                }
                                Text {
                                    width: Math.min(implicitWidth, recentFlow.width - 18 - chipIcon.width - 6)
                                    elide: Text.ElideMiddle
                                    text: chip.modelData.label
                                    color: chipMa.containsMouse ? Theme.text : Theme.subtext0
                                    font.family: Theme.font
                                    font.pixelSize: 11
                                }
                            }
                            MouseArea {
                                id: chipMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: chip.kbActivate()
                            }
                            FocusRing {}
                        }
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
                    Segmented {
                        width: parent.width - 74 - parent.spacing
                        height: 30
                        fontSize: 11
                        accent: pop.tint
                        options: pop.speeds.map(s => s.bps ? s.label : "\u{f06e4}")
                        currentIndex: Math.max(0, pop.speeds.findIndex(s => s.bps === pop.st.speed))
                        onSelected: i => pop.setSt("speed", pop.speeds[i].bps)
                    }
                }
                Row {
                    width: parent.width
                    spacing: 6
                    FieldLabel { text: "\u{f00fb}  Chunks" }
                    Segmented {
                        width: parent.width - 74 - parent.spacing
                        height: 30
                        fontSize: 11
                        accent: pop.tint
                        options: pop.chunkOpts.map(String)
                        currentIndex: Math.max(0, pop.chunkOpts.indexOf(pop.st.chunks))
                        onSelected: i => pop.setSt("chunks", pop.chunkOpts[i])
                    }
                }
                Row {
                    width: parent.width
                    spacing: 6
                    FieldLabel { text: "\u{f0328}  Parallel" }
                    Segmented {
                        width: parent.width - 74 - parent.spacing
                        height: 30
                        fontSize: 11
                        accent: pop.tint
                        options: pop.parOpts.map(String)
                        currentIndex: Math.max(0, pop.parOpts.indexOf(pop.st.parallel))
                        onSelected: i => pop.setSt("parallel", pop.parOpts[i])
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
                    text: pop.jd ? "JDownloader names the file itself; parallel applies to all of JD."
                                 : "Chunks = connections per file (aria2 caps it at 16); parallel = downloads at once."
                    color: Theme.overlay1
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
