// Settings › Sound: output and input devices (PipeWire) — pick the
// default, set its volume, mute. The full mixer is the audio panel.
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

SettingsPage {
    id: page
    title: "Sound"
    subtitle: "Where sound goes and where it comes from."

    // real devices only (not app streams, not the EQ's virtual nodes)
    // (properties only arrive once a node is tracked: track every candidate)
    readonly property var candidates: Pipewire.nodes.values.filter(n => n.audio && !n.isStream)
    PwObjectTracker { objects: page.candidates }
    // HDMI / DisplayPort outputs exist even with nothing plugged in (silence
    // if picked): listed only while a second screen is connected, or in use
    function devices(sink) {
        return candidates.filter(n => n.isSink === sink
            && !/(monitor|filter|equalizer|rice-eq|eq_)/i.test(n.name || "")
            && (n.properties["media.class"] || "").startsWith(sink ? "Audio/Sink" : "Audio/Source")
            && !(sink && /hdmi|displayport/i.test((n.name || "") + " " + label(n))
                 && Displays.count <= 1 && n !== Pipewire.defaultAudioSink));
    }
    readonly property var sinks: devices(true)
    readonly property var sources: devices(false)

    function label(n) { return n.description || n.nickname || n.name; }
    function glyph(n, sink) {
        const s = (n.name + " " + label(n)).toLowerCase();
        if (s.includes("bluez")) return sink ? "\u{f02cb}" : "\u{f036c}";
        if (s.includes("hdmi") || s.includes("displayport")) return "\u{f0379}";
        if (s.includes("usb")) return "\u{f0553}";
        return sink ? "\u{f04c3}" : "\u{f036c}";
    }

    component DeviceCard: SettingsCard {
        id: dc
        required property bool sink
        readonly property var list: sink ? page.sinks : page.sources
        readonly property var def: sink ? Pipewire.defaultAudioSink : Theme.micSource(Pipewire.defaultAudioSource)
        readonly property bool ok: !!def && !!def.audio

        SettingsRow {
            icon: dc.ok && dc.def.audio.muted ? (dc.sink ? "\u{f075f}" : "\u{f036d}") : dc.sink ? "\u{f057e}" : "\u{f036c}"
            iconColor: dc.sink ? Theme.pink : Theme.green
            title: dc.sink ? "Output volume" : "Input volume"
            subtitle: dc.ok ? page.label(dc.def) + "  ·  " + (dc.def.audio.muted ? "muted" : Math.round(dc.def.audio.volume * 100) + "%") : "No device"
            keywords: dc.sink ? "speaker headphones loud" : "microphone mic"
            IconBtn {
                anchors.verticalCenter: parent.verticalCenter
                size: 30
                iconSize: 14
                icon: dc.ok && dc.def.audio.muted ? (dc.sink ? "\u{f075f}" : "\u{f036d}") : dc.sink ? "\u{f057e}" : "\u{f036c}"
                active: dc.ok && dc.def.audio.muted
                activeFg: Theme.red
                tip: dc.ok && dc.def.audio.muted ? "Unmute" : "Mute"
                onClicked: if (dc.ok) dc.def.audio.muted = !dc.def.audio.muted
            }
            Slider {
                width: 260
                anchors.verticalCenter: parent.verticalCenter
                color: dc.sink ? Theme.pink : Theme.green
                enabled: dc.ok
                value: dc.ok ? Math.min(1, dc.def.audio.volume) : 0
                onMoved: v => { if (dc.ok) dc.def.audio.volume = v; }
            }
        }

        Repeater {
            model: dc.list
            delegate: SettingsRow {
                id: dr
                required property var modelData
                required property int index
                readonly property bool isDef: dc.def === modelData
                icon: page.glyph(modelData, dc.sink)
                iconColor: isDef ? Theme.accent : Theme.overlay1
                title: page.label(modelData)
                subtitle: isDef ? "In use" : "Click to use this " + (dc.sink ? "output" : "input")
                keywords: dc.sink ? "output device" : "input device"
                hoverable: !isDef
                last: index === dc.list.length - 1
                onClicked: {
                    if (dc.sink) Pipewire.preferredDefaultAudioSink = modelData;
                    else Pipewire.preferredDefaultAudioSource = modelData;
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 20; height: 20; radius: 10
                    color: "transparent"
                    border.width: 2
                    border.color: dr.isDef ? Theme.accent : Theme.overlay0
                    Rectangle {
                        anchors.centerIn: parent
                        width: 10; height: 10; radius: 5
                        color: Theme.accent
                        visible: dr.isDef
                    }
                }
            }
        }
    }

    DeviceCard { sink: true; title: "Output"; icon: "\u{f04c3}" }
    DeviceCard { sink: false; title: "Input"; icon: "\u{f036c}" }

    SettingsCard {
        title: "More"
        icon: "\u{f062e}"
        SettingsRow {
            icon: "\u{f062e}"
            title: "Audio panel"
            subtitle: "Per-app volumes, streams, quick device switching"
            keywords: "mixer apps streams"
            IconBtn {
                text: "Open"
                icon: "\u{f03cc}"
                onClicked: BarState.panelRequested("audio", "")
            }
        }
        SettingsRow {
            icon: "\u{f04c3}"
            title: "PulseAudio Volume Control"
            subtitle: "Profiles, ports and everything else (pavucontrol)"
            keywords: "pavucontrol profile port advanced"
            last: true
            IconBtn {
                text: "Open"
                icon: "\u{f03cc}"
                onClicked: { SettingsState.closeRequested(); Theme.exec("pavucontrol"); }
            }
        }
    }
}
