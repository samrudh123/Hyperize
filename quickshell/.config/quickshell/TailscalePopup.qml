// The Tailscale panel (Serpantinum-style) above the bottom bar's Tailscale
// pill — replaces its old menu. Data and actions are the pill's (`tsp`:
// `tailscale status --json`, up/down, set --exit-node).
//
//   header   the orb (NetOrb: ripples while connected; hold it 1 s to
//            disconnect), the tailnet, who is online, a connect switch
//   tabs     Machines | Exit node (the second only when a peer offers one)
//   machines this one, then every peer as a card: OS badge, online dot, IP,
//            direct / relay / last seen; SSH in · Send files (Taildrop) ·
//            Copy IP
//   exit     None, or any peer that offers itself
//
// Opened by the pill's click and `qs ipc call bottombar menu tailscale`.
import QtQuick
import Quickshell

PanelPopup {
    id: pop
    tabBar: menuTabs                          // Ctrl+Tab / Ctrl+Shift+Tab cycle it
    TabFade { id: tabFx; key: pop.tab; active: pop.isOpen }   // soft tab swap

    property var tsp: null                     // the pill
    edge: Edges.Top
    panelWidth: 440

    readonly property bool running: !!tsp && tsp.running
    readonly property string backend: tsp ? tsp.backend : ""
    readonly property var peers: tsp ? tsp.peers : []
    readonly property var self: tsp ? tsp.self : ({})
    readonly property bool hasExit: running && !!tsp && tsp.exitOptions.length > 0
    readonly property color tint: Theme.teal
    property int tab: 0                       // 0 machines, 1 exit node
    property string copied: ""                // an IP just copied (a moment's tick)
    Timer { id: uncopy; interval: 1600; onTriggered: pop.copied = "" }

    onOpened: if (!hasExit) tab = 0
    function act(cmd) { close(); Theme.exec(cmd); }
    function stage(k) { return Math.max(0, Math.min(1, (pop.intro - k * 0.13) / (1 - k * 0.13))); }

    Column {
        width: parent.width
        spacing: 14

        // ── header ──────────────────────────────────────────────────────────
        Item {
            width: parent.width
            height: 120
            opacity: pop.stage(0)
            transform: Translate { y: 12 * (1 - pop.stage(0)) }

            NetOrb {
                id: orb
                anchors.verticalCenter: parent.verticalCenter
                x: -4
                tint: pop.tint
                icon: "\u{f0582}"
                hoverIcon: "\u{f0319}"                 // md-lan_disconnect
                active: pop.running
                busy: pop.backend === "Starting"
                holdable: pop.running
                onHeld: pop.tsp.toggle()
            }

            Column {
                anchors { left: orb.right; leftMargin: 12; right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 3
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: pop.running ? (((pop.tsp.st.CurrentTailnet || {}).Name) || "Tailscale") : "Tailscale"
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 16
                    font.weight: Font.Bold
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: orb.hovered && orb.holdable ? "Hold the orb to disconnect"
                        : pop.running ? pop.tsp.online + " of " + pop.peers.length + " machines online"
                                        + (pop.tsp.exitNode ? " · via " + pop.tsp.shortName(pop.tsp.exitNode) : "")
                        : pop.backend === "NeedsLogin" ? "Needs login" : "Disconnected"
                    color: orb.hovered && orb.holdable ? Theme.red : pop.running ? pop.tint : Theme.overlay1
                    font.family: Theme.font
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
                Text {
                    visible: pop.running
                    width: parent.width
                    elide: Text.ElideRight
                    text: "\u{f0322} this machine  " + (pop.tsp ? pop.tsp.ip(pop.self) : "")
                    color: Theme.overlay1
                    font.family: Theme.font
                    font.pixelSize: 11
                }
                Item { width: 1; height: 5 }
                Row {
                    spacing: 8
                    Toggle {
                        anchors.verticalCenter: parent.verticalCenter
                        accent: pop.tint
                        checked: pop.running
                        onToggled: v => { if (v !== pop.running) pop.tsp.toggle(); }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: pop.backend === "NeedsLogin" ? "Log in…" : "Connected"
                        color: Theme.subtext0
                        font.family: Theme.font
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }
                }
            }
        }

        Segmented {
            id: menuTabs
            visible: pop.hasExit
            width: parent.width
            options: ["\u{f0322}  Machines", "\u{f01e7}  Exit node"]
            currentIndex: pop.tab
            accent: pop.tint
            onSelected: i => pop.tab = i
            opacity: pop.stage(1)
        }

        // ── machines ────────────────────────────────────────────────────────
        Item {
            id: listBox
            visible: pop.tab === 0 || !pop.hasExit
            width: parent.width
            height: pop.running ? listHead.height + 6 + flick.height : offText.height
            opacity: pop.stage(1) * tabFx.value
            transform: Translate { y: 14 * (1 - pop.stage(1)) + 8 * (1 - tabFx.value) }

            Text {
                id: offText
                visible: !pop.running
                width: parent.width
                height: 70
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: pop.backend === "NeedsLogin" ? "Log in to join your tailnet (the switch opens a terminal)"
                    : "Turn it on to see your machines"
                color: Theme.overlay0
                wrapMode: Text.Wrap
                font.family: Theme.font
                font.pixelSize: 12
            }

            Text {
                id: listHead
                visible: pop.running
                text: "MACHINES  ·  " + pop.peers.length
                color: Theme.overlay1
                font.family: Theme.font
                font.pixelSize: 10
                font.weight: Font.Bold
                font.letterSpacing: 1.2
            }

            Flickable {
                id: flick
                visible: pop.running
                y: listHead.height + 6
                width: parent.width
                height: Math.min(contentHeight, 340)
                contentHeight: cards.height
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height

                Column {
                    id: cards
                    width: flick.width
                    spacing: 7

                    Repeater {
                        model: pop.running ? pop.peers : []
                        delegate: Rectangle {
                            id: card
                            required property var modelData
                            readonly property var p: modelData
                            readonly property bool on: p.Online === true
                            readonly property bool phone: p.OS === "android" || p.OS === "iOS"
                            width: cards.width
                            height: 60
                            radius: 12
                            color: cma.containsMouse ? Theme.alpha(Theme.surface1, 0.5) : Theme.alpha(Theme.surface0, 0.5)
                            border.width: 1
                            border.color: Theme.alpha(card.on ? pop.tint : Theme.surface1, card.on ? 0.3 : 0.4)
                            Behavior on color { ColorAnimation { duration: Theme.fast } }
                            MouseArea { id: cma; anchors.fill: parent; hoverEnabled: true }

                            Rectangle {
                                id: badge
                                x: 10
                                anchors.verticalCenter: parent.verticalCenter
                                width: 38
                                height: 38
                                radius: 11
                                color: Theme.alpha(card.on ? pop.tint : Theme.overlay0, 0.16)
                                Text {
                                    anchors.centerIn: parent
                                    text: pop.tsp.osGlyph(card.p)
                                    color: card.on ? pop.tint : Theme.overlay1
                                    font.family: Theme.font
                                    font.pixelSize: 18
                                }
                                Rectangle {              // online dot
                                    anchors { right: parent.right; bottom: parent.bottom; margins: -2 }
                                    width: 11
                                    height: 11
                                    radius: 6
                                    color: card.on ? Theme.green : Theme.overlay0
                                    border.width: 2
                                    border.color: Theme.mantle
                                }
                            }
                            Column {
                                anchors { left: badge.right; leftMargin: 11; right: btns.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                spacing: 2
                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: pop.tsp.shortName(card.p) + (card.p.ExitNode ? "  \u{f01e7}" : "")
                                    color: card.on ? Theme.text : Theme.subtext0
                                    font.family: Theme.font
                                    font.pixelSize: 13
                                    font.weight: Font.Bold
                                }
                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: (pop.copied === pop.tsp.ip(card.p) ? "copied ✓" : pop.tsp.ip(card.p)) + "  ·  " + pop.tsp.seen(card.p)
                                    color: pop.copied === pop.tsp.ip(card.p) ? Theme.green : Theme.overlay1
                                    font.family: Theme.font
                                    font.pixelSize: 10
                                }
                            }
                            Row {
                                id: btns
                                anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                                spacing: 4
                                IconBtn {
                                    visible: !card.phone
                                    enabled: card.on
                                    size: 30
                                    iconSize: 14
                                    icon: "\u{f018d}"              // md-console
                                    tip: "SSH in"
                                    tipEdge: Edges.Top
                                    onClicked: pop.act("ghostty --gtk-single-instance=false --title=ssh-" + pop.tsp.shortName(card.p)
                                                       + " -e ssh " + pop.tsp.host(card.p))
                                }
                                IconBtn {
                                    enabled: card.on
                                    size: 30
                                    iconSize: 14
                                    icon: "\u{f022a}"              // md-file_send
                                    tip: "Send files… (Taildrop)"
                                    tipEdge: Edges.Top
                                    onClicked: pop.act(Theme.hypr + "/tailscale-send.sh " + pop.tsp.host(card.p))
                                }
                                IconBtn {
                                    size: 30
                                    iconSize: 14
                                    icon: pop.copied === pop.tsp.ip(card.p) ? "\u{f012c}" : "\u{f018f}"
                                    active: pop.copied === pop.tsp.ip(card.p)
                                    activeFg: Theme.green
                                    tip: "Copy IP  " + pop.tsp.ip(card.p)
                                    tipEdge: Edges.Top
                                    onClicked: {
                                        Quickshell.execDetached(["wl-copy", pop.tsp.ip(card.p)]);
                                        pop.copied = pop.tsp.ip(card.p);
                                        uncopy.restart();
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        visible: pop.running && pop.peers.length === 0
                        width: parent.width
                        height: 50
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: "No other machines on this tailnet yet"
                        color: Theme.overlay0
                        font.family: Theme.font
                        font.pixelSize: 12
                    }
                }
            }
        }

        // ── exit node ───────────────────────────────────────────────────────
        Column {
            visible: pop.hasExit && pop.tab === 1
            width: parent.width
            spacing: 6
            opacity: pop.stage(1) * tabFx.value

            Repeater {
                model: pop.hasExit ? [null].concat(pop.tsp.exitOptions) : []
                delegate: Rectangle {
                    id: ex
                    required property var modelData
                    readonly property bool none: modelData === null
                    readonly property bool cur: none ? !pop.tsp.exitNode : modelData.ExitNode === true
                    readonly property bool ok: none || modelData.Online === true
                    activeFocusOnTab: ok && visible
                    function kbActivate() { if (ok && !cur) pop.tsp.run("tailscale set --exit-node=" + (none ? "" : pop.tsp.ip(modelData))); }
                    Keys.onPressed: ev => {
                        if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter || ev.key === Qt.Key_Space) { kbActivate(); ev.accepted = true; }
                    }
                    width: parent.width
                    height: 44
                    radius: 11
                    color: cur ? Theme.alpha(pop.tint, 0.18) : ok && (exma.containsMouse || activeFocus || BarState.kbItem === ex) ? Theme.alpha(Theme.surface1, 0.55) : Theme.alpha(Theme.surface0, 0.5)
                    border.width: cur ? 1 : 0
                    border.color: Theme.alpha(pop.tint, 0.6)
                    opacity: ok ? 1 : 0.45
                    Text {
                        x: 14
                        anchors.verticalCenter: parent.verticalCenter
                        text: (ex.cur ? "\u{f0133}  " : "\u{f0130}  ")       // md-checkbox_blank_circle / outline
                            + (ex.none ? "None — straight out" : pop.tsp.shortName(ex.modelData) + (ex.ok ? "" : "  · offline"))
                        color: ex.cur ? pop.tint : Theme.subtext1
                        font.family: Theme.font
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }
                    MouseArea {
                        id: exma
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: ex.ok && !ex.cur
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ex.kbActivate()
                    }
                    FocusRing {}
                }
            }
        }

        // ── footer ──────────────────────────────────────────────────────────
        Row {
            spacing: 8
            opacity: pop.stage(2)
            IconBtn {
                icon: "\u{f0493}"
                text: "Tailscale settings"
                tipEdge: Edges.Top
                onClicked: { pop.close(); BarState.panelRequested("settings", "tailscale"); }
            }
        }
    }
}
