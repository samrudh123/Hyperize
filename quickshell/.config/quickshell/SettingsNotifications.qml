// Settings › Notifications: do not disturb (notif-center.py dnd = mako's
// do-not-disturb mode, state in ~/.local/state/notif-center/dnd) and the
// notification panels.
import QtQuick
import Quickshell
import Quickshell.Io

SettingsPage {
    id: page
    title: "Notifications"
    subtitle: "Popups, do not disturb, history."

    property bool dnd: false
    property int count: 0
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || Theme.home + "/.local/state") + "/notif-center"

    Process {
        id: check
        running: true
        command: ["sh", "-c", "[ -e \"$1/dnd\" ] && echo on || echo off; python3 -c 'import json,sys;print(len(json.load(open(sys.argv[1]))))' \"$1/history.json\" 2>/dev/null || echo 0", "sh", page.stateDir]
        stdout: StdioCollector {
            onStreamFinished: {
                const l = text.trim().split("\n");
                page.dnd = l[0] === "on";
                page.count = Number(l[1]) || 0;
            }
        }
    }
    Process {
        id: setDnd
        onExited: check.running = true
    }

    SettingsCard {
        title: "Alerts"
        icon: "\u{f009a}"
        SettingsRow {
            icon: page.dnd ? "\u{f009b}" : "\u{f009e}"
            iconColor: page.dnd ? Theme.overlay1 : Theme.accent
            title: "Do not disturb"
            subtitle: page.dnd ? "On — popups are hidden, they still land in the history" : "Off — notifications pop up (right-click the bell toggles this too)"
            keywords: "dnd silent quiet focus mute"
            Toggle {
                anchors.verticalCenter: parent.verticalCenter
                checked: page.dnd
                onToggled: v => {
                    page.dnd = v;
                    setDnd.command = ["/usr/bin/python3", Theme.hypr + "/notif-center.py", "dnd", v ? "on" : "off"];
                    setDnd.running = true;
                }
            }
        }
        SettingsRow {
            icon: "\u{f02da}"
            title: "Notification history"
            subtitle: page.count + " saved  ·  the bell in the top bar (SUPER+N)"
            keywords: "history centre center log"
            IconBtn {
                text: "Open"
                icon: "\u{f03cc}"
                onClicked: BarState.panelRequested("notifications", "system")
            }
        }
        SettingsRow {
            icon: "\u{f011c}"
            title: "Phone notifications"
            subtitle: "Mirrored from the phone over KDE Connect"
            keywords: "android kde connect"
            last: true
            IconBtn {
                text: "Open"
                icon: "\u{f03cc}"
                onClicked: BarState.panelRequested("notifications", "phone")
            }
        }
    }

    SettingsCard {
        title: "Popups"
        icon: "\u{f0493}"
        SettingsRow {
            icon: "\u{f0493}"
            title: "Popup style"
            subtitle: "Popups are drawn by mako — position, size and timeouts in ~/.config/mako/config "
                    + "(a themed file: saving re-derives its template and reloads mako)"
            keywords: "mako timeout position"
            IconBtn {
                text: "Edit config"
                icon: "\u{f03eb}"
                // the live file is a set-accent / theme template: after editing,
                // --resync carries the edit into the template (else the next
                // accent or theme change would undo it), then mako reloads
                onClicked: {
                    SettingsState.closeRequested();
                    Quickshell.execDetached(["ghostty", "--gtk-single-instance=false", "-e", "sh", "-c",
                        "nvim \"$HOME/.config/mako/config\"; \"$HOME/.config/hypr/set-accent.sh\" --resync >/dev/null 2>&1; makoctl reload"]);
                }
            }
        }
        SettingsRow {
            icon: "\u{f0450}"
            title: "Dismiss all popups"
            subtitle: "Clear whatever is on screen right now"
            keywords: "clear dismiss"
            last: true
            IconBtn {
                text: "Dismiss"
                icon: "\u{f0156}"
                onClicked: Theme.exec("makoctl dismiss --all")
            }
        }
    }
}
