// The month card under the clock (Clock.qml). Monday first; today is a red
// pill (waybar's calendar had it red too); other months' days are dimmed.
// Task deadlines (~/notes/tasks.md, see ~/.config/hypr/tasks.py) are dots
// under their days, coloured by priority (red when overdue), and listed
// under the month: the shown month's, plus anything overdue on this one.
import QtQuick
import Quickshell
import Quickshell.Io

Rectangle {
    id: root

    property date today: new Date()
    property int monthOffset: 0

    FileView {
        id: tasksFile
        path: Theme.home + "/notes/tasks.md"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }

    // [{day: Date (midnight), key: "Y-M-D", time: "17:00" | "", text, prio, every}], soonest first
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
    readonly property date midnight: new Date(today.getFullYear(), today.getMonth(), today.getDate())
    function overdue(d) {
        if (d.day < midnight) return true;
        if (d.day > midnight || !d.time) return false;
        return d.time < Qt.formatTime(today, "HH:mm");
    }
    function dotColor(d) {
        return overdue(d) ? Theme.red : [Theme.sapphire, Theme.yellow, Theme.peach, Theme.red][d.prio];
    }
    // listed under the month
    readonly property var listed: deadlines.filter(d =>
        (d.day.getFullYear() === cal.shown.getFullYear() && d.day.getMonth() === cal.shown.getMonth()
         && (monthOffset !== 0 || !overdue(d))) || (monthOffset === 0 && overdue(d)))

    implicitWidth: 7 * 34 + 2 * 14
    implicitHeight: cal.implicitHeight + 2 * 14
    radius: 14
    color: Theme.alpha(Theme.mantle, 0.97)
    border.width: 1
    border.color: Theme.surface1

    Column {
        id: cal
        x: 14
        y: 14
        spacing: 6

        readonly property date shown: {
            const d = new Date(root.today.getFullYear(), root.today.getMonth() + root.monthOffset, 1);
            return d;
        }

        // Month + year
        Item {
            width: 7 * 34
            height: 26
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Qt.formatDate(cal.shown, "MMMM")
                color: Theme.accent
                font.family: Theme.font
                font.pixelSize: 15
                font.weight: Font.Bold
            }
            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: cal.shown.getFullYear()
                color: Theme.overlay2
                font.family: Theme.font
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }
        }

        // Weekday names, Monday first
        Row {
            Repeater {
                model: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
                Text {
                    required property string modelData
                    required property int index
                    width: 34
                    horizontalAlignment: Text.AlignHCenter
                    text: modelData
                    color: index >= 5 ? Theme.overlay2 : Theme.accent
                    font.family: Theme.font
                    font.pixelSize: 12
                    font.weight: Font.Bold
                }
            }
        }

        Grid {
            id: grid
            readonly property int lead: (cal.shown.getDay() + 6) % 7
            readonly property int days: new Date(cal.shown.getFullYear(), cal.shown.getMonth() + 1, 0).getDate()
            readonly property int cells: Math.ceil((lead + days) / 7) * 7
            columns: 7
            Repeater {
                model: 42
                Item {
                    id: cell
                    required property int index
                    readonly property date day: new Date(cal.shown.getFullYear(), cal.shown.getMonth(), index - grid.lead + 1)
                    readonly property bool inMonth: day.getMonth() === cal.shown.getMonth()
                    readonly property bool today: day.toDateString() === root.today.toDateString()
                    readonly property var due: root.deadlines.filter(d => d.key === day.toDateString())
                    visible: index < grid.cells
                    width: 34
                    height: 28

                    Rectangle {
                        anchors.centerIn: parent
                        width: 28
                        height: 26
                        radius: 8
                        color: parent.today ? Theme.red : "transparent"
                    }
                    Text {
                        anchors.centerIn: parent
                        text: parent.day.getDate()
                        color: parent.today ? Theme.crust : parent.inMonth ? Theme.text : Theme.surface2
                        font.family: Theme.font
                        font.pixelSize: 12
                        font.weight: parent.today ? Font.Bold : Font.Medium
                    }
                    // up to three dots, one per deadline that day
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 2
                        spacing: 2
                        Repeater {
                            model: cell.due.slice(0, 3)
                            Rectangle {
                                required property var modelData
                                width: 4
                                height: 4
                                radius: 2
                                color: cell.today ? Theme.crust : root.dotColor(modelData)
                                opacity: cell.inMonth ? 1 : 0.5
                            }
                        }
                    }
                }
            }
        }

        // The deadlines under the month
        Column {
            visible: root.listed.length > 0
            width: 7 * 34
            spacing: 3
            topPadding: 4
            Rectangle { width: parent.width; height: 1; color: Theme.surface1 }
            Text {
                topPadding: 4
                text: "DEADLINES"
                color: Theme.accent
                font.family: Theme.font
                font.pixelSize: 11
                font.weight: Font.Bold
            }
            Repeater {
                model: root.listed.slice(0, 7)
                Row {
                    required property var modelData
                    spacing: 6
                    readonly property color tint: root.overdue(modelData) ? Theme.red : Theme.subtext0
                    Text {
                        width: 84
                        text: Qt.formatDate(modelData.day, "ddd d") + (modelData.time ? " " + modelData.time : "")
                        color: parent.tint
                        font.family: Theme.font
                        font.pixelSize: 11
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 5
                        height: 5
                        radius: 2.5
                        color: root.dotColor(modelData)
                    }
                    Text {
                        width: 7 * 34 - 84 - 5 - 12
                        elide: Text.ElideRight
                        text: (modelData.prio ? "!".repeat(modelData.prio) + " " : "") + modelData.text
                              + (modelData.every ? "  \u21bb" : "")
                        color: root.overdue(modelData) ? Theme.red : Theme.text
                        font.family: Theme.font
                        font.pixelSize: 11
                    }
                }
            }
            Text {
                visible: root.listed.length > 7
                text: "+ " + (root.listed.length - 7) + " more"
                color: Theme.overlay2
                font.family: Theme.font
                font.pixelSize: 10
            }
        }
    }
}
