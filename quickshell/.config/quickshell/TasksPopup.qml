// The tasks panel (Serpantinum-style) above the bottom bar's tasks pill —
// the WHOLE panel (the GTK one, tasks.py panel, only stands in when the shell
// is down). Left-click the pill; right-click = the same, "new task" focused;
// SUPER+T and a reminder's "Open tasks" (tasks.py toggle / open_panel) too.
//
//   header   ☑ Tasks · counts · [Undo]
//   add      "Report !! @fri 5pm" — tasks.py's syntax (! !! !!! priority,
//            @when deadline, @every … repeat)
//   tabs     Tasks · Done today · Log · History
//     Tasks    DUE SOON (overdue + next 2 days, soonest first), then
//              REMAINING in the sort you pick (manual ↑↓ › deadline ›
//              priority — shared with the GTK panel); TaskCard each
//     Done     today's ticked-off ones (untick, edit, delete)
//     Log      today's log: add an update, edit / delete lines
//     History  the day files (~/notes/daily): Done · Still open · Log
//
// Data: `tasks.py json` (re-read whenever ~/notes/tasks.md or today's day
// file changes); changes: `tasks.py op …` (one JSON answer each; every one
// undoable). History: `tasks.py day DATE`. `qs ipc call tasks toggle|open|add|close`.
import QtQuick
import Quickshell
import Quickshell.Io

PanelPopup {
    id: pop
    tabBar: menuTabs                          // Ctrl+Tab / Ctrl+Shift+Tab cycle it
    TabFade { id: tabFx; key: pop.tab; active: pop.isOpen }   // soft tab swap
    initialFocus: addField.input                    // keyboard-opened: start typing here

    edge: Edges.Top
    panelWidth: 520
    pad: 16

    property var scriptPill: null             // the bar pill, poked after a change
    // for the cards' `pop: …` (a bare `pop` there would be the card's own property)
    readonly property var panelRef: pop
    property var tasks: []
    property string today: ""
    property string sortMode: "manual"
    property int undoN: 0
    property var log: []
    property var days: []
    property int tab: 0                       // 0 tasks, 1 done, 2 log, 3 history
    property string msg: ""
    property bool msgBad: false
    property string editing: ""               // key of the card / log line being edited
    property string delArmed: ""
    property string histDay: ""
    property var hist: null

    readonly property var open_: tasks.filter(t => !t.done).sort((a, b) => a.i - b.i)
    readonly property var done_: tasks.filter(t => t.done)
    readonly property var overdue: open_.filter(t => t.level === "overdue")
    function dueMs(t) {
        if (!t.due) return 8.64e15;
        const p = t.dueDay.split("-");
        const tm = (t.dueTime || "23:59").split(":");
        return new Date(+p[0], +p[1] - 1, +p[2], +tm[0], +tm[1]).getTime();
    }
    // overdue + due within two days, soonest first — like the GTK panel
    readonly property var soon: open_.filter(t => t.due && dueMs(t) <= Date.now() + 2 * 86400000)
                                     .sort((a, b) => dueMs(a) - dueMs(b) || b.prio - a.prio)
    readonly property var rest: {
        const r = open_.filter(t => !soon.includes(t));
        if (sortMode === "deadline") r.sort((a, b) => dueMs(a) - dueMs(b) || b.prio - a.prio);
        else if (sortMode === "priority") r.sort((a, b) => b.prio - a.prio || dueMs(a) - dueMs(b));
        return r;
    }
    function key(t) { return t.text + "\n" + t.due + "\n" + (t.done ? "x" : ""); }
    function armDelete(k) { delArmed = k; disarm.restart(); }
    Timer { id: disarm; interval: 4000; onTriggered: pop.delArmed = "" }

    // ── data ────────────────────────────────────────────────────────────────
    function refresh() { if (!lister.running) lister.running = true; else again.restart(); }
    Timer { id: again; interval: 300; onTriggered: pop.refresh() }
    Process {
        id: lister
        command: ["/usr/bin/python3", Theme.hypr + "/tasks.py", "json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    pop.tasks = d.tasks || [];
                    pop.today = d.today || "";
                    pop.sortMode = d.sort || "manual";
                    pop.undoN = d.undo || 0;
                    pop.log = d.log || [];
                    pop.days = d.days || [];
                    if (pop.tab === 3) pop.loadDay(pop.histDay || (pop.days[0] ? pop.days[0].day : ""));
                } catch (e) {}
            }
        }
    }
    FileView {
        path: Theme.home + "/notes/tasks.md"
        watchChanges: true
        printErrors: false
        onFileChanged: { reload(); if (pop.isOpen) pop.refresh(); }
    }
    FileView {
        path: pop.today ? Theme.home + "/notes/daily/" + pop.today + ".md" : ""
        watchChanges: true
        printErrors: false
        onFileChanged: { reload(); if (pop.isOpen) pop.refresh(); }
    }
    // relative labels ("in 25m") age: re-read now and then while open
    Timer { interval: 30000; repeat: true; running: pop.isOpen; onTriggered: pop.refresh() }
    onOpened: { refresh(); msg = ""; editing = ""; delArmed = ""; }

    Process {
        id: act
        property var after: null
        stdout: StdioCollector {
            onStreamFinished: {
                let r = {};
                try { r = JSON.parse(text); } catch (e) { r = { ok: false, msg: text.trim() || "tasks.py failed" }; }
                pop.msg = r.msg || "";
                pop.msgBad = r.ok === false;
                const f = act.after;
                act.after = null;
                if (r.ok && f) f();
                pop.refresh();
                if (pop.scriptPill && pop.scriptPill.refresh) pop.scriptPill.refresh();
                msgClear.restart();
            }
        }
    }
    Timer { id: msgClear; interval: 6000; onTriggered: if (!pop.msgBad) pop.msg = "" }
    function op(args, after) {
        if (act.running) { queued.push([args, after]); return; }
        act.after = after || null;
        act.command = ["/usr/bin/python3", Theme.hypr + "/tasks.py", "op"].concat(args);
        act.running = true;
    }
    // a second change while one is on its way (rename → due) waits its turn
    property var queued: []
    Connections {
        target: act
        function onRunningChanged() {
            if (!act.running && pop.queued.length) {
                const n = pop.queued.shift();
                pop.op(n[0], n[1]);
            }
        }
    }
    // tasks | done | log | history (also `qs ipc call tasks tab NAME`)
    function showTab(name) {
        const i = ["tasks", "done", "log", "history"].indexOf(name);
        if (i < 0) return;
        tab = i; editing = ""; delArmed = "";
        if (i === 3) loadDay(histDay || (days[0] ? days[0].day : ""));
    }
    function focusAdd() { tab = tab === 2 ? 0 : tab; addField.input.forceActiveFocus(); }

    // History
    Process {
        id: dayProc
        stdout: StdioCollector {
            onStreamFinished: { try { pop.hist = JSON.parse(text); } catch (e) { pop.hist = null; } }
        }
    }
    function loadDay(d) {
        histDay = d;
        if (!d) { hist = null; return; }
        dayProc.command = ["/usr/bin/python3", Theme.hypr + "/tasks.py", "day", d];
        dayProc.running = true;
    }

    function prioColor(p) { return [Theme.overlay1, Theme.yellow, Theme.peach, Theme.red][p] || Theme.overlay1; }
    function levelColor(t) { return t.level === "overdue" ? Theme.red : t.level === "soon" ? Theme.yellow : Theme.subtext0; }

    function stage(k) { return Math.max(0, Math.min(1, (pop.intro - k * 0.12) / (1 - k * 0.12))); }

    component SectionHead: Item {
        property string label
        property color tint: Theme.overlay1
        width: parent ? parent.width : 0
        height: 22
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: parent.label
            color: parent.tint
            font.family: Theme.font
            font.pixelSize: 10
            font.weight: Font.Bold
            font.letterSpacing: 1.2
        }
    }

    Column {
        width: parent.width
        spacing: 12

        // ── header ──────────────────────────────────────────────────────────
        Item {
            width: parent.width
            height: 42
            opacity: pop.stage(0)
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12
                Rectangle {
                    width: 42
                    height: 42
                    radius: 13
                    color: Theme.alpha(pop.overdue.length ? Theme.red : Theme.accent, 0.18)
                    Text {
                        anchors.centerIn: parent
                        text: pop.open_.length ? "\u{f0131}" : "\u{f0132}"
                        color: pop.overdue.length ? Theme.red : Theme.accent
                        font.family: Theme.font
                        font.pixelSize: 21
                    }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        text: "Tasks"
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: 18
                        font.weight: Font.Bold
                    }
                    Text {
                        text: (pop.open_.length ? pop.open_.length + " open" : "All clear")
                            + (pop.overdue.length ? "  ·  " + pop.overdue.length + " overdue" : "")
                            + (pop.done_.length ? "  ·  " + pop.done_.length + " done today" : "")
                        color: pop.overdue.length ? Theme.red : Theme.overlay1
                        font.family: Theme.font
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }
                }
            }
            IconBtn {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                size: 30
                icon: "\u{f054c}"                      // md-undo
                text: "Undo"
                enabled: pop.undoN > 0 && !act.running
                tip: pop.undoN > 0 ? "Undo the last change (" + pop.undoN + " kept)" : "Nothing to undo"
                tipEdge: Edges.Top
                onClicked: pop.op(["undo"])
            }
        }

        // ── add (a task, or on the Log tab an update) ───────────────────────
        Row {
            width: parent.width
            spacing: 8
            opacity: pop.stage(1)
            visible: pop.tab !== 3
            SettingsField {
                id: addField
                width: parent.width - addBtn.width - 8
                height: 36
                placeholder: pop.tab === 2 ? "Log an update…  e.g. finished the report draft"
                                           : "New task  ·  !! priority  ·  @fri 5pm deadline  ·  @every mon"
                onAccepted: addBtn.clicked(Qt.LeftButton)
                onEscaped: pop.close()
            }
            IconBtn {
                id: addBtn
                size: 36
                icon: pop.tab === 2 ? "\u{f14e9}" : "\u{f0415}"
                active: addField.text.trim() !== ""
                tip: pop.tab === 2 ? "Log it (Enter)" : "Add (Enter)"
                tipEdge: Edges.Top
                onClicked: {
                    const t = addField.text.trim();
                    if (!t) { addField.input.forceActiveFocus(); return; }
                    pop.op([pop.tab === 2 ? "log" : "add", t], () => addField.text = "");
                }
            }
        }
        Text {
            visible: pop.msg !== ""
            width: parent.width
            wrapMode: Text.Wrap
            text: (pop.msgBad ? "\u{f0026}  " : "\u{f012c}  ") + pop.msg
            color: pop.msgBad ? Theme.red : Theme.green
            font.family: Theme.font
            font.pixelSize: 11
        }

        Segmented {
            id: menuTabs
            width: parent.width
            height: 32
            opacity: pop.stage(1)
            options: ["Tasks · " + pop.open_.length, "Done · " + pop.done_.length, "Log · " + pop.log.length, "History"]
            currentIndex: pop.tab
            onSelected: i => {
                pop.tab = i; pop.editing = ""; pop.delArmed = "";
                if (i === 3) pop.loadDay(pop.histDay || (pop.days[0] ? pop.days[0].day : ""));
            }
        }

        // ── the list ────────────────────────────────────────────────────────
        Item {
            width: parent.width
            height: Math.min(list.height, 420)
            Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            opacity: pop.stage(2) * tabFx.value
            transform: Translate { y: 14 * (1 - pop.stage(2)) + 8 * (1 - tabFx.value) }

            Flickable {
                id: flick
                anchors.fill: parent
                contentHeight: list.height
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height

                Column {
                    id: list
                    width: flick.width
                    spacing: 7

                    // ── Tasks ──
                    SectionHead {
                        visible: pop.tab === 0 && pop.soon.length > 0
                        label: "DUE SOON  ·  " + pop.soon.length
                        tint: pop.soon.some(t => t.level === "overdue") ? Theme.red : Theme.yellow
                    }
                    Repeater {
                        model: pop.tab === 0 ? pop.soon : []
                        delegate: TaskCard { required property var modelData; pop: panelRef; t: modelData }
                    }
                    Item {
                        visible: pop.tab === 0
                        width: parent.width
                        height: 26
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "REMAINING  ·  " + pop.rest.length
                            color: Theme.overlay1
                            font.family: Theme.font
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            font.letterSpacing: 1.2
                        }
                        IconBtn {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            size: 24
                            iconSize: 12
                            icon: "\u{f04ba}"                 // md-sort
                            text: "sort: " + pop.sortMode
                            tip: "Order of this list: manual (↑↓ on hover) › deadline › priority"
                            tipEdge: Edges.Top
                            onClicked: {
                                const modes = ["manual", "deadline", "priority"];
                                pop.op(["sort", modes[(modes.indexOf(pop.sortMode) + 1) % 3]]);
                            }
                        }
                    }
                    Repeater {
                        model: pop.tab === 0 ? pop.rest : []
                        delegate: TaskCard {
                            required property var modelData
                            required property int index
                            pop: panelRef
                            t: modelData
                            up: pop.sortMode === "manual" && index > 0 ? pop.rest[index - 1] : null
                            down: pop.sortMode === "manual" && index < pop.rest.length - 1 ? pop.rest[index + 1] : null
                        }
                    }

                    // ── Done today ──
                    Repeater {
                        model: pop.tab === 1 ? pop.done_ : []
                        delegate: TaskCard { required property var modelData; pop: panelRef; t: modelData }
                    }

                    // ── Log ──
                    Repeater {
                        model: pop.tab === 2 ? pop.log : []
                        delegate: Rectangle {
                            id: logRow
                            required property var modelData
                            readonly property string k: "log:" + modelData.i + ":" + modelData.text
                            readonly property bool editingMe: pop.editing === k
                            width: list.width
                            height: editingMe ? 50 : Math.max(42, logText.implicitHeight + 20)
                            radius: 11
                            color: logMa.containsMouse || editingMe ? Theme.alpha(Theme.surface1, 0.5) : Theme.alpha(Theme.surface0, 0.55)
                            MouseArea {
                                id: logMa
                                anchors.fill: parent
                                hoverEnabled: true
                                onDoubleClicked: { pop.editing = logRow.k; logEdit.text = logRow.modelData.text; logEdit.input.forceActiveFocus(); }
                            }
                            Text {
                                id: stamp
                                visible: !logRow.editingMe
                                x: 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: logRow.modelData.stamp || "·"
                                color: Theme.peach
                                font.family: Theme.font
                                font.pixelSize: 11
                                font.weight: Font.Bold
                            }
                            Text {
                                id: logText
                                visible: !logRow.editingMe
                                anchors.left: stamp.right
                                anchors.leftMargin: 12
                                anchors.right: logBtns.left
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                text: logRow.modelData.text
                                wrapMode: Text.Wrap
                                color: Theme.text
                                font.family: Theme.font
                                font.pixelSize: 12
                            }
                            Row {
                                id: logBtns
                                visible: !logRow.editingMe
                                anchors.right: parent.right
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 4
                                opacity: logMa.containsMouse || pop.delArmed === logRow.k ? 1 : 0
                                IconBtn {
                                    size: 26
                                    iconSize: 13
                                    icon: "\u{f03eb}"
                                    tip: "Edit (or double-click)"
                                    tipEdge: Edges.Top
                                    onClicked: { pop.editing = logRow.k; logEdit.text = logRow.modelData.text; logEdit.input.forceActiveFocus(); }
                                }
                                IconBtn {
                                    readonly property bool armed: pop.delArmed === logRow.k
                                    size: 26
                                    iconSize: 13
                                    icon: "\u{f0a7a}"
                                    text: armed ? "Delete?" : ""
                                    fg: Theme.red
                                    active: armed
                                    activeFg: Theme.red
                                    tip: armed ? "Click again to delete" : "Delete"
                                    tipEdge: Edges.Top
                                    onClicked: {
                                        if (!armed) { pop.armDelete(logRow.k); return; }
                                        pop.delArmed = "";
                                        pop.op(["logdel", String(logRow.modelData.i)]);
                                    }
                                }
                            }
                            SettingsField {
                                id: logEdit
                                visible: logRow.editingMe
                                x: 10
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 20
                                placeholder: "The update"
                                onAccepted: { pop.editing = ""; if (text.trim()) pop.op(["logedit", String(logRow.modelData.i), text.trim()]); }
                                onEscaped: pop.editing = ""
                            }
                        }
                    }

                    // ── History ──
                    Flow {
                        visible: pop.tab === 3 && pop.days.length > 0
                        width: parent.width
                        spacing: 6
                        Repeater {
                            model: pop.tab === 3 ? pop.days.slice(0, 14) : []
                            delegate: IconBtn {
                                required property var modelData
                                size: 26
                                text: modelData.label + (modelData.done ? "  ·  " + modelData.done + " ✓" : "")
                                active: pop.histDay === modelData.day
                                onClicked: pop.loadDay(modelData.day)
                            }
                        }
                    }
                    Rectangle {
                        visible: pop.tab === 3 && !!pop.hist && !!pop.hist.day
                        width: parent.width
                        height: histCol.implicitHeight + 24
                        radius: 12
                        color: Theme.alpha(Theme.surface0, 0.45)
                        Column {
                            id: histCol
                            x: 14
                            y: 12
                            width: parent.width - 28
                            spacing: 5
                            Item {
                                width: parent.width
                                height: 26
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: pop.hist ? pop.hist.title || "" : ""
                                    color: Theme.text
                                    font.family: Theme.font
                                    font.pixelSize: 14
                                    font.weight: Font.Bold
                                }
                                IconBtn {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    size: 24
                                    iconSize: 12
                                    icon: "\u{f0219}"
                                    text: "Open file"
                                    tip: "This day's markdown file"
                                    tipEdge: Edges.Top
                                    onClicked: { pop.close(); Quickshell.execDetached(["xdg-open", pop.hist.path]); }
                                }
                            }
                            Repeater {
                                model: pop.hist ? [["Done", pop.hist.done, "\u{f012c}", Theme.green],
                                                   ["Still open", pop.hist.open, "\u{f0130}", Theme.overlay1]] : []
                                delegate: Column {
                                    id: sec
                                    required property var modelData
                                    width: histCol.width
                                    spacing: 3
                                    Text {
                                        topPadding: 6
                                        text: modelData[0].toUpperCase() + "  ·  " + modelData[1].length
                                        color: Theme.accent
                                        font.family: Theme.font
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                        font.letterSpacing: 1.2
                                    }
                                    Repeater {
                                        model: modelData[1]
                                        delegate: Text {
                                            required property var modelData
                                            width: histCol.width
                                            wrapMode: Text.Wrap
                                            text: "<font color='" + sec.modelData[3] + "'>" + sec.modelData[2] + "</font>  " + modelData
                                            textFormat: Text.StyledText
                                            color: Theme.subtext1
                                            font.family: Theme.font
                                            font.pixelSize: 12
                                        }
                                    }
                                    Text {
                                        visible: modelData[1].length === 0
                                        text: "nothing"
                                        color: Theme.overlay0
                                        font.italic: true
                                        font.family: Theme.font
                                        font.pixelSize: 11
                                    }
                                }
                            }
                            Text {
                                topPadding: 6
                                text: "LOG  ·  " + (pop.hist && pop.hist.log ? pop.hist.log.length : 0)
                                color: Theme.accent
                                font.family: Theme.font
                                font.pixelSize: 10
                                font.weight: Font.Bold
                                font.letterSpacing: 1.2
                            }
                            Repeater {
                                model: pop.hist && pop.hist.log ? pop.hist.log : []
                                delegate: Text {
                                    required property var modelData
                                    width: histCol.width
                                    wrapMode: Text.Wrap
                                    text: "<font color='" + Theme.peach + "'>" + (modelData.stamp || "·") + "</font>  " + modelData.text
                                    textFormat: Text.StyledText
                                    color: Theme.subtext1
                                    font.family: Theme.font
                                    font.pixelSize: 12
                                }
                            }
                        }
                    }

                    // empty states
                    Column {
                        visible: (pop.tab === 0 && pop.open_.length === 0) || (pop.tab === 1 && pop.done_.length === 0)
                              || (pop.tab === 2 && pop.log.length === 0) || (pop.tab === 3 && pop.days.length === 0)
                        width: parent.width
                        topPadding: 18
                        bottomPadding: 14
                        spacing: 6
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: pop.tab === 2 ? "\u{f14e9}" : pop.tab === 3 ? "\u{f02da}" : pop.tab === 1 ? "\u{f0131}" : "\u{f0132}"
                            color: Theme.alpha(Theme.overlay0, 0.8)
                            font.family: Theme.font
                            font.pixelSize: 40
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: ["Nothing on the list", "Nothing ticked off yet today",
                                   "No updates logged today", "No day files yet"][pop.tab]
                            color: Theme.subtext0
                            font.family: Theme.font
                            font.pixelSize: 13
                            font.weight: Font.Bold
                        }
                    }
                }
            }

            Rectangle {
                visible: flick.contentHeight > flick.height && !flick.atYEnd
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 26
                gradient: Gradient {
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 1; color: Theme.panel(Theme.mantle) }
                }
            }
        }
    }
}
