// The phone over KDE Connect (hypr/phone.py), as two pills with their own
// hover: battery / charging / signal, and how many notifications are
// waiting on it (accent; only while there are some).
//
//   phone:          click: menu (ring · send clipboard · send files · browse
//                   files · the phone's notifications) · middle-click: ring
//   notifications:  click: the notification centre's Phone tab · right: menu
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
            return t + "<br>" + dim("Click: menu · Middle-click: ring");
        }

        function toggleMenu() { menu.isOpen ? menu.close() : menu.open(phone); }

        onClicked: button => {
            if (button === Qt.MiddleButton && up) run("ring");
            else if (button !== Qt.MiddleButton) menu.isOpen ? menu.close() : menu.open(phone);
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

        MenuPopup {
            id: menu
            edge: Edges.Top
            minWidth: 250

            MenuRow {
                header: true
                text: (phone.st.name || "PHONE").toUpperCase()
                      + (phone.up && phone.batt >= 0 ? "  ·  " + phone.batt + "%" + (phone.st.charging ? " ⚡" : "") : phone.up ? "" : "  ·  OFFLINE")
            }
            MenuRow {
                text: "Ring phone"
                glyph: "\u{f11ab}"                          // md-phone_ring
                enabled: phone.up
                onActivated: { menu.close(); phone.run("ring"); }
            }
            MenuRow {
                text: "Send clipboard"
                glyph: "\u{f0cf9}"                          // md-clipboard_arrow_right
                enabled: phone.up
                onActivated: { menu.close(); phone.run("clip"); }
            }
            MenuRow {
                text: "Send files…"
                glyph: "\u{f022a}"                          // md-file_send
                enabled: phone.up
                onActivated: { menu.close(); phone.run("send"); }
            }
            MenuRow {
                text: "Browse phone files"
                glyph: "\u{f0770}"                          // md-folder_open
                enabled: phone.up
                onActivated: { menu.close(); phone.run("browse"); }
            }

            MenuRow { separator: true; visible: phone.notifs.length > 0 }
            MenuRow {
                header: true
                visible: phone.notifs.length > 0
                text: "NOTIFICATIONS  ·  " + phone.notifs.length
            }
            Repeater {
                model: phone.notifs.slice(0, 6)
                MenuRow {
                    required property var modelData
                    text: modelData.app + "  ·  " + modelData.title
                    glyph: "\u{f036a}"                      // md-message_text_outline
                    // the notification centre's Phone tab: reply, dismiss
                    onActivated: { menu.close(); Theme.exec("/usr/bin/python3 " + Theme.hypr + "/notif-center.py phone"); }
                }
            }
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
            return t + "<br>" + dim("Click: open them · Right-click: phone menu");
        }
        onClicked: button => {
            if (button === Qt.LeftButton) Theme.exec("/usr/bin/python3 " + Theme.hypr + "/notif-center.py phone");
            else if (button === Qt.RightButton) phone.toggleMenu();
        }
    }
}
