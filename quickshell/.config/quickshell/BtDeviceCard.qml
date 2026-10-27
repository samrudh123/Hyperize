// One Bluetooth device in the network panel (NetworkPopup.qml).
//
//   connected       click: details + Disconnect / Forget
//   paired          click: connect        ⋯: Forget
//   discovered      click: pair (blueman's agent asks to confirm the code —
//                   mako's click menu), then trust + connect
//
// Forget asks twice, like the Wi-Fi cards.
import QtQuick
import Quickshell
import Quickshell.Bluetooth

Rectangle {
    id: card

    // keyboard: Tab to the card, Enter does what a click does (activate())
    activeFocusOnTab: true
    function kbActivate() { activate(); }
    Keys.onPressed: ev => {
        if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter || ev.key === Qt.Key_Space) { kbActivate(); ev.accepted = true; }
    }

    required property var dev
    required property var pop

    readonly property string key: dev ? dev.address : ""
    readonly property string name: dev ? (dev.name || dev.deviceName || dev.address) : ""
    readonly property bool connected: !!dev && dev.connected
    readonly property bool paired: !!dev && (dev.paired || dev.bonded)
    readonly property bool busy: !!dev && (dev.pairing || dev.state === BluetoothDeviceState.Connecting
                                           || dev.state === BluetoothDeviceState.Disconnecting)
    readonly property bool expanded: pop.expanded === "bt:" + key
    readonly property bool armed: pop.forgetArmed === "bt:" + key
    readonly property string error: pop.errors["bt:" + key] || ""

    readonly property string glyph: {
        const i = dev ? dev.icon || "" : "";
        if (/headset|headphone/.test(i)) return "\u{f02cb}";          // md-headphones
        if (/audio|speaker/.test(i)) return "\u{f04c3}";              // md-speaker
        if (/phone/.test(i)) return "\u{f011c}";                      // md-cellphone
        if (/keyboard/.test(i)) return "\u{f030c}";
        if (/mouse/.test(i)) return "\u{f037d}";
        if (/gaming|joystick/.test(i)) return "\u{f02b4}";
        if (/computer|laptop/.test(i)) return "\u{f0322}";
        if (/watch/.test(i)) return "\u{f0897}";
        return "\u{f00af}";
    }
    readonly property string battery: dev && dev.batteryAvailable ? Math.round(dev.battery * 100) + "%" : ""

    function activate() {
        pop.setError("bt:" + key, "");
        if (busy) return;
        if (connected) { pop.expanded = expanded ? "" : "bt:" + key; return; }
        if (paired) { pop.btConnect(dev); return; }
        pop.btPair(dev);
    }

    width: parent ? parent.width : 380
    height: col.height + 20
    radius: 14
    color: connected ? Theme.alpha(pop.tint, 0.13)
         : ma.containsMouse ? Theme.alpha(Theme.surface1, 0.7) : Theme.alpha(Theme.surface0, 0.55)
    border.width: connected ? 1 : 0
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
                    text: card.glyph
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
                        text: !card.dev ? ""
                            : card.dev.pairing ? "Pairing — confirm the code"
                            : card.dev.state === BluetoothDeviceState.Connecting ? "Connecting"
                            : card.dev.state === BluetoothDeviceState.Disconnecting ? "Disconnecting"
                            : card.connected ? "Connected" + (card.battery ? " · \u{f0079} " + card.battery : "")
                            : card.paired ? "Paired" + (card.dev.trusted ? "" : " · not trusted")
                            : "Click to pair"
                        color: card.busy ? pop.tint : Theme.overlay1
                        font.family: Theme.font
                        font.pixelSize: 11
                    }
                    NetDots {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: card.busy
                        color: pop.tint
                    }
                }
            }

            Row {
                id: tail
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 6
                IconBtn {
                    visible: card.paired && !card.connected
                    size: 26
                    iconSize: 13
                    icon: card.expanded ? "\u{f0143}" : "\u{f01d8}"
                    tip: "More"
                    onClicked: pop.expanded = card.expanded ? "" : "bt:" + card.key
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

        Column {
            visible: card.expanded
            width: parent.width
            spacing: 9

            Grid {
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
                Val { text: card.key }
                Key { visible: card.battery !== ""; text: "Battery" }
                Val { visible: card.battery !== ""; text: card.battery }
                Key { text: "Trusted" }
                Val { text: card.dev && card.dev.trusted ? "yes — reconnects by itself" : "no" }
            }

            Row {
                spacing: 8
                IconBtn {
                    visible: card.connected
                    icon: "\u{f00b2}"
                    text: "Disconnect"
                    onClicked: pop.btDisconnect(card.dev)
                }
                IconBtn {
                    visible: !card.connected
                    icon: "\u{f00b1}"
                    text: "Connect"
                    onClicked: pop.btConnect(card.dev)
                }
                IconBtn {
                    icon: "\u{f0a7a}"
                    text: card.armed ? "Forget? click again" : "Forget"
                    fg: Theme.red
                    active: card.armed
                    activeFg: Theme.red
                    onClicked: {
                        if (card.armed) pop.btForget(card.dev);
                        else pop.armForget("bt:" + card.key);
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
