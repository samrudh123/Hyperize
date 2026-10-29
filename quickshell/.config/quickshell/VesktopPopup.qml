// The Discord panel (Serpantinum-style) under the top bar's Vesktop tray
// icon — left-click it (middle = show Vesktop, right = its own tray menu).
// In the Ctrl+← / → round like every pill's panel (Tray.qml makes it).
//
//   header   the tray icon (it carries Vesktop's unread badge) on a lavender
//            orb · where the window is (workspace N / hidden in the tray) ·
//            "in a call" while Vesktop records audio
//   actions  tiles: Open · Hide to tray (minimizeToTray) · Restart · Quit
//            (Quit asks for a second press, 3 s)
//   call     Vesktop's own PipeWire streams (AudioCard: mute + volume) —
//            muting its recording = Discord hears silence; its playback =
//            a deafen for this computer only
//   recent   the last Discord notifications, from the notification log
//            (hypr/notif-log.py's history.json); a click opens Vesktop
//   footer   the rest of the tray menu (About · Repair Vencord · Reset
//            Vesktop — Reset asks twice too)
//
// Restart / Quit / the footer are the tray menu's own entries (dbusmenu),
// so they do exactly what the right-click menu does.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray

PanelPopup {
    id: pop

    property var item: null                   // the SystemTrayItem
    edge: Edges.Bottom
    panelWidth: 420
    pad: 16
    navName: "vesktop"

    tint: Theme.lavender
    function stage(k) { return Math.max(0, Math.min(1, (pop.intro - k * 0.12) / (1 - k * 0.12))); }

    // ── the window ──────────────────────────────────────────────────────────
    readonly property var win: {
        for (const t of Hyprland.toplevels.values) {
            const c = (t.wayland && t.wayland.appId) || (t.lastIpcObject || {})["class"] || "";
            if (/vesktop|discord/i.test(c)) return t;
        }
        return null;
    }
    readonly property string wsName: win && win.workspace ? String(win.workspace.name) : ""

    FileView {
        id: settingsFile
        path: Theme.home + "/.config/vesktop/settings.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }
    readonly property bool toTray: {
        try { return JSON.parse(settingsFile.text() || "{}").minimizeToTray !== false; }
        catch (e) { return true; }
    }

    // ── the tray menu (Open, About, Repair Vencord, Reset, Restart, Quit) ───
    QsMenuOpener {
        id: opener
        menu: pop.isOpen && pop.item && pop.item.hasMenu ? pop.item.menu : null
    }
    readonly property var entries: opener.children ? opener.children.values.filter(e => !e.isSeparator && e.text) : []
    function label(e) { return e.text.replace(/_(?!_)/g, ""); }
    function entry(name) { return entries.find(e => label(e).toLowerCase() === name.toLowerCase()) || null; }
    readonly property var extras: entries.filter(e => !/^(open|restart|quit)$/i.test(label(e)))

    property string armed: ""
    Timer { id: disarm; interval: 3000; onTriggered: pop.armed = "" }
    onClosed2: armed = ""
    // a second press within 3 s for the ones that can't be taken back
    function confirm(id) {
        if (armed === id) { armed = ""; return true; }
        armed = id;
        disarm.restart();
        return false;
    }
    function trigger(name) {
        const e = entry(name);
        close();
        if (e) e.triggered();
    }
    function openApp() {
        close();
        if (win) Hyprland.dispatch("focuswindow address:0x" + win.address);
        else {
            const e = entry("Open");
            if (e) e.triggered(); else if (item) item.activate();
        }
    }
    function hideApp() {
        close();
        if (win) Hyprland.dispatch("closewindow address:0x" + win.address);
    }

    // ── its audio ───────────────────────────────────────────────────────────
    function isVesktop(n) {
        const p = n.properties || {};
        return /vesktop|discord/i.test((p["application.process.binary"] || "") + " " + (p["application.name"] || ""));
    }
    readonly property var streams: Pipewire.nodes.values.filter(n => n.audio && n.isStream && isVesktop(n))
    readonly property var playing: streams.filter(n => n.isSink)
    readonly property var recording: streams.filter(n => !n.isSink)
    readonly property bool inCall: recording.length > 0

    // ── its notifications ───────────────────────────────────────────────────
    property real now: Date.now() / 1000
    onOpened: now = Date.now() / 1000
    FileView {
        id: history
        path: pop.isOpen ? Theme.home + "/.local/state/notif-center/history.json" : ""
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }
    readonly property var notes: {
        let all = [];
        try { all = JSON.parse(history.text() || "{}").entries || []; } catch (e) { return []; }
        return all.filter(e => /vesktop|discord/i.test((e.app || "") + " " + (e.hints || "")))
                  .slice(-4).reverse();
    }
    function ago(t) {
        t = Number(t);
        if (!t) return "";
        const d = now - t;
        if (d < 60) return "now";
        if (d < 3600) return Math.floor(d / 60) + "m";
        const lt = new Date(t * 1000);
        if (lt.toDateString() === new Date(now * 1000).toDateString()) return Qt.formatTime(lt, "hh:mm");
        if (d < 7 * 86400) return Qt.formatDateTime(lt, "ddd hh:mm");
        return Qt.formatDate(lt, "dd MMM");
    }

    component Tile: Rectangle {
        id: tile
        property string glyph
        property string label
        property string hint
        property color tint: pop.tint
        property bool armed: false
        signal activated()
        readonly property bool lit: tma.containsMouse || activeFocus || BarState.kbItem === tile
        activeFocusOnTab: visible
        function kbActivate() { activated(); }
        Keys.onPressed: ev => {
            if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter || ev.key === Qt.Key_Space) { kbActivate(); ev.accepted = true; }
        }
        height: 84
        radius: 14
        color: armed ? tint : lit ? Theme.alpha(tint, 0.2) : Theme.alpha(Theme.surface1, 0.45)
        border.width: 1
        border.color: Theme.alpha(tint, armed ? 0 : lit ? 0.6 : 0.15)
        Behavior on color { ColorAnimation { duration: Theme.fast } }
        scale: tma.pressed ? 0.95 : 1
        Behavior on scale { NumberAnimation { duration: 110 } }

        // the countdown of an armed tile
        Rectangle {
            visible: tile.armed
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 7
            x: 12
            height: 3
            radius: 2
            color: Theme.alpha(Theme.crust, 0.5)
            width: tile.width - 24
            NumberAnimation on width {
                running: tile.armed
                from: tile.width - 24; to: 0; duration: 3000
            }
        }
        Column {
            anchors.centerIn: parent
            spacing: 4
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: tile.glyph
                color: tile.armed ? Theme.crust : tile.tint
                font.family: Theme.font
                font.pixelSize: 22
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: tile.armed ? "Again" : tile.label
                color: tile.armed ? Theme.crust : Theme.text
                font.family: Theme.font
                font.pixelSize: 11
                font.weight: Font.DemiBold
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: tile.hint
                color: tile.armed ? Theme.alpha(Theme.crust, 0.75) : Theme.overlay0
                font.family: Theme.font
                font.pixelSize: 9
            }
        }
        MouseArea {
            id: tma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: tile.activated()
        }
        FocusRing {}
    }

    Column {
        width: parent.width
        spacing: 14

        // ── header ──────────────────────────────────────────────────────────
        Item {
            width: parent.width
            height: 64
            opacity: pop.stage(0)
            transform: Translate { y: 12 * (1 - pop.stage(0)) }

            Rectangle {
                id: orb
                width: 64
                height: 64
                radius: 32
                color: Theme.alpha(pop.tint, 0.16)
                border.width: 2
                border.color: Theme.alpha(pop.inCall ? Theme.green : pop.tint, 0.55)
                // a slow breath while in a call
                SequentialAnimation on scale {
                    running: pop.isOpen && pop.inCall
                    loops: Animation.Infinite
                    onRunningChanged: if (!running) orb.scale = 1
                    NumberAnimation { to: 1.06; duration: 900; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1.0; duration: 900; easing.type: Easing.InOutSine }
                }
                IconImage {
                    anchors.centerIn: parent
                    implicitSize: 30
                    visible: !!pop.item && pop.item.icon !== ""
                    source: pop.item ? pop.item.icon : ""
                }
                Text {
                    anchors.centerIn: parent
                    visible: !pop.item || pop.item.icon === ""
                    text: "\u{f066f}"                  // md-discord
                    color: pop.tint
                    font.family: Theme.font
                    font.pixelSize: 28
                }
            }
            Column {
                anchors { left: orb.right; leftMargin: 14; right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 3
                Text {
                    text: "Discord"
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 17
                    font.weight: Font.Bold
                    Text {
                        anchors.left: parent.right
                        anchors.leftMargin: 8
                        anchors.baseline: parent.baseline
                        text: "Vesktop"
                        color: Theme.overlay1
                        font.family: Theme.font
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: pop.armed ? "press again to confirm · Esc cancels"
                        : pop.win ? "\u{f05b2}  open on " + (pop.wsName.startsWith("special") ? "a special workspace" : "workspace " + pop.wsName)
                        : "\u{f0209}  hidden in the tray"
                    color: pop.armed ? Theme.peach : pop.tint
                    font.family: Theme.font
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
                Row {
                    spacing: 6
                    topPadding: 2
                    Rectangle {
                        width: callChip.implicitWidth + 14
                        height: 20
                        radius: 6
                        color: Theme.alpha(pop.inCall ? Theme.green : pop.playing.length ? pop.tint : Theme.overlay0, 0.16)
                        Text {
                            id: callChip
                            anchors.centerIn: parent
                            text: pop.inCall ? "● In a call" : pop.playing.length ? "\u{f057e} Playing audio" : "○ Not in a call"
                            color: pop.inCall ? Theme.green : pop.playing.length ? pop.tint : Theme.overlay1
                            font.family: Theme.font
                            font.pixelSize: 10
                            font.weight: Font.Bold
                        }
                    }
                }
            }
        }

        // ── actions ─────────────────────────────────────────────────────────
        Row {
            id: tiles
            width: parent.width
            spacing: 8
            opacity: pop.stage(1)
            transform: Translate { y: 14 * (1 - pop.stage(1)) }
            readonly property int n: hideTile.visible ? 4 : 3
            readonly property real tileW: (width - (n - 1) * spacing) / n

            Tile {
                width: tiles.tileW
                glyph: "\u{f03cc}"                     // md-open_in_new
                label: pop.win ? "Focus" : "Open"
                hint: pop.win ? "go to it" : "show the window"
                onActivated: pop.openApp()
            }
            Tile {
                id: hideTile
                visible: !!pop.win && pop.toTray
                width: tiles.tileW
                glyph: "\u{f0209}"                     // md-eye_off
                label: "Hide"
                hint: "to the tray"
                onActivated: pop.hideApp()
            }
            Tile {
                width: tiles.tileW
                glyph: "\u{f0709}"                     // md-restart
                label: "Restart"
                hint: "reload Vesktop"
                tint: Theme.peach
                onActivated: pop.trigger("Restart")
            }
            Tile {
                width: tiles.tileW
                glyph: "\u{f015a}"                     // md-close_circle_outline
                label: "Quit"
                hint: "leave the tray"
                tint: Theme.red
                armed: pop.armed === "quit"
                onActivated: if (pop.confirm("quit")) pop.trigger("Quit")
            }
        }

        // ── its audio ───────────────────────────────────────────────────────
        Column {
            visible: pop.streams.length > 0
            width: parent.width
            spacing: 6
            opacity: pop.stage(2)
            transform: Translate { y: 14 * (1 - pop.stage(2)) }

            Text {
                text: (pop.inCall ? "CALL" : "AUDIO") + "  ·  mute here = Discord hears silence / you hear none"
                color: Theme.overlay1
                font.family: Theme.font
                font.pixelSize: 10
                font.weight: Font.Bold
                font.letterSpacing: 1.2
            }
            Repeater {
                model: pop.recording.concat(pop.playing)
                delegate: AudioCard {
                    required property var modelData
                    width: parent.width
                    node: modelData
                    kind: "apps"
                    tint: modelData.isSink ? pop.tint : Theme.green
                }
            }
        }

        // ── recent notifications ────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 6
            opacity: pop.stage(2)
            transform: Translate { y: 14 * (1 - pop.stage(2)) }

            Text {
                text: "RECENT  ·  " + (pop.notes.length ? "from the notification log" : "nothing from Discord yet")
                color: Theme.overlay1
                font.family: Theme.font
                font.pixelSize: 10
                font.weight: Font.Bold
                font.letterSpacing: 1.2
            }
            Repeater {
                model: pop.notes
                delegate: Rectangle {
                    id: nrow
                    required property var modelData
                    width: parent.width
                    height: ncol.implicitHeight + 16
                    radius: 11
                    activeFocusOnTab: true
                    function kbActivate() { pop.openApp(); }
                    Keys.onPressed: ev => {
                        if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter || ev.key === Qt.Key_Space) { kbActivate(); ev.accepted = true; }
                    }
                    color: nma.containsMouse || activeFocus || BarState.kbItem === nrow
                           ? Theme.alpha(Theme.surface1, 0.55) : Theme.alpha(Theme.surface0, 0.5)
                    Behavior on color { ColorAnimation { duration: Theme.fast } }
                    Rectangle {
                        id: nbadge
                        x: 9
                        y: 9
                        width: 26
                        height: 26
                        radius: 8
                        color: Theme.alpha(pop.tint, 0.16)
                        Text {
                            anchors.centerIn: parent
                            text: "\u{f066f}"
                            color: pop.tint
                            font.family: Theme.font
                            font.pixelSize: 13
                        }
                    }
                    Column {
                        id: ncol
                        anchors { left: nbadge.right; leftMargin: 10; right: parent.right; rightMargin: 10; top: parent.top; topMargin: 8 }
                        spacing: 1
                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: (nrow.modelData.summary || "Discord") + "  ·  " + pop.ago(nrow.modelData.time)
                            color: Theme.text
                            font.family: Theme.font
                            font.pixelSize: 11
                            font.weight: Font.Bold
                        }
                        Text {
                            visible: text !== ""
                            width: parent.width
                            elide: Text.ElideRight
                            text: (nrow.modelData.body || "").replace(/<[^>]*>/g, "").replace(/\n/g, " ")
                            color: Theme.overlay1
                            font.family: Theme.font
                            font.pixelSize: 10
                        }
                    }
                    MouseArea {
                        id: nma
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: nrow.kbActivate()
                    }
                    FocusRing {}
                }
            }
        }

        // ── footer: the rest of the tray menu ───────────────────────────────
        Flow {
            visible: pop.extras.length > 0
            width: parent.width
            spacing: 8
            opacity: pop.stage(3)
            Repeater {
                model: pop.extras
                delegate: IconBtn {
                    required property var modelData
                    readonly property string name: pop.label(modelData)
                    readonly property bool risky: /reset/i.test(name)
                    readonly property bool isArmed: pop.armed === "x:" + name
                    icon: /about/i.test(name) ? "\u{f02fd}"          // md-information_outline
                        : /repair/i.test(name) ? "\u{f05b7}"         // md-wrench
                        : risky ? "\u{f099b}" : "\u{f035c}"           // md-restore / md-menu
                    text: isArmed ? "Again to " + name.toLowerCase() : name
                    active: isArmed
                    activeFg: Theme.red
                    fg: risky ? Theme.red : Theme.subtext0
                    tipEdge: Edges.Top
                    onClicked: {
                        if (risky && !pop.confirm("x:" + name)) return;
                        pop.close();
                        modelData.triggered();
                    }
                }
            }
        }
    }
}
