// Bottom bar — replaces the second waybar (bottom.jsonc + bottom.css).
//
// left:   this laptop's player (+ a small spectrum while it plays), the
//         phone's player, "---" when neither has anything, the Spotify login
//         prompt, the players menu chevron
// centre: focus timer, weather (slides aside, or hides, when the sides
//         leave no room)
// right:  phone (KDE Connect), Tailscale | downloads (only while there are
//         any), tasks, keep-awake, power profile, wallpaper
//
// `qs ipc call bottombar toggle|open|close` (bottom-bar.sh) hides it;
// `qs ipc call bottombar menu phone|tailscale|focus` opens a pill's menu.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: bar

    property alias shown: state.shown
    PersistentProperties {
        id: state
        reloadableId: "bottomBarState"
        property bool shown: true
    }

    IpcHandler {
        target: "bottombar"
        function toggle(): void { bar.shown = !bar.shown; }
        function open(): void { bar.shown = true; }
        function close(): void { bar.shown = false; }
        // a pill's menu, for keybinds: phone | tailscale | focus
        function menu(name: string): void {
            const p = { phone: phonePill, tailscale: tsPill, focus: focusPill }[name];
            if (p) { bar.shown = true; p.toggleMenu(); }
        }
        // the focus timer, for keybinds: toggle | stop | skip
        function focus(cmd: string): void { focusPill.run([cmd || "toggle"]); }
    }

    visible: shown
    anchors { bottom: true; left: true; right: true }
    implicitHeight: Theme.islands ? 42 : 40
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "qs-bottombar"    // layerrule blur-qs-bars
    color: "transparent"

    Rectangle {
        anchors.fill: parent
        visible: !Theme.islands
        color: Theme.alpha(Theme.base, 0.80)
        Rectangle {
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: 1
            color: Theme.alpha(Theme.surface1, 0.7)
        }
    }

    // ── left: media ─────────────────────────────────────────────────────────
    Island {
        id: leftGroup
        x: Theme.islands ? 10 : 6
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        NowPlaying { id: local; scope: "local" }
        Visualizer {
            active: local.visible && local.playing
            tint: local.tint
        }
        Item { width: 6; height: 1; visible: local.visible && remote.visible }
        NowPlaying { id: remote; scope: "remote" }
        Visualizer {
            active: remote.visible && remote.playing
            fake: true
            tint: remote.tint
        }

        // Nothing playing anywhere: a faint, empty progress line — the "no
        // player is open" sign. Not clickable.
        Pill {
            shown: !local.visible && !remote.visible
            label: "---"
            fg: Theme.overlay0
            interactive: false
            padLeft: 6
            padRight: 6
            marginH: 0
            progress: 0
            tip: "Nothing playing"
            tipEdge: Edges.Top
        }

        ScriptPill {
            command: [Theme.hypr + "/spotify-remote.py", "status"]
            interval: 3000
            defaultFg: Theme.green
            colors: ({ login: Theme.overlay0, paused: Theme.subtext0 })
            padLeft: 12
            padRight: 12
            marginH: 2
            tipEdge: Edges.Top
            onLeft: Theme.hypr + "/spotify-remote.py login"
        }

        Pill {
            label: "\u{f0143}"                     // md-chevron_up
            fg: Theme.subtext0
            hoverFg: Theme.text
            hoverBg: Theme.alpha(Theme.surface0, 0.8)
            fontSize: 15
            padLeft: 8
            padRight: 8
            marginH: 2
            tip: "Players & now playing"
            tipEdge: Edges.Top
            onClicked: button => { if (button === Qt.LeftButton) Theme.exec(Theme.hypr + "/media-menu.sh"); }
        }
    }

    // ── centre: focus timer · weather ───────────────────────────────────────
    // Centred on the bar, but pushed aside by the side groups (two players
    // and a long wallpaper name can take most of the width), and hidden
    // when there is no room for it at all.
    Island {
        id: centreGroup
        readonly property real minX: leftGroup.x + leftGroup.width + 12
        readonly property real maxX: rightGroup.x - 12 - width
        x: Math.round(Math.max(minX, Math.min((bar.width - width) / 2, maxX)))
        visible: minX <= maxX
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        FocusPill { id: focusPill }

        // Open-Meteo; the script caches 15 min, so the 60 s poll is free
        ScriptPill {
            id: weather
            command: [Theme.hypr + "/weather.py", "status"]
            interval: 60000
            defaultFg: Theme.text
            colors: ({ unset: Theme.overlay0, error: Theme.overlay0, stale: Theme.subtext0,
                       rain: Theme.sapphire, sunny: Theme.yellow, night: Theme.lavender })
            padLeft: 10
            padRight: 12
            marginH: 2
            tipEdge: Edges.Top
            // click: fetch now; right-click: choose the place (fuzzel)
            onClicked: button => {
                if (button === Qt.LeftButton && !weatherFetch.running) weatherFetch.running = true;
                else if (button === Qt.RightButton && !weatherPlace.running) weatherPlace.running = true;
            }
            Process {
                id: weatherFetch
                command: [Theme.hypr + "/weather.py", "refresh"]
                onExited: weather.refresh()
            }
            Process {
                id: weatherPlace
                command: [Theme.hypr + "/weather.py", "locate"]
                onExited: weather.refresh()
            }
        }
    }

    // ── right ───────────────────────────────────────────────────────────────
    Row {
        id: rightGroup
        anchors.right: parent.right
        anchors.rightMargin: Theme.islands ? 10 : 6
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.islands ? 10 : 6

        // devices: the phone and the tailnet
        Island {
            anchors.verticalCenter: parent.verticalCenter
            visible: phonePill.shown || tsPill.shown
            spacing: 0

            PhonePill { id: phonePill }
            TailscalePill { id: tsPill }
        }

        Island {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 0

            // dl-popup downloads (aria2 + JDownloader), hidden when idle. The
            // ▰▱ meter is drawn as a real line under the text instead. (Moved
            // here from the top bar 2026-10-11.)
            ScriptPill {
                id: downloads
                command: [Theme.home + "/.local/bin/dl-popup", "bar"]
                interval: 2000
                textFilter: t => t.replace(/\s*[▰▱]+/, "")
                defaultFg: Theme.sapphire
                colors: ({ paused: Theme.subtext0 })
                defaultBg: Theme.alpha(Theme.surface0, 0.7)
                hoverFg: Theme.crust
                hoverBg: Theme.sapphire
                progress: json.percentage !== undefined && !hovered ? json.percentage / 100 : -1
                padLeft: 12
                padRight: 12
                marginH: 2
                tipEdge: Edges.Top
                onLeft: Theme.home + "/.local/bin/dl-popup status"
                onRight: Theme.home + "/.local/bin/dl-popup bar-toggle"
            }
            Item { width: 6; height: 1; visible: downloads.shown }

            ScriptPill {
                command: [Theme.hypr + "/tasks.py", "status"]
                interval: 2000
                colors: ({ pending: Theme.peach, "due-soon": Theme.yellow, overdue: Theme.red, clear: Theme.green, empty: Theme.overlay0, error: Theme.red })
                defaultBg: Theme.alpha(Theme.surface0, 0.7)
                hoverFg: Theme.crust
                hoverBg: Theme.accent
                padLeft: 14
                padRight: 14
                marginH: 2
                tipEdge: Edges.Top
                onLeft: Theme.hypr + "/tasks.py toggle"
                onRight: Theme.hypr + "/tasks.py quickadd"
            }

            // Keep the screen awake: a Wayland idle inhibitor, which hypridle
            // honours (the same protocol waybar's idle_inhibitor used).
            Pill {
                id: awake
                // kept across config reloads, like the bar's own shown state
                property alias on: awakeState.on
                PersistentProperties {
                    id: awakeState
                    reloadableId: "keepAwake"
                    property bool on: false
                }
                label: on ? "\u{f0176}" : "\u{f0faa}"
                fg: on ? Theme.crust : Theme.overlay0
                bg: on ? Theme.yellow : "transparent"
                hoverFg: on ? Theme.crust : Theme.text
                hoverBg: on ? Qt.lighter(Theme.yellow, 1.05) : Theme.alpha(Theme.surface0, 0.9)
                fontSize: 15
                padLeft: 10
                padRight: 10
                marginH: 2
                tip: on ? "Screen stays awake — click to allow sleep" : "Screen may sleep/lock — click to keep awake"
                tipEdge: Edges.Top
                onClicked: button => { if (button === Qt.LeftButton) on = !on; }

                IdleInhibitor {
                    window: bar
                    enabled: awake.on
                }
            }

            ScriptPill {
                command: [Theme.hypr + "/power-profile.sh", "status"]
                interval: 5000
                defaultFg: Theme.green
                colors: ({ balanced: Theme.blue, performance: Theme.crust })
                bgs: ({ performance: Theme.peach })
                padLeft: 10
                padRight: 10
                marginH: 2
                tipEdge: Edges.Top
                onLeft: Theme.hypr + "/power-profile.sh next"
            }

            ScriptPill {
                command: [Theme.hypr + "/wallpaper-control.sh", "status"]
                interval: 2000
                maxChars: 48
                defaultFg: Theme.lavender
                colors: ({ paused: Theme.overlay0 })
                defaultBg: Theme.alpha(Theme.surface0, 0.7)
                hoverFg: Theme.crust
                hoverBg: Theme.accent
                padLeft: 10
                padRight: 10
                marginH: 2
                tipEdge: Edges.Top
                onLeft: Theme.hypr + "/wallpaper-control.sh toggle"
                onRight: Theme.home + "/.local/bin/qs ipc call wallpicker toggle desktop"
            }
        }
    }
}
