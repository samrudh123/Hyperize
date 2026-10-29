// Settings › Power: battery (UPower), power profile (power-profiles-daemon,
// the same busctl calls as power-profile.sh), keep awake (BarState — the
// bottom bar's coffee pill), and lock / suspend / log out / restart / off.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

SettingsPage {
    id: page
    title: "Power"
    subtitle: "Battery, performance and the session."

    readonly property var bat: UPower.displayDevice
    readonly property bool hasBat: !!bat && bat.isLaptopBattery
    readonly property int pct: hasBat ? Math.round(bat.percentage * 100) : 0
    readonly property bool charging: hasBat && (bat.state === UPowerDeviceState.Charging || bat.state === UPowerDeviceState.FullyCharged)

    function dur(s) {
        if (!s || s <= 0) return "";
        const h = Math.floor(s / 3600), m = Math.round((s % 3600) / 60);
        return (h ? h + " h " : "") + m + " min";
    }

    property string profile: ""
    readonly property var profiles: ["power-saver", "balanced", "performance"]
    Process {
        id: getProf
        running: true
        command: ["busctl", "--system", "get-property", "org.freedesktop.UPower.PowerProfiles",
                  "/org/freedesktop/UPower/PowerProfiles", "org.freedesktop.UPower.PowerProfiles", "ActiveProfile"]
        stdout: StdioCollector {
            onStreamFinished: { const m = /"(.*)"/.exec(text); if (m) page.profile = m[1]; }
        }
    }
    Process {
        id: setProf
        onExited: getProf.running = true
    }

    // destructive actions ask for a second click
    property string armed: ""
    Timer { id: disarm; interval: 3000; onTriggered: page.armed = "" }
    function act(id, cmd, confirm) {
        if (confirm && armed !== id) { armed = id; disarm.restart(); return; }
        armed = "";
        SettingsState.closeRequested();
        Theme.exec(cmd);
    }

    SettingsCard {
        title: "Battery"
        icon: "\u{f0079}"
        SettingsRow {
            visible: page.hasBat && matches
            icon: page.charging ? "\u{f0084}" : "\u{f0079}"
            iconColor: page.pct <= 15 && !page.charging ? Theme.red : Theme.green
            title: page.pct + "%" + (page.charging ? "  ·  charging" : "")
            subtitle: page.charging ? (page.bat.timeToFull > 0 ? "Full in " + page.dur(page.bat.timeToFull) : "Plugged in")
                    : (page.bat.timeToEmpty > 0 ? page.dur(page.bat.timeToEmpty) + " left" : "On battery")
                      + (page.bat.changeRate > 0 ? "  ·  using " + page.bat.changeRate.toFixed(1) + " W" : "")
            keywords: "charge level"
            last: true
            Rectangle {
                width: 220; height: 10; radius: 5
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.alpha(Theme.surface1, 0.9)
                Rectangle {
                    width: parent.width * page.pct / 100
                    height: parent.height
                    radius: 5
                    color: page.pct <= 15 && !page.charging ? Theme.red : Theme.green
                    Behavior on width { NumberAnimation { duration: 400 } }
                }
            }
        }
    }

    SettingsCard {
        title: "Performance"
        icon: "\u{f04c5}"
        SettingsRow {
            icon: page.profile === "performance" ? "\u{f14de}" : page.profile === "power-saver" ? "\u{f032a}" : "\u{f05d1}"
            iconColor: page.profile === "performance" ? Theme.peach : page.profile === "power-saver" ? Theme.green : Theme.blue
            title: "Power mode"
            subtitle: page.profile === "performance" ? "Performance — fastest, hungriest"
                    : page.profile === "power-saver" ? "Power saver — quieter and longer battery"
                    : "Balanced"
            keywords: "profile saver performance balanced cpu fan"
            Segmented {
                width: 330
                height: 32
                options: ["Saver", "Balanced", "Performance"]
                currentIndex: Math.max(0, page.profiles.indexOf(page.profile))
                accent: currentIndex === 2 ? Theme.peach : currentIndex === 0 ? Theme.green : Theme.blue
                onSelected: i => {
                    page.profile = page.profiles[i];
                    setProf.command = ["busctl", "--system", "set-property", "org.freedesktop.UPower.PowerProfiles",
                                       "/org/freedesktop/UPower/PowerProfiles", "org.freedesktop.UPower.PowerProfiles",
                                       "ActiveProfile", "s", page.profiles[i]];
                    setProf.running = true;
                }
            }
        }
        SettingsRow {
            icon: "\u{f0176}"
            title: "Keep awake"
            subtitle: BarState.keepAwake ? "The screen won't dim, lock or sleep" : "The screen dims, locks and sleeps when idle"
            keywords: "caffeine idle inhibit sleep lock"
            last: true
            Toggle {
                anchors.verticalCenter: parent.verticalCenter
                checked: BarState.keepAwake
                onToggled: v => BarState.keepAwake = v
            }
        }
    }

    SettingsCard {
        title: "Session"
        icon: "\u{f0425}"
        Item {
            width: parent.width
            height: 96
            Row {
                anchors.centerIn: parent
                spacing: 12
                Repeater {
                    model: [
                        { id: "lock", name: "Lock", icon: "\u{f033e}", cmd: "hyprlock", c: false, col: "accent" },
                        { id: "suspend", name: "Suspend", icon: "\u{f04b2}", cmd: "systemctl suspend", c: false, col: "blue" },
                        { id: "logout", name: "Log out", icon: "\u{f0343}", cmd: "hyprctl dispatch exit", c: true, col: "yellow" },
                        { id: "reboot", name: "Restart", icon: "\u{f0709}", cmd: "systemctl reboot", c: true, col: "peach" },
                        { id: "off", name: "Power off", icon: "\u{f0425}", cmd: "systemctl poweroff", c: true, col: "red" }
                    ]
                    delegate: Rectangle {
                        id: sb
                        required property var modelData
                        readonly property color col: Theme[modelData.col]
                        readonly property bool armed: page.armed === modelData.id
                        width: 118
                        height: 76
                        radius: 14
                        color: armed ? col : sma.containsMouse ? Theme.alpha(col, 0.22) : Theme.alpha(Theme.surface1, 0.5)
                        Behavior on color { ColorAnimation { duration: Theme.fast } }
                        scale: sma.pressed ? 0.95 : 1
                        Behavior on scale { NumberAnimation { duration: 120 } }
                        Column {
                            anchors.centerIn: parent
                            spacing: 5
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: sb.modelData.icon
                                color: sb.armed ? Theme.crust : sb.col
                                font.family: Theme.font
                                font.pixelSize: 22
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: sb.armed ? "Click again" : sb.modelData.name
                                color: sb.armed ? Theme.crust : Theme.text
                                font.family: Theme.font
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }
                        }
                        MouseArea {
                            id: sma
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: page.act(sb.modelData.id, sb.modelData.cmd, sb.modelData.c)
                        }
                    }
                }
            }
        }
    }
}
