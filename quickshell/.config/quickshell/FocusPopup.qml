// The focus timer's panel (Serpantinum-style) above the bottom bar's timer
// pill (FocusPill.qml) — right-click it, or `qs ipc call bottombar menu focus`.
//
//   ring     the countdown as a draining arc (red focus · green break ·
//            yellow paused), time left in the middle, the phase under it
//   controls start / pause·resume · +5 min · finish now (or end break) · stop
//   length   25·5 · 50·10 · 90·15
//   task     none · open tasks from ~/notes/tasks.md · typed ones (× forgets)
//            · a field for anything else (focus.py use); picking one while
//            idle starts the session on it
//   today    sessions done today and the focus lines of today's log
//
// Everything runs focus.py, like the pill (its state file is the truth).
import QtQuick
import Quickshell
import Quickshell.Io

PanelPopup {
    id: pop

    property var fp: null                     // the FocusPill (state + run())
    edge: Edges.Top
    panelWidth: 470
    pad: 16

    readonly property bool idle: !fp || fp.idle
    readonly property color tint: !fp || fp.idle ? Theme.accent : fp.tint
    readonly property real frac: fp && fp.frac >= 0 ? fp.frac : 1

    // today's focus sessions, from today's log (tasks.py json)
    property var sessions: []
    Process {
        id: logProc
        command: ["/usr/bin/python3", Theme.hypr + "/tasks.py", "json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    pop.sessions = (d.log || []).filter(l => l.text.indexOf("min focus") >= 0);
                } catch (e) {}
            }
        }
    }
    onOpened: logProc.running = true

    function run(args) { if (fp) fp.run(args); }
    // pick a task: idle -> start on it, running -> rename the session
    function pick(t) { run(idle ? ["start", String(fp.workMin)].concat(t ? [t] : []) : ["task"].concat(t ? [t] : [])); }

    function stage(k) { return Math.max(0, Math.min(1, (pop.intro - k * 0.12) / (1 - k * 0.12))); }

    Column {
        width: parent.width
        spacing: 14

        // ── ring + state ────────────────────────────────────────────────────
        Row {
            width: parent.width
            spacing: 18
            opacity: pop.stage(0)
            transform: Translate { y: 12 * (1 - pop.stage(0)) }

            Item {
                id: ringBox
                width: 132
                height: 132
                Canvas {
                    id: ring
                    anchors.fill: parent
                    property real f: pop.frac
                    property color c: pop.tint
                    onFChanged: requestPaint()
                    onCChanged: requestPaint()
                    Connections { target: Theme; function onAccentChanged() { ring.requestPaint(); } }
                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.reset();
                        const r = width / 2 - 8;
                        ctx.lineWidth = 9;
                        ctx.lineCap = "round";
                        ctx.strokeStyle = Qt.rgba(Theme.surface1.r, Theme.surface1.g, Theme.surface1.b, 0.7);
                        ctx.beginPath();
                        ctx.arc(width / 2, height / 2, r, 0, 2 * Math.PI);
                        ctx.stroke();
                        ctx.strokeStyle = c;
                        ctx.beginPath();
                        ctx.arc(width / 2, height / 2, r, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * Math.max(0.001, f));
                        ctx.stroke();
                    }
                }
                // a soft glow while running
                Rectangle {
                    anchors.centerIn: parent
                    width: 96
                    height: 96
                    radius: 48
                    color: Theme.alpha(pop.tint, pop.idle ? 0.08 : 0.16)
                    SequentialAnimation on scale {
                        running: pop.isOpen && !pop.idle && !(pop.fp && pop.fp.paused)
                        loops: Animation.Infinite
                        NumberAnimation { to: 1.06; duration: 1200; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1.0; duration: 1200; easing.type: Easing.InOutSine }
                    }
                }
                Column {
                    anchors.centerIn: parent
                    spacing: 0
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: !pop.fp ? "" : pop.idle ? pop.fp.workMin + ":00" : pop.fp.clock(pop.fp.remain)
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: 26
                        font.weight: Font.Bold
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: !pop.fp ? "" : pop.idle ? "ready" : pop.fp.paused ? "paused" : pop.fp.phase === "break" ? "break" : "focus"
                        color: pop.tint
                        font.family: Theme.font
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        font.letterSpacing: 1.5
                        font.capitalization: Font.AllUppercase
                    }
                }
            }

            Column {
                width: parent.width - ringBox.width - parent.spacing
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                Text {
                    width: parent.width
                    text: !pop.fp ? "" : pop.idle ? "Focus timer" : pop.fp.phase === "break" ? "Break" : "Focusing"
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 18
                    font.weight: Font.Bold
                }
                Text {
                    width: parent.width
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    text: pop.fp && pop.fp.task ? "\u{f0131}  " + pop.fp.task : "No particular task"
                    color: pop.fp && pop.fp.task ? Theme.subtext1 : Theme.overlay1
                    font.family: Theme.font
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width
                    text: !pop.fp ? "" : pop.idle ? pop.fp.workMin + " min focus (do not disturb), then " + pop.fp.brkMin + " min break"
                        : Math.round(pop.fp.st.total / 60) + " min " + (pop.fp.phase === "break" ? "break" : "session")
                          + (pop.fp.phase === "work" ? "  ·  notifications held" : "  ·  notifications back")
                    wrapMode: Text.Wrap
                    color: Theme.overlay1
                    font.family: Theme.font
                    font.pixelSize: 11
                }
                Row {
                    spacing: 6
                    topPadding: 4
                    IconBtn {
                        size: 34
                        iconSize: 17
                        active: true
                        activeFg: pop.tint
                        icon: pop.idle ? "\u{f040a}" : pop.fp && pop.fp.paused ? "\u{f040a}" : "\u{f03e4}"
                        text: pop.idle ? "Start" : pop.fp && pop.fp.paused ? "Resume" : "Pause"
                        onClicked: pop.run(pop.idle ? ["start"] : ["toggle"])
                    }
                    IconBtn {
                        visible: !pop.idle
                        size: 34
                        icon: "\u{f0415}"
                        text: "5 min"
                        tip: "Add 5 minutes"
                        tipEdge: Edges.Top
                        onClicked: pop.run(["add", "5"])
                    }
                    IconBtn {
                        visible: !pop.idle
                        size: 34
                        icon: "\u{f04ad}"
                        tip: pop.fp && pop.fp.phase === "break" ? "End the break" : "Finish now — take the break"
                        tipEdge: Edges.Top
                        onClicked: pop.run(["skip"])
                    }
                    IconBtn {
                        visible: !pop.idle
                        size: 34
                        icon: "\u{f04db}"
                        fg: Theme.red
                        tip: "Stop (nothing logged)"
                        tipEdge: Edges.Top
                        onClicked: pop.run(["stop"])
                    }
                }
            }
        }

        // ── length ──────────────────────────────────────────────────────────
        Segmented {
            width: parent.width
            height: 32
            opacity: pop.stage(1)
            readonly property var lens: [[25, 5], [50, 10], [90, 15]]
            options: lens.map(l => l[0] + " / " + l[1] + " min")
            currentIndex: pop.fp ? Math.max(0, lens.findIndex(l => l[0] === pop.fp.workMin && l[1] === pop.fp.brkMin)) : 0
            accent: pop.tint
            onSelected: i => pop.run(["lengths", String(lens[i][0]), String(lens[i][1])])
        }

        // ── task ────────────────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 6
            opacity: pop.stage(2)
            transform: Translate { y: 12 * (1 - pop.stage(2)) }
            Text {
                text: "TASK" + (pop.idle ? "  ·  picking one starts the session" : "")
                color: Theme.overlay1
                font.family: Theme.font
                font.pixelSize: 10
                font.weight: Font.Bold
                font.letterSpacing: 1.2
            }
            Flickable {
                width: parent.width
                height: Math.min(taskCol.height, 190)
                contentHeight: taskCol.height
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height
                Column {
                    id: taskCol
                    width: parent.width
                    spacing: 4
                    Repeater {
                        model: pop.fp ? [{ t: "", typed: false }]
                                        .concat(pop.fp.tasks.slice(0, 10).map(t => ({ t: t, typed: false })))
                                        .concat(pop.fp.recent.map(t => ({ t: t, typed: true }))) : []
                        delegate: Rectangle {
                            id: trow
                            required property var modelData
                            readonly property bool cur: pop.fp && pop.fp.task === modelData.t
                            width: taskCol.width
                            height: 34
                            radius: 9
                            color: cur ? Theme.alpha(pop.tint, 0.18) : tma.containsMouse ? Theme.alpha(Theme.surface1, 0.6) : Theme.alpha(Theme.surface0, 0.45)
                            border.width: cur ? 1 : 0
                            border.color: Theme.alpha(pop.tint, 0.6)
                            MouseArea {
                                id: tma
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: pop.pick(trow.modelData.t)
                            }
                            Text {
                                x: 12
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 24 - (forget.visible ? forget.width + 6 : 0)
                                elide: Text.ElideRight
                                text: (trow.cur ? "\u{f012c}  " : trow.modelData.typed ? "\u{f03eb}  " : trow.modelData.t ? "\u{f0131}  " : "\u{f0156}  ")
                                      + (trow.modelData.t || "No particular task")
                                color: trow.cur ? Theme.text : trow.modelData.t ? Theme.subtext1 : Theme.overlay1
                                font.family: Theme.font
                                font.pixelSize: 12
                                font.weight: trow.cur ? Font.Bold : Font.Normal
                            }
                            IconBtn {
                                id: forget
                                visible: trow.modelData.typed && tma.containsMouse
                                anchors.right: parent.right
                                anchors.rightMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                size: 22
                                iconSize: 11
                                icon: "\u{f0156}"
                                tip: "Forget this one"
                                tipEdge: Edges.Top
                                onClicked: pop.run(["forget", trow.modelData.t])
                            }
                        }
                    }
                }
            }
            SettingsField {
                width: parent.width
                height: 34
                placeholder: "Something else…  (Enter)"
                onAccepted: { if (text.trim()) { pop.run(["use", text.trim()]); text = ""; } }
                onEscaped: pop.close()
            }
        }

        // ── today ───────────────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 4
            opacity: pop.stage(3)
            Text {
                text: "TODAY  ·  " + (pop.fp ? pop.fp.st.round || 0 : 0) + " session" + ((pop.fp ? pop.fp.st.round : 0) === 1 ? "" : "s")
                color: Theme.overlay1
                font.family: Theme.font
                font.pixelSize: 10
                font.weight: Font.Bold
                font.letterSpacing: 1.2
            }
            Repeater {
                model: pop.sessions.slice(-4)
                delegate: Text {
                    required property var modelData
                    width: parent.width
                    elide: Text.ElideRight
                    text: "<font color='" + Theme.peach + "'>" + (modelData.stamp || "·") + "</font>  " + modelData.text
                    textFormat: Text.StyledText
                    color: Theme.subtext0
                    font.family: Theme.font
                    font.pixelSize: 11
                }
            }
            Text {
                visible: pop.sessions.length === 0
                text: "None logged yet"
                color: Theme.overlay0
                font.italic: true
                font.family: Theme.font
                font.pixelSize: 11
            }
        }
    }
}
