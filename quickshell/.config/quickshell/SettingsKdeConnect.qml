// Settings › KDE Connect: the phone (hypr/phone.py watch — event-driven, runs
// only while this page is open) and what you can do with it.
import QtQuick
import Quickshell
import Quickshell.Io

SettingsPage {
    id: page
    title: "KDE Connect"
    subtitle: "Your phone and this laptop: battery, notifications, files, find-my-phone."

    property var st: ({})
    readonly property bool up: !!st.available && !!st.reachable
    readonly property string script: Theme.hypr + "/phone.py"
    function run(args) { Theme.exec("/usr/bin/python3 " + script + " " + args); }

    Process {
        running: true
        command: ["/usr/bin/python3", page.script, "watch"]
        stdout: SplitParser {
            onRead: line => { try { page.st = JSON.parse(line); } catch (e) {} }
        }
    }

    // device hero
    Rectangle {
        width: parent.width
        height: 104
        radius: 16
        color: Theme.alpha(Theme.surface0, 0.45)
        border.width: 1
        border.color: page.up ? Theme.alpha(Theme.green, 0.5) : Theme.alpha(Theme.surface1, 0.5)
        Row {
            x: 20
            anchors.verticalCenter: parent.verticalCenter
            spacing: 16
            Rectangle {
                width: 62; height: 62; radius: 18
                color: page.up ? Theme.green : Theme.surface1
                Text {
                    anchors.centerIn: parent
                    text: "\u{f011c}"
                    color: page.up ? Theme.crust : Theme.overlay1
                    font.family: Theme.font
                    font.pixelSize: 32
                }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                Text {
                    text: page.st.name || (page.st.available === false ? "KDE Connect isn't running" : "No phone paired")
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 18
                    font.weight: Font.Bold
                }
                Text {
                    text: !page.st.paired ? "Pair from the phone's KDE Connect app"
                        : page.up ? "Connected" + (page.st.network ? "  ·  " + page.st.network : "")
                        : "Paired  ·  not reachable right now"
                    color: page.up ? Theme.green : Theme.overlay1
                    font.family: Theme.font
                    font.pixelSize: 12
                }
                Row {
                    visible: page.up && page.st.battery >= 0
                    spacing: 8
                    Rectangle {
                        width: 120; height: 8; radius: 4
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.alpha(Theme.surface1, 0.9)
                        Rectangle {
                            width: parent.width * Math.max(0, Math.min(1, (page.st.battery || 0) / 100))
                            height: parent.height
                            radius: 4
                            color: (page.st.battery || 0) <= 20 ? Theme.red : Theme.green
                        }
                    }
                    Text {
                        text: (page.st.battery ?? "?") + "%" + (page.st.charging ? "  \u{f0084} charging" : "")
                        color: Theme.subtext0
                        font.family: Theme.font
                        font.pixelSize: 11
                    }
                }
            }
        }
    }

    SettingsCard {
        title: "Actions"
        icon: "\u{f0952}"
        SettingsRow {
            icon: "\u{f11ab}"
            title: "Find my phone"
            subtitle: "Ring it, even on silent"
            keywords: "ring find lost"
            IconBtn { text: "Ring"; icon: "\u{f11ab}"; enabled: page.up; onClicked: page.run("ring") }
        }
        SettingsRow {
            icon: "\u{f0497}"
            title: "Ping"
            subtitle: "A notification on the phone, to check the link"
            keywords: "test"
            IconBtn { text: "Ping"; icon: "\u{f0497}"; enabled: page.up; onClicked: page.run("ping") }
        }
        SettingsRow {
            icon: "\u{f018f}"
            title: "Send clipboard"
            subtitle: "This computer's clipboard → the phone's"
            keywords: "copy paste share"
            IconBtn { text: "Send"; icon: "\u{f048a}"; enabled: page.up; onClicked: page.run("clip") }
        }
        SettingsRow {
            icon: "\u{f022a}"
            title: "Send files"
            subtitle: "Pick files in yazi and share them to the phone"
            keywords: "share transfer"
            IconBtn { text: "Pick files…"; icon: "\u{f022a}"; enabled: page.up; onClicked: { SettingsState.closeRequested(); page.run("send"); } }
        }
        SettingsRow {
            icon: "\u{f0770}"
            title: "Browse the phone"
            subtitle: "Mount it over SFTP and open it in yazi"
            keywords: "files storage sftp"
            IconBtn { text: "Browse"; icon: "\u{f0770}"; enabled: page.up; onClicked: { SettingsState.closeRequested(); page.run("browse"); } }
        }
        SettingsRow {
            icon: "\u{f009a}"
            title: "Phone notifications"
            subtitle: (page.st.notifs ? page.st.notifs.length : 0) + " on the phone right now"
            keywords: "alerts messages"
            last: true
            IconBtn { text: "Show"; icon: "\u{f03cc}"; onClicked: BarState.panelRequested("notifications", "phone") }
        }
    }

    SettingsCard {
        title: "Connection"
        icon: "\u{f0317}"
        SettingsRow {
            icon: "\u{f0450}"
            title: "Reconnect"
            subtitle: "Look for the phone again (it is reached over Tailscale too)"
            keywords: "refresh discover"
            IconBtn { text: "Refresh"; icon: "\u{f0450}"; onClicked: Theme.exec("kdeconnect-cli --refresh") }
        }
        SettingsRow {
            icon: "\u{f0493}"
            title: "KDE Connect settings"
            subtitle: "Plugins, pairing, permissions"
            keywords: "plugins pair unpair app"
            last: true
            IconBtn { text: "Open"; icon: "\u{f03cc}"; onClicked: { SettingsState.closeRequested(); Theme.exec("kdeconnect-app"); } }
        }
    }
}
