// One Wi-Fi network in the network panel (NetworkPopup.qml).
//
//   connected   click: details (address, rates) + Disconnect / Forget
//   saved/open  click: connect           ⋯: Forget
//   secured     click: inline password   Enter: connect   Esc: cancel
//   802.1X      click: nm-connection-editor (a form, not a password box)
//
// Forget asks twice (the button turns red: "Forget?"). Shared UI state
// (which card is expanded / asking for a password, errors) lives in the
// panel so a rescan that rebuilds the list doesn't lose it.
import QtQuick
import Quickshell
import Quickshell.Networking

Rectangle {
    id: card

    // keyboard: Tab to the card, Enter does what a click does (activate())
    activeFocusOnTab: true
    function kbActivate() { activate(); }
    Keys.onPressed: ev => {
        if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter || ev.key === Qt.Key_Space) { kbActivate(); ev.accepted = true; }
    }

    required property var net
    required property var pop

    readonly property string name: net ? net.name : ""
    readonly property bool connected: !!net && net.connected
    readonly property bool known: !!net && net.known
    readonly property bool connecting: !!net && (net.state === ConnectionState.Connecting || (net.stateChanging && !connected))
    readonly property bool disconnecting: !!net && net.state === ConnectionState.Disconnecting
    readonly property int sec: net ? net.security : WifiSecurityType.Unknown
    readonly property bool open: sec === WifiSecurityType.Open || sec === WifiSecurityType.Owe
    readonly property bool enterprise: [WifiSecurityType.Wpa2Eap, WifiSecurityType.WpaEap, WifiSecurityType.Leap,
                                        WifiSecurityType.DynamicWep, WifiSecurityType.Wpa3SuiteB192].includes(sec)
    readonly property int signal: net ? Math.round(net.signalStrength * 100) : 0
    readonly property bool expanded: pop.expanded === name
    readonly property bool asking: pop.pwFor === name
    readonly property string error: pop.errors[name] || ""
    readonly property bool armed: pop.forgetArmed === name

    function glyph(s) {
        return ["\u{f092f}", "\u{f091f}", "\u{f0922}", "\u{f0925}", "\u{f0928}"][Math.min(4, Math.floor(s * 5 / 101))];
    }

    function activate() {
        pop.setError(name, "");
        if (connected) { pop.expanded = expanded ? "" : name; return; }
        if (connecting) return;
        if (known || open) { pop.connectNet(net, ""); return; }
        if (enterprise) {
            pop.launch("nm-connection-editor --create --type=802-11-wireless");
            return;
        }
        pop.pwFor = asking ? "" : name;
    }

    // a NoSecrets failure on a saved network = its key is wrong / gone
    Connections {
        target: card.net
        function onConnectionFailed(reason) {
            if (reason === ConnectionFailReason.NoSecrets && !card.enterprise) {
                pop.pwFor = card.name;
                pop.setError(card.name, card.known ? "The saved password was refused — enter it again" : "");
            } else {
                pop.setError(card.name, "Couldn't connect: " + ConnectionFailReason.toString(reason));
            }
        }
    }

    width: parent ? parent.width : 380
    height: col.height + 20
    radius: 14
    color: connected ? Theme.alpha(pop.tint, 0.13)
         : ma.containsMouse ? Theme.alpha(Theme.surface1, 0.7) : Theme.alpha(Theme.surface0, 0.55)
    border.width: connected || asking ? 1 : 0
    border.color: Theme.alpha(pop.tint, 0.55)
    Behavior on color { ColorAnimation { duration: Theme.fast } }
    Behavior on height { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
    clip: true

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: card.activate()
    }

    Column {
        id: col
        x: 12
        y: 10
        width: parent.width - 24
        spacing: 9

        // ── the row ─────────────────────────────────────────────────────────
        Item {
            width: parent.width
            height: 34

            Rectangle {
                id: badge
                width: 34
                height: 34
                radius: 10
                anchors.verticalCenter: parent.verticalCenter
                color: card.connected ? pop.tint : Theme.alpha(Theme.surface1, 0.8)
                Text {
                    anchors.centerIn: parent
                    text: card.glyph(card.signal)
                    color: card.connected ? Theme.crust : Theme.subtext1
                    font.family: Theme.font
                    font.pixelSize: 17
                }
            }

            Column {
                anchors { left: badge.right; leftMargin: 11; right: tail.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                spacing: 2
                Text {
                    width: parent.width
                    text: card.name
                    elide: Text.ElideRight
                    color: card.connected ? pop.tint : Theme.text
                    font.family: Theme.font
                    font.pixelSize: 13
                    font.weight: card.connected ? Font.Bold : Font.DemiBold
                }
                Row {
                    spacing: 6
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: card.connecting ? "Connecting" + (pop.stage ? " · " + pop.stage : "")
                            : card.disconnecting ? "Disconnecting"
                            : card.connected ? "Connected · " + card.signal + "%"
                            : card.known ? "Saved · " + card.signal + "%"
                            : (card.open ? "Open" : card.enterprise ? "Enterprise (802.1X)" : "Secured") + " · " + card.signal + "%"
                        color: card.connecting || card.disconnecting ? pop.tint : Theme.overlay1
                        font.family: Theme.font
                        font.pixelSize: 11
                    }
                    NetDots {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: card.connecting || card.disconnecting
                        color: pop.tint
                    }
                }
            }

            Row {
                id: tail
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 6
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !card.open
                    text: "\u{f033e}"                  // md-lock
                    color: Theme.overlay0
                    font.family: Theme.font
                    font.pixelSize: 13
                }
                // saved, not connected: a way to Forget without connecting
                IconBtn {
                    visible: card.known && !card.connected
                    size: 26
                    iconSize: 13
                    icon: card.expanded ? "\u{f0143}" : "\u{f01d8}"   // chevron-up / dots
                    tip: "More"
                    onClicked: pop.expanded = card.expanded ? "" : card.name
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: card.connected
                    text: card.expanded ? "\u{f0143}" : "\u{f0140}"
                    color: pop.tint
                    font.family: Theme.font
                    font.pixelSize: 15
                }
            }
        }

        // ── password ────────────────────────────────────────────────────────
        Rectangle {
            visible: card.asking
            width: parent.width
            height: 36
            radius: 10
            color: Theme.alpha(Theme.crust, 0.6)
            border.width: 1
            border.color: pw.activeFocus ? pop.tint : Theme.surface1

            onVisibleChanged: if (visible) { pw.text = ""; focusLater.restart(); }
            Timer { id: focusLater; interval: 60; onTriggered: pw.forceActiveFocus() }

            Text {
                id: key
                x: 11
                anchors.verticalCenter: parent.verticalCenter
                text: "\u{f0306}"                      // md-key
                color: Theme.overlay1
                font.family: Theme.font
                font.pixelSize: 14
            }
            TextInput {
                id: pw
                anchors { left: key.right; leftMargin: 9; right: eye.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
                echoMode: eye.reveal ? TextInput.Normal : TextInput.Password
                passwordCharacter: "•"
                color: Theme.text
                selectionColor: Theme.alpha(pop.tint, 0.4)
                font.family: Theme.font
                font.pixelSize: 13
                clip: true
                Text {
                    visible: !pw.text
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Password for " + card.name
                    color: Theme.overlay0
                    font: pw.font
                }
                Keys.onReturnPressed: go.clicked(Qt.LeftButton)
                Keys.onEnterPressed: go.clicked(Qt.LeftButton)
                Keys.onEscapePressed: pop.pwFor = ""
            }
            IconBtn {
                id: eye
                property bool reveal: false
                anchors { right: go.left; rightMargin: 4; verticalCenter: parent.verticalCenter }
                size: 28
                iconSize: 14
                icon: reveal ? "\u{f0209}" : "\u{f0208}"     // eye-off / eye
                tip: reveal ? "Hide" : "Show"
                onClicked: reveal = !reveal
            }
            IconBtn {
                id: go
                anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                size: 28
                iconSize: 14
                icon: "\u{f0054}"                      // arrow-right
                active: pw.text.length >= 8
                activeFg: pop.tint
                enabled: pw.text.length >= 8
                tip: "Connect"
                onClicked: {
                    if (pw.text.length < 8) return;
                    pop.connectNet(card.net, pw.text);
                    pop.pwFor = "";
                }
            }
        }

        // ── details ─────────────────────────────────────────────────────────
        Column {
            visible: card.expanded
            width: parent.width
            spacing: 9

            Grid {
                visible: card.connected
                columns: 2
                columnSpacing: 14
                rowSpacing: 4
                component Key: Text {
                    color: Theme.overlay1
                    font.family: Theme.font
                    font.pixelSize: 11
                }
                component Val: Text {
                    color: Theme.subtext1
                    font.family: Theme.font
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
                Key { text: "Address" }
                Val { text: Stats.ipaddr || "—" }
                Key { text: "Interface" }
                Val { text: Stats.ifname || "—" }
                Key { text: "Down / up" }
                Val { text: "\u{f01da} " + Stats.bits(Stats.rxBps) + "   \u{f0552} " + Stats.bits(Stats.txBps) }
                Key { text: "Security" }
                Val { text: WifiSecurityType.toString(card.sec) }
            }

            Row {
                spacing: 8
                IconBtn {
                    visible: card.connected
                    icon: "\u{f092d}"
                    text: "Disconnect"
                    onClicked: pop.disconnectNet(card.net)
                }
                IconBtn {
                    visible: !card.connected
                    icon: "\u{f0928}"
                    text: "Connect"
                    onClicked: pop.connectNet(card.net, "")
                }
                IconBtn {
                    icon: "\u{f0a7a}"                  // md-trash
                    text: card.armed ? "Forget? click again" : "Forget"
                    fg: Theme.red
                    active: card.armed
                    activeFg: Theme.red
                    onClicked: {
                        if (card.armed) pop.forgetNet(card.net);
                        else pop.armForget(card.name);
                    }
                }
            }
        }

        Text {
            visible: card.error !== ""
            width: parent.width
            text: "\u{f0026}  " + card.error
            wrapMode: Text.Wrap
            color: Theme.red
            font.family: Theme.font
            font.pixelSize: 11
        }
    }
    FocusRing {}
}
