// The power panel (Serpantinum-style) under the top bar's ⏻ pill — replaces
// nwg-bar. Five tiles in Settings › Power's colours (SettingsPower.qml):
// Lock accent · Suspend blue · Log out yellow · Restart peach · Power off red.
// Log out / Restart / Power off ask for a second click (3 s); Esc or a click
// outside cancels. Tab / Shift+Tab (or ← →) walk the tiles, Enter / Space
// press one. Same commands as nwg-bar (~/.config/nwg-bar/bar.json).
//
//   `qs ipc call power toggle|open|close`  (SUPER+SHIFT+X)
import QtQuick
import Quickshell
import Quickshell.Io

PanelPopup {
    id: pop

    edge: Edges.Bottom
    panelWidth: 560
    pad: 16

    readonly property var actions: [
        { id: "lock", name: "Lock", icon: "\u{f033e}", cmd: "hyprlock", c: false, col: "accent", hint: "hyprlock" },
        { id: "suspend", name: "Suspend", icon: "\u{f04b2}", cmd: "systemctl suspend", c: false, col: "blue", hint: "keep the session" },
        { id: "logout", name: "Log out", icon: "\u{f0343}", cmd: "hyprctl dispatch exit", c: true, col: "yellow", hint: "end Hyprland" },
        { id: "reboot", name: "Restart", icon: "\u{f0709}", cmd: "systemctl reboot", c: true, col: "peach", hint: "reboot" },
        { id: "off", name: "Power off", icon: "\u{f0425}", cmd: "systemctl poweroff", c: true, col: "red", hint: "shut down" }
    ]

    property string armed: ""
    Timer { id: disarm; interval: 3000; onTriggered: pop.armed = "" }
    function act(a) {
        if (a.c && armed !== a.id) { armed = a.id; disarm.restart(); return; }
        armed = "";
        close();
        Theme.exec(a.cmd);
    }
    onClosed2: armed = ""

    // who / where / how long
    property string user: Quickshell.env("USER") || ""
    property string host: ""
    property string uptime: ""
    Process {
        id: info
        command: ["sh", "-c", "cat /proc/sys/kernel/hostname; cut -d' ' -f1 /proc/uptime"]
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.trim().split("\n");
                pop.host = l[0] || "";
                const s = Math.floor(Number(l[1] || 0));
                const d = Math.floor(s / 86400), h = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60);
                pop.uptime = (d ? d + "d " : "") + (d || h ? h + "h " : "") + m + "m";
            }
        }
    }
    onOpened: info.running = true

    IpcHandler {
        target: "power"
        enabled: !!pop.anchor.window && !!pop.anchor.window.screen && pop.anchor.window.screen.name === BarState.active
        function toggle(): void { pop.toggle(); }
        function open(): void { pop.open(); }
        function close(): void { pop.close(); }
    }

    function stage(k) { return Math.max(0, Math.min(1, (pop.intro - k * 0.12) / (1 - k * 0.12))); }

    Column {
        width: parent.width
        spacing: 14

        // ── header ──────────────────────────────────────────────────────────
        Item {
            width: parent.width
            height: 46
            opacity: pop.stage(0)
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12
                Rectangle {
                    width: 46
                    height: 46
                    radius: 23
                    color: Theme.alpha(Theme.red, 0.18)
                    border.width: 2
                    border.color: Theme.alpha(Theme.red, 0.5)
                    Text {
                        anchors.centerIn: parent
                        text: pop.user ? pop.user[0].toUpperCase() : "\u{f0004}"
                        color: Theme.red
                        font.family: Theme.font
                        font.pixelSize: 20
                        font.weight: Font.Bold
                    }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Text {
                        width: pop.panelWidth - 2 * pop.pad - 58
                        elide: Text.ElideRight
                        text: pop.user + (pop.host ? "@" + pop.host : "")
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: 16
                        font.weight: Font.Bold
                    }
                    Text {
                        text: "\u{f0954}  up " + (pop.uptime || "…") + "   ·   "
                            + (pop.armed ? "click again to confirm, Esc cancels" : "Esc or a click outside cancels")
                        color: pop.armed ? Theme.peach : Theme.overlay1
                        font.family: Theme.font
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }
                }
            }
        }

        // ── the five ────────────────────────────────────────────────────────
        Row {
            id: tiles
            width: parent.width
            spacing: 10
            Repeater {
                model: pop.actions
                delegate: Rectangle {
                    id: tile
                    required property var modelData
                    required property int index
                    readonly property color col: Theme[modelData.col]
                    readonly property bool armed: pop.armed === modelData.id
                    readonly property real t: pop.stage(1 + index * 0.35)
                    // keyboard: Tab / Shift+Tab (or arrows) to it, Enter / Space
                    // press it — same two-step confirm as a click (PanelPopup.navKey)
                    readonly property bool lit: tma.containsMouse || activeFocus || BarState.kbItem === tile
                    activeFocusOnTab: visible
                    function kbActivate() { pop.act(modelData); }
                    Keys.onPressed: ev => {
                        if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter || ev.key === Qt.Key_Space) {
                            kbActivate();
                            ev.accepted = true;
                        }
                    }
                    width: (tiles.width - 4 * tiles.spacing) / 5
                    height: 104
                    radius: 16
                    color: armed ? col : lit ? Theme.alpha(col, 0.22) : Theme.alpha(Theme.surface1, 0.45)
                    border.width: 1
                    border.color: Theme.alpha(col, armed ? 0 : lit ? 0.6 : 0.2)
                    Behavior on color { ColorAnimation { duration: Theme.fast } }
                    scale: tma.pressed ? 0.95 : 1
                    Behavior on scale { NumberAnimation { duration: 120 } }
                    opacity: t
                    transform: Translate { y: 16 * (1 - tile.t) }

                    // the countdown of an armed tile
                    Rectangle {
                        visible: tile.armed
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 8
                        x: 14
                        height: 3
                        radius: 2
                        color: Theme.alpha(Theme.crust, 0.5)
                        width: tile.width - 28
                        NumberAnimation on width {
                            running: tile.armed
                            from: tile.width - 28; to: 0; duration: 3000
                        }
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 6
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 42
                            height: 42
                            radius: 21
                            color: tile.armed ? Theme.alpha(Theme.crust, 0.18) : Theme.alpha(tile.col, 0.16)
                            Text {
                                anchors.centerIn: parent
                                text: tile.modelData.icon
                                color: tile.armed ? Theme.crust : tile.col
                                font.family: Theme.font
                                font.pixelSize: 22
                            }
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: tile.armed ? "Click again" : tile.modelData.name
                            color: tile.armed ? Theme.crust : Theme.text
                            font.family: Theme.font
                            font.pixelSize: 12
                            font.weight: Font.Bold
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: tile.modelData.hint
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
                        onClicked: pop.act(tile.modelData)
                    }
                    FocusRing {}
                }
            }
        }
    }
}
