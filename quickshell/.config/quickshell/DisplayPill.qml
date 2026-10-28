// Displays: duplicate or extend onto an external monitor. Only shown while
// more than one monitor is connected.
//
//   click: the displays panel (DisplayPopup.qml: Duplicate · Extend, where
//          the external screen sits, every monitor)
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

    function toggleMenu() { panel.toggle(); }

    // (demo: `qs ipc call display demo` shows pill + panel with a made-up screen)
    shown: count > 1 || panel.demo
    label: (mirror ? "\u{f1483}" : "\u{f037a}") + " " + (mirror ? "dup" : "ext")   // md-monitor_share / md-monitor_multiple
    fg: mirror ? Theme.crust : Theme.lavender
    bg: mirror ? Theme.lavender : "transparent"
    fillHover: true
    tip: {
        const dim = s => "<font color='" + Theme.overlay2 + "'>" + s + "</font>";
        let t = "<b>Displays</b>&nbsp;&nbsp;" + dim(mirror ? "duplicated" : "extended, external " + dir) + "<br>";
        for (const m of mons)
            t += "<br>" + (m.main ? "\u{f0322}" : "\u{f0379}") + " " + m.name + "&nbsp;&nbsp;"
               + dim((m.model ? m.model + " · " : "") + m.res + (m.hz ? "@" + m.hz : "")
                     + (m.mirrored ? " · mirroring" : m.disabled ? " · off" : ""));
        return t + "<br><br>" + dim(PillClicks.hint("display"));
    }

    pillId: "display"                    // wheel: Settings › Pills
    onClicked: button => {
        PillClicks.dispatch("display", button, {
            menu: () => toggleMenu(),
            toggle: () => Displays.toggle(),
            settings: () => BarState.panelRequested("settings", "display")
        });
    }

    IpcHandler {
        target: "display"
        enabled: dp.active
        function toggle(): void { Displays.toggle(); }
        // SUPER+P: toggle, with an OSD (also when there is nothing to switch)
        function cycle(): void { Displays.toggle(true); }
        function menu(): void { if (dp.count > 1 || panel.demo) dp.toggleMenu(); }
        // the panel with a made-up external screen (nothing changes)
        function demo(): void { panel.demo = true; Qt.callLater(panel.open); }
        // mirror | extend | right | left | above | below (= extend that way)
        function set(layout: string): void {
            if (layout === "mirror" || layout === "extend") Displays.set(layout, layout === "extend" ? dp.dir : "");
            else Displays.set("extend", layout);
        }
    }

    DisplayPopup {
        id: panel
        pill: dp
    }
}
