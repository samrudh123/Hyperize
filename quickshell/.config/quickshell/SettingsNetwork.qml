// Settings › Network: Wi-Fi on/off and the current connection
// (Quickshell.Networking), Bluetooth on/off and paired devices
// (Quickshell.Bluetooth). Scanning / joining lives in the network panel.
import QtQuick
import Quickshell
import Quickshell.Networking
import Quickshell.Bluetooth

SettingsPage {
    id: page
    title: "Network"
    subtitle: "Wi-Fi, wired and Bluetooth."

    SettingsCard {
        title: "Wi-Fi"
        icon: "\u{f05a9}"
        SettingsRow {
            icon: Networking.wifiEnabled ? "\u{f05a9}" : "\u{f05aa}"
            iconColor: Theme.blue
            title: "Wi-Fi"
            subtitle: !Networking.wifiHardwareEnabled ? "Turned off by the hardware switch (airplane mode)"
                    : Networking.wifiEnabled ? (Stats.essid ? "Connected to " + Stats.essid : "On  ·  not connected") : "Off"
            keywords: "wireless wlan"
            Toggle {
                anchors.verticalCenter: parent.verticalCenter
                accent: Theme.blue
                checked: Networking.wifiEnabled
                onToggled: v => Networking.wifiEnabled = v
            }
        }
        SettingsRow {
            visible: Stats.netKind !== "offline" && matches
            icon: Stats.netKind === "wired" ? "\u{f0200}" : "\u{f0928}"
            iconColor: Theme.blue
            title: Stats.netKind === "wired" ? "Wired  ·  " + Stats.ifname : Stats.essid || Stats.ifname
            subtitle: (Stats.ipaddr || "no address yet") + (Stats.netKind === "wifi" ? "  ·  signal " + Stats.signal + "%" : "")
                      + "  ·  \u{f01da} " + Stats.bits(Stats.rxBps) + "  \u{f0552} " + Stats.bits(Stats.txBps)
            keywords: "ip address connection speed"
        }
        SettingsRow {
            icon: "\u{f03cc}"
            title: "Networks"
            subtitle: "Scan, join, forget — the Wi-Fi panel (click the Wi-Fi pill)"
            keywords: "scan join password"
            last: true
            IconBtn {
                text: "Wi-Fi panel"
                icon: "\u{f03cc}"
                onClicked: BarState.panelRequested("network", "wifi")
            }
            IconBtn {
                text: "Connections…"
                icon: "\u{f0493}"
                tip: "nm-connection-editor: VPNs, static IPs, everything"
                onClicked: { SettingsState.closeRequested(); Theme.exec("nm-connection-editor"); }
            }
        }
    }

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool btOn: !!adapter && adapter.enabled
    readonly property var paired: (Bluetooth.devices ? Bluetooth.devices.values : [])
        .filter(d => d.paired || d.bonded || d.connected)
        .sort((a, b) => (b.connected - a.connected) || a.name.localeCompare(b.name))

    function btGlyph(d) {
        const i = d.icon || "";
        return i.includes("headset") || i.includes("headphone") ? "\u{f02cb}"
             : i.includes("phone") ? "\u{f011c}" : i.includes("audio") ? "\u{f04c3}"
             : i.includes("mouse") ? "\u{f037d}" : i.includes("keyboard") ? "\u{f030c}"
             : i.includes("computer") ? "\u{f0322}" : "\u{f00af}";
    }

    SettingsCard {
        title: "Bluetooth"
        icon: "\u{f00af}"
        SettingsRow {
            icon: page.btOn ? "\u{f00af}" : "\u{f00b2}"
            iconColor: Theme.sapphire
            title: "Bluetooth"
            subtitle: !page.adapter ? "No adapter" : page.btOn ? (page.paired.filter(d => d.connected).length + " connected  ·  " + page.paired.length + " paired") : "Off"
            keywords: "bt wireless headphones"
            Toggle {
                anchors.verticalCenter: parent.verticalCenter
                accent: Theme.sapphire
                checked: page.btOn
                onToggled: v => { if (page.adapter) page.adapter.enabled = v; }
            }
        }
        Repeater {
            model: page.btOn ? page.paired : []
            delegate: SettingsRow {
                id: br
                required property var modelData
                readonly property var d: modelData
                readonly property bool busy: d.state === BluetoothDeviceState.Connecting || d.state === BluetoothDeviceState.Disconnecting
                icon: page.btGlyph(d)
                iconColor: d.connected ? Theme.sapphire : Theme.overlay1
                title: d.name || d.address
                subtitle: (busy ? (d.state === BluetoothDeviceState.Connecting ? "Connecting…" : "Disconnecting…")
                          : d.connected ? "Connected" : "Paired")
                          + (d.batteryAvailable ? "  ·  battery " + Math.round(d.battery * 100) + "%" : "")
                keywords: "device paired"
                IconBtn {
                    anchors.verticalCenter: parent.verticalCenter
                    text: br.d.connected ? "Disconnect" : "Connect"
                    active: br.d.connected
                    activeFg: Theme.sapphire
                    enabled: !br.busy
                    onClicked: { if (br.d.connected) br.d.disconnect(); else br.d.connect(); }
                }
            }
        }
        SettingsRow {
            icon: "\u{f03cc}"
            title: "Pair a new device"
            subtitle: "Scanning and pairing: the Bluetooth panel (click the Bluetooth pill), or Blueman"
            keywords: "pair scan discover"
            last: true
            IconBtn {
                text: "Bluetooth panel"
                icon: "\u{f03cc}"
                onClicked: BarState.panelRequested("network", "bluetooth")
            }
            IconBtn {
                text: "Blueman"
                icon: "\u{f00af}"
                onClicked: { SettingsState.closeRequested(); Theme.exec("blueman-manager"); }
            }
        }
    }
}
