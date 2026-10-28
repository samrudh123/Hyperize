// Top bar — replaces waybar (config.jsonc + style.css). Same geometry
// (full width × 40, one continuous panel edge to edge, 1px line underneath) and
// the same modules in the same places; the popups positioned under it
// (notif-center, network-panel, tasks…) still line up.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower

PanelWindow {
    id: bar

    // popups keep this bar live; presses on it are announced (BarState):
    // pills report their own (Pill.qml), this catches the empty bar — it is
    // UNDER everything, so it only ever gets presses nothing else took
    Component.onCompleted: BarState.addBar(bar)
    // keyboard navigation between popups (BarState.navPopup / startNav)
    function navRoot() { return BarState.rootOf(barBg); }
    readonly property bool isTopBar: true
    // Esc reaching the bar (pointer over one of its popups): close them
    Shortcut {
        sequences: ["Escape"]
        context: Qt.WindowShortcut
        onActivated: BarState.escapePressed()
    }
    Shortcut {
        sequences: ["Ctrl+Tab"]
        context: Qt.WindowShortcut
        onActivated: BarState.tabPressed(1)
    }
    Shortcut {
        sequences: ["Ctrl+Shift+Tab", "Ctrl+Backtab", "Ctrl+Shift+Backtab"]
        context: Qt.WindowShortcut
        onActivated: BarState.tabPressed(-1)
    }
    // keyboard navigation inside / between popups (PanelPopup.navKey): only
    // while a popup is open, so the bar never takes these keys otherwise
    Repeater {
        // (Tab / Shift+Tab are the key sink's below: as Shortcuts, "Shift+Tab",
        // "Backtab" and "Shift+Backtab" all matched one Shift+Tab press —
        // ambiguous, so Qt fired none of them)
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
    // focused text box (Keys.forwardTo), Shift+Tab / Esc are handled here
    // whatever form they arrive in (the Shortcuts above cover the rest)
    Item {
        focus: true
        readonly property var target: BarState.activePopup && BarState.activePopup.isOpen ? BarState.activePopup : null
        Keys.forwardTo: target && target.textTarget ? [target.textTarget] : []
        Keys.onPressed: ev => {
            const p = target;
            if (!p) return;
            if (ev.modifiers & Qt.ControlModifier) return;      // Ctrl+Tab: the Shortcuts
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

    // one per screen (shell.qml); the focused screen's owns the IPC targets
    readonly property bool active: screen && screen.name === BarState.active

    anchors { top: true; left: true; right: true }
    // islands: the groups float 4 px below the screen edge (Island.qml)
    implicitHeight: Theme.islands ? 42 : 40
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "qs-bar"          // layerrule blur-qs-bars
    color: "transparent"

    Rectangle {
        anchors.fill: parent
        visible: !Theme.islands
        color: Theme.alpha(Theme.base, 0.80)
        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 1
            color: Theme.alpha(Theme.surface1, 0.7)
        }
    }

    // ── left ────────────────────────────────────────────────────────────────
    // mirrors the right: launcher · workspaces | system (cpu, memory, temp)
    Row {
        id: left
        x: Theme.islands ? 10 : 6
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.islands ? 10 : 0

        Island {
        // The app grid (SUPER+D); right-click = fuzzel, to run by name.
        Pill {
            label: "\u{f003b}"
            fg: Theme.accent
            bg: Theme.alpha(Theme.surface0, 0.7)
            hoverFg: Theme.crust
            hoverBg: Theme.accent
            fontSize: 15
            padLeft: 10
            padRight: 11
            marginH: 2
            tip: "Apps" + PillClicks.hintLine("apps")
            // what each button does: PillClicks (Settings › Pills)
            pillId: "apps"                    // wheel: Settings › Pills
            onClicked: button => PillClicks.dispatch("apps", button, {
                grid: () => Theme.exec(Theme.hypr + "/app-grid.sh"),
                run: () => Theme.exec("fuzzel")
            })
        }

        Item { width: 4; height: 1 }

        Workspaces {}

        Item { width: 6; height: 1 }

        // screenshots + recording (wf-recorder / OBS)
        RecordPill {}

        // clipboard history (cliphist)
        Pill {
            id: clipPill
            label: "\u{f0a38}"                     // md-clipboard_text_outline
            fg: Theme.accent                        // follows SUPER+ALT+C (was peach)
            fontSize: 15
            padLeft: 9
            fillHover: true
            padRight: 10
            tip: clipboard.isOpen ? "" : "Clipboard history" + PillClicks.hintLine("clipboard")
            pillId: "clipboard"                    // wheel: Settings › Pills
            onClicked: button => PillClicks.dispatch("clipboard", button, { panel: () => clipboard.toggle() })
        }

        Pill {
            id: submap
            property string name: ""
            shown: name !== ""
            label: "\u{f030c} " + name
            fg: Theme.peach
            interactive: false
            padLeft: 10
            padRight: 10
            Connections {
                target: Hyprland
                function onRawEvent(event) {
                    if (event.name === "submap") submap.name = event.data;
                }
            }
        }
        }

        Island {
        // CPU / memory / temperature: click = their panel (SysPopup.qml),
        // right-click = btop
        Pill {
            id: cpuPill
            label: "\u{f0ee0} " + Stats.cpu + "%"
            fg: Theme.green
            fillHover: true
            // per-core usage, four to a line (22 cores)
            tip: {
                const rows = [];
                const c = Stats.cores;
                for (let i = 0; i < c.length; i += 4)
                    rows.push(c.slice(i, i + 4).map((v, j) => String(i + j).padStart(2) + " " + String(v).padStart(3) + "%").join("   "));
                return "<b>CPU " + Stats.cpu + "%</b>  ·  load " + Stats.load
                     + "<br><font color='" + Theme.overlay2 + "'><pre>" + rows.join("<br>") + "</pre></font>"
                     + "<font color='" + Theme.overlay2 + "'>" + PillClicks.hint("cpu") + "</font>";
            }
            pillId: "cpu"                    // wheel: Settings › Pills
            onClicked: button => PillClicks.dispatch("cpu", button, {
                panel: () => bar.openSys("cpu"),
                btop: () => Theme.exec("ghostty -e btop"),
                resources: () => Theme.exec("resources --open-tab-id cpu")
            })
        }

        Pill {
            id: memPill
            label: "\u{f035b} " + Stats.memPct + "%"
            fg: Theme.teal
            fillHover: true
            tip: Stats.memUsedGiB.toFixed(1) + " GiB / " + Stats.memTotalGiB.toFixed(1) + " GiB"
                 + PillClicks.hintLine("mem")
            pillId: "mem"                    // wheel: Settings › Pills
            onClicked: button => PillClicks.dispatch("mem", button, {
                panel: () => bar.openSys("mem"),
                btop: () => Theme.exec("ghostty -e btop"),
                resources: () => Theme.exec("resources --open-tab-id memory")
            })
        }

        Pill {
            id: tempPill
            readonly property bool critical: Stats.tempC >= Stats.tempCritical
            label: (Stats.tempC < 50 ? "\u{f10c3}" : Stats.tempC < 75 ? "\u{f050f}" : "\u{f10c2}") + " " + Stats.tempC + "°"
            // the panel's heat scale: sapphire · yellow ≥60 · peach ≥70 · red (filled) ≥82
            fg: critical ? Theme.crust : Stats.tempColor(Stats.tempC)
            bg: critical ? Theme.red : "transparent"
            fillHover: true
            tip: "CPU temperature " + Stats.tempC + " °C"
                 + PillClicks.hintLine("temp")
            pillId: "temp"                    // wheel: Settings › Pills
            onClicked: button => PillClicks.dispatch("temp", button, {
                panel: () => bar.openSys("temp"),
                btop: () => Theme.exec("ghostty -e btop"),
                resources: () => Theme.exec("resources --open-tab-id cpu")
            })
        }
        }
    }

    // ── centre: the focused window's state and title ────────────────────────
    // (in its own island, in the islands style)
    //
    // Floating / pinned / fullscreen come from Hyprland's client JSON, which
    // quickshell only fetches on demand: refresh it when any of them changes.
    // Hyprland re-sends activewindowv2 on every TITLE change of the focused
    // window too (a terminal's spinner: several a second) — only a focus
    // change to another window needs the JSON again.
    property string lastActive: ""
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "activewindowv2") {
                if (event.data === bar.lastActive)
                    return;
                bar.lastActive = event.data;
            }
            if (["activewindowv2", "openwindow", "changefloatingmode", "fullscreen", "pin"].includes(event.name))
                ipcRefresh.restart();
        }
    }
    Timer {
        id: ipcRefresh
        interval: 50
        onTriggered: Hyprland.refreshToplevels()
    }

    Rectangle {
        visible: Theme.islands && title.valid
        x: centre.x - 4
        width: centre.width + 4 + 16
        anchors.verticalCenter: parent.verticalCenter
        height: 34
        radius: 12
        color: Theme.alpha(Theme.base, 0.86)
        border.width: 1
        border.color: Theme.alpha(Theme.surface1, 0.8)
    }

    Row {
        id: centre
        anchors.centerIn: parent
        spacing: 2
        opacity: title.valid ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.fast } }

        // tiled / floating / maximised / fullscreen, plus a pin when pinned.
        // Click floats/tiles, right-click pins (floating it first: Hyprland
        // pins floating windows only), middle-click fullscreens.
        Pill {
            id: winState
            readonly property var win: title.win
            readonly property var ipc: title.valid && win ? win.lastIpcObject : ({})
            readonly property bool floating: !!ipc.floating
            readonly property bool pinned: !!ipc.pinned
            readonly property int fs: ipc.fullscreen || 0        // 1 maximised, 2 fullscreen
            readonly property string addr: title.valid && win ? "address:0x" + win.address : ""

            shown: title.valid
            label: (fs >= 2 ? "\u{f0293}" : fs === 1 ? "\u{f05af}" : floating ? "\u{f10ac}" : "\u{f0574}")
                 + (pinned ? " \u{f0403}" : "")
            fg: fs > 0 ? Theme.peach : pinned ? Theme.yellow : floating ? Theme.accent : Theme.overlay1
            fillHover: true
            fontSize: 14
            padLeft: 7
            padRight: 7
            tip: (fs >= 2 ? "Fullscreen" : fs === 1 ? "Maximised" : floating ? "Floating" : "Tiled") + (pinned ? " · pinned" : "")
                 + PillClicks.hintLine("window")
            pillId: "window"                    // wheel: Settings › Pills
            onClicked: button => {
                if (!title.valid) return;
                PillClicks.dispatch("window", button, {
                    float: () => Hyprland.dispatch("togglefloating " + addr),
                    pin: () => {
                        if (!floating) Hyprland.dispatch("setfloating " + addr);
                        Hyprland.dispatch("pin " + addr);
                    },
                    fullscreen: () => { Hyprland.dispatch("focuswindow " + addr); Hyprland.dispatch("fullscreen 0"); },
                    maximise: () => { Hyprland.dispatch("focuswindow " + addr); Hyprland.dispatch("fullscreen 1"); },
                    close: () => Hyprland.dispatch("closewindow " + addr),
                    panel: () => winPop.toggle()
                });
            }
            // the window panel (WindowPopup.qml): float, pin, size, move, close
            WindowPopup { id: winPop; pill: winState }
        }

        Text {
            id: title
            readonly property var win: Hyprland.activeToplevel
            readonly property bool valid: !!win && win.workspace === Hyprland.focusedWorkspace
            readonly property string raw: valid ? win.title : ""
            readonly property string rewritten: {
                let m;
                if ((m = /^(.*) — Mozilla Firefox$/.exec(raw))) return "\u{f0239}  " + m[1];
                if ((m = /^(?:(.*) — )?Zen Browser$/.exec(raw))) return "\u{f05dd}  " + (m[1] || "Zen");   // md-bullseye ≈ Zen's rings
                if (/Ghostty$/.test(raw)) return "\u{f02a0}  terminal";
                if ((m = /^(.*) - Visual Studio Code$/.exec(raw))) return "\u{f0a1e}  " + m[1];
                return raw;
            }
            anchors.verticalCenter: parent.verticalCenter
            // The group is centred on the bar, so it can only grow as far as
            // the NEARER side group allows (the right one, in practice), less
            // the island's padding and a 12 px gap on each side.
            readonly property real maxWidth: 2 * Math.min(bar.width / 2 - (left.x + left.width),
                                                          bar.width / 2 - (right.width + right.anchors.rightMargin))
                                             - 2 * (16 + 12) - winState.width - centre.spacing
            width: Math.max(0, Math.min(implicitWidth, maxWidth))
            text: rewritten.length > 55 ? rewritten.slice(0, 54) + "…" : rewritten
            elide: Text.ElideRight
            color: Theme.subtext0
            font.family: Theme.font
            font.pixelSize: 13
            font.weight: Font.Medium
        }
    }

    // ── right ───────────────────────────────────────────────────────────────
    // two islands in the islands style: status | clock & session
    Row {
        id: right
        anchors.right: parent.right
        anchors.rightMargin: Theme.islands ? 10 : 6
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.islands ? 10 : 0

        Island {
        Tray {}

        // Audio: the default sink. Click opens the audio panel (AudioPopup),
        // right-click mutes, scroll ±5 %.
        Pill {
            id: audio
            readonly property var sink: Pipewire.defaultAudioSink
            readonly property bool ok: sink !== null && sink.audio !== null
            readonly property int pct: ok ? Math.round(sink.audio.volume * 100) : 0
            readonly property bool muted: ok && sink.audio.muted
            // the headphones — also bt-follow.py's silent stand-in for them
            // while the phone has them (node bt-follow-hold)
            readonly property bool bt: sink !== null && ((sink.name || "").startsWith("bluez") || sink.name === "bt-follow-hold")

            PwObjectTracker { objects: [audio.sink] }

            label: muted ? "\u{f075f} muted"
                 : (bt ? "\u{f00af}" : pct < 34 ? "\u{f057f}" : pct < 67 ? "\u{f0580}" : "\u{f057e}") + " " + pct + "%"
            fg: muted ? Theme.overlay0 : Theme.pink
            fillHover: true
            tip: ok ? (sink.description || sink.name) + "  ·  " + (muted ? "muted" : pct + "%")
                      + "<br><font color='" + Theme.overlay2 + "'>" + [PillClicks.hint("audio"), "Scroll: volume"].filter(x => x).join(" · ") + "</font>" : ""
            pillId: "audio"                    // wheel: Settings › Pills
            onClicked: button => PillClicks.dispatch("audio", button, {
                panel: () => audioPop.toggle(),
                mute: () => { if (ok) sink.audio.muted = !sink.audio.muted; },
                mixer: () => Theme.exec("pavucontrol")
            })
            // scroll: Settings › Pills (default: volume ±5 %)
        }

        MicPill { id: micPill }

        // Brightness, and the night light (night-light.sh): right-click
        // toggles it, middle-click cycles 4500 / 3500 / 2700 K. While it is
        // on the icon is a moon and the pill turns peach.
        Pill {
            id: brightnessPill
            readonly property var night: (nightFile.text() || "off 3500").trim().split(/\s+/)
            readonly property bool nightOn: night[0] === "on"
            label: (nightOn ? "\u{f0594} " : "\u{f06e8} ") + Stats.brightness + "%"
            fg: nightOn ? Theme.peach : Theme.yellow
            fillHover: true
            tip: "Screen brightness " + Stats.brightness + "%"
                 + (nightOn ? "<br>\u{f0594} Night light on, " + night[1] + " K" : "")
                 + "<br><font color='" + Theme.overlay2 + "'>" + [PillClicks.hint("brightness"), "Scroll: ±5 %"].filter(x => x).join(" · ") + "</font>"
            pillId: "brightness"                    // wheel: Settings › Pills
            onClicked: button => PillClicks.dispatch("brightness", button, {
                panel: () => brightPop.toggle(),
                night: () => Theme.exec(Theme.hypr + "/night-light.sh toggle"),
                nightcycle: () => Theme.exec(Theme.hypr + "/night-light.sh cycle"),
                half: () => { Theme.exec(Theme.hypr + "/brightness.sh set 50"); Stats.refreshBacklight(); }
            })

            FileView {
                id: nightFile
                path: Theme.hypr + "/night-light"
                watchChanges: true
                printErrors: false
                onFileChanged: reload()
            }
            // scroll: Settings › Pills (default: brightness ±5 %)
        }

        // duplicate / extend: only while an external monitor is connected
        DisplayPill { active: bar.active }

        Pill {
            id: netPill
            readonly property string kind: Stats.netKind === "wifi" && !Stats.ipaddr ? "linked" : Stats.netKind
            label: kind === "wifi" ? "\u{f0928} " + Stats.signal + "%"
                 : kind === "wired" ? "\u{f0200} wired"
                 : kind === "linked" ? "\u{f092b} no IP" : "\u{f092d} offline"
            fg: kind === "offline" ? Theme.red : Theme.accent
            fillHover: true
            tip: (kind === "wifi" ? Stats.essid + "  ·  " + Stats.ipaddr + "<br>\u{f01da} " + Stats.bits(Stats.rxBps) + "   \u{f0552} " + Stats.bits(Stats.txBps)
               : kind === "wired" ? Stats.ifname + "  ·  " + Stats.ipaddr
               : kind === "linked" ? Stats.essid + "  ·  no address yet" : "Offline")
               + PillClicks.hintLine("network")
            pillId: "network"                    // wheel: Settings › Pills
            onClicked: button => PillClicks.dispatch("network", button, {
                panel: () => bar.openNet("wifi"),
                editor: () => Theme.exec("nm-connection-editor"),
                settings: () => BarState.panelRequested("settings", "network")
            })
        }

        // Bluetooth: adapter state + connected devices; click = the
        // Bluetooth panel (its own popup).
        BluetoothPill {
            id: btPill
            pillId: "bluetooth"                    // wheel: Settings › Pills
            onClicked: button => PillClicks.dispatch("bluetooth", button, {
                panel: () => bar.openNet("bluetooth"),
                blueman: () => Theme.exec("blueman-manager"),
                power: () => { if (btPill.adapter) btPill.adapter.enabled = !btPill.adapter.enabled; }
            })
        }

        Battery { id: batPill }
        }

        Island {
        Clock {}

        ScriptPill {
            id: bellPill
            command: ["/usr/bin/python3", Theme.hypr + "/notif-center.py", "bar"]
            interval: 0
            defaultFg: Theme.subtext0
            colors: ({ unread: Theme.accent, dnd: Theme.overlay0 })
            fillHover: true
            fontSize: 15
            // the bell's ink overflows its advance box to the right
            padLeft: 8
            padRight: classes.includes("unread") ? 9 : 10
            pillId: "bell"
            onClicked: button => PillClicks.dispatch("bell", button, {
                panel: () => notifPop.openTab("system"),
                dnd: () => { Theme.exec("/usr/bin/python3 " + Theme.hypr + "/notif-center.py dnd"); bellPill.poke(); },
                phone: () => notifPop.openTab("phone")
            })
        }

        Pill {
            id: settingsPill
            label: "\u{f0493}"
            fg: Theme.subtext0
            fillHover: true
            fontSize: 15
            padLeft: 8
            padRight: 11
            tip: "Settings" + PillClicks.hintLine("settings")
            pillId: "settings"                    // wheel: Settings › Pills
            onClicked: button => PillClicks.dispatch("settings", button, {
                settings: () => BarState.panelRequested("settings", ""),
                gnome: () => Theme.exec("gtk-launch org.gnome.Settings")
            })
            // Settings is its own full-screen panel: a keyboard stop here
            // (Ctrl+arrows land on the gear, Enter opens Settings)
            PillStop { pill: settingsPill }
        }

        Item { width: 4; height: 1 }

        Pill {
            id: powerPill
            label: "\u{f011}"
            fg: Theme.red
            bg: Theme.alpha(Theme.surface0, 0.7)
            hoverFg: Theme.crust
            hoverBg: Theme.red
            fontSize: 15
            // U+F011's ink sits right of its advance box: 12/8 centres it
            padLeft: 8
            padRight: 12
            marginH: 2
            tip: powerPop.isOpen ? "" : "Lock · Suspend · Log out · Restart · Power off" + PillClicks.hintLine("power")
            // the power panel (PowerPopup.qml; was nwg-bar)
            pillId: "power"                    // wheel: Settings › Pills
            onClicked: button => PillClicks.dispatch("power", button, {
                panel: () => powerPop.toggle(),
                lock: () => Theme.exec("hyprlock")
            })
        }
        }
    }

    PowerPopup { id: powerPop; pill: powerPill }

    ClipboardPopup {
        id: clipboard
        pill: clipPill
    }

    AudioPopup { id: audioPop; pill: audio; navName: "audio" }
    AudioPopup { id: micPop; pill: micPill; mode: "mic" }
    BrightnessPopup { id: brightPop; pill: brightnessPill }
    // system panels: CPU / memory / temperature (one file, three instances)
    // and the battery (inside Battery.qml)
    SysPopup { id: cpuPop; pill: cpuPill; kind: "cpu" }
    SysPopup { id: memPop; pill: memPill; kind: "mem" }
    SysPopup { id: tempPop; pill: tempPill; kind: "temp" }
    function openSys(which) {
        const p = { cpu: cpuPop, mem: memPop, temp: tempPop }[which];
        for (const q of [cpuPop, memPop, tempPop]) if (q !== p) q.close();
        if (which === "battery") batPill.toggleMenu();
        else if (p) p.toggle();
    }
    IpcHandler {
        target: "sysinfo"
        enabled: bar.active
        // cpu | mem | temp | battery
        function toggle(which: string): void { bar.openSys(which); }
    }
    // Wi-Fi and Bluetooth: two popups, one under each pill
    NetworkPopup { id: netPop; pill: netPill; mode: "wifi" }
    NetworkPopup { id: btPop; pill: btPill; mode: "bluetooth" }
    function openNet(which) {
        const p = which === "bluetooth" ? btPop : netPop;
        (p === btPop ? netPop : btPop).close();
        p.openTab(which === "bluetooth" ? "bluetooth" : (which || "wifi"));
    }
    NotifPopup { id: notifPop; pill: bellPill }

    // panels asked for from elsewhere (keybinds, the bottom bar, IPC)
    Connections {
        target: BarState
        enabled: bar.active
        function onPanelRequested(name, arg) {
            if (name === "audio") audioPop.toggle();
            else if (name === "mic") micPop.toggle();
            else if (name === "brightness") brightPop.toggle();
            else if (name === "network") bar.openNet(arg || "wifi");
            else if (name === "notifications") notifPop.openTab(arg || "system");
        }
    }
    IpcHandler {
        target: "panels"
        enabled: bar.active
        // audio | network [wifi|bluetooth] | notifications [system|phone] | settings [TAB]
        function toggle(name: string, arg: string): void { BarState.panelRequested(name, arg); }
        // what Ctrl+Tab / Ctrl+Shift+Tab do in an open panel (1 / -1)
        function tab(dir: int): void { BarState.tabPressed(dir); }
        // keyboard navigation, for keybinds and testing:
        //   start            open the sound panel (or close the open one)
        //   left|right|up|down   the neighbouring panel (as Ctrl+arrows)
        //   next|prev|enter|space|inc|dec   inside the open panel (Tab, Shift+Tab,
        //                    Enter, Space, → / ←)
        function nav(dir: string): void {
            if (dir === "start") { BarState.startNav(); return; }
            const p = BarState.activePopup;
            if (!p) return;
            const k = { next: [Qt.Key_Tab, 0], prev: [Qt.Key_Backtab, 0], enter: [Qt.Key_Return, 0],
                        space: [Qt.Key_Space, 0], inc: [Qt.Key_Right, 0], dec: [Qt.Key_Left, 0],
                        left: [Qt.Key_Left, Qt.ControlModifier], right: [Qt.Key_Right, Qt.ControlModifier],
                        up: [Qt.Key_Up, Qt.ControlModifier], down: [Qt.Key_Down, Qt.ControlModifier] }[dir];
            if (k) p.navKey(k[0], k[1]);
        }
    }

    IpcHandler {
        target: "clipboard"
        enabled: bar.active
        function toggle(): void { clipboard.toggle(); }
    }
}
