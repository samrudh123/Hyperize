// The brightness panel (Serpantinum-style) under the top bar's brightness
// pill (left-click; right-click still toggles the night light, middle-click
// cycles its strength, scroll still steps 5 %):
//
//   hero     liquid orb with the level (yellow; peach with the night light)
//            · scroll it ±5 % · big slider · 10 / 25 / 50 / 75 / 100 picks
//   night    night light switch · 4500 / 3500 / 2700 K · fine Kelvin slider
//   footer   Display settings (Settings › Display)
//
// brightness.sh (logind) and night-light.sh, the same as the pill and
// Settings › Display; the night state is read from hypr/night-light.
import QtQuick
import Quickshell
import Quickshell.Io

PanelPopup {
    id: pop

    panelWidth: 400
    pad: 16

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
    readonly property color tint: nightOn ? Theme.peach : Theme.yellow
    // the Kelvin shown: the slider's while it moves / a change is on its way
    property int pendingK: -1
    Timer { id: kSettle; interval: 1200; onTriggered: pop.pendingK = -1 }
    readonly property int shownK: kelvin.dragging ? Math.round((6500 - kelvin.dragValue * 5000) / 100) * 100
                                : pendingK > 0 ? pendingK : nightK
    function nearestPreset(k) {
        const ps = [4500, 3500, 2700];
        let best = 0;
        for (let i = 1; i < ps.length; i++) if (Math.abs(ps[i] - k) < Math.abs(ps[best] - k)) best = i;
        return best;
    }
    Binding { target: kPresets; property: "currentIndex"; value: pop.nearestPreset(pop.shownK) }

    // optimistic while a change is on its way
    property int pending: -1
    readonly property int pct: pending >= 0 ? pending : Stats.brightness
    Timer { id: settle; interval: 900; onTriggered: pop.pending = -1 }
    function setLevel(p) {
        p = Math.max(2, Math.min(100, Math.round(p)));
        pending = p;
        settle.restart();
        sendTimer.target = p;
        sendTimer.restart();
    }
    Timer {
        id: sendTimer
        property int target: 50
        interval: 50
        onTriggered: { Theme.exec(Theme.hypr + "/brightness.sh set " + target); Stats.refreshBacklight(); }
    }
    function night_(args) { Theme.exec(Theme.hypr + "/night-light.sh " + args); }

    onOpened: Stats.refreshBacklight()

    function stage(k) { return Math.max(0, Math.min(1, (pop.intro - k * 0.14) / (1 - k * 0.14))); }

    Column {
        width: parent.width
        spacing: 14

        // ── hero ────────────────────────────────────────────────────────────
        Row {
            width: parent.width
            spacing: 16
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
                onScrolled: dir => pop.setLevel(pop.pct + 5 * dir)
                onClicked: pop.setLevel(pop.pct >= 50 ? 25 : 75)
            }
            Column {
                width: parent.width - orb.width - parent.spacing
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                Text {
                    text: "Brightness"
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 17
                    font.weight: Font.Bold
                }
                Text {
                    text: pop.nightOn ? "\u{f0594}  Night light on  ·  " + pop.nightK + " K" : "\u{f06e8}  Built-in screen"
                    color: pop.tint
                    font.family: Theme.font
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
                Text {
                    text: "Scroll the orb or the pill: ±5 %"
                    color: Theme.overlay1
                    font.family: Theme.font
                    font.pixelSize: 10
                }
            }
        }

        // ── level ───────────────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 10
            opacity: pop.stage(1)
            transform: Translate { y: 12 * (1 - pop.stage(1)) }
            Item {
                width: parent.width
                height: 26
                Text {
                    id: lo
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u{f00de}"                      // md-brightness_5
                    color: Theme.overlay1
                    font.family: Theme.font
                    font.pixelSize: 14
                }
                Slider {
                    id: slider
                    anchors.left: lo.right
                    anchors.leftMargin: 10
                    anchors.right: hi.left
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    thickness: 8
                    color: pop.tint
                    value: pop.pct / 100
                    onMoved: v => pop.setLevel(v * 100)
                }
                Text {
                    id: hi
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u{f00e0}"                      // md-brightness_7
                    color: pop.tint
                    font.family: Theme.font
                    font.pixelSize: 16
                }
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 6
                Repeater {
                    model: [10, 25, 50, 75, 100]
                    delegate: IconBtn {
                        required property int modelData
                        size: 28
                        text: modelData + "%"
                        active: Math.abs(pop.pct - modelData) <= 2
                        activeFg: pop.tint
                        onClicked: pop.setLevel(modelData)
                    }
                }
            }
        }

        // ── night light ─────────────────────────────────────────────────────
        Rectangle {
            width: parent.width
            height: nightCol.implicitHeight + 24
            radius: 14
            color: Theme.alpha(pop.nightOn ? Theme.peach : Theme.surface0, pop.nightOn ? 0.1 : 0.45)
            border.width: 1
            border.color: Theme.alpha(pop.nightOn ? Theme.peach : Theme.surface1, pop.nightOn ? 0.4 : 0.5)
            Behavior on color { ColorAnimation { duration: Theme.normal } }
            opacity: pop.stage(2)
            transform: Translate { y: 12 * (1 - pop.stage(2)) }

            Column {
                id: nightCol
                x: 14
                y: 12
                width: parent.width - 28
                spacing: 10
                Item {
                    width: parent.width
                    height: 30
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 10
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "\u{f0594}"
                            color: pop.nightOn ? Theme.peach : Theme.overlay1
                            font.family: Theme.font
                            font.pixelSize: 18
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            Text {
                                text: "Night light"
                                color: Theme.text
                                font.family: Theme.font
                                font.pixelSize: 13
                                font.weight: Font.Bold
                            }
                            Text {
                                text: pop.nightOn ? "Warmer is lower  ·  right-click the pill to toggle" : "Warms the screen to go easy on the eyes"
                                color: Theme.overlay1
                                font.family: Theme.font
                                font.pixelSize: 10
                            }
                        }
                    }
                    Toggle {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        accent: Theme.peach
                        checked: pop.nightOn
                        onToggled: v => pop.night_(v ? "on" : "off")
                    }
                }
                Segmented {
                    id: kPresets
                    width: parent.width
                    height: 30
                    options: ["4500 K", "3500 K", "2700 K"]
                    // the preset nearest to the slider, live while it moves
                    // (set by the Binding below: a click assigns currentIndex,
                    // which would break a plain binding); off: shown dim
                    opacity: pop.nightOn ? 1 : 0.55
                    accent: Theme.peach
                    onSelected: i => {
                        pop.pendingK = [4500, 3500, 2700][i];
                        kSettle.restart();
                        pop.night_("set " + pop.pendingK);
                    }
                }
                Item {
                    width: parent.width
                    height: 22
                    Slider {
                        id: kelvin
                        anchors.left: parent.left
                        anchors.right: kLabel.left
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        color: Theme.peach
                        // left = cool 6500 K, right = warm 1500 K; a mouse notch =
                        // 2 steps of 200 K (was one of 250), a touchpad twice as fast
                        value: (6500 - pop.shownK) / 5000
                        step: 0.04
                        wheelUnit: 60
                        onMoved: v => {
                            kTimer.k = Math.round((6500 - v * 5000) / 100) * 100;
                            pop.pendingK = kTimer.k;
                            kTimer.restart();
                            kSettle.restart();
                        }
                        Timer {
                            id: kTimer
                            property int k: 3500
                            interval: 120
                            onTriggered: pop.night_("set " + k)
                        }
                    }
                    Text {
                        id: kLabel
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 52
                        horizontalAlignment: Text.AlignRight
                        text: pop.shownK + " K"
                        color: Theme.subtext0
                        font.family: Theme.font
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }
                }
            }
        }

        IconBtn {
            opacity: pop.stage(2)
            icon: "\u{f0379}"
            text: "Display settings"
            onClicked: { pop.close(); BarState.panelRequested("settings", "display"); }
        }
    }
}
