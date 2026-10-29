// The audio panels (Serpantinum's volume popup), TWO instances in TopBar:
//   mode "sound" under the sound pill:     Outputs | Streams (apps playing)
//   mode "mic"   under the microphone pill: Inputs  | Recording (apps using it)
// An orb with the default device's level (click = mute, scroll = ±5 %), its
// name and a slider; then every device / stream as a card with its own
// mute + volume. Clicking a device card makes it the default.
//
// The header follows the tab: the default microphone on Inputs, the default
// output otherwise. Filter / virtual sinks (the EQ's filter-chain) are not
// listed. Unused HDMI / DisplayPort outputs only show while an external
// screen is connected (the laptop has three that are always there).
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

PanelPopup {
    id: pop
    tabBar: menuTabs                          // Ctrl+Tab / Ctrl+Shift+Tab cycle it

    panelWidth: 400

    property string mode: "sound"             // sound | mic
    readonly property var tabIds: mode === "mic" ? ["inputs", "recording"] : ["outputs", "apps"]
    property string tab: mode === "mic" ? "inputs" : "outputs"
    function openTab(name) { if (tabIds.includes(name)) tab = name; open(); }

    readonly property bool inputs: mode === "mic"
    readonly property var dev: inputs ? Theme.micSource(Pipewire.defaultAudioSource) : Pipewire.defaultAudioSink
    readonly property bool ok: !!dev && !!dev.audio
    readonly property real vol: ok ? dev.audio.volume : 0
    readonly property bool muted: ok && dev.audio.muted
    // the pill's colour: sound pink; mic flamingo (red while an app records)
    tint: !inputs ? Theme.pink
                                : pill && pill.live && !muted ? Theme.red : Theme.flamingo

    function setVol(v) {
        if (!ok) return;
        dev.audio.muted = false;
        dev.audio.volume = Math.max(0, Math.min(1, v));
    }
    function devTitle(n) {
        if (!n) return "No device";
        const d = n.nickname || n.description || n.name;
        const m = /Controller (.+)$/.exec(d);
        return m ? m[1] : d;
    }

    function hidden(n) {
        const p = n.properties || {};
        const name = n.name || "";
        // Bluetooth headphones are WirePlumber "virtual" loopback nodes in
        // 0.5 (bluez_output.<MAC>) — real devices for the user: keep them
        // (their *_internal halves stay hidden); and never hide the default
        if (/^bluez_(output|input)\./.test(name)) return false;
        if (n === Pipewire.defaultAudioSink || n === Pipewire.defaultAudioSource) return false;
        if (p["node.virtual"] === true || p["node.virtual"] === "true" || p["filter.smart"]) return true;
        if (/filter-chain/.test(p["node.group"] || "")) return true;
        if (/(^|[_.-])(effect|eq|equalizer)([_.-]|$)|rice-eq/i.test(name)) return true;
        return false;
    }
    readonly property var all: Pipewire.nodes.values
    readonly property var outputs: all.filter(n => n.audio && n.isSink && !n.isStream && !hidden(n)
        && (n === Pipewire.defaultAudioSink || Quickshell.screens.length > 1
            || !/hdmi|displayport/i.test((n.name || "") + (n.description || ""))))
    readonly property var inputList: all.filter(n => n.audio && !n.isSink && !n.isStream && !hidden(n))
    readonly property var streams: all.filter(n => n.audio && n.isSink && n.isStream && !hidden(n)
        && !/^(qs|quickshell|speech-dispatcher)/i.test((n.properties || {})["application.name"] || ""))
    // apps recording (a microphone or anything else) — not our own meters
    readonly property var recording: all.filter(n => n.audio && !n.isSink && n.isStream && !hidden(n)
        && !/^(qs|quickshell|speech-dispatcher|cava|pw-cat|parec)/i.test((n.properties || {})["application.name"] || "")
        && !/visualizer|monitor/i.test(n.name || ""))
    // the list shows `shownTab`, which follows `tab` through a quick
    // cross-fade (out 90 ms, swap, in 200 ms with a small rise) — swapping the
    // model straight away ran every card's add / remove animation and the
    // height change at once, which looked slow and jumpy
    property string shownTab: tab
    property bool swapping: false
    onTabChanged: {
        if (!isOpen || shownTab === tab) { shownTab = tab; return; }
        swapAnim.restart();
    }
    SequentialAnimation {
        id: swapAnim
        ScriptAction { script: pop.swapping = true }
        NumberAnimation { target: listBox; property: "fade"; to: 0; duration: 90; easing.type: Easing.InCubic }
        ScriptAction { script: pop.shownTab = pop.tab }
        NumberAnimation { target: listBox; property: "fade"; to: 1; duration: 200; easing.type: Easing.OutCubic }
        ScriptAction { script: pop.swapping = false }
    }
    readonly property var listed: ({ outputs: outputs, inputs: inputList, apps: streams, recording: recording })[shownTab] || []

    PwObjectTracker { objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource] }

    Column {
        width: parent.width
        spacing: 14

        // ── header: orb + default device ────────────────────────────────
        Item {
            width: parent.width
            height: orb.height + 4
            opacity: pop.intro
            transform: Translate { y: 14 * (1 - pop.intro) }

            AudioOrb {
                id: orb
                x: 2
                y: 2
                level: pop.vol
                muted: pop.muted
                tint: pop.tint
                running: pop.isOpen
                label: !pop.ok ? "—" : pop.muted ? "Mute" : Math.round(pop.vol * 100) + "%"
                onClicked: if (pop.ok) pop.dev.audio.muted = !pop.dev.audio.muted
                onScrolled: dir => pop.setVol(Math.round(pop.vol * 20 + dir) / 20)
            }

            Column {
                anchors { left: orb.right; leftMargin: 16; right: parent.right; verticalCenter: orb.verticalCenter }
                spacing: 4

                Text {
                    width: parent.width
                    text: pop.inputs ? "MICROPHONE" : "OUTPUT"
                    color: pop.tint
                    font.family: Theme.font
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    font.letterSpacing: 1.2
                }
                Text {
                    width: parent.width
                    text: pop.devTitle(pop.dev)
                    elide: Text.ElideRight
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 16
                    font.weight: Font.Bold
                }
                Text {
                    width: parent.width
                    text: pop.dev ? (pop.dev.description || pop.dev.name) : ""
                    elide: Text.ElideMiddle
                    color: Theme.overlay1
                    font.family: Theme.font
                    font.pixelSize: 11
                }
                Item { width: 1; height: 4 }
                Row {
                    width: parent.width
                    spacing: 8
                    IconBtn {
                        size: 30
                        iconSize: 15
                        anchors.verticalCenter: parent.verticalCenter
                        icon: pop.muted ? (pop.inputs ? "\u{f036d}" : "\u{f075f}")
                                        : (pop.inputs ? "\u{f036c}" : "\u{f057e}")
                        active: pop.muted
                        activeFg: Theme.red
                        tip: pop.muted ? "Unmute" : "Mute"
                        onClicked: if (pop.ok) pop.dev.audio.muted = !pop.dev.audio.muted
                    }
                    Slider {
                        width: parent.width - 30 - 40 - 16
                        anchors.verticalCenter: parent.verticalCenter
                        value: pop.vol
                        color: pop.muted ? Theme.overlay0 : pop.tint
                        onMoved: v => pop.setVol(v)
                    }
                    Text {
                        width: 40
                        anchors.verticalCenter: parent.verticalCenter
                        horizontalAlignment: Text.AlignRight
                        text: Math.round(pop.vol * 100) + "%"
                        color: Theme.subtext0
                        font.family: Theme.font
                        font.pixelSize: 12
                        font.weight: Font.Bold
                    }
                }
            }
        }

        Segmented {
            id: menuTabs
            width: parent.width
            options: pop.mode === "mic"
                ? ["Inputs", "Recording" + (pop.recording.length ? " " + pop.recording.length : "")]
                : ["Outputs", "Streams" + (pop.streams.length ? " " + pop.streams.length : "")]
            currentIndex: Math.max(0, pop.tabIds.indexOf(pop.tab))
            accent: pop.tint
            opacity: pop.intro
            transform: Translate { y: 18 * (1 - pop.intro) }
            onSelected: i => pop.tab = pop.tabIds[i]
        }

        // ── the cards ───────────────────────────────────────────────────
        Item {
            id: listBox
            property real fade: 1
            width: parent.width
            height: Math.max(list.count ? 0 : 90, Math.min(list.contentHeight, 78 * 4.5))
            Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            opacity: pop.intro * fade
            transform: Translate { y: 24 * (1 - pop.intro) + 8 * (1 - listBox.fade) }

            ListView {
                id: list
                anchors.fill: parent
                clip: true
                spacing: 8
                boundsBehavior: Flickable.StopAtBounds
                model: ScriptModel { values: pop.listed }

                // a device / stream coming or going animates; a tab swap doesn't
                add: Transition {
                    enabled: !pop.swapping
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 320; easing.type: Easing.OutQuint }
                    NumberAnimation { property: "scale"; from: 0.92; to: 1; duration: 360; easing.type: Easing.OutBack }
                }
                remove: Transition {
                    enabled: !pop.swapping
                    NumberAnimation { property: "opacity"; to: 0; duration: 180 }
                    NumberAnimation { property: "scale"; to: 0.92; duration: 180 }
                }
                displaced: Transition {
                    enabled: !pop.swapping
                    NumberAnimation { property: "y"; duration: 260; easing.type: Easing.OutCubic }
                }

                delegate: AudioCard {
                    required property var modelData
                    width: list.width
                    node: modelData
                    kind: pop.shownTab === "recording" ? "apps" : pop.shownTab
                    tint: pop.tint
                    isDefault: kind === "outputs" ? modelData === Pipewire.defaultAudioSink
                             : kind === "inputs" ? modelData === Pipewire.defaultAudioSource : false
                }
            }

            Column {
                visible: list.count === 0
                anchors.centerIn: parent
                spacing: 6
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: pop.shownTab === "apps" ? "\u{f075b}" : pop.shownTab === "recording" ? "\u{f036d}" : "\u{f0581}"
                    color: Theme.surface2
                    font.family: Theme.font
                    font.pixelSize: 28
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: pop.shownTab === "apps" ? "Nothing is playing" : pop.shownTab === "recording" ? "Nothing is recording" : "No devices"
                    color: Theme.overlay0
                    font.family: Theme.font
                    font.pixelSize: 12
                }
            }
        }

        // ── footer ──────────────────────────────────────────────────────
        Row {
            anchors.right: parent.right
            spacing: 8
            opacity: pop.intro
            IconBtn {
                size: 30
                iconSize: 14
                icon: "\u{f062e}"
                text: "Mixer"
                onClicked: { pop.close(); Theme.exec(pop.mode === "mic" ? "pavucontrol -t 4" : "pavucontrol"); }
            }
            IconBtn {
                size: 30
                iconSize: 14
                icon: "\u{f0493}"
                text: "Sound settings"
                onClicked: { pop.close(); BarState.panelRequested("settings", "sound"); }
            }
        }
    }
}
