// Bottom bar — replaces the second waybar (bottom.jsonc + bottom.css).
//
// left:   this laptop's player (+ a small spectrum while it plays), the
//         phone's player, "---" when neither has anything, the Spotify login
//         prompt, the ⌃ chevron: the players deck (PlayersPopup — SUPER+M)
// centre: focus timer, weather (slides aside, or hides, when the sides
//         leave no room)
// right:  phone (KDE Connect), Tailscale | downloads (only while there are
//         any), tasks, keep-awake, power profile, wallpaper
//
// `qs ipc call bottombar toggle|open|close` (bottom-bar.sh) hides it;
// `qs ipc call bottombar menu phone|tailscale|focus` opens a pill's menu;
// `qs ipc call players toggle|open|close` the players deck.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: bar

    // popups keep this bar live; presses on it are announced (BarState):
    // pills report their own (Pill.qml), this catches the empty bar — it is
    // UNDER everything, so it only ever gets presses nothing else took
    Component.onCompleted: BarState.addBar(bar)
    // keyboard navigation between popups (BarState.navPopup / startNav)
    function navRoot() { return BarState.rootOf(barBg); }
    readonly property bool isTopBar: false
    // Esc reaching the bar (pointer over one of its popups): close them
    Shortcut {
        sequences: ["Escape"]
        context: Qt.WindowShortcut
        onActivated: BarState.escapePressed()
    }
    // keyboard navigation inside / between popups (PanelPopup.navKey): only
    // while a popup is open, so the bar never takes these keys otherwise
    Repeater {
        // (Tab / Shift+Tab / Ctrl+Tab / Ctrl+Shift+Tab are the key sink's
        // below: as Shortcuts, "Shift+Tab", "Backtab" and "Shift+Backtab" all
        // matched one Shift+Tab press — ambiguous, so Qt fired none of them;
        // the Ctrl+Shift+Tab Shortcut had the same problem)
        model: [["Return", Qt.Key_Return, 0], ["Enter", Qt.Key_Enter, 0], ["Space", Qt.Key_Space, 0],
                ["Left", Qt.Key_Left, 0], ["Right", Qt.Key_Right, 0], ["Up", Qt.Key_Up, 0], ["Down", Qt.Key_Down, 0],
                ["Ctrl+Left", Qt.Key_Left, Qt.ControlModifier], ["Ctrl+Right", Qt.Key_Right, Qt.ControlModifier],
                ["Ctrl+Up", Qt.Key_Up, Qt.ControlModifier], ["Ctrl+Down", Qt.Key_Down, Qt.ControlModifier]]
        delegate: Item {
            id: navKeyItem
            required property var modelData
            // Space / Enter / plain arrows belong to a text box being typed in
            readonly property bool textKey: ["Return", "Enter", "Space", "Left", "Right", "Up", "Down"].includes(modelData[0])
            Shortcut {
                enabled: BarState.activePopup !== null
                         && !(navKeyItem.textKey && BarState.activePopup.textTarget)
                sequences: [navKeyItem.modelData[0]]
                context: Qt.WindowShortcut
                onActivated: if (BarState.activePopup) BarState.activePopup.navKey(navKeyItem.modelData[1], navKeyItem.modelData[2])
            }
        }
    }
    Component.onDestruction: BarState.removeBar(bar)
    // Keys reaching the bar while one of the bar popups is open (Hyprland
    // gives them to a bar, not the popup): text goes on to the popup's
    // focused text box (Keys.forwardTo), (Ctrl+)(Shift+)Tab / Esc are
    // handled here whatever form they arrive in (the Shortcuts above cover
    // the rest)
    Item {
        focus: true
        readonly property var target: BarState.activePopup && BarState.activePopup.isOpen ? BarState.activePopup : null
        Keys.forwardTo: target && target.textTarget ? [target.textTarget] : []
        Keys.onPressed: ev => {
            const p = target;
            if (!p) return;
            if (ev.modifiers & Qt.ControlModifier) {
                // Ctrl+Tab / Ctrl+Shift+Tab: the popup's menu tabs
                if (ev.key === Qt.Key_Tab || ev.key === Qt.Key_Backtab) {
                    BarState.tabPressed(ev.key === Qt.Key_Backtab || (ev.modifiers & Qt.ShiftModifier) ? -1 : 1);
                    ev.accepted = true;
                }
                return;
            }
            if (ev.key === Qt.Key_Escape) { p.close(); ev.accepted = true; }
            else if (ev.key === Qt.Key_Backtab || (ev.key === Qt.Key_Tab && (ev.modifiers & Qt.ShiftModifier)))
                ev.accepted = p.navKey(Qt.Key_Backtab, 0);
            else if (ev.key === Qt.Key_Tab) ev.accepted = p.navKey(Qt.Key_Tab, 0);
        }
    }
    MouseArea {
        id: barBg
        anchors.fill: parent
        z: -1000
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: ev => BarState.barPressed(BarState.rootOf(barBg), ev.x, ev.y)
        onWheel: ev => ev.accepted = false
    }

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
            else if (name === "downloads" && downloads.shown) { BarState.bottomShown = true; dlPop.toggle(); }
        }
        // the focus timer, for keybinds: toggle | stop | skip
        function focus(cmd: string): void { focusPill.run([cmd || "toggle"]); }
    }

    // keyboard stops on the pills without a popup (Ctrl+arrows land here;
    // Enter = click, Esc = out)
    PillStop { pill: awake }
    PillStop { pill: profilePill }
    PillStop { pill: wallPill }

    // the players deck: laptop | phone columns, each with its own controls
    PlayersPopup {
        id: playersPop
        pill: menuChevron
        npLocal: local
        npRemote: remote
    }
    function togglePlayers() {
        if (!BarState.bottomShown) BarState.bottomShown = true;
        playersPop.toggle();
    }
    IpcHandler {
        target: "players"
        enabled: bar.active
        function toggle(): void { bar.togglePlayers(); }
        function open(): void { BarState.bottomShown = true; playersPop.open(); }
        function close(): void { playersPop.close(); }
        // what clicking a column does: that side's music panel (local | remote)
        function panel(side: string): void { playersPop.openPanel(side === "remote" ? remote : local); }
    }
    Connections {
        target: BarState
        enabled: bar.active
        function onPanelRequested(name, arg) { if (name === "players") bar.togglePlayers(); }
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
        + (remote.visible ? remote.chromeWidth : 0)
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
        // no visualizer for the phone: its audio isn't here, and the made-up
        // one (Visualizer fake: true) redrew this bar ~20 times a second
        NowPlaying { id: remote; scope: "remote"; maxTextWidth: bar.titleWidths[1] }

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
            pillId: "spotify"
            onClicked: button => PillClicks.dispatch("spotify", button, {
                login: () => { Theme.exec(Theme.hypr + "/spotify-remote.py login"); spotifyLogin.poke(); }
            })
            // one action (log in, in a browser): a keyboard stop, no panel
            PillStop { pill: spotifyLogin }
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
            tip: "Players — laptop & phone  ·  SUPER+M" + PillClicks.hintLine("players")
            tipEdge: Edges.Top
            // what each button does on the bars' pills: PillClicks (Settings › Pills)
            pillId: "players"                    // wheel: Settings › Pills
            onClicked: button => PillClicks.dispatch("players", button, {
                deck: () => bar.togglePlayers(),
                pauseall: () => Theme.exec("playerctl -a pause")
            })
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
            // click: the weather panel (WeatherPopup.qml); right-click: choose
            // the place (fuzzel)
            pillId: "weather"
            onClicked: button => PillClicks.dispatch("weather", button, {
                panel: () => weatherPop.toggle(),
                place: () => { if (!weatherPlace.running) weatherPlace.running = true; },
                refresh: () => { if (!weatherFetch.running) weatherFetch.running = true; }
            })
            WeatherPopup { id: weatherPop; pill: weather; pillRef: weather }
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
                // idle (nothing downloading): just the download glyph, dimmed —
                // the pill stays, so the panel (finished ones too) is a click away
                readonly property bool idle: rawText === "" || classes.includes("hidden") || classes.includes("idle")
                textFilter: t => idle ? "\u{f01da}" : t.replace(/\s*[▰▱]+/, "")
                defaultFg: idle ? Theme.overlay1 : Theme.sapphire
                colors: ({ paused: Theme.subtext0 })
                // hover fills the pill in its text colour with dark text
                hoverFg: Theme.crust
                hoverBg: fg
                progress: json.percentage !== undefined && !hovered ? json.percentage / 100 : -1
                padLeft: 12
                padRight: 12
                marginH: 2
                tipEdge: Edges.Top
                // always on the bar (idle: the glyph); was: only while downloading
                shown: true
                pillId: "downloads"
                onClicked: button => PillClicks.dispatch("downloads", button, {
                    menu: () => dlPop.toggle(),
                    fuzzel: () => { Theme.exec(Theme.home + "/.local/bin/dl-popup status"); downloads.poke(); },
                    pause: () => { Theme.exec(Theme.home + "/.local/bin/dl-popup bar-toggle"); downloads.poke(); }
                })

                // the downloads panel (DownloadsPopup.qml)
                DownloadsPopup {
                    id: dlPop
                    pill: downloads
                    scriptPill: downloads
                }
                // a new download from the browser (DownloadAskPopup.qml,
                // `dl-popup add` → `ask PATH`)
                DownloadAskPopup {
                    id: askPop
                    pill: downloads
                }
                IpcHandler {
                    target: "downloads"
                    enabled: bar.active
                    function toggle(): void { BarState.bottomShown = true; dlPop.toggle(); }
                    function open(): void { BarState.bottomShown = true; dlPop.open(); }
                    function close(): void { dlPop.close(); }
                    // sample cards (nothing real happens), to see the panel idle
                    function demo(): void { BarState.bottomShown = true; dlPop.demo = true; Qt.callLater(dlPop.open); }
                    // dl-popup add: show the new-download panel for the request
                    // in PATH (answer → PATH.reply)
                    function ask(path: string): string { BarState.bottomShown = true; askPop.ask(path); return "ok"; }
                    // close it unanswered (= cancel)
                    function dismiss(): void { askPop.close(); }
                    // the request the panel is answering ("" = none), so
                    // dl-popup can tell a reload / crash lost its popup
                    function asking(): string { return askPop.reqPath; }
                }
            }
            Item { width: 6; height: 1; visible: downloads.shown }

            // Tasks: click = the tasks panel (TasksPopup.qml — the whole
            // panel: tasks, done, the day's log, history), right-click = the
            // same with "new task" focused. `qs ipc call tasks toggle|open|add|close`
            // (SUPER+T and reminders' "Open tasks" go through `tasks.py toggle`,
            // which calls this; the GTK panel only stands in when the shell is down).
            ScriptPill {
                id: tasksPill
                command: [Theme.hypr + "/tasks.py", "watch", "2"]
                interval: 0
                pokable: true
                colors: ({ pending: Theme.peach, "due-soon": Theme.yellow, overdue: Theme.red, clear: Theme.green, empty: Theme.overlay0, error: Theme.red })
                // hover fills the pill in its text colour with dark text
                hoverFg: Theme.crust
                hoverBg: fg
                padLeft: 14
                padRight: 14
                marginH: 2
                tipEdge: Edges.Top
                pillId: "tasks"
                onClicked: button => PillClicks.dispatch("tasks", button, {
                    panel: () => tasksPop.toggle(),
                    add: () => { tasksPop.open(); tasksPop.focusAdd(); }
                })

                TasksPopup {
                    id: tasksPop
                    pill: tasksPill
                    scriptPill: tasksPill
                }
                IpcHandler {
                    target: "tasks"
                    enabled: bar.active
                    function toggle(): void { BarState.bottomShown = true; tasksPop.toggle(); }
                    function open(): void { BarState.bottomShown = true; tasksPop.open(); }
                    function add(): void { BarState.bottomShown = true; tasksPop.open(); tasksPop.focusAdd(); }
                    function close(): void { tasksPop.close(); }
                    // tasks | done | log | history
                    function tab(name: string): void { BarState.bottomShown = true; tasksPop.open(); tasksPop.showTab(name); }
                }
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
                tip: (on ? "Screen stays awake" : "Screen may sleep / lock") + PillClicks.hintLine("awake")
                tipEdge: Edges.Top
                pillId: "awake"                    // wheel: Settings › Pills
                onClicked: button => PillClicks.dispatch("awake", button, { toggle: () => BarState.keepAwake = !on })

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
                colors: ({ balanced: Theme.blue, performance: Theme.peach })
                // saver / balanced / performance: green / blue / orange
                // text; hover fills the pill in that colour with dark text
                hoverFg: Theme.crust
                hoverBg: fg
                padLeft: 10
                padRight: 10
                marginH: 2
                tipEdge: Edges.Top
                id: profilePill
                pillId: "profile"
                onClicked: button => PillClicks.dispatch("profile", button, {
                    next: () => { Theme.exec(Theme.hypr + "/power-profile.sh next"); profilePill.poke(); },
                    battery: () => Theme.exec(Theme.home + "/.local/bin/qs ipc call sysinfo toggle battery")
                })
            }

            ScriptPill {
                command: [Theme.hypr + "/wallpaper-control.sh", "status"]
                interval: 2000
                maxChars: 48
                defaultFg: Theme.accent
                colors: ({ paused: Theme.overlay0 })
                hoverFg: Theme.crust
                hoverBg: Theme.accent
                padLeft: 10
                padRight: 10
                marginH: 2
                tipEdge: Edges.Top
                id: wallPill
                pillId: "wallpaper"
                onClicked: button => PillClicks.dispatch("wallpaper", button, {
                    toggle: () => { Theme.exec(Theme.hypr + "/wallpaper-control.sh toggle"); wallPill.poke(); },
                    picker: () => Theme.exec(Theme.home + "/.local/bin/qs ipc call wallpicker toggle desktop")
                })
            }
        }
    }
}
