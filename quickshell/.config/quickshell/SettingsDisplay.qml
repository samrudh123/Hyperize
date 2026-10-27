// Settings › Display: monitors (mode, scale, duplicate/extend), brightness,
// night light, and how the bars look.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

SettingsPage {
    id: page
    title: "Display"
    subtitle: "Screens, brightness, night light and the bars."

    property var monitors: []
    function refresh() { monProc.running = true; }
    Process {
        id: monProc
        running: true
        command: ["hyprctl", "monitors", "all", "-j"]
        stdout: StdioCollector {
            onStreamFinished: { try { page.monitors = JSON.parse(text); } catch (e) {} }
        }
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name.startsWith("monitor") || event.name === "configreloaded") again.restart();
        }
    }
    Timer { id: again; interval: 300; onTriggered: page.refresh() }

    // runtime rule; keeps the position and a mirror
    function applyMon(m, mode, scale) {
        const rule = m.name + "," + mode + "," + m.x + "x" + m.y + "," + scale
                   + (m.mirrorOf && m.mirrorOf !== "none" ? ",mirror," + m.mirrorOf : "");
        Theme.exec("hyprctl keyword monitor '" + rule + "'");
        again.restart();
    }
    function modes(m) {
        const seen = {}, out = [];
        for (const s of m.availableModes || []) {
            const r = /^(\d+)x(\d+)@([\d.]+)Hz$/.exec(s);
            if (!r) continue;
            const k = r[1] + "x" + r[2] + "@" + Math.round(Number(r[3]));
            if (seen[k]) continue;
            seen[k] = true;
            out.push({ key: k, mode: r[1] + "x" + r[2] + "@" + r[3], w: +r[1], h: +r[2], hz: Math.round(Number(r[3])) });
        }
        return out.slice(0, 12);
    }

    // ── monitors ─────────────────────────────────────────────────────────────
    Repeater {
        model: page.monitors
        delegate: SettingsCard {
            id: mc
            required property var modelData
            readonly property var m: modelData
            readonly property string cur: m.width + "x" + m.height + "@" + Math.round(m.refreshRate)
            title: m.name + (m.disabled ? "  (off)" : "")
            icon: /^(eDP|LVDS|DSI)/.test(m.name) ? "\u{f0322}" : "\u{f0379}"

            SettingsRow {
                icon: "\u{f0379}"
                title: mc.m.description || mc.m.name
                subtitle: mc.cur + " Hz  ·  scale " + mc.m.scale + "  ·  at " + mc.m.x + "," + mc.m.y
                          + (mc.m.mirrorOf && mc.m.mirrorOf !== "none" ? "  ·  mirroring " + mc.m.mirrorOf : "")
                keywords: "monitor screen"
            }
            SettingsRow {
                icon: "\u{f0a24}"
                title: "Resolution & refresh rate"
                subtitle: "Applies now; back to the preferred mode at the next login"
                keywords: "mode hz"
                height: 58 + (modeFlow.height > 30 ? modeFlow.height - 24 : 0)
                Flow {
                    id: modeFlow
                    width: Math.min(420, implicitWidthHint)
                    readonly property real implicitWidthHint: 420
                    spacing: 6
                    layoutDirection: Qt.RightToLeft
                    Repeater {
                        model: page.modes(mc.m)
                        delegate: IconBtn {
                            required property var modelData
                            size: 28
                            text: modelData.w + "×" + modelData.h + " " + modelData.hz + "Hz"
                            active: modelData.key === mc.cur
                            onClicked: if (!active) page.applyMon(mc.m, modelData.mode, mc.m.scale)
                        }
                    }
                }
            }
            SettingsRow {
                icon: "\u{f0a68}"
                title: "Scale"
                subtitle: "Bigger = everything larger"
                keywords: "zoom dpi size"
                last: true
                Segmented {
                    width: 280
                    height: 32
                    readonly property var vals: [1, 1.25, 1.5, 2]
                    options: ["100%", "125%", "150%", "200%"]
                    currentIndex: Math.max(0, vals.findIndex(v => Math.abs(v - mc.m.scale) < 0.01))
                    onSelected: i => page.applyMon(mc.m, mc.m.width + "x" + mc.m.height + "@" + mc.m.refreshRate.toFixed(2), vals[i])
                }
            }
        }
    }

    // only while a second screen is connected (nothing to choose otherwise;
    // the card hides with its rows)
    SettingsCard {
        title: "Multiple displays"
        icon: "\u{f0379}"
        SettingsRow {
            visible: Displays.count > 1 && matches
            icon: "\u{f037a}"
            title: "Duplicate or extend"
            subtitle: "SUPER+P switches too. Remembered per monitor."
            keywords: "mirror extend duplicate external projector"
            Segmented {
                width: 220
                height: 32
                options: ["Duplicate", "Extend"]
                currentIndex: Displays.mirror ? 0 : 1
                onSelected: i => Displays.set(i === 0 ? "mirror" : "extend", Displays.dir)
            }
        }
        SettingsRow {
            visible: Displays.count > 1 && !Displays.mirror && matches
            icon: "\u{f1483}"
            title: "External display position"
            subtitle: "Where the other screen sits, relative to the laptop"
            keywords: "left right above below arrangement"
            last: true
            Segmented {
                width: 300
                height: 32
                readonly property var dirs: ["left", "above", "below", "right"]
                options: ["Left", "Above", "Below", "Right"]
                currentIndex: Math.max(0, dirs.indexOf(Displays.dir))
                onSelected: i => Displays.set("extend", dirs[i])
            }
        }
    }

    // ── brightness / night light ─────────────────────────────────────────────
    FileView {
        id: nightFile
        path: Theme.hypr + "/night-light"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }
    readonly property var night: (nightFile.text() || "off 3500").trim().split(/\s+/)
    readonly property bool nightOn: night[0] === "on"
    readonly property int nightK: Number(night[1]) || 3500

    SettingsCard {
        title: "Brightness & colour"
        icon: "\u{f00df}"
        SettingsRow {
            icon: "\u{f00df}"
            iconColor: Theme.yellow
            title: "Brightness"
            subtitle: (bright.dragging ? Math.round(bright.dragValue * 100) : Stats.brightness) + "%"
            keywords: "backlight screen"
            Slider {
                id: bright
                width: 300
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.yellow
                value: Stats.brightness / 100
                onMoved: v => { brightTimer.target = Math.max(2, Math.round(v * 100)); brightTimer.restart(); }
                Timer {
                    id: brightTimer
                    property int target: 50
                    interval: 60
                    onTriggered: { Theme.exec(Theme.hypr + "/brightness.sh set " + target); Stats.refreshBacklight(); }
                }
            }
        }
        SettingsRow {
            icon: "\u{f0594}"
            iconColor: Theme.peach
            title: "Night light"
            subtitle: page.nightOn ? "On  ·  " + page.nightK + " K — warmer is lower" : "Off  ·  warms the screen to go easy on the eyes"
            keywords: "blue light warm filter temperature redshift"
            Toggle {
                anchors.verticalCenter: parent.verticalCenter
                accent: Theme.peach
                checked: page.nightOn
                onToggled: v => Theme.exec(Theme.hypr + "/night-light.sh " + (v ? "on" : "off"))
            }
        }
        SettingsRow {
            visible: page.nightOn && matches
            icon: "\u{f050f}"
            iconColor: Theme.peach
            title: "Night light temperature"
            subtitle: (kelvin.dragging ? Math.round((6500 - kelvin.dragValue * 5000) / 100) * 100 : page.nightK) + " K"
            keywords: "kelvin warmth"
            last: true
            Slider {
                id: kelvin
                width: 300
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.peach
                // left = cool (6500 K), right = warm (1500 K)
                value: (6500 - page.nightK) / 5000
                onMoved: v => { kTimer.k = Math.round((6500 - v * 5000) / 100) * 100; kTimer.restart(); }
                Timer {
                    id: kTimer
                    property int k: 3500
                    interval: 250
                    onTriggered: Theme.exec(Theme.hypr + "/night-light.sh set " + k)
                }
            }
        }
    }

    // ── bars ─────────────────────────────────────────────────────────────────
    FileView {
        id: barFile
        path: Theme.hypr + "/theme/bar-style"
        printErrors: false
    }

    SettingsCard {
        title: "Bars & dock"
        icon: "\u{f06fc}"
        SettingsRow {
            icon: "\u{f06fc}"
            title: "Bar style"
            subtitle: "Classic: edge-to-edge panels · Islands: floating rounded groups"
            keywords: "islands classic panel top bottom"
            Segmented {
                width: 220
                height: 32
                options: ["Classic", "Islands"]
                currentIndex: Theme.islands ? 1 : 0
                onSelected: i => barFile.setText((i === 1 ? "islands" : "classic") + "\n")
            }
        }
        SettingsRow {
            icon: "\u{f10a9}"
            title: "Bottom bar"
            subtitle: "Media, phone, focus timer, weather, tasks…"
            keywords: "bottom bar media"
            Toggle {
                anchors.verticalCenter: parent.verticalCenter
                checked: BarState.bottomShown
                onToggled: v => BarState.bottomShown = v
            }
        }
        SettingsRow {
            icon: "\u{f10aa}"
            title: "Dock"
            subtitle: "Show or hide the side dock (SUPER+A)"
            keywords: "dock launcher sidebar"
            last: true
            IconBtn {
                text: "Show / hide"
                icon: "\u{f10aa}"
                onClicked: Theme.exec(Theme.hypr + "/dock-toggle.sh")
            }
        }
    }
}
