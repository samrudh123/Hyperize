// The calendar (Serpantinum-style) under the top bar's clock — click the
// clock (right-click toggles time / date; scroll pages months while it is
// open). `qs ipc call calendar toggle|open|close`.
//
//   hero     today: big day number · weekday · month year · what is due
//   month    ‹ October 2026 › [Today]; Monday first; today filled in the
//            accent, the picked day ringed; deadline dots by priority (red
//            when overdue); scroll pages; other months' days page there
//   agenda   the picked day's deadlines, and a field to add a task due that
//            day (tasks.py op add "TEXT @YYYY-MM-DD")
//
// Deadlines come straight from ~/notes/tasks.md (watched), as the old hover
// card (CalendarCard.qml) read them.
import QtQuick
import Quickshell
import Quickshell.Io

PanelPopup {
    id: pop

    edge: Edges.Bottom
    panelWidth: 392
    pad: 16

    property int monthOffset: 0
    property date picked: new Date()
    property string msg: ""
    property bool msgBad: false

    SystemClock {
        id: sys
        precision: SystemClock.Minutes
    }
    readonly property date now_: sys.date
    readonly property date midnight: new Date(now_.getFullYear(), now_.getMonth(), now_.getDate())
    readonly property date shown: new Date(now_.getFullYear(), now_.getMonth() + monthOffset, 1)

    onOpened: { monthOffset = 0; picked = midnight; msg = ""; }
    function page(d) { monthOffset += d; }
    function pick(day) {
        picked = day;
        const off = (day.getFullYear() - now_.getFullYear()) * 12 + day.getMonth() - now_.getMonth();
        if (off !== monthOffset) monthOffset = off;
    }

    // ── deadlines (tasks.md) ────────────────────────────────────────────────
    FileView {
        id: tasksFile
        path: Theme.home + "/notes/tasks.md"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }
    // [{day, key, time, text, prio, every}], soonest first
    readonly property var deadlines: {
        const out = [];
        for (const l of (tasksFile.text() || "").split("\n")) {
            const m = l.match(/^\s*[-*] \[ \]\s+(.*?)\s*<!--(.*?)-->\s*$/);
            if (!m) continue;
            const due = m[2].match(/due (\d{4})-(\d{2})-(\d{2})(?: (\d{2}:\d{2}))?/);
            if (!due) continue;
            const prio = m[2].match(/prio ([1-3])/);
            const day = new Date(+due[1], +due[2] - 1, +due[3]);
            out.push({ day: day, key: day.toDateString(), time: due[4] || "", text: m[1],
                       prio: prio ? +prio[1] : 0, every: /every /.test(m[2]) });
        }
        return out.sort((a, b) => a.day - b.day || (a.time || "99").localeCompare(b.time || "99"));
    }
    function overdue(d) {
        if (d.day < midnight) return true;
        if (d.day > midnight || !d.time) return false;
        return d.time < Qt.formatTime(now_, "HH:mm");
    }
    function dotColor(d) { return overdue(d) ? Theme.red : [Theme.sapphire, Theme.yellow, Theme.peach, Theme.red][d.prio]; }
    readonly property var pickedDue: deadlines.filter(d => d.key === picked.toDateString())
    readonly property var overdueAll: deadlines.filter(d => overdue(d))
    readonly property int weekCount: deadlines.filter(d => !overdue(d) && d.day - midnight < 7 * 86400000).length

    // ── add a task due on the picked day ────────────────────────────────────
    Process {
        id: act
        stdout: StdioCollector {
            onStreamFinished: {
                let r = {};
                try { r = JSON.parse(text); } catch (e) { r = { ok: false, msg: "tasks.py failed" }; }
                pop.msg = r.msg || "";
                pop.msgBad = r.ok === false;
                if (r.ok) addField.text = "";
            }
        }
    }
    function addTask() {
        const t = addField.text.trim();
        if (!t || act.running) return;
        // the picked day; "@5pm" / "@17:30" alone = that time ON the picked
        // day; any other @… typed by hand wins
        const day = Qt.formatDate(picked, "yyyy-MM-dd");
        const tm = t.match(/(^|\s)@(\d{1,2}(?::\d{2})?\s*(?:am|pm)?)\s*$/i);
        const text = tm ? t.slice(0, tm.index) + tm[1] + "@" + day + " " + tm[2].replace(/\s+/g, "")
                   : /(^|\s)@\S/.test(t) ? t : t + " @" + day;
        act.command = ["/usr/bin/python3", Theme.hypr + "/tasks.py", "op", "add", text];
        act.running = true;
    }

    function stage(k) { return Math.max(0, Math.min(1, (pop.intro - k * 0.12) / (1 - k * 0.12))); }

    Column {
        width: parent.width
        spacing: 14

        // ── hero: today ─────────────────────────────────────────────────────
        Row {
            spacing: 14
            opacity: pop.stage(0)
            transform: Translate { y: 10 * (1 - pop.stage(0)) }
            Rectangle {
                width: 64
                height: 64
                radius: 18
                color: Theme.accent
                Column {
                    anchors.centerIn: parent
                    spacing: -4
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Qt.formatDate(pop.now_, "MMM").toUpperCase()
                        color: Theme.alpha(Theme.crust, 0.75)
                        font.family: Theme.font
                        font.pixelSize: 11
                        font.weight: Font.Bold
                        font.letterSpacing: 1.2
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: pop.now_.getDate()
                        color: Theme.crust
                        font.family: Theme.font
                        font.pixelSize: 28
                        font.weight: Font.Black
                    }
                }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Text {
                    text: Qt.formatDate(pop.now_, "dddd")
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 19
                    font.weight: Font.Bold
                }
                Text {
                    text: Qt.formatDate(pop.now_, "d MMMM yyyy") + "  ·  " + Qt.formatTime(pop.now_, "HH:mm")
                    color: Theme.subtext0
                    font.family: Theme.font
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
                Text {
                    text: pop.overdueAll.length ? "\u{f0026}  " + pop.overdueAll.length + " overdue"
                                                  + (pop.weekCount ? "  ·  " + pop.weekCount + " due this week" : "")
                        : pop.weekCount ? "\u{f00f0}  " + pop.weekCount + " due this week" : "\u{f0132}  nothing due this week"
                    color: pop.overdueAll.length ? Theme.red : Theme.accent
                    font.family: Theme.font
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
            }
        }

        // ── month ───────────────────────────────────────────────────────────
        Rectangle {
            width: parent.width
            height: monthCol.height + 24
            radius: 14
            color: Theme.alpha(Theme.surface0, 0.45)
            border.width: 1
            border.color: Theme.alpha(Theme.surface1, 0.5)
            opacity: pop.stage(1)
            transform: Translate { y: 14 * (1 - pop.stage(1)) }

            // scroll anywhere on the month to page it
            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                property real acc: 0
                onWheel: ev => {
                    acc += Theme.wheelDelta(ev);
                    while (Math.abs(acc) >= 120) { pop.page(acc > 0 ? -1 : 1); acc -= acc > 0 ? 120 : -120; }
                }
            }

            Column {
                id: monthCol
                x: 12
                y: 12
                width: parent.width - 24
                spacing: 8

                Item {
                    width: parent.width
                    height: 30
                    IconBtn {
                        id: prevBtn
                        anchors.verticalCenter: parent.verticalCenter
                        size: 28
                        icon: "\u{f0141}"
                        tip: "Previous month"
                        onClicked: pop.page(-1)
                    }
                    Text {
                        anchors.centerIn: parent
                        text: Qt.formatDate(pop.shown, "MMMM") + "  "
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: 15
                        font.weight: Font.Bold
                        Text {
                            anchors.left: parent.right
                            anchors.baseline: parent.baseline
                            text: pop.shown.getFullYear()
                            color: Theme.overlay2
                            font.family: Theme.font
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }
                    }
                    Row {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4
                        IconBtn {
                            visible: pop.monthOffset !== 0 || pop.picked.toDateString() !== pop.midnight.toDateString()
                            size: 28
                            iconSize: 13
                            icon: "\u{f00f6}"
                            text: "Today"
                            onClicked: { pop.monthOffset = 0; pop.picked = pop.midnight; }
                        }
                        IconBtn {
                            size: 28
                            icon: "\u{f0142}"
                            tip: "Next month"
                            onClicked: pop.page(1)
                        }
                    }
                }

                Row {
                    Repeater {
                        model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
                        Text {
                            required property string modelData
                            required property int index
                            width: monthCol.width / 7
                            horizontalAlignment: Text.AlignHCenter
                            text: modelData
                            color: index >= 5 ? Theme.overlay1 : Theme.accent
                            font.family: Theme.font
                            font.pixelSize: 11
                            font.weight: Font.Bold
                        }
                    }
                }

                Grid {
                    id: grid
                    // keyboard: one Tab stop; ← → a day, ↑ ↓ a week (pages the
                    // month when it leaves it), Enter → the add field below
                    readonly property bool kb: activeFocus || BarState.kbItem === grid
                    activeFocusOnTab: true
                    function kbStep(d, key) {
                        const n = (key === Qt.Key_Up || key === Qt.Key_Down ? 7 : 1) * d;
                        pop.pick(new Date(pop.picked.getFullYear(), pop.picked.getMonth(), pop.picked.getDate() + n));
                    }
                    function kbActivate() { pop.move(1); }
                    Keys.onPressed: ev => {
                        const k = ev.key;
                        const d = k === Qt.Key_Left || k === Qt.Key_Up ? -1 : k === Qt.Key_Right || k === Qt.Key_Down ? 1 : 0;
                        if (d && !(ev.modifiers & Qt.ControlModifier)) { kbStep(d, k); ev.accepted = true; }
                        else if (k === Qt.Key_Return || k === Qt.Key_Enter) { kbActivate(); ev.accepted = true; }
                    }
                    readonly property int lead: (pop.shown.getDay() + 6) % 7
                    readonly property int days: new Date(pop.shown.getFullYear(), pop.shown.getMonth() + 1, 0).getDate()
                    readonly property int cells: Math.ceil((lead + days) / 7) * 7
                    columns: 7
                    Repeater {
                        model: 42
                        Item {
                            id: cell
                            required property int index
                            readonly property date day: new Date(pop.shown.getFullYear(), pop.shown.getMonth(), index - grid.lead + 1)
                            readonly property bool inMonth: day.getMonth() === pop.shown.getMonth()
                            readonly property bool isToday: day.toDateString() === pop.midnight.toDateString()
                            readonly property bool isPicked: day.toDateString() === pop.picked.toDateString()
                            readonly property var due: pop.deadlines.filter(d => d.key === day.toDateString())
                            visible: index < grid.cells
                            width: monthCol.width / 7
                            height: 38

                            Rectangle {
                                anchors.centerIn: parent
                                width: 34
                                height: 34
                                radius: 11
                                color: cell.isToday ? Theme.accent
                                     : dayMa.containsMouse || cell.isPicked && grid.kb ? Theme.alpha(Theme.surface1, 0.8)
                                     : cell.due.length && cell.inMonth ? Theme.alpha(pop.dotColor(cell.due[0]), 0.1) : "transparent"
                                // picked = accent ring; the keyboard cursor (grid
                                // focused) = a thicker one, crust on today's fill
                                border.width: cell.isPicked && (!cell.isToday || grid.kb) ? (grid.kb ? 3 : 2) : 0
                                border.color: cell.isToday ? Theme.crust : Theme.accent
                                Behavior on color { ColorAnimation { duration: Theme.fast } }
                            }
                            Text {
                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: cell.due.length ? -3 : 0
                                text: cell.day.getDate()
                                color: cell.isToday ? Theme.crust : cell.inMonth ? Theme.text : Theme.surface2
                                font.family: Theme.font
                                font.pixelSize: 12
                                font.weight: cell.isToday || cell.isPicked ? Font.Bold : Font.Medium
                            }
                            Row {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 7
                                spacing: 2
                                Repeater {
                                    model: cell.due.slice(0, 3)
                                    Rectangle {
                                        required property var modelData
                                        width: 4
                                        height: 4
                                        radius: 2
                                        color: cell.isToday ? Theme.crust : pop.dotColor(modelData)
                                        opacity: cell.inMonth ? 1 : 0.5
                                    }
                                }
                            }
                            MouseArea {
                                id: dayMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: pop.pick(cell.day)
                            }
                        }
                    }
                }
            }
        }

        // ── the picked day ──────────────────────────────────────────────────
        Column {
            width: parent.width
            spacing: 8
            opacity: pop.stage(2)
            transform: Translate { y: 14 * (1 - pop.stage(2)) }

            Text {
                text: (pop.picked.toDateString() === pop.midnight.toDateString() ? "TODAY" : Qt.formatDate(pop.picked, "dddd d MMM").toUpperCase())
                      + "  ·  " + (pop.pickedDue.length ? pop.pickedDue.length + " due" : "nothing due")
                color: Theme.overlay1
                font.family: Theme.font
                font.pixelSize: 10
                font.weight: Font.Bold
                font.letterSpacing: 1.2
            }
            Repeater {
                model: pop.pickedDue
                Rectangle {
                    required property var modelData
                    readonly property color c: pop.dotColor(modelData)
                    width: parent.width
                    height: 38
                    radius: 10
                    color: Theme.alpha(Theme.surface0, 0.55)
                    border.width: 1
                    border.color: Theme.alpha(c, pop.overdue(modelData) ? 0.5 : 0.2)
                    Rectangle {
                        x: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: 4
                        height: 18
                        radius: 2
                        color: parent.c
                    }
                    Text {
                        x: 22
                        anchors.verticalCenter: parent.verticalCenter
                        width: 52
                        text: modelData.time || "all day"
                        color: pop.overdue(modelData) ? Theme.red : Theme.subtext0
                        font.family: Theme.font
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }
                    Text {
                        x: 80
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 90
                        elide: Text.ElideRight
                        text: (modelData.prio ? "!".repeat(modelData.prio) + "  " : "") + modelData.text
                              + (modelData.every ? "   \u{f0456}" : "")
                        color: pop.overdue(modelData) ? Theme.red : Theme.text
                        font.family: Theme.font
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }
                }
            }
            Row {
                width: parent.width
                spacing: 8
                SettingsField {
                    id: addField
                    width: parent.width - addBtn.width - 8
                    height: 34
                    placeholder: "Add a task due " + (pop.picked.toDateString() === pop.midnight.toDateString()
                                                      ? "today" : Qt.formatDate(pop.picked, "ddd d MMM")) + "  ·  !! · @5pm"
                    onAccepted: pop.addTask()
                    onEscaped: pop.close()
                }
                IconBtn {
                    id: addBtn
                    size: 34
                    icon: "\u{f0415}"
                    active: addField.text.trim() !== ""
                    tip: "Add (Enter)"
                    onClicked: pop.addTask()
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
        }
    }
}
