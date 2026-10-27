// One device or app stream in the audio panel: icon, name, subtitle, and a
// mute button + volume slider. Clicking a device card makes it the default.
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

Rectangle {
    id: card

    // keyboard: Tab to the card, Enter makes it the default (as a click)
    activeFocusOnTab: kind !== "apps" && !isDefault
    function kbActivate() {
        if (kind === "apps" || isDefault) return;
        if (kind === "outputs") Pipewire.preferredDefaultAudioSink = node;
        else Pipewire.preferredDefaultAudioSource = node;
    }
    Keys.onPressed: ev => {
        if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter || ev.key === Qt.Key_Space) { kbActivate(); ev.accepted = true; }
    }

    required property var node
    property string kind: "outputs"           // outputs | inputs | apps
    property bool isDefault: false
    property color tint: Theme.pink

    readonly property var props: node ? node.properties || {} : {}
    readonly property bool ok: !!node && !!node.audio
    readonly property real vol: ok ? node.audio.volume : 0
    readonly property bool muted: ok && node.audio.muted
    readonly property string devName: node ? (node.name || "") : ""

    // "Meteor Lake-P HD Audio Controller Speaker" -> "Speaker"
    function shortName(n) {
        if (!n) return "";
        if (kind === "apps")
            return props["application.name"] || n.description || n.name;
        const d = n.nickname || n.description || n.name;
        const m = /Controller (.+)$/.exec(d);
        return m ? m[1] : d;
    }
    readonly property string title: shortName(node)
    readonly property string subtitle: {
        if (kind === "apps") return props["media.name"] || "";
        if (node && node.name === "bt-follow-hold") return "Phone is using them · laptop sound waits here, silent";
        if (isDefault) return "Active default";
        if (devName.startsWith("bluez")) return "Bluetooth";
        if (/hdmi|displayport/i.test(devName + (node ? node.description : ""))) return "HDMI / DisplayPort";
        if (/usb/i.test(devName)) return "USB";
        return kind === "inputs" ? "Built-in microphone" : "Built-in";
    }
    readonly property string glyph: {
        const n = devName + " " + (props["device.form-factor"] || "") + " " + (node ? node.description || "" : "");
        if (kind === "apps") return "\u{f075a}";                          // md-music_note
        if (kind === "inputs") return /bluez|headset/i.test(n) ? "\u{f02ce}" : "\u{f036c}";  // headset / microphone
        if (n.startsWith("bluez") || (node && node.name === "bt-follow-hold")) return "\u{f00b0}";   // bluetooth_audio
        if (/headphone|headset/i.test(n)) return "\u{f02cb}";             // headphones
        if (/hdmi|displayport/i.test(n)) return "\u{f0379}";              // monitor
        return "\u{f04c3}";                                                // speaker
    }
    readonly property string appIcon: {
        if (kind !== "apps") return "";
        const cand = [props["application.icon-name"], props["application.process.binary"],
                      (props["application.name"] || "").toLowerCase()];
        for (const c of cand) {
            if (!c) continue;
            const p = Quickshell.iconPath(c, true);
            if (p) return p;
        }
        return "";
    }

    function setVol(v) { if (ok) { node.audio.muted = false; node.audio.volume = v; } }

    PwObjectTracker { objects: [card.node] }

    implicitHeight: 70
    radius: 14
    color: hover.hovered && kind !== "apps" ? Theme.alpha(Theme.surface0, 0.95) : Theme.alpha(Theme.surface0, 0.55)
    border.width: 1
    border.color: isDefault ? Theme.alpha(tint, 0.6) : Theme.alpha(Theme.surface1, 0.5)
    Behavior on color { ColorAnimation { duration: Theme.fast } }
    Behavior on border.color { ColorAnimation { duration: Theme.normal } }

    HoverHandler { id: hover; cursorShape: card.kind !== "apps" && !card.isDefault ? Qt.PointingHandCursor : Qt.ArrowCursor }
    TapHandler {
        enabled: card.kind !== "apps" && !card.isDefault
        onTapped: {
            if (card.kind === "outputs") Pipewire.preferredDefaultAudioSink = card.node;
            else Pipewire.preferredDefaultAudioSource = card.node;
        }
    }

    // icon
    Rectangle {
        id: badge
        x: 11
        anchors.verticalCenter: parent.verticalCenter
        width: 40
        height: 40
        radius: 12
        color: card.isDefault ? card.tint : Theme.alpha(Theme.surface1, 0.8)
        Behavior on color { ColorAnimation { duration: Theme.normal } }
        Image {
            visible: card.appIcon !== ""
            anchors.centerIn: parent
            width: 24
            height: 24
            sourceSize: Qt.size(48, 48)
            source: card.appIcon
            asynchronous: true
        }
        Text {
            visible: card.appIcon === ""
            anchors.centerIn: parent
            text: card.glyph
            color: card.isDefault ? Theme.crust : card.muted ? Theme.overlay0 : Theme.subtext1
            font.family: Theme.font
            font.pixelSize: 19
        }
    }

    Column {
        anchors { left: badge.right; leftMargin: 11; right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
        spacing: 3

        Row {
            width: parent.width
            spacing: 6
            Text {
                width: parent.width - (card.subtitle ? Math.min(sub.implicitWidth, parent.width * 0.5) + 6 : 0)
                text: card.title
                elide: Text.ElideRight
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 13
                font.weight: Font.Bold
            }
        }
        Text {
            id: sub
            width: parent.width
            visible: text !== ""
            text: card.subtitle
            elide: Text.ElideRight
            color: card.isDefault ? card.tint : Theme.overlay1
            font.family: Theme.font
            font.pixelSize: 11
        }

        Row {
            width: parent.width
            spacing: 8
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: card.muted ? "\u{f075f}" : card.kind === "inputs" ? "\u{f036c}" : "\u{f057e}"
                color: card.muted ? Theme.red : muteMa.containsMouse ? Theme.text : Theme.overlay2
                font.family: Theme.font
                font.pixelSize: 14
                MouseArea {
                    id: muteMa
                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (card.ok) card.node.audio.muted = !card.node.audio.muted
                }
            }
            Slider {
                width: parent.width - 22 - pct.width - 16
                height: 16
                thickness: 4
                anchors.verticalCenter: parent.verticalCenter
                value: card.vol
                color: card.muted ? Theme.overlay0 : card.tint
                onMoved: v => card.setVol(v)
            }
            Text {
                id: pct
                width: 34
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                text: Math.round(card.vol * 100) + "%"
                color: card.muted ? Theme.overlay0 : Theme.subtext0
                font.family: Theme.font
                font.pixelSize: 11
                font.weight: Font.DemiBold
            }
        }
    }
    FocusRing {}
}
