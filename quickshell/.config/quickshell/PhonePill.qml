// The phone over KDE Connect (hypr/phone.py), as two pills with their own
// hover: battery / charging / signal, and how many notifications are
// waiting on it (accent; only while there are some).
//
//   phone:          click: the phone panel (PhonePopup: battery orb, ring ·
//                   ping · clipboard · send / browse files, the phone's
//                   notifications) · middle-click: ring
//   notifications:  click: the notification centre's Phone tab · right: panel
//
// Dim icon only while the phone is paired but out of reach; hidden when
// kdeconnectd isn't running or nothing is paired.
import QtQuick
import Quickshell
import Quickshell.Io

Row {
    id: root

    readonly property bool shown: phone.shown
    function toggleMenu() { phone.toggleMenu(); }

    visible: shown
    spacing: 0

    Pill {
        id: phone

        property var st: ({})
        readonly property bool up: st.reachable === true
        readonly property int batt: st.battery !== undefined ? st.battery : -1
        readonly property var notifs: st.notifs || []
        readonly property string script: Theme.hypr + "/phone.py"

        function run(args) { Theme.exec(script + " " + args); }
        function battGlyph() {
            if (st.charging) return "\u{f0084}";                       // md-battery_charging
            const g = ["\u{f007a}", "\u{f007b}", "\u{f007c}", "\u{f007d}", "\u{f007e}",
                       "\u{f007f}", "\u{f0080}", "\u{f0081}", "\u{f0082}", "\u{f0079}"];
            return g[Math.max(0, Math.min(9, Math.floor(batt / 10)))];
        }

        shown: st.paired === true
        label: !up ? "\u{f0950}"                                         // md-cellphone_off
             : "\u{f011c}" + (batt >= 0 ? " " + batt + "%" : "")
               + (st.charging ? " \u{f140b}" : "")                      // md-lightning_bolt
        fg: !up ? Theme.overlay0 : st.charging ? Theme.green : batt >= 0 && batt <= 15 ? Theme.red
            : batt >= 0 && batt <= 30 ? Theme.peach : Theme.sky
        fillHover: true
        padLeft: 10
        padRight: 10
        marginH: 2
        tipEdge: Edges.Top
        tip: {
            if (!up) return (st.name || "Phone") + " — not connected";
            const dim = s => "<font color='" + Theme.overlay2 + "'>" + s + "</font>";
            let t = "<b>" + st.name + "</b>";
            if (batt >= 0) t += "<br>" + battGlyph() + " " + batt + "%" + (st.charging ? ", charging" : "");
            if (st.signal >= 0) t += "<br>\u{f08be} " + (st.network || "Signal") + " " + "▂▄▆█".slice(0, Math.max(1, st.signal)) ;
            return t + "<br>" + dim(PillClicks.hint("phone"));
        }

        function toggleMenu() { menu.toggle(); }

        pillId: "phone"                    // wheel: Settings › Pills
        onClicked: button => {
            PillClicks.dispatch("phone", button, {
                panel: () => menu.toggle(),
                ring: () => { if (up) run("ring"); },
                notifs: () => BarState.panelRequested("notifications", "phone")
            });
        }

        Process {
            id: watcher
            running: true
            command: ["/usr/bin/python3", phone.script, "watch"]
            stdout: SplitParser {
                onRead: line => { try { phone.st = JSON.parse(line); } catch (e) {} }
            }
            onExited: again.restart()
        }
        Timer { id: again; interval: 5000; onTriggered: watcher.running = true }

        // the panel (PhonePopup.qml) — was a MenuPopup
        PhonePopup {
            id: menu
            pill: phone
            ph: phone
        }
    }

    // the phone's notification count
    Pill {
        id: notifPill
        readonly property var notifs: phone.notifs
        shown: phone.shown && phone.up && notifs.length > 0
        label: "\u{f009e} " + notifs.length                         // md-bell
        fg: Theme.accent
        fillHover: true
        padLeft: 9
        padRight: 10
        marginH: 2
        tipEdge: Edges.Top
        tip: {
            const dim = s => "<font color='" + Theme.overlay2 + "'>" + s + "</font>";
            let t = "<b>" + notifs.length + " notification" + (notifs.length > 1 ? "s" : "") + " on the phone</b>";
            for (const n of notifs.slice(0, 5))
                t += "<br>" + dim(n.app) + "&nbsp;&nbsp;" + n.title.replace(/</g, "&lt;");
            if (notifs.length > 5) t += "<br>" + dim("… " + (notifs.length - 5) + " more");
            return t + "<br>" + dim(PillClicks.hint("phonenotifs"));
        }
        pillId: "phonenotifs"                    // wheel: Settings › Pills
        onClicked: button => {
            PillClicks.dispatch("phonenotifs", button, {
                notifs: () => BarState.panelRequested("notifications", "phone"),
                panel: () => phone.toggleMenu()
            });
        }
        // its click opens the notification centre's Phone tab (a panel on
        // the top bar): here just a keyboard stop, Enter = that click
        PillStop { pill: notifPill }
    }
}
