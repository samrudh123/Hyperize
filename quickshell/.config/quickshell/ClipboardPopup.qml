// Clipboard history (cliphist) under the top bar's clipboard pill —
// Serpantinum-style (PanelPopup: focus grab, Esc, intro).
//
//   header   clipboard orb · count · [Clear all] (click twice)
//   search   type to filter · ↑ ↓ move · Enter copy · Del remove · Tab kind
//   tabs     All · Text · Images
//   cards    text (two lines) or the image's thumbnail; click copies,
//            right-click / × removes
//
// The list comes from hypr/clip-list.py (newest 150; images decoded once
// into ~/.cache/cliphist-thumbs). Copying is `cliphist decode | wl-copy`, so
// images go back on the clipboard as images. SUPER+SHIFT+V opens it too
// (`qs ipc call clipboard toggle`).
import QtQuick
import Quickshell
import Quickshell.Io

PanelPopup {
    id: pop
    tabBar: menuTabs                          // Ctrl+Tab / Ctrl+Shift+Tab cycle it
    TabFade { id: tabFx; key: pop.kind; active: pop.isOpen }   // soft tab swap
    initialFocus: search                    // keyboard-opened: start typing here

    edge: Edges.Bottom
    panelWidth: 480
    pad: 16

    property var entries: []
    property string query: ""
    property int sel: 0
    property int kind: 0                      // 0 all, 1 text, 2 images

    readonly property var shown: {
        const q = query.trim().toLowerCase();
        return entries.filter(e => (kind === 0 || (kind === 1) === (e.image === ""))
                                   && (!q || e.text.toLowerCase().includes(q)));
    }
    readonly property int nImages: entries.filter(e => e.image !== "").length
    onShownChanged: sel = Math.max(0, Math.min(sel, shown.length - 1))

    onOpened: {
        query = "";
        search.text = "";
        sel = 0;
        clear.armed = false;
        lister.running = true;
        search.forceActiveFocus();
    }

    function copy(e) {
        if (!e) return;
        Theme.exec("cliphist decode " + e.id + " | wl-copy");
        close();
    }
    function remove(e) {
        if (!e) return;
        entries = entries.filter(x => x.id !== e.id);      // at once; the file follows
        Theme.exec("/usr/bin/python3 " + Theme.hypr + "/clip-list.py delete " + e.id);
    }
    function move(d) {
        sel = Math.max(0, Math.min(sel + d, shown.length - 1));
        list.positionViewAtIndex(sel, ListView.Contain);
    }

    Process {
        id: lister
        command: ["/usr/bin/python3", Theme.hypr + "/clip-list.py"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { pop.entries = JSON.parse(text); } catch (e) { pop.entries = []; }
            }
        }
    }

    function stage(k) { return Math.max(0, Math.min(1, (pop.intro - k * 0.12) / (1 - k * 0.12))); }

    Column {
        width: parent.width
        spacing: 12

        // ── header ──────────────────────────────────────────────────────────
        Item {
            width: parent.width
            height: 42
            opacity: pop.stage(0)
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12
                Rectangle {
                    width: 42
                    height: 42
                    radius: 13
                    color: Theme.alpha(Theme.accent, 0.18)
                    Text {
                        anchors.centerIn: parent
                        text: "\u{f0a38}"
                        color: Theme.accent
                        font.family: Theme.font
                        font.pixelSize: 21
                    }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        text: "Clipboard"
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: 18
                        font.weight: Font.Bold
                    }
                    Text {
                        text: lister.running && pop.entries.length === 0 ? "loading…"
                            : pop.entries.length + " item" + (pop.entries.length === 1 ? "" : "s")
                              + (pop.nImages ? "  ·  " + pop.nImages + " image" + (pop.nImages === 1 ? "" : "s") : "")
                        color: Theme.overlay1
                        font.family: Theme.font
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }
                }
            }
            IconBtn {
                id: clear
                property bool armed: false
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: pop.entries.length > 0
                size: 30
                icon: "\u{f05e9}"
                text: armed ? "Click again to clear all" : "Clear all"
                fg: Theme.red
                active: armed
                activeFg: Theme.red
                onClicked: {
                    if (!armed) { armed = true; disarm.restart(); return; }
                    armed = false;
                    pop.entries = [];
                    Theme.exec("/usr/bin/python3 " + Theme.hypr + "/clip-list.py wipe");
                }
                Timer { id: disarm; interval: 3000; onTriggered: clear.armed = false }
            }
        }

        // ── search ──────────────────────────────────────────────────────────
        Rectangle {
            width: parent.width
            height: 36
            radius: 10
            opacity: pop.stage(1)
            color: Theme.alpha(Theme.surface0, 0.8)
            border.width: 1
            border.color: search.activeFocus ? Theme.alpha(Theme.accent, 0.7) : Theme.alpha(Theme.surface1, 0.8)
            Text {
                id: lens
                x: 11
                anchors.verticalCenter: parent.verticalCenter
                text: "\u{f0349}"
                color: search.activeFocus ? Theme.accent : Theme.overlay1
                font.family: Theme.font
                font.pixelSize: 15
            }
            TextInput {
                id: search
                anchors { left: lens.right; leftMargin: 9; right: count.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                color: Theme.text
                selectionColor: Theme.alpha(Theme.accent, 0.4)
                font.family: Theme.font
                font.pixelSize: 13
                clip: true
                onTextChanged: { pop.query = text; pop.sel = 0; list.positionViewAtBeginning(); }
                Keys.onEscapePressed: pop.close()
                Keys.onReturnPressed: pop.copy(pop.shown[pop.sel])
                Keys.onEnterPressed: pop.copy(pop.shown[pop.sel])
                Keys.onDownPressed: pop.move(1)
                Keys.onUpPressed: pop.move(-1)
                Keys.onTabPressed: pop.kind = (pop.kind + 1) % 3
                Keys.onDeletePressed: event => {
                    if (search.text === "" || event.modifiers & Qt.ShiftModifier) pop.remove(pop.shown[pop.sel]);
                    else event.accepted = false;
                }
                Text {
                    visible: search.text === ""
                    text: "Search clipboard"
                    color: Theme.overlay0
                    font: search.font
                }
            }
            Text {
                id: count
                anchors { right: parent.right; rightMargin: 11; verticalCenter: parent.verticalCenter }
                text: pop.shown.length + (pop.query || pop.kind ? " / " + pop.entries.length : "")
                color: Theme.overlay0
                font.family: Theme.font
                font.pixelSize: 11
            }
        }

        Segmented {
            id: menuTabs
            width: parent.width
            height: 30
            opacity: pop.stage(1)
            options: ["\u{f0a38}  All", "\u{f09aa}  Text", "\u{f0976}  Images · " + pop.nImages]
            currentIndex: pop.kind
            onSelected: i => { pop.kind = i; search.forceActiveFocus(); }
        }

        // ── the list ────────────────────────────────────────────────────────
        Item {
            width: parent.width
            height: pop.shown.length ? Math.min(list.contentHeight, 430) : 70
            Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            opacity: pop.stage(2) * tabFx.value
            transform: Translate { y: 12 * (1 - pop.stage(2)) + 8 * (1 - tabFx.value) }

            ListView {
                id: list
                anchors.fill: parent
                clip: true
                spacing: 6
                boundsBehavior: Flickable.StopAtBounds
                model: pop.shown

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool isImage: modelData.image !== ""
                    readonly property bool current: index === pop.sel

                    width: ListView.view.width
                    height: isImage ? 86 : Math.max(46, txt.implicitHeight + 22)
                    radius: 12
                    color: current ? Theme.alpha(Theme.accent, 0.14)
                         : mouse.containsMouse ? Theme.alpha(Theme.surface1, 0.5) : Theme.alpha(Theme.surface0, 0.55)
                    border.width: 1
                    border.color: current ? Theme.alpha(Theme.accent, 0.6) : Theme.alpha(Theme.surface1, 0.35)
                    Behavior on color { ColorAnimation { duration: Theme.fast } }

                    Rectangle {
                        id: kindDot
                        x: 10
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !row.isImage
                        width: 26
                        height: 26
                        radius: 8
                        color: Theme.alpha(row.current ? Theme.accent : Theme.overlay0, 0.16)
                        Text {
                            anchors.centerIn: parent
                            text: /^https?:\/\//.test(row.modelData.text.trim()) ? "\u{f0337}" : "\u{f09aa}"
                            color: row.current ? Theme.accent : Theme.overlay1
                            font.family: Theme.font
                            font.pixelSize: 13
                        }
                    }
                    Rectangle {
                        id: thumbBox
                        visible: row.isImage
                        x: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(240, thumb.paintedWidth > 0 ? thumb.paintedWidth : 120)
                        height: 70
                        radius: 8
                        clip: true
                        color: Theme.alpha(Theme.crust, 0.6)
                        Image {
                            id: thumb
                            anchors.fill: parent
                            sourceSize.height: 140
                            fillMode: Image.PreserveAspectFit
                            horizontalAlignment: Image.AlignLeft
                            asynchronous: true
                            source: row.isImage ? "file://" + row.modelData.image : ""
                        }
                    }

                    Text {
                        id: txt
                        anchors {
                            left: row.isImage ? thumbBox.right : kindDot.right
                            leftMargin: 10
                            right: del.left; rightMargin: 8
                            verticalCenter: parent.verticalCenter
                        }
                        text: row.modelData.text.replace(/\s+/g, " ").trim()
                        textFormat: Text.PlainText
                        wrapMode: Text.Wrap
                        elide: Text.ElideRight
                        maximumLineCount: row.isImage ? 3 : 2
                        color: row.isImage ? Theme.subtext0 : Theme.text
                        font.family: Theme.font
                        font.pixelSize: 12
                    }

                    MouseArea {
                        id: mouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onEntered: pop.sel = row.index
                        onClicked: ev => {
                            if (ev.button === Qt.RightButton) pop.remove(row.modelData);
                            else pop.copy(row.modelData);
                        }
                    }

                    IconBtn {
                        id: del
                        anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                        opacity: mouse.containsMouse || hovered ? 1 : 0
                        size: 26
                        iconSize: 12
                        icon: "\u{f0156}"
                        fg: Theme.red
                        tip: "Remove (right-click, Del)"
                        onClicked: pop.remove(row.modelData)
                    }
                }
            }

            Column {
                visible: pop.shown.length === 0
                anchors.centerIn: parent
                spacing: 4
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "\u{f0a38}"
                    color: Theme.alpha(Theme.overlay0, 0.8)
                    font.family: Theme.font
                    font.pixelSize: 28
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: lister.running && pop.entries.length === 0 ? "Loading…"
                        : pop.query || pop.kind ? "No matches" : "Clipboard history is empty"
                    color: Theme.subtext0
                    font.family: Theme.font
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
            }
        }

        Text {
            opacity: pop.stage(3)
            text: "↵ copy   ↑↓ move   Tab kind   Del remove   Esc close"
            color: Theme.overlay0
            font.family: Theme.font
            font.pixelSize: 10
        }
    }
}
