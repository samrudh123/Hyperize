// The phone panel (Serpantinum-style) above the bottom bar's phone pill —
// replaces its old menu. KDE Connect, via the pill's hypr/phone.py feed.
//
//   header   the battery as a liquid orb (AudioOrb: green while charging,
//            peach / red when low), the phone's name, reachability, signal
//   actions  tiles: Ring · Ping · Send clipboard · Send files · Browse files ·
//            Notifications (the notification centre's Phone tab)
//   list     the phone's notifications (click: the Phone tab, to reply /
//            dismiss)
//   footer   Settings › KDE Connect
//
// Every action is the pill's own `phone.py <cmd>` (`ph.run`). Opened by the
// pill's click, the notification-count pill's right-click, and
// `qs ipc call bottombar menu phone`.
import QtQuick
import Quickshell

PanelPopup {
    id: pop

    property var ph: null                     // the pill (st, up, batt, run())
    edge: Edges.Top
    panelWidth: 420

    readonly property var st: ph ? ph.st : ({})
    readonly property bool up: !!ph && ph.up
    readonly property int batt: ph ? ph.batt : -1
    readonly property var notifs: ph ? ph.notifs : []
    tint: !up ? Theme.overlay0 : st.charging ? Theme.green
                                : batt >= 0 && batt <= 15 ? Theme.red
                                : batt >= 0 && batt <= 30 ? Theme.peach : Theme.sky

    function act(cmd) { close(); ph.run(cmd); }
    function stage(k) { return Math.max(0, Math.min(1, (pop.intro - k * 0.13) / (1 - k * 0.13))); }

    Column {
        width: parent.width
        spacing: 14

        // ── header ──────────────────────────────────────────────────────────
        Item {
            width: parent.width
            height: 116
            opacity: pop.stage(0)
            transform: Translate { y: 12 * (1 - pop.stage(0)) }

            AudioOrb {
                id: orb
                x: 2
                y: 2
                level: pop.batt >= 0 ? pop.batt / 100 : 0
                muted: !pop.up || pop.batt < 0
                tint: pop.tint
                running: pop.isOpen && pop.up
                label: !pop.up ? "Off" : pop.batt < 0 ? "—" : pop.batt + "%"
            }

            Column {
                anchors { left: orb.right; leftMargin: 14; right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 4
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: pop.st.name || "Phone"
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 17
                    font.weight: Font.Bold
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: !pop.up ? "Not reachable — on another network, or KDE Connect asleep"
                        : pop.st.charging ? "\u{f140b} Charging · " + pop.batt + "%"
                        : pop.batt >= 0 ? "Connected · battery " + pop.batt + "%" : "Connected"
                    color: pop.up ? pop.tint : Theme.overlay1
                    wrapMode: pop.up ? Text.NoWrap : Text.Wrap
                    maximumLineCount: 2
                    font.family: Theme.font
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
                Text {
                    visible: pop.up && pop.st.signal >= 0
                    text: "\u{f08be} " + (pop.st.network || "Signal") + "  " + "▂▄▆█".slice(0, Math.max(1, pop.st.signal || 0))
                    color: Theme.overlay1
                    font.family: Theme.font
                    font.pixelSize: 11
                }
                Row {
                    spacing: 6
                    topPadding: 2
                    Rectangle {
                        width: kc.implicitWidth + 14
                        height: 20
                        radius: 6
                        color: Theme.alpha(pop.up ? Theme.green : Theme.overlay0, 0.16)
                        Text {
                            id: kc
                            anchors.centerIn: parent
                            text: (pop.up ? "● " : "○ ") + "KDE Connect"
                            color: pop.up ? Theme.green : Theme.overlay1
                            font.family: Theme.font
                            font.pixelSize: 10
                            font.weight: Font.Bold
                        }
                    }
                    Rectangle {
                        visible: pop.notifs.length > 0
                        width: nc.implicitWidth + 14
                        height: 20
                        radius: 6
                        color: Theme.alpha(pop.tint, 0.16)
                        Text {
                            id: nc
                            anchors.centerIn: parent
                            text: "\u{f009e} " + pop.notifs.length + " waiting"
                            color: pop.tint
                            font.family: Theme.font
                            font.pixelSize: 10
                            font.weight: Font.Bold
                        }
                    }
                }
            }
        }

        // ── action tiles ────────────────────────────────────────────────────
        Grid {
            id: tiles
            width: parent.width
            columns: 3
            spacing: 8
            opacity: pop.stage(1)
            transform: Translate { y: 14 * (1 - pop.stage(1)) }
            readonly property real tileW: (width - 2 * spacing) / 3

            Repeater {
                model: [
                    { icon: "\u{f11ab}", text: "Ring", tip: "Make it ring, even on silent (find my phone)", cmd: "ring" },
                    { icon: "\u{f1821}", text: "Ping", tip: "A ping notification on the phone", cmd: "ping" },
                    { icon: "\u{f0cf9}", text: "Clipboard", tip: "Send this computer's clipboard to the phone", cmd: "clip" },
                    { icon: "\u{f022a}", text: "Send files", tip: "Pick files (yazi) and share them to the phone", cmd: "send" },
                    { icon: "\u{f0770}", text: "Browse", tip: "The phone's storage in yazi (SFTP)", cmd: "browse" },
                    { icon: "\u{f009e}", text: "Notifications", tip: "The notification centre's Phone tab: reply, dismiss", cmd: "" }
                ]
                delegate: Rectangle {
                    id: tile
                    required property var modelData
                    readonly property bool isNotif: modelData.cmd === ""
                    readonly property bool ok: pop.up
                    readonly property bool lit: ok && (tma.containsMouse || activeFocus || BarState.kbItem === tile)
                    activeFocusOnTab: ok
                    function kbActivate() { if (!ok) return;
                        if (isNotif) { pop.close(); BarState.panelRequested("notifications", "phone"); }
                        else pop.act(modelData.cmd); }
                    Keys.onPressed: ev => {
                        if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter || ev.key === Qt.Key_Space) { kbActivate(); ev.accepted = true; }
                    }
                    width: tiles.tileW
                    height: 66
                    radius: 13
                    color: lit ? Theme.alpha(pop.tint, 0.2) : Theme.alpha(Theme.surface0, 0.55)
                    border.width: 1
                    border.color: lit ? Theme.alpha(pop.tint, 0.6) : Theme.alpha(Theme.surface1, 0.5)
                    opacity: ok ? 1 : 0.4
                    scale: tma.pressed && ok ? 0.96 : 1
                    Behavior on color { ColorAnimation { duration: Theme.fast } }
                    Behavior on scale { NumberAnimation { duration: 110 } }

                    Column {
                        anchors.centerIn: parent
                        spacing: 4
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: tile.modelData.icon
                            color: tile.lit ? pop.tint : Theme.subtext1
                            font.family: Theme.font
                            font.pixelSize: 20
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: tile.modelData.text + (tile.isNotif && pop.notifs.length ? " · " + pop.notifs.length : "")
                            color: Theme.subtext0
                            font.family: Theme.font
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                        }
                    }
                    MouseArea {
                        id: tma
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: tile.ok
                        cursorShape: Qt.PointingHandCursor
                        onClicked: tile.kbActivate()
                    }
                    Tooltip { target: tile; text: tile.modelData.tip; shown: tma.containsMouse; edge: Edges.Top }
                    FocusRing {}
                }
            }
        }

        // ── the phone's notifications ───────────────────────────────────────
        Column {
            visible: pop.up && pop.notifs.length > 0
            width: parent.width
            spacing: 6
            opacity: pop.stage(2)
            transform: Translate { y: 14 * (1 - pop.stage(2)) }

            Text {
                text: "ON THE PHONE  ·  " + pop.notifs.length
                color: Theme.overlay1
                font.family: Theme.font
                font.pixelSize: 10
                font.weight: Font.Bold
                font.letterSpacing: 1.2
            }
            Repeater {
                model: pop.notifs.slice(0, 4)
                delegate: Rectangle {
                    id: nrow
                    required property var modelData
                    width: parent.width
                    height: ncol.implicitHeight + 16
                    radius: 11
                    activeFocusOnTab: true
                    function kbActivate() { pop.close(); BarState.panelRequested("notifications", "phone"); }
                    Keys.onPressed: ev => {
                        if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter || ev.key === Qt.Key_Space) { kbActivate(); ev.accepted = true; }
                    }
                    color: nma.containsMouse || activeFocus || BarState.kbItem === nrow ? Theme.alpha(Theme.surface1, 0.55) : Theme.alpha(Theme.surface0, 0.5)
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
                            text: "\u{f036a}"            // md-message_text_outline
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
                            text: nrow.modelData.app + "  ·  " + nrow.modelData.title
                            color: Theme.text
                            font.family: Theme.font
                            font.pixelSize: 11
                            font.weight: Font.Bold
                        }
                        Text {
                            visible: text !== ""
                            width: parent.width
                            elide: Text.ElideRight
                            text: (nrow.modelData.text || "").replace(/\n/g, " ")
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
            Text {
                visible: pop.notifs.length > 4
                text: "… " + (pop.notifs.length - 4) + " more in the Phone tab"
                color: Theme.overlay0
                font.family: Theme.font
                font.pixelSize: 10
            }
        }

        // ── footer ──────────────────────────────────────────────────────────
        Row {
            spacing: 8
            opacity: pop.stage(3)
            IconBtn {
                icon: "\u{f0493}"                          // md-cog
                text: "KDE Connect settings"
                tipEdge: Edges.Top
                onClicked: { pop.close(); BarState.panelRequested("settings", "kdeconnect"); }
            }
        }
    }
}
