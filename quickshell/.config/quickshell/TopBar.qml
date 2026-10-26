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
            tip: "Apps  ·  right-click: run by name"
            onClicked: button => {
                if (button === Qt.LeftButton) Theme.exec(Theme.hypr + "/app-grid.sh");
                else if (button === Qt.RightButton) Theme.exec("fuzzel");
            }
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
            fg: Theme.peach
            fontSize: 15
            padLeft: 9
            fillHover: true
            padRight: 10
            tip: clipboard.isOpen ? "" : "Clipboard history"
            onClicked: button => { if (button === Qt.LeftButton) clipboard.toggle(); }
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
        Pill {
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
                     + "<br><font color='" + Theme.overlay2 + "'><pre>" + rows.join("<br>") + "</pre></font>";
            }
            onClicked: button => { if (button === Qt.LeftButton) Theme.exec("ghostty -e btop"); }
        }

        Pill {
            label: "\u{f035b} " + Stats.memPct + "%"
            fg: Theme.teal
            fillHover: true
            tip: Stats.memUsedGiB.toFixed(1) + " GiB / " + Stats.memTotalGiB.toFixed(1) + " GiB"
            onClicked: button => { if (button === Qt.LeftButton) Theme.exec("ghostty -e btop"); }
        }

        Pill {
            readonly property bool critical: Stats.tempC >= Stats.tempCritical
            label: (Stats.tempC < 50 ? "\u{f10c3}" : Stats.tempC < 75 ? "\u{f050f}" : "\u{f10c2}") + " " + Stats.tempC + "°"
            fg: critical ? Theme.crust : Theme.sapphire
            bg: critical ? Theme.red : "transparent"
            fillHover: true
            tip: "CPU temperature " + Stats.tempC + " °C"
                 + "<br><font color='" + Theme.overlay2 + "'>Click: Resources (CPU, with its temperature graph) · Right-click: btop</font>"
            onClicked: button => {
                if (button === Qt.LeftButton) Theme.exec("resources --open-tab-id cpu");
                else if (button === Qt.RightButton) Theme.exec("ghostty -e btop");
            }
        }
        }
    }

    // ── centre: the focused window's state and title ────────────────────────
    // (in its own island, in the islands style)
    //
    // Floating / pinned / fullscreen come from Hyprland's client JSON, which
    // quickshell only fetches on demand: refresh it when any of them changes.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
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
                 + "<br><font color='" + Theme.overlay2 + "'>Click: " + (floating ? "tile" : "float")
                 + " · Right-click: " + (pinned ? "unpin" : "pin") + " · Middle-click: fullscreen</font>"
            onClicked: button => {
                if (!title.valid) return;
                if (button === Qt.LeftButton) {
                    Hyprland.dispatch("togglefloating " + addr);
                } else if (button === Qt.RightButton) {
                    if (!floating) Hyprland.dispatch("setfloating " + addr);
                    Hyprland.dispatch("pin " + addr);
                } else if (button === Qt.MiddleButton) {
                    Hyprland.dispatch("focuswindow " + addr);
                    Hyprland.dispatch("fullscreen 0");
                }
            }
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

        // Audio: the default sink. Click mutes, right-click pavucontrol,
        // scroll ±5 %.
        Pill {
            id: audio
            readonly property var sink: Pipewire.defaultAudioSink
            readonly property bool ok: sink !== null && sink.audio !== null
            readonly property int pct: ok ? Math.round(sink.audio.volume * 100) : 0
            readonly property bool muted: ok && sink.audio.muted
            readonly property bool bt: sink !== null && (sink.name || "").startsWith("bluez")

            PwObjectTracker { objects: [audio.sink] }

            label: muted ? "\u{f075f} muted"
                 : (bt ? "\u{f00af}" : pct < 34 ? "\u{f057f}" : pct < 67 ? "\u{f0580}" : "\u{f057e}") + " " + pct + "%"
            fg: muted ? Theme.overlay0 : Theme.pink
            fillHover: true
            tip: ok ? (sink.description || sink.name) + "  ·  " + (muted ? "muted" : pct + "%")
                      + "<br><font color='" + Theme.overlay2 + "'>Click: mute · Right-click: mixer · Scroll: volume</font>" : ""
            onClicked: button => {
                if (button === Qt.LeftButton && ok) sink.audio.muted = !sink.audio.muted;
                else if (button === Qt.RightButton) Theme.exec("pavucontrol");
            }
            onScrolled: dir => {
                if (ok) sink.audio.volume = Math.max(0, Math.min(1, Math.round(sink.audio.volume * 20 + dir) / 20));
            }
        }

        MicPill {}

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
            tip: "Screen brightness " + Stats.brightness + "%  ·  scroll to change, click for 50%<br>"
                 + (nightOn ? "\u{f0594} Night light on, " + night[1] + " K  ·  right-click off, middle-click warmer/cooler"
                            : "Right-click: night light")
            onClicked: button => {
                if (button === Qt.RightButton) Theme.exec(Theme.hypr + "/night-light.sh toggle");
                else if (button === Qt.MiddleButton) Theme.exec(Theme.hypr + "/night-light.sh cycle");
                if (button !== Qt.LeftButton) return;
                Theme.exec(Theme.hypr + "/brightness.sh set 50");
                Stats.refreshBacklight();
            }

            FileView {
                id: nightFile
                path: Theme.hypr + "/night-light"
                watchChanges: true
                printErrors: false
                onFileChanged: reload()
            }
            onScrolled: dir => {
                Theme.exec(Theme.hypr + "/brightness.sh " + (dir > 0 ? "up" : "down") + " 5");
                Stats.refreshBacklight();
            }
        }

        // duplicate / extend: only while an external monitor is connected
        DisplayPill { active: bar.active }

        Pill {
            readonly property string kind: Stats.netKind === "wifi" && !Stats.ipaddr ? "linked" : Stats.netKind
            label: kind === "wifi" ? "\u{f0928} " + Stats.signal + "%"
                 : kind === "wired" ? "\u{f0200} wired"
                 : kind === "linked" ? "\u{f092b} no IP" : "\u{f092d} offline"
            fg: kind === "offline" ? Theme.red : Theme.blue
            fillHover: true
            tip: kind === "wifi" ? Stats.essid + "  ·  " + Stats.ipaddr + "<br>\u{f01da} " + Stats.bits(Stats.rxBps) + "   \u{f0552} " + Stats.bits(Stats.txBps)
               : kind === "wired" ? Stats.ifname + "  ·  " + Stats.ipaddr
               : kind === "linked" ? Stats.essid + "  ·  no address yet" : "Offline"
            onClicked: button => {
                if (button === Qt.LeftButton) Theme.exec(Theme.hypr + "/network-panel.py");
                else if (button === Qt.RightButton) Theme.exec("nm-connection-editor");
            }
        }

        Battery {}
        }

        Island {
        Clock {}

        ScriptPill {
            command: ["/usr/bin/python3", Theme.hypr + "/notif-center.py", "bar"]
            interval: 0
            defaultFg: Theme.subtext0
            colors: ({ unread: Theme.accent, dnd: Theme.overlay0 })
            fillHover: true
            fontSize: 15
            // the bell's ink overflows its advance box to the right
            padLeft: 8
            padRight: classes.includes("unread") ? 9 : 10
            onLeft: "/usr/bin/python3 " + Theme.hypr + "/notif-center.py"
            onRight: "/usr/bin/python3 " + Theme.hypr + "/notif-center.py dnd"
        }

        Pill {
            label: "\u{f0493}"
            fg: Theme.subtext0
            fillHover: true
            fontSize: 15
            padLeft: 8
            padRight: 11
            tip: "Settings"
            onClicked: button => { if (button === Qt.LeftButton) Theme.exec("gtk-launch org.gnome.Settings"); }
        }

        Item { width: 4; height: 1 }

        Pill {
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
            tip: "Lock · Suspend · Log out · Restart · Power off"
            onClicked: button => { if (button === Qt.LeftButton) Theme.exec("nwg-bar"); }
        }
        }
    }

    ClipboardPopup {
        id: clipboard
        pill: clipPill
    }

    IpcHandler {
        target: "clipboard"
        enabled: bar.active
        function toggle(): void { clipboard.toggle(); }
    }
}
