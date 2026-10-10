// The accent clock pill. Click toggles time / date (waybar's format-alt);
// hovering opens a month calendar card, and scrolling over the clock pages
// it by month (waybar's shift_up / shift_down). Today is red, as before.
import QtQuick
import Quickshell

Pill {
    id: clock

    property bool showDate: false
    property int monthOffset: 0

    SystemClock {
        id: sys
        precision: SystemClock.Minutes
    }

    label: showDate ? "\u{f00ed} " + Qt.formatDate(sys.date, "ddd dd MMM")
                    : "\u{f0954} " + Qt.formatTime(sys.date, "HH:mm")
    fg: Theme.crust
    bg: Theme.accent
    hoverBg: Qt.lighter(Theme.accent, 1.08)
    fontWeight: Font.Bold

    onClicked: button => { if (button === Qt.LeftButton) showDate = !showDate; }
    onScrolled: dir => monthOffset -= dir
    onHoveredChanged: if (!hovered) resetTimer.restart()

    Timer {
        id: resetTimer
        interval: 1500
        onTriggered: if (!clock.hovered) clock.monthOffset = 0
    }

    PopupWindow {
        id: card

        property bool open: false
        visible: open
        color: "transparent"
        anchor.item: clock
        anchor.rect.x: clock.width - 1
        anchor.rect.y: clock.height + 6
        anchor.gravity: Edges.Bottom | Edges.Left
        implicitWidth: calCard.implicitWidth
        implicitHeight: calCard.implicitHeight

        Timer {
            interval: 350
            running: clock.hovered
            onTriggered: card.open = true
        }
        Connections {
            target: clock
            function onHoveredChanged() { if (!clock.hovered) card.open = false; }
        }

        CalendarCard {
            id: calCard
            anchors.fill: parent
            today: sys.date
            monthOffset: clock.monthOffset
        }
    }
}
