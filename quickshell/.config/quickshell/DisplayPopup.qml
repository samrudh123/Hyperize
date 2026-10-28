// The displays panel (Serpantinum-style) under the top bar's display pill
// (shown only while an external monitor is connected) — what its menu did:
//
//   header   orb glyph (dup / ext) · "2 connected · extended, external right"
//   mode     Duplicate | Extend
//   side     where the external screen sits: ← left · → right · ↑ above · ↓ below
//   cards    every monitor: name, model, resolution @ refresh, scale, state
//   footer   Display settings (Settings › Display)
//
// hypr/display-mode.py through Displays.qml, exactly as the menu ran it.
// `qs ipc call display menu` (the pill's IPC) opens it; `qs ipc call display
// demo` shows it with a made-up external screen (changes do nothing then).
import QtQuick
import Quickshell

PanelPopup {
    id: pop

    panelWidth: 440
    pad: 16

    property bool demo: false
    readonly property var demoMons: Displays.mons.concat([
        { name: "HDMI-A-1", model: "DELL U2419H (demo)", res: "1920x1080", hz: 60, scale: 1.0, main: false, mirrored: false, disabled: false }])
    readonly property var mons: demo ? demoMons : Displays.mons
    readonly property bool mirror: Displays.mirror
    readonly property string dir: Displays.dir
    readonly property int count: demo ? Math.max(2, Displays.count + 1) : Displays.count
    readonly property color tint: Theme.lavender
    property string msg: ""

    function set(m, d) {
        if (demo) { msg = "demo — nothing changed"; return; }
        Displays.set(m, d);
    }
    onOpened: msg = ""
    onClosed2: demo = false

    function stage(k) { return Math.max(0, Math.min(1, (pop.intro - k * 0.12) / (1 - k * 0.12))); }

    Column {
        width: parent.width
        spacing: 12

        // ── header ──────────────────────────────────────────────────────────
        Row {
            width: parent.width
            spacing: 14
            opacity: pop.stage(0)
            transform: Translate { y: 12 * (1 - pop.stage(0)) }
            Rectangle {
                id: orb
                width: 72
                height: 72
                radius: 36
                color: Theme.alpha(pop.tint, pop.mirror ? 0.85 : 0.18)
                border.width: 2
                border.color: Theme.alpha(pop.tint, 0.6)
                Text {
                    anchors.centerIn: parent
                    text: pop.mirror ? "\u{f1483}" : "\u{f037a}"
                    color: pop.mirror ? Theme.crust : pop.tint
                    font.family: Theme.font
                    font.pixelSize: 30
                }
            }
            Column {
                width: parent.width - orb.width - parent.spacing
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                Text {
                    text: "Displays" + (pop.demo ? "  ·  demo" : "")
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 17
                    font.weight: Font.Bold
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: pop.count + " connected  ·  " + (pop.mirror ? "duplicated" : "extended, external " + pop.dir)
                    color: pop.tint
                    font.family: Theme.font
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
                Text {
                    visible: pop.msg !== ""
                    text: pop.msg
                    color: Theme.overlay1
                    font.family: Theme.font
                    font.pixelSize: 10
                }
            }
        }

        // ── mode + side ─────────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 8
            opacity: pop.stage(1)
            transform: Translate { y: 12 * (1 - pop.stage(1)) }
            Segmented {
                width: parent.width
                height: 32
                options: ["\u{f1483}  Duplicate", "\u{f037a}  Extend"]
                currentIndex: pop.mirror ? 0 : 1
                accent: pop.tint
                onSelected: i => pop.set(i === 0 ? "mirror" : "extend", i === 0 ? "" : pop.dir)
            }
            Text {
                text: "EXTERNAL SCREEN SITS"
                color: Theme.overlay1
                opacity: pop.mirror ? 0.5 : 1
                font.family: Theme.font
                font.pixelSize: 10
                font.weight: Font.Bold
                font.letterSpacing: 1.2
            }
            Row {
                spacing: 6
                Repeater {
                    model: [["left", "Left", "\u{f004d}"], ["right", "Right", "\u{f0054}"],
                            ["above", "Above", "\u{f005d}"], ["below", "Below", "\u{f0045}"]]
                    delegate: IconBtn {
                        required property var modelData
                        size: 30
                        iconSize: 13
                        icon: modelData[2]
                        text: modelData[1]
                        enabled: !pop.mirror
                        active: !pop.mirror && pop.dir === modelData[0]
                        activeFg: pop.tint
                        tip: "Extend, with the external screen " + modelData[1].toLowerCase()
                             + (modelData[0] === "left" || modelData[0] === "right" ? " of the laptop" : " the laptop")
                        onClicked: pop.set("extend", modelData[0])
                    }
                }
            }
        }

        // ── monitors ────────────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 7
            opacity: pop.stage(2)
            transform: Translate { y: 12 * (1 - pop.stage(2)) }
            Repeater {
                model: pop.mons
                delegate: Rectangle {
                    required property var modelData
                    readonly property var m: modelData
                    width: parent.width
                    height: 54
                    radius: 12
                    color: Theme.alpha(Theme.surface0, 0.55)
                    border.width: 1
                    border.color: Theme.alpha(pop.tint, m.main ? 0.35 : 0.15)
                    Rectangle {
                        id: ic
                        x: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: 34
                        height: 34
                        radius: 10
                        color: Theme.alpha(pop.tint, 0.16)
                        Text {
                            anchors.centerIn: parent
                            text: m.main ? "\u{f0322}" : "\u{f0379}"
                            color: pop.tint
                            font.family: Theme.font
                            font.pixelSize: 17
                        }
                    }
                    Column {
                        anchors.left: ic.right
                        anchors.leftMargin: 10
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: m.name + (m.main ? "  ·  this laptop" : "") + (m.model ? "  ·  " + m.model : "")
                            color: Theme.text
                            font.family: Theme.font
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                        Text {
                            width: parent.width
                            elide: Text.ElideRight
                            text: [m.res + (m.hz ? " @ " + m.hz + " Hz" : ""), m.scale ? "scale " + m.scale : "",
                                   m.mirrored ? "mirroring" : m.disabled ? "off" : ""].filter(s => s).join("  ·  ")
                            color: Theme.subtext0
                            font.family: Theme.font
                            font.pixelSize: 10
                        }
                    }
                }
            }
        }

        IconBtn {
            opacity: pop.stage(2)
            icon: "\u{f0493}"
            text: "Display settings"
            onClicked: { pop.close(); BarState.panelRequested("settings", "display"); }
        }
    }
}
