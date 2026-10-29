// The window panel (Serpantinum-style) under the top bar's window-state pill
// (the tiled / floating / maximised / fullscreen glyph left of the title):
// everything the pill's buttons do, for the focused window, in one place.
//
//   header   the state glyph · title · class · workspace
//   switches Floating · Pinned (pinning floats it first: Hyprland pins
//            floating windows only)
//   size     Normal | Maximised | Fullscreen
//   move     to workspace 1–9 (stays here: movetoworkspacesilent)
//   close    Close window (click twice)
//
// The same Hyprland dispatches as the pill (TopBar.qml `winState`).
import QtQuick
import Quickshell
import Quickshell.Hyprland

PanelPopup {
    id: pop

    panelWidth: 400
    pad: 16

    // the pill: TopBar's winState (win, ipc, floating, pinned, fs, addr)
    readonly property var w: pill
    readonly property bool valid: !!w && w.addr !== ""
    readonly property var ipc: valid ? w.ipc : ({})
    tint: !valid ? Theme.overlay1 : w.fs > 0 ? Theme.peach : w.pinned ? Theme.yellow
                                : w.floating ? Theme.accent : Theme.overlay1
    property bool closeArmed: false
    Timer { id: disarm; interval: 3000; onTriggered: pop.closeArmed = false }
    onOpened: closeArmed = false

    function d(cmd) { Hyprland.dispatch(cmd); }
    function setSize(i) {
        if (!valid) return;
        d("focuswindow " + w.addr);
        if (i === 0) { if (w.fs > 0) d("fullscreen " + (w.fs >= 2 ? 0 : 1)); }
        else if (i === 1) { if (w.fs !== 1) d("fullscreen 1"); }
        else { if (w.fs < 2) d("fullscreen 0"); }
    }

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
                width: 64
                height: 64
                radius: 20
                color: Theme.alpha(pop.tint, 0.18)
                border.width: 2
                border.color: Theme.alpha(pop.tint, 0.55)
                Text {
                    anchors.centerIn: parent
                    text: !pop.valid ? "\u{f05b2}" : pop.w.fs >= 2 ? "\u{f0293}" : pop.w.fs === 1 ? "\u{f05af}"
                        : pop.w.floating ? "\u{f10ac}" : "\u{f0574}"
                    color: pop.tint
                    font.family: Theme.font
                    font.pixelSize: 28
                }
            }
            Column {
                width: parent.width - orb.width - parent.spacing
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: pop.valid ? (pop.w.win.title || pop.ipc.class || "Window") : "No window"
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 15
                    font.weight: Font.Bold
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: !pop.valid ? "" : [pop.ipc.class || "", pop.ipc.workspace ? "workspace " + pop.ipc.workspace.name : "",
                        pop.w.fs >= 2 ? "fullscreen" : pop.w.fs === 1 ? "maximised" : pop.w.floating ? "floating" : "tiled",
                        pop.w.pinned ? "pinned" : ""].filter(s => s).join("  ·  ")
                    color: pop.tint
                    font.family: Theme.font
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
            }
        }

        // ── switches ────────────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 10
            enabled: pop.valid
            opacity: pop.stage(1) * (pop.valid ? 1 : 0.5)
            transform: Translate { y: 12 * (1 - pop.stage(1)) }
            Repeater {
                model: [["Floating", "\u{f10ac}", "float"], ["Pinned", "\u{f0403}", "pin"]]
                delegate: Item {
                    required property var modelData
                    width: parent.width
                    height: 30
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 10
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData[1]
                            color: Theme.subtext0
                            font.family: Theme.font
                            font.pixelSize: 15
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData[0]
                            color: Theme.text
                            font.family: Theme.font
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }
                    }
                    Toggle {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        accent: modelData[2] === "pin" ? Theme.yellow : Theme.accent
                        checked: pop.valid && (modelData[2] === "pin" ? pop.w.pinned : pop.w.floating)
                        onToggled: v => {
                            if (modelData[2] === "float") pop.d("togglefloating " + pop.w.addr);
                            else {
                                if (!pop.w.floating) pop.d("setfloating " + pop.w.addr);
                                pop.d("pin " + pop.w.addr);
                            }
                        }
                    }
                }
            }
            Segmented {
                width: parent.width
                height: 30
                options: ["\u{f0574}  Normal", "\u{f05af}  Maximised", "\u{f0293}  Fullscreen"]
                currentIndex: pop.valid ? Math.min(2, pop.w.fs) : 0
                accent: Theme.peach
                onSelected: i => pop.setSize(i)
            }
        }

        // ── move ────────────────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 6
            enabled: pop.valid
            opacity: pop.stage(2) * (pop.valid ? 1 : 0.5)
            transform: Translate { y: 12 * (1 - pop.stage(2)) }
            Text {
                text: "MOVE TO WORKSPACE"
                color: Theme.overlay1
                font.family: Theme.font
                font.pixelSize: 10
                font.weight: Font.Bold
                font.letterSpacing: 1.2
            }
            Row {
                spacing: 5
                Repeater {
                    model: 9
                    delegate: IconBtn {
                        required property int index
                        size: 34
                        text: String(index + 1)
                        active: pop.valid && pop.ipc.workspace && pop.ipc.workspace.id === index + 1
                        activeFg: pop.tint
                        tip: "Move it to workspace " + (index + 1) + " (you stay here)"
                        tipEdge: Edges.Bottom
                        onClicked: pop.d("movetoworkspacesilent " + (index + 1) + "," + pop.w.addr)
                    }
                }
            }
        }

        IconBtn {
            opacity: pop.stage(2)
            enabled: pop.valid
            icon: "\u{f0156}"
            text: pop.closeArmed ? "Click again to close it" : "Close window"
            fg: Theme.red
            active: pop.closeArmed
            activeFg: Theme.red
            onClicked: {
                if (!pop.closeArmed) { pop.closeArmed = true; disarm.restart(); return; }
                pop.closeArmed = false;
                pop.close();
                pop.d("closewindow " + pop.w.addr);
            }
        }
    }
}
