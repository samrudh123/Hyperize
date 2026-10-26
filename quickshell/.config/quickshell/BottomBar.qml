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

    // one per screen (shell.qml), all shown/hidden together; the focused
    // screen's owns the IPC target, the primary's runs the focus timer's
    // phase changes
    readonly property bool shown: BarState.bottomShown
    readonly property bool active: screen && screen.name === BarState.active
    readonly property bool primary: screen && screen.name === BarState.primary

    IpcHandler {
        target: "bottombar"
        enabled: bar.active
        function toggle(): void { BarState.bottomShown = !BarState.bottomShown; }
        function open(): void { BarState.bottomShown = true; }
        function close(): void { BarState.bottomShown = false; }
        // a pill's menu, for keybinds: phone | tailscale | focus
        function menu(name: string): void {
            const p = { phone: phonePill, tailscale: tsPill, focus: focusPill }[name];
            if (p) { BarState.bottomShown = true; p.toggleMenu(); }
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
    // The players' titles are cut short ("…") so the group ends left of
    // where the centre island wants to sit — two players (with ⇄ ⏮ ⏭ ⟲ each)
    // used to push the focus timer off centre, or off the bar. Shared fairly:
    // a short title keeps all of its width, the other gets the rest.
    readonly property real minTitle: 90
    readonly property real leftRoom: {
        const c = centreGroup;
        const want = Math.min((bar.width - c.width) / 2, rightGroup.x - 12 - c.width);
        return want - 12 - leftGroup.x;
    }
    // the left group's width without the two titles — summed from where
    // each part is heading, not from the laid-out widths (those lag a frame
    // behind and fed back into the titles: the row jittered and overlapped)
    readonly property real leftFixed: 2 * leftGroup.pad
        + (local.visible ? local.chromeWidth : 0) + visLocal.targetWidth
        + (local.visible && remote.visible ? 6 : 0)
        + (remote.visible ? remote.chromeWidth : 0) + visRemote.targetWidth
        + nothingPill.implicitWidth + spotifyLogin.implicitWidth + menuChevron.implicitWidth
    readonly property var titleWidths: {
        const a = local.visible ? local.naturalTextWidth : 0;
        const b = remote.visible ? remote.naturalTextWidth : 0;
        const room = Math.max(leftRoom - leftFixed,
                              (local.visible ? minTitle : 0) + (remote.visible ? minTitle : 0));
        if (a + b <= room) return [a, b];
        if (!remote.visible) return [room, 0];
        if (!local.visible) return [0, room];
        const half = room / 2;
        if (a <= half) return [a, room - a];
        if (b <= half) return [room - b, b];
        return [half, half];
    }

    Island {
        id: leftGroup
        x: Theme.islands ? 10 : 6
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        NowPlaying { id: local; scope: "local"; maxTextWidth: bar.titleWidths[0] }
        Visualizer {
            id: visLocal
            active: local.visible && local.playing
            tint: local.tint
        }
        Item { width: 6; height: 1; visible: local.visible && remote.visible }
        NowPlaying { id: remote; scope: "remote"; maxTextWidth: bar.titleWidths[1] }
        Visualizer {
            id: visRemote
            active: remote.visible && remote.playing
            fake: true
            tint: remote.tint
        }

        // Nothing playing anywhere: a faint, empty progress line — the "no
        // player is open" sign. Not clickable.
        Pill {
            id: nothingPill
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
            id: spotifyLogin
            command: [Theme.hypr + "/spotify-remote.py", "watch", "3"]
            interval: 0
            pokable: true
            defaultFg: Theme.green
            colors: ({ login: Theme.overlay0, paused: Theme.subtext0 })
            padLeft: 12
            padRight: 12
            marginH: 2
            tipEdge: Edges.Top
            onLeft: Theme.hypr + "/spotify-remote.py login"
        }

        Pill {
            id: menuChevron
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

        FocusPill { id: focusPill; primary: bar.primary }

        // Open-Meteo; the script caches 15 min, so the 60 s poll is free
        ScriptPill {
            id: weather
            command: [Theme.hypr + "/weather.py", "status"]
            interval: 60000
            // accent; grey only when there is no (fresh) data
            defaultFg: Theme.accent
            colors: ({ unset: Theme.overlay0, error: Theme.overlay0, stale: Theme.subtext0 })
            // hover fills the pill in its current colour with dark text
            hoverFg: Theme.crust
            hoverBg: fg
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
                // long-running: `bar` every 2 s in one process (pokable: a
                // click re-polls at once)
                command: [Theme.home + "/.local/bin/dl-popup", "watch", "2"]
                interval: 0
                pokable: true
                textFilter: t => t.replace(/\s*[▰▱]+/, "")
                defaultFg: Theme.sapphire
                colors: ({ paused: Theme.subtext0 })
                defaultBg: Theme.alpha(Theme.surface0, 0.7)
                // hover fills the pill in its text colour with dark text
                hoverFg: Theme.crust
                hoverBg: fg
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
                command: [Theme.hypr + "/tasks.py", "watch", "2"]
                interval: 0
                pokable: true
                colors: ({ pending: Theme.peach, "due-soon": Theme.yellow, overdue: Theme.red, clear: Theme.green, empty: Theme.overlay0, error: Theme.red })
                defaultBg: Theme.alpha(Theme.surface0, 0.7)
                // hover fills the pill in its text colour with dark text
                hoverFg: Theme.crust
                hoverBg: fg
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
                // shared by every screen's bar, kept across config reloads
                readonly property bool on: BarState.keepAwake
                label: on ? "\u{f0176}" : "\u{f0faa}"
                // accent icon either way (the glyph tells on from off); hover
                // fills the pill accent with a dark icon, like the power pill
                fg: Theme.accent
                hoverFg: Theme.crust
                hoverBg: Theme.accent
                fontSize: 15
                padLeft: 10
                padRight: 10
                marginH: 2
                tip: on ? "Screen stays awake — click to allow sleep" : "Screen may sleep/lock — click to keep awake"
                tipEdge: Edges.Top
                onClicked: button => { if (button === Qt.LeftButton) BarState.keepAwake = !on; }

                IdleInhibitor {
                    window: bar
                    enabled: awake.on
                }
            }

            ScriptPill {
                // long-running: a line per profile change (D-Bus), so a click
                // shows the new profile at once instead of at the next poll
                command: [Theme.hypr + "/power-profile.sh", "watch"]
                interval: 0
                defaultFg: Theme.green
                colors: ({ balanced: Theme.accent, performance: Theme.peach })
                // saver / balanced / performance: green / accent / orange
                // text; hover fills the pill in that colour with dark text
                hoverFg: Theme.crust
                hoverBg: fg
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
                defaultFg: Theme.accent
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
