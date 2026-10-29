// The battery panel (Serpantinum-style) under the top bar's battery pill:
//
//   hero     liquid orb with the charge (green charging, peach low, red
//            critical) · state · time to full / empty · power draw
//   cards    health (full charge vs design), cycles, voltage, make
//   power    mode switch (power-profiles-daemon, the same as Settings ›
//            Power and the bottom bar's profile pill) — brightness has its own
//            panel now (the brightness pill, BrightnessPopup.qml)
//   footer   Power settings (Settings › Power)
//
// Live values from UPower (Quickshell.Services.UPower); health / cycles /
// voltage from sysfs once per open (sysinfo.py battery).
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

PanelPopup {
    id: pop

    panelWidth: 430
    pad: 16

    readonly property var dev: UPower.displayDevice
    readonly property bool present: dev !== null && dev.ready && dev.isPresent
    readonly property int pct: present ? Math.round(dev.percentage * 100) : 0
    readonly property int st: present ? dev.state : UPowerDeviceState.Unknown
    readonly property bool charging: st === UPowerDeviceState.Charging
    readonly property bool plugged: st === UPowerDeviceState.FullyCharged || st === UPowerDeviceState.PendingCharge
    tint: charging ? Theme.green : pct <= 12 ? Theme.red : pct <= 25 ? Theme.peach : Theme.lavender
    function hm(sec) {
        if (!sec || sec <= 0) return "";
        const h = Math.floor(sec / 3600), m = Math.round(sec % 3600 / 60);
        return h > 0 ? h + " h " + m + " min" : m + " min";
    }
    function stage(k) { return Math.max(0, Math.min(1, (pop.intro - k * 0.12) / (1 - k * 0.12))); }

    // sysfs details, once per open
    property var info: ({})
    Process {
        id: infoProc
        command: ["/usr/bin/python3", Theme.hypr + "/sysinfo.py", "battery"]
        stdout: StdioCollector { onStreamFinished: { try { pop.info = JSON.parse(text); } catch (e) {} } }
    }

    // power mode (same calls as Settings › Power)
    property string profile: ""
    readonly property var profiles: ["power-saver", "balanced", "performance"]
    Process {
        id: getProf
        command: ["busctl", "--system", "get-property", "org.freedesktop.UPower.PowerProfiles",
                  "/org/freedesktop/UPower/PowerProfiles", "org.freedesktop.UPower.PowerProfiles", "ActiveProfile"]
        stdout: StdioCollector { onStreamFinished: { const m = /"(.*)"/.exec(text); if (m) pop.profile = m[1]; } }
    }
    Process { id: setProf; onExited: getProf.running = true }
    onOpened: { infoProc.running = true; getProf.running = true; }

    component Stat: Rectangle {
        property string icon
        property string value
        property string label
        property color accent: Theme.subtext0
        height: 58
        radius: 12
        color: Theme.alpha(Theme.surface0, 0.55)
        Text {
            x: 12
            y: 10
            text: parent.icon + "  " + parent.value
            color: parent.accent
            font.family: Theme.font
            font.pixelSize: 14
            font.weight: Font.Bold
        }
        Text {
            x: 12
            y: 34
            width: parent.width - 24
            elide: Text.ElideRight
            text: parent.label
            color: Theme.overlay1
            font.family: Theme.font
            font.pixelSize: 10
        }
    }

    Column {
        width: parent.width
        spacing: 12

        // ── hero ────────────────────────────────────────────────────────────
        Row {
            width: parent.width
            spacing: 14
            opacity: pop.stage(0)
            transform: Translate { y: 12 * (1 - pop.stage(0)) }
            AudioOrb {
                id: orb
                implicitWidth: 104
                implicitHeight: 104
                running: pop.isOpen
                tint: pop.tint
                level: pop.pct / 100
                label: pop.pct + "%"
            }
            Column {
                width: parent.width - orb.width - parent.spacing
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                Text {
                    text: "Battery"
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 18
                    font.weight: Font.Bold
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: !pop.present ? "No battery"
                        : pop.charging ? (pop.hm(pop.dev.timeToFull) ? "Charging  ·  full in " + pop.hm(pop.dev.timeToFull) : "Charging")
                        : pop.plugged ? "Plugged in  ·  not charging"
                        : (pop.hm(pop.dev.timeToEmpty) ? pop.hm(pop.dev.timeToEmpty) + " left" : "On battery")
                    color: pop.tint
                    font.family: Theme.font
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
                Text {
                    text: pop.present && Math.abs(pop.dev.changeRate) > 0.05
                          ? (pop.charging ? "taking in " : "using ") + Math.abs(pop.dev.changeRate).toFixed(1) + " W" : ""
                    visible: text !== ""
                    color: Theme.overlay1
                    font.family: Theme.font
                    font.pixelSize: 11
                }
                Text {
                    text: pop.present && pop.dev.energy > 0 ? pop.dev.energy.toFixed(1) + " of " + pop.dev.energyCapacity.toFixed(1) + " Wh" : ""
                    visible: text !== ""
                    color: Theme.overlay1
                    font.family: Theme.font
                    font.pixelSize: 11
                }
            }
        }

        // ── health ──────────────────────────────────────────────────────────
        Grid {
            width: parent.width
            columns: 3
            spacing: 8
            opacity: pop.stage(1)
            transform: Translate { y: 12 * (1 - pop.stage(1)) }
            readonly property real cw: (width - 2 * spacing) / 3
            Stat {
                width: parent.cw
                icon: "\u{f120f}"
                value: pop.info.health ? pop.info.health + "%" : "—"
                label: pop.info.fullWh ? pop.info.fullWh + " / " + pop.info.designWh + " Wh" : "health"
                accent: (pop.info.health || 100) < 60 ? Theme.peach : Theme.green
            }
            Stat {
                width: parent.cw
                icon: "\u{f0456}"
                value: pop.info.cycles !== undefined ? String(pop.info.cycles) : "—"
                label: "charge cycles"
            }
            Stat {
                width: parent.cw
                icon: "\u{f140b}"
                value: pop.info.voltage ? pop.info.voltage + " V" : "—"
                label: pop.info.technology ? pop.info.technology + " now" : "voltage"
            }
        }

        // ── power mode ──────────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 8
            opacity: pop.stage(2)
            transform: Translate { y: 12 * (1 - pop.stage(2)) }
            Text {
                text: "POWER MODE"
                color: Theme.overlay1
                font.family: Theme.font
                font.pixelSize: 10
                font.weight: Font.Bold
                font.letterSpacing: 1.2
            }
            Segmented {
                width: parent.width
                height: 32
                options: ["\u{f032a}  Saver", "\u{f05d1}  Balanced", "\u{f14de}  Performance"]
                currentIndex: Math.max(0, pop.profiles.indexOf(pop.profile))
                accent: currentIndex === 2 ? Theme.peach : currentIndex === 0 ? Theme.green : Theme.blue
                onSelected: i => {
                    pop.profile = pop.profiles[i];
                    setProf.command = ["busctl", "--system", "set-property", "org.freedesktop.UPower.PowerProfiles",
                                       "/org/freedesktop/UPower/PowerProfiles", "org.freedesktop.UPower.PowerProfiles",
                                       "ActiveProfile", "s", pop.profiles[i]];
                    setProf.running = true;
                }
            }
        }

        IconBtn {
            opacity: pop.stage(2)
            icon: "\u{f0493}"
            text: "Power settings"
            onClicked: { pop.close(); BarState.panelRequested("settings", "power"); }
        }
    }
}
