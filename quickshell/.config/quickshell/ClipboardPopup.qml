// Clipboard history (cliphist) under the top bar's clipboard pill.
//
//   type          filter            ↑ ↓   move          Enter  copy
//   click         copy              right-click / ×  remove   Esc  close
//
// The list comes from hypr/clip-list.py (newest 150; images decoded once
// into ~/.cache/cliphist-thumbs). Copying is `cliphist decode | wl-copy`, so
// images go back on the clipboard as images. SUPER+SHIFT+V opens it too
// (`qs ipc call clipboard toggle`; it used to be a fuzzel picker).
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

PopupWindow {
    id: pop

    property Item pill: null
    property bool isOpen: false
    property var entries: []
    property string query: ""
    property int sel: 0

    readonly property var shown: {
        const q = query.trim().toLowerCase();
        if (!q) return entries;
        return entries.filter(e => e.text.toLowerCase().includes(q));
    }
    onShownChanged: sel = Math.max(0, Math.min(sel, shown.length - 1))

    function open() {
        query = "";
        search.text = "";
        sel = 0;
        lister.running = true;
        isOpen = true;
        search.forceActiveFocus();
    }
    function close() { isOpen = false; }
    function toggle() { if (isOpen) close(); else open(); }

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

    visible: isOpen
    color: "transparent"
    anchor.item: pill
    anchor.rect.x: pill ? pill.width / 2 : 0
    anchor.rect.y: pill ? pill.height + 6 : 0
    anchor.gravity: Edges.Bottom
    implicitWidth: 440
    implicitHeight: card.height

    HyprlandFocusGrab {
        active: pop.isOpen
        windows: [pop]
        onCleared: pop.close()
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

    Rectangle {
        id: card
        width: parent.width
        height: col.height + 16
        radius: 14
        color: Theme.alpha(Theme.mantle, 0.97)
        border.width: 1
        border.color: Theme.surface1
        opacity: pop.isOpen ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 120 } }

        Column {
            id: col
            x: 8
            y: 8
            width: parent.width - 16
            spacing: 6

            // search
            Rectangle {
                width: parent.width
                height: 34
                radius: 9
                color: Theme.alpha(Theme.surface0, 0.8)
                border.width: search.activeFocus ? 1 : 0
                border.color: Theme.alpha(Theme.accent, 0.6)

                Text {
                    id: lens
                    x: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u{f0349}"                  // md-magnify
                    color: Theme.overlay1
                    font.family: Theme.font
                    font.pixelSize: 15
                }
                TextInput {
                    id: search
                    anchors { left: lens.right; leftMargin: 8; right: count.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    color: Theme.text
                    selectionColor: Theme.alpha(Theme.accent, 0.4)
                    font.family: Theme.uiFont
                    font.pixelSize: 13
                    clip: true
                    onTextChanged: { pop.query = text; pop.sel = 0; list.positionViewAtBeginning(); }
                    Keys.onEscapePressed: pop.close()
                    Keys.onReturnPressed: pop.copy(pop.shown[pop.sel])
                    Keys.onEnterPressed: pop.copy(pop.shown[pop.sel])
                    Keys.onDownPressed: { pop.sel = Math.min(pop.sel + 1, pop.shown.length - 1); list.positionViewAtIndex(pop.sel, ListView.Contain); }
                    Keys.onUpPressed: { pop.sel = Math.max(pop.sel - 1, 0); list.positionViewAtIndex(pop.sel, ListView.Contain); }
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
                    anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                    text: pop.shown.length + (pop.query ? " / " + pop.entries.length : "")
                    color: Theme.overlay0
                    font.family: Theme.font
                    font.pixelSize: 11
                }
            }

            ListView {
                id: list
                width: parent.width
                height: Math.min(contentHeight, 470)
                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                model: pop.shown

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool isImage: modelData.image !== ""
                    readonly property bool current: index === pop.sel

                    width: ListView.view.width
                    height: isImage ? 74 : 38
                    radius: 8
                    color: current ? Theme.alpha(Theme.surface0, 0.95)
                         : mouse.containsMouse ? Theme.alpha(Theme.surface0, 0.6) : "transparent"
                    border.width: current ? 1 : 0
                    border.color: Theme.alpha(Theme.accent, 0.35)

                    Image {
                        id: thumb
                        visible: row.isImage
                        x: 8
                        anchors.verticalCenter: parent.verticalCenter
                        height: 62
                        width: Math.min(220, implicitWidth > 0 ? implicitWidth * height / Math.max(1, implicitHeight) : 110)
                        sourceSize.height: 124
                        fillMode: Image.PreserveAspectFit
                        horizontalAlignment: Image.AlignLeft
                        asynchronous: true
                        source: row.isImage ? "file://" + row.modelData.image : ""
                    }

                    Text {
                        anchors {
                            left: row.isImage ? thumb.right : parent.left
                            leftMargin: row.isImage ? 10 : 10
                            right: del.left; rightMargin: 6
                            verticalCenter: parent.verticalCenter
                        }
                        text: row.modelData.text.replace(/\s+/g, " ").trim()
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        color: row.isImage ? Theme.subtext0 : Theme.text
                        font.family: Theme.uiFont
                        font.pixelSize: 13
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

                    // remove, on hover
                    Text {
                        id: del
                        anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                        opacity: mouse.containsMouse || delMouse.containsMouse ? 1 : 0
                        text: "\u{f0156}"              // md-close
                        color: delMouse.containsMouse ? Theme.red : Theme.overlay1
                        font.family: Theme.font
                        font.pixelSize: 14
                        MouseArea {
                            id: delMouse
                            anchors.fill: parent
                            anchors.margins: -5
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: pop.remove(row.modelData)
                        }
                    }
                }
            }

            Text {
                visible: pop.shown.length === 0
                width: parent.width
                height: 60
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: lister.running && pop.entries.length === 0 ? "Loading…"
                    : pop.query ? "No matches" : "Clipboard history is empty"
                color: Theme.overlay0
                font.family: Theme.uiFont
                font.pixelSize: 13
            }

            // footer: hints · clear all
            Item {
                width: parent.width
                height: 28

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    x: 4
                    text: "↵ copy   ↑↓ move   Del remove   Esc close"
                    color: Theme.overlay0
                    font.family: Theme.uiFont
                    font.pixelSize: 11
                }

                Rectangle {
                    id: clear
                    property bool armed: false
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: clearText.implicitWidth + 20
                    height: 26
                    radius: 7
                    color: clearMouse.containsMouse || armed ? Theme.alpha(Theme.red, armed ? 0.9 : 0.18) : "transparent"
                    Text {
                        id: clearText
                        anchors.centerIn: parent
                        // two clicks: the first arms it
                        text: clear.armed ? "\u{f05e9}  Click again to clear all" : "\u{f05e9}  Clear all"
                        color: clear.armed ? Theme.crust : Theme.red
                        font.family: Theme.font
                        font.pixelSize: 12
                    }
                    MouseArea {
                        id: clearMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (!clear.armed) { clear.armed = true; disarm.restart(); return; }
                            clear.armed = false;
                            pop.entries = [];
                            Theme.exec("/usr/bin/python3 " + Theme.hypr + "/clip-list.py wipe");
                        }
                    }
                    Timer { id: disarm; interval: 3000; onTriggered: clear.armed = false }
                }
            }
        }
    }
}
