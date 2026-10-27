// The accent clock pill. Click opens the calendar (CalendarPopup.qml:
// today, the month with task deadlines, the picked day's agenda);
// right-click toggles time / date (waybar's format-alt); scrolling over the
// clock pages the open calendar by month. (Was a hover card, CalendarCard.qml
// — kept, unused.)
import QtQuick
import Quickshell
import Quickshell.Io

Pill {
    id: clock

    property bool showDate: false

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
    tip: Qt.formatDate(sys.date, "dddd d MMMM yyyy")
         + PillClicks.hintLine("clock")

    pillId: "clock"                    // wheel: Settings › Pills
    onClicked: button => PillClicks.dispatch("clock", button, {
        calendar: () => cal.toggle(),
        date: () => { showDate = !showDate; },
        tasks: () => Quickshell.execDetached(["/usr/bin/python3", Theme.hypr + "/tasks.py", "toggle"])
    })
    // scroll: Settings › Pills (default: page the calendar while it is open)
    scrollTable: ({ month: dir => { if (cal.isOpen) cal.page(-dir); } })

    CalendarPopup {
        id: cal
        pill: clock
    }

    // keybind / testing hook, on the focused screen's bar only
    readonly property bool onActiveScreen: !!cal.anchor.window && !!cal.anchor.window.screen
                                           && cal.anchor.window.screen.name === BarState.active
    IpcHandler {
        target: "calendar"
        enabled: clock.onActiveScreen
        function toggle(): void { cal.toggle(); }
        function open(): void { cal.open(); }
        function close(): void { cal.close(); }
    }
}
