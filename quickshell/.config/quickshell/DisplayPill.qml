// Displays: duplicate or extend onto an external monitor. Only shown while
// more than one monitor is connected.
//
//   click: menu (Duplicate · Extend, and where the external screen sits)
//   middle-click: duplicate <-> extend
//   `qs ipc call display toggle|cycle|menu` (cycle = SUPER+P: toggle + OSD), `qs ipc call display set mirror|extend|right|left|above|below`
//
// hypr/display-mode.py does the work and remembers the choice per monitor;
// on hotplug and config reload it puts the remembered layout back (`sync`).
// State and the script runs are shared by every bar: Displays.qml.
import QtQuick
import Quickshell
import Quickshell.Io

Pill {
    id: dp

    // the bar on the focused monitor owns the `display` IPC target
    property bool active: true

    readonly property int count: Displays.count
    readonly property string dir: Displays.dir
    readonly property var mons: Displays.mons
    readonly property bool mirror: Displays.mirror

    function toggleMenu() { dmenu.isOpen ? dmenu.close() : dmenu.open(dp); }

    shown: count > 1
    label: (mirror ? "\u{f1483}" : "\u{f037a}") + " " + (mirror ? "dup" : "ext")   // md-monitor_share / md-monitor_multiple
    fg: mirror ? Theme.crust : Theme.lavender
    bg: mirror ? Theme.lavender : "transparent"
    hoverFg: fg
    hoverBg: mirror ? Qt.lighter(Theme.lavender, 1.08) : Theme.alpha(Theme.surface0, 0.9)
    tip: {
        const dim = s => "<font color='" + Theme.overlay2 + "'>" + s + "</font>";
        let t = "<b>Displays</b>&nbsp;&nbsp;" + dim(mirror ? "duplicated" : "extended, external " + dir) + "<br>";
        for (const m of mons)
            t += "<br>" + (m.main ? "\u{f0322}" : "\u{f0379}") + " " + m.name + "&nbsp;&nbsp;"
               + dim((m.model ? m.model + " · " : "") + m.res + (m.hz ? "@" + m.hz : "")
                     + (m.mirrored ? " · mirroring" : m.disabled ? " · off" : ""));
        return t + "<br><br>" + dim("Click: menu · Middle-click: " + (mirror ? "extend" : "duplicate"));
    }

    onClicked: button => {
        if (button === Qt.MiddleButton) Displays.toggle();
        else if (button === Qt.LeftButton) toggleMenu();
    }

    IpcHandler {
        target: "display"
        enabled: dp.active
        function toggle(): void { Displays.toggle(); }
        // SUPER+P: toggle, with an OSD (also when there is nothing to switch)
        function cycle(): void { Displays.toggle(true); }
        function menu(): void { if (dp.count > 1) dp.toggleMenu(); }
        // mirror | extend | right | left | above | below (= extend that way)
        function set(layout: string): void {
            if (layout === "mirror" || layout === "extend") Displays.set(layout, layout === "extend" ? dp.dir : "");
            else Displays.set("extend", layout);
        }
    }

    MenuPopup {
        id: dmenu
        minWidth: 230

        MenuRow {
            header: true
            text: "DISPLAYS  ·  " + dp.count + " CONNECTED"
        }
        MenuRow {
            text: "Duplicate"
            check: dp.mirror ? 1 : 0
            onActivated: { dmenu.close(); Displays.set("mirror"); }
        }
        MenuRow {
            text: "Extend"
            check: dp.mirror ? 0 : 1
            onActivated: { dmenu.close(); Displays.set("extend", dp.dir); }
        }

        MenuRow { separator: true }
        MenuRow {
            header: true
            text: (Displays.externals.length > 1 ? "EXTERNAL SCREENS" : "EXTERNAL SCREEN") + " SITS"
        }
        Repeater {
            model: [["right", "To the right", "\u{f0054}"], ["left", "To the left", "\u{f004d}"],
                    ["above", "Above", "\u{f005d}"], ["below", "Below", "\u{f0045}"]]
            MenuRow {
                required property var modelData
                text: modelData[1]
                glyph: modelData[2]                       // md-arrow_*
                // the current side gets the check mark instead of its arrow
                check: !dp.mirror && dp.dir === modelData[0] ? 1 : -1
                onActivated: { dmenu.close(); Displays.set("extend", modelData[0]); }
            }
        }
    }
}
