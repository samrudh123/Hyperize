// The weather panel (Serpantinum-style) above the bottom bar's weather pill —
// click it. Open-Meteo through weather.py (`weather.py json`, the same 15 min
// cache the pill uses):
//
//   hero     the sky's glyph in a glowing orb · temperature · what it is ·
//            the place · feels like
//   chips    humidity · wind · UV · sunrise · sunset (+ rain soon)
//   hours    the next 12, scrollable sideways: glyph, temperature, rain %
//   days     4 days: glyph, what, high / low bar, rain %
//   footer   Refresh · Change place (weather.py locate: fuzzel) · age
//
// `qs ipc call weather toggle|open|close`
import QtQuick
import Quickshell
import Quickshell.Io

PanelPopup {
    id: pop

    property var pillRef: null                // the ScriptPill, refreshed after a change
    edge: Edges.Top
    panelWidth: 480
    pad: 16

    property var w: null
    readonly property bool ok: !!w && w.ok
    readonly property color tint: !ok ? Theme.overlay1 : w.wet ? Theme.sapphire : w.day ? Theme.yellow : Theme.lavender

    function load() { if (!jsonProc.running) jsonProc.running = true; }
    Process {
        id: jsonProc
        command: [Theme.hypr + "/weather.py", "json"]
        stdout: StdioCollector {
            onStreamFinished: { try { pop.w = JSON.parse(text); } catch (e) { pop.w = { ok: false, why: "error" }; } }
        }
    }
    Process {
        id: refreshProc
        command: [Theme.hypr + "/weather.py", "refresh"]
        onExited: { pop.load(); if (pop.pillRef) pop.pillRef.refresh(); }
    }
    Process {
        id: placeProc
        command: [Theme.hypr + "/weather.py", "locate"]
        onExited: { pop.load(); if (pop.pillRef) pop.pillRef.refresh(); }
    }
    onOpened: load()
    IpcHandler {
        target: "weather"
        enabled: !!pop.anchor.window && !!pop.anchor.window.screen && pop.anchor.window.screen.name === BarState.active
        function toggle(): void { BarState.bottomShown = true; pop.toggle(); }
        function open(): void { BarState.bottomShown = true; pop.open(); }
        function close(): void { pop.close(); }
    }

    function stage(k) { return Math.max(0, Math.min(1, (pop.intro - k * 0.12) / (1 - k * 0.12))); }

    component Chip: Rectangle {
        property string glyph
        property string label
        property color tint: Theme.subtext0
        width: chipRow.implicitWidth + 18
        height: 28
        radius: 9
        color: Theme.alpha(Theme.surface0, 0.75)
        Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: 6
            Text { text: parent.parent.glyph; color: parent.parent.tint; font.family: Theme.font; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter }
            Text { text: parent.parent.label; color: Theme.subtext1; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
        }
    }

    Column {
        width: parent.width
        spacing: 14

        // ── hero ────────────────────────────────────────────────────────────
        Row {
            width: parent.width
            spacing: 16
            opacity: pop.stage(0)
            transform: Translate { y: 12 * (1 - pop.stage(0)) }
            Item {
                width: 104
                height: 104
                Rectangle {
                    anchors.centerIn: parent
                    width: 96
                    height: 96
                    radius: 48
                    color: Theme.alpha(pop.tint, 0.16)
                    border.width: 2
                    border.color: Theme.alpha(pop.tint, 0.4)
                    SequentialAnimation on scale {
                        running: pop.isOpen
                        loops: Animation.Infinite
                        NumberAnimation { to: 1.05; duration: 2200; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1.0; duration: 2200; easing.type: Easing.InOutSine }
                    }
                }
                Text {
                    anchors.centerIn: parent
                    text: pop.ok ? pop.w.glyph : "\u{f0590}"
                    color: pop.tint
                    font.family: Theme.font
                    font.pixelSize: 50
                }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Row {
                    spacing: 10
                    Text {
                        text: pop.ok ? pop.w.temp + "°" : "–"
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: 44
                        font.weight: Font.Bold
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            text: pop.ok ? pop.w.desc : pop.w && pop.w.why === "unset" ? "No place set" : "Weather unavailable"
                            color: pop.tint
                            font.family: Theme.font
                            font.pixelSize: 14
                            font.weight: Font.Bold
                        }
                        Text {
                            text: pop.ok ? "feels like " + pop.w.feels + "°" : pop.w && pop.w.why === "unset" ? "Change place below" : "offline?"
                            color: Theme.overlay1
                            font.family: Theme.font
                            font.pixelSize: 11
                        }
                    }
                }
                Text {
                    text: "\u{f034e}  " + (pop.ok ? pop.w.place : "—")
                    color: Theme.subtext0
                    font.family: Theme.font
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
            }
        }

        // ── chips ───────────────────────────────────────────────────────────
        Flow {
            visible: pop.ok
            width: parent.width
            spacing: 6
            opacity: pop.stage(1)
            Chip { glyph: "\u{f058e}"; label: pop.ok ? pop.w.humidity + "%" : ""; tint: Theme.sapphire }
            Chip { glyph: "\u{f059d}"; label: pop.ok ? pop.w.wind + " km/h" : ""; tint: Theme.teal }
            Chip { visible: pop.ok && pop.w.uv !== null; glyph: "\u{f0599}"; label: pop.ok ? "UV " + pop.w.uv : ""; tint: Theme.peach }
            Chip { glyph: "\u{f059c}"; label: pop.ok ? pop.w.sunrise : ""; tint: Theme.yellow }
            Chip { glyph: "\u{f059b}"; label: pop.ok ? pop.w.sunset : ""; tint: Theme.mauve }
        }
        Text {
            visible: pop.ok && pop.w.soon !== ""
            width: parent.width
            wrapMode: Text.Wrap
            text: "\u{f054a}  " + (pop.ok ? pop.w.soon : "")
            color: Theme.sapphire
            font.family: Theme.font
            font.pixelSize: 12
            font.weight: Font.DemiBold
        }

        // ── next hours ──────────────────────────────────────────────────────
        Column {
            visible: pop.ok
            width: parent.width
            spacing: 6
            opacity: pop.stage(2)
            transform: Translate { y: 12 * (1 - pop.stage(2)) }
            Text {
                text: "NEXT HOURS"
                color: Theme.overlay1
                font.family: Theme.font
                font.pixelSize: 10
                font.weight: Font.Bold
                font.letterSpacing: 1.2
            }
            Flickable {
                width: parent.width
                height: 84
                contentWidth: hoursRow.width
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.HorizontalFlick
                WheelHandler {
                    onWheel: ev => parent.contentX = Math.max(0, Math.min(parent.contentWidth - parent.width,
                                                       parent.contentX - (ev.angleDelta.y || ev.angleDelta.x) / 2))
                }
                Row {
                    id: hoursRow
                    spacing: 6
                    Repeater {
                        model: pop.ok ? pop.w.hours : []
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            width: 56
                            height: 84
                            radius: 12
                            color: index === 0 ? Theme.alpha(pop.tint, 0.16) : Theme.alpha(Theme.surface0, 0.55)
                            Column {
                                anchors.centerIn: parent
                                spacing: 3
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.time; color: Theme.overlay1; font.family: Theme.font; font.pixelSize: 10; font.weight: Font.DemiBold }
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.glyph; color: Theme.subtext1; font.family: Theme.font; font.pixelSize: 20 }
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.temp !== null ? modelData.temp + "°" : "–"; color: Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Bold }
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.rain ? modelData.rain + "%" : " "; color: Theme.sapphire; font.family: Theme.font; font.pixelSize: 9 }
                            }
                        }
                    }
                }
            }
        }

        // ── days ────────────────────────────────────────────────────────────
        Column {
            visible: pop.ok
            width: parent.width
            spacing: 5
            opacity: pop.stage(3)
            transform: Translate { y: 12 * (1 - pop.stage(3)) }
            readonly property int lo: pop.ok ? Math.min.apply(null, pop.w.days.map(d => d.min)) : 0
            readonly property int hi: pop.ok ? Math.max.apply(null, pop.w.days.map(d => d.max)) : 1
            Repeater {
                model: pop.ok ? pop.w.days : []
                delegate: Rectangle {
                    id: drow
                    required property var modelData
                    width: parent.width
                    height: 38
                    radius: 10
                    color: Theme.alpha(Theme.surface0, 0.45)
                    readonly property real span: Math.max(1, parent.hi - parent.lo)
                    Text { id: dn; x: 12; width: 52; anchors.verticalCenter: parent.verticalCenter; text: drow.modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Bold }
                    Text { id: dg; anchors.left: dn.right; anchors.verticalCenter: parent.verticalCenter; text: drow.modelData.glyph; color: Theme.subtext1; font.family: Theme.font; font.pixelSize: 17 }
                    Text {
                        id: dd
                        anchors.left: dg.right; anchors.leftMargin: 10
                        width: 120
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: drow.modelData.desc + (drow.modelData.rain ? "  ·  " + drow.modelData.rain + "%" : "")
                        color: drow.modelData.rain >= 50 ? Theme.sapphire : Theme.overlay1
                        font.family: Theme.font
                        font.pixelSize: 11
                    }
                    Text { id: dmin; anchors.left: dd.right; anchors.leftMargin: 6; anchors.verticalCenter: parent.verticalCenter; text: drow.modelData.min + "°"; color: Theme.overlay1; font.family: Theme.font; font.pixelSize: 11 }
                    // the day's range on the week's scale
                    Rectangle {
                        id: track
                        anchors.left: dmin.right; anchors.leftMargin: 8
                        anchors.right: dmax.left; anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        height: 5
                        radius: 3
                        color: Theme.alpha(Theme.surface1, 0.8)
                        Rectangle {
                            x: track.width * (drow.modelData.min - drow.parent.lo) / drow.span
                            width: Math.max(6, track.width * (drow.modelData.max - drow.modelData.min) / drow.span)
                            height: parent.height
                            radius: 3
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0; color: Theme.sapphire }
                                GradientStop { position: 1; color: Theme.peach }
                            }
                        }
                    }
                    Text { id: dmax; anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: drow.modelData.max + "°"; color: Theme.text; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Bold }
                }
            }
        }

        // ── footer ──────────────────────────────────────────────────────────
        Item {
            width: parent.width
            height: 32
            opacity: pop.stage(3)
            Row {
                spacing: 8
                anchors.verticalCenter: parent.verticalCenter
                IconBtn {
                    size: 30
                    icon: "\u{f0450}"
                    text: refreshProc.running ? "Updating…" : "Refresh"
                    enabled: !refreshProc.running
                    onClicked: refreshProc.running = true
                }
                IconBtn {
                    size: 30
                    icon: "\u{f034e}"
                    text: "Change place"
                    tip: "Type a place (fuzzel), then pick the match"
                    tipEdge: Edges.Top
                    onClicked: { pop.close(); placeProc.running = true; }
                }
            }
            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: pop.ok ? (pop.w.stale ? "stale · " : "") + "updated " + pop.w.age + " min ago · Open-Meteo" : ""
                color: pop.ok && pop.w.stale ? Theme.peach : Theme.overlay0
                font.family: Theme.font
                font.pixelSize: 10
            }
        }
    }
}
