// The month card under the clock (Clock.qml). Monday first; today is a red
// pill (waybar's calendar had it red too); other months' days are dimmed.
import QtQuick

Rectangle {
    id: root

    property date today: new Date()
    property int monthOffset: 0

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
                    required property int index
                    readonly property date day: new Date(cal.shown.getFullYear(), cal.shown.getMonth(), index - grid.lead + 1)
                    readonly property bool inMonth: day.getMonth() === cal.shown.getMonth()
                    readonly property bool today: day.toDateString() === root.today.toDateString()
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
                }
            }
        }
    }
}
