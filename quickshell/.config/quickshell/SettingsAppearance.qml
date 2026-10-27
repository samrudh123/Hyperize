// Settings › Appearance: desktop theme (set-theme.sh), accent colour
// (set-accent.sh), wallpaper and lock screen (the Quickshell pickers), font.
import QtQuick
import Quickshell
import Quickshell.Io

SettingsPage {
    id: page
    title: "Appearance"
    subtitle: "Theme, accent colour, wallpaper and font — the whole desktop follows."

    property var themes: []
    property string pendingTheme: ""
    property string pendingAccent: ""
    Process {
        running: true
        command: ["/usr/bin/python3", Theme.hypr + "/rice-theme.py", "list"]
        stdout: StdioCollector {
            onStreamFinished: { try { page.themes = JSON.parse(text); } catch (e) {} }
        }
    }
    // a theme / accent switch takes a few seconds (it re-renders every app)
    onPendingThemeChanged: if (pendingTheme) pendTimer.restart()
    Connections {
        target: Theme
        function onThemeIdChanged() { page.pendingTheme = ""; }
        function onAccentChanged() { page.pendingAccent = ""; }
    }
    Timer { id: pendTimer; interval: 15000; onTriggered: { page.pendingTheme = ""; page.pendingAccent = ""; } }

    readonly property var accentRoles: ["rosewater", "flamingo", "pink", "mauve", "red", "maroon", "peach",
                                        "yellow", "green", "teal", "sky", "sapphire", "blue", "lavender"]
    function hex(c) { return c.toString().slice(1, 7).toLowerCase(); }

    // ── themes ───────────────────────────────────────────────────────────────
    SettingsCard {
        title: "Theme"
        icon: "\u{f050e}"
        SettingsRow {
            icon: "\u{f03d8}"
            title: "Desktop theme"
            subtitle: Theme.themeName + (page.pendingTheme ? "  ·  switching…" : "") + "  ·  also SUPER+SHIFT+T"
            keywords: "colours palette catppuccin tokyo gruvbox nord rose pine everforest dracula kanagawa"
            last: true
            IconBtn {
                text: "Open picker"
                icon: "\u{f0e51}"
                onClicked: { SettingsState.closeRequested(); Theme.exec("~/.local/bin/qs ipc call themepicker toggle"); }
            }
        }
        Item {
            visible: SettingsState.query === "" || "theme colours palette catppuccin tokyo gruvbox nord rose pine everforest dracula kanagawa".includes(SettingsState.query.toLowerCase())
            width: parent.width
            height: themeGrid.height + 14
                Grid {
                    id: themeGrid
                    columns: 4
                    spacing: 10
                    width: parent.width - 28
                    x: 14
                    Repeater {
                        model: page.themes
                        delegate: Rectangle {
                            id: tcard
                            required property var modelData
                            readonly property bool cur: modelData.id === Theme.themeId
                            readonly property bool busy: modelData.id === page.pendingTheme
                            width: (themeGrid.width - 3 * 10) / 4
                            height: 64
                            radius: 12
                            color: modelData.base
                            border.width: cur ? 2 : 1
                            border.color: cur ? Theme.accent : tma.containsMouse ? modelData.overlay0 : modelData.surface0
                            Behavior on border.color { ColorAnimation { duration: Theme.fast } }
                            scale: tma.pressed ? 0.97 : 1
                            Behavior on scale { NumberAnimation { duration: 120 } }

                            Text {
                                x: 12
                                y: 10
                                width: parent.width - 24
                                text: tcard.modelData.name
                                elide: Text.ElideRight
                                color: tcard.modelData.text
                                font.family: Theme.font
                                font.pixelSize: 12
                                font.weight: Font.Bold
                            }
                            Row {
                                x: 12
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 12
                                spacing: 4
                                Repeater {
                                    model: ["red", "peach", "yellow", "green", "blue", "mauve"]
                                    delegate: Rectangle {
                                        required property var modelData
                                        width: 11; height: 11; radius: 6
                                        color: tcard.modelData[modelData]
                                    }
                                }
                            }
                            Text {
                                visible: tcard.cur || tcard.busy
                                anchors.right: parent.right
                                anchors.rightMargin: 10
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 8
                                text: tcard.busy ? "\u{f051f}" : "\u{f012c}"
                                color: Theme.accent
                                font.family: Theme.font
                                font.pixelSize: 15
                            }
                            MouseArea {
                                id: tma
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (tcard.cur) return;
                                    page.pendingTheme = tcard.modelData.id;
                                    Theme.exec(Theme.hypr + "/set-theme.sh " + tcard.modelData.id);
                                }
                            }
                        }
                    }
                }
        }
    }

    // ── accent ───────────────────────────────────────────────────────────────
    SettingsCard {
        title: "Accent colour"
        icon: "\u{f0266}"
        SettingsRow {
            icon: "\u{f0266}"
            iconColor: Theme.accent
            title: "Accent"
            subtitle: Theme.accent + (page.pendingAccent ? "  ·  applying…" : "") + "  ·  also SUPER+ALT+C"
            keywords: "highlight colour color tint"
            last: true
            Flow {
                width: 15 * 30
                spacing: 6
                Repeater {
                    model: page.accentRoles
                    delegate: Rectangle {
                        required property var modelData
                        readonly property color c: Theme[modelData]
                        readonly property bool cur: page.hex(c) === page.hex(Theme.accent)
                        width: 24
                        height: 24
                        radius: 12
                        color: c
                        border.width: cur ? 3 : 0
                        border.color: Theme.text
                        scale: am.containsMouse ? 1.18 : 1
                        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
                        MouseArea {
                            id: am
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                page.pendingAccent = page.hex(parent.c);
                                pendTimer.restart();
                                Theme.exec(Theme.hypr + "/set-accent.sh " + page.hex(parent.c));
                            }
                        }
                        Tooltip { target: parent; text: modelData; shown: am.containsMouse }
                    }
                }
                IconBtn {
                    size: 24
                    iconSize: 13
                    icon: "\u{f020a}"
                    tip: "Any colour…"
                    onClicked: { SettingsState.closeRequested(); Theme.exec("/usr/bin/python3 " + Theme.hypr + "/accent-picker.py"); }
                }
            }
        }
    }

    // ── transparency ─────────────────────────────────────────────────────────
    SettingsCard {
        title: "Transparency"
        icon: "\u{f1853}"
        SettingsRow {
            icon: "\u{f1853}"
            title: "Panels & popups"
            subtitle: Math.round(opac.dragging ? 35 + opac.dragValue * 65 : Theme.panelOpacity * 100) + "%  ·  this window and every bar popup "
                    + "(sound, Wi-Fi, tasks, power, music…) — blurred behind"
            keywords: "transparency opacity translucent glass blur see-through alpha"
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                Slider {
                    id: opac
                    width: 240
                    anchors.verticalCenter: parent.verticalCenter
                    // 35–100 %: lower and the popups fall under the bars'
                    // blur ignore_alpha (0.3) and lose their frosting
                    step: 1 / 13               // = 5 % per wheel notch
                    value: (Theme.panelOpacity * 100 - 35) / 65
                    onMoved: v => { opacTimer.pct = 35 + Math.round(v * 65); opacTimer.restart(); }
                    Timer {
                        id: opacTimer
                        property int pct: 100
                        interval: 40
                        onTriggered: Theme.setPanelOpacity(pct)
                    }
                }
                IconBtn {
                    anchors.verticalCenter: parent.verticalCenter
                    size: 28
                    icon: "\u{f0450}"
                    tip: "Solid (100 %)"
                    enabled: Theme.panelOpacity < 0.999
                    onClicked: Theme.setPanelOpacity(100)
                }
            }
        }
        SettingsRow {
            icon: "\u{f05b2}"
            title: "Windows"
            subtitle: "SUPER+SHIFT+Scroll over a window changes its transparency; its OSD can make that the app's default"
            keywords: "transparency opacity window app"
            last: true
        }
    }

    // ── wallpaper ────────────────────────────────────────────────────────────
    FileView {
        id: wallFile
        path: Theme.hypr + "/wallpaper"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }
    readonly property string wall: (wallFile.text() || "").trim()
    readonly property bool wallIsImage: /\.(png|jpe?g|webp|bmp)$/i.test(wall)

    SettingsCard {
        title: "Wallpaper"
        icon: "\u{f02e9}"
        SettingsRow {
            icon: "\u{f02e9}"
            title: "Desktop wallpaper"
            subtitle: page.wall ? page.wall.split("/").pop() + (page.wallIsImage ? "" : "  ·  live (video)") : "—"
            keywords: "background picture video"
            Rectangle {
                visible: page.wallIsImage
                width: 96; height: 54; radius: 8
                clip: true
                color: Theme.surface0
                anchors.verticalCenter: parent.verticalCenter
                Image {
                    anchors.fill: parent
                    source: page.wallIsImage ? "file://" + page.wall : ""
                    sourceSize.width: 192
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
            }
            IconBtn {
                anchors.verticalCenter: parent.verticalCenter
                text: "Choose…"
                icon: "\u{f0770}"
                onClicked: { SettingsState.closeRequested(); Theme.exec("~/.local/bin/qs ipc call wallpicker toggle desktop"); }
            }
        }
        SettingsRow {
            icon: "\u{f033e}"
            title: "Lock screen image"
            subtitle: "What hyprlock shows (SUPER+SHIFT+W)"
            keywords: "lockscreen hyprlock"
            last: true
            IconBtn {
                text: "Choose…"
                icon: "\u{f0770}"
                onClicked: { SettingsState.closeRequested(); Theme.exec("~/.local/bin/qs ipc call wallpicker toggle lock"); }
            }
        }
    }

    // ── font ─────────────────────────────────────────────────────────────────
    // hypr/set-font.py: `get` lists the installed choices and what the shell
    // and the apps use now; `set FAMILY --shell|--apps` applies one (the
    // shell follows theme/font-shell live; apps = GTK, Qt/KDE, fontconfig,
    // Hyprland, ghostty, mako, fuzzel, hyprlock, zathura, nwg-bar).
    property var fonts: ({ shell: Theme.font, apps: "", choices: [] })
    property int fontTarget: 0                    // 0 shell, 1 apps & system
    property string fontBusy: ""
    readonly property string fontKeys: "font typeface family adwaita mono iosevka jetbrains geist fira caskaydia cascadia hack ubuntu cantarell noto sans system gtk qt terminal"
    Process {
        id: fontGet
        running: true
        command: ["/usr/bin/python3", Theme.hypr + "/set-font.py", "get"]
        stdout: StdioCollector {
            onStreamFinished: { try { page.fonts = JSON.parse(text); } catch (e) {} }
        }
    }
    Process {
        id: fontSet
        stdout: StdioCollector {
            onStreamFinished: { page.fontBusy = ""; fontGet.running = true; }
        }
    }
    function setFont(fam) {
        if (fontSet.running) return;
        fontBusy = fam;
        fontSet.command = ["/usr/bin/python3", Theme.hypr + "/set-font.py", "set", fam, fontTarget === 0 ? "--shell" : "--apps"];
        fontSet.running = true;
    }

    SettingsCard {
        title: "Font"
        icon: "\u{f06d6}"
        SettingsRow {
            icon: page.fontTarget === 0 ? "\u{f0379}" : "\u{f05b2}"
            title: "Apply to"
            subtitle: page.fontTarget === 0
                ? "Bars, popups and this window — now " + page.fonts.shell
                : "Apps & system — GTK & Qt apps, web pages' default font, Hyprland, terminal, notifications, launcher, lock screen, PDF viewer — now "
                  + page.fonts.apps + ". New windows pick it up."
            keywords: page.fontKeys
            Segmented {
                anchors.verticalCenter: parent.verticalCenter
                width: 330
                height: 32
                options: ["Shell (bars & popups)", "Apps & system"]
                currentIndex: page.fontTarget
                onSelected: i => page.fontTarget = i
            }
        }
        Item {
            visible: SettingsState.query === "" || page.fontKeys.includes(SettingsState.query.toLowerCase())
            width: parent.width
            height: fontGrid.height + 14
            Grid {
                id: fontGrid
                columns: 3
                spacing: 10
                width: parent.width - 28
                x: 14
                Repeater {
                    model: page.fonts.choices
                    delegate: Rectangle {
                        id: fcard
                        required property var modelData
                        readonly property string fam: modelData.family
                        readonly property bool cur: fam === (page.fontTarget === 0 ? page.fonts.shell : page.fonts.apps)
                        width: (fontGrid.width - 2 * 10) / 3
                        height: 76
                        radius: 12
                        color: fma.containsMouse ? Theme.alpha(Theme.surface1, 0.5) : Theme.alpha(Theme.surface0, 0.55)
                        border.width: cur ? 2 : 1
                        border.color: cur ? Theme.accent : Theme.alpha(Theme.surface1, 0.8)
                        Behavior on border.color { ColorAnimation { duration: Theme.fast } }
                        scale: fma.pressed ? 0.97 : 1
                        Behavior on scale { NumberAnimation { duration: 120 } }

                        Text {
                            x: 12
                            y: 9
                            width: parent.width - 24
                            elide: Text.ElideRight
                            text: "Aa Bb 0123 {}"
                            color: fcard.cur ? Theme.accent : Theme.text
                            font.family: fcard.fam
                            font.pixelSize: 20
                            font.weight: Font.Bold
                        }
                        Text {
                            x: 12
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 9
                            width: parent.width - 24 - badges.width
                            elide: Text.ElideRight
                            text: fcard.fam.replace(" Nerd Font", "") + (fcard.modelData.mono ? "" : "  ·  proportional")
                            color: Theme.subtext0
                            font.family: fcard.fam
                            font.pixelSize: 11
                        }
                        // where it's used now
                        Row {
                            id: badges
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 8
                            spacing: 4
                            Repeater {
                                model: [fcard.fam === page.fonts.shell ? "shell" : "", fcard.fam === page.fonts.apps ? "apps" : ""].filter(x => x)
                                delegate: Rectangle {
                                    required property string modelData
                                    width: bt.implicitWidth + 10
                                    height: 16
                                    radius: 5
                                    color: Theme.alpha(Theme.accent, 0.2)
                                    Text {
                                        id: bt
                                        anchors.centerIn: parent
                                        text: parent.modelData
                                        color: Theme.accent
                                        font.family: Theme.font
                                        font.pixelSize: 9
                                        font.weight: Font.Bold
                                    }
                                }
                            }
                        }
                        Text {
                            visible: page.fontBusy === fcard.fam
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            y: 10
                            text: "applying…"
                            color: Theme.accent
                            font.family: Theme.font
                            font.pixelSize: 10
                        }
                        MouseArea {
                            id: fma
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (!fcard.cur) page.setFont(fcard.fam)
                        }
                    }
                }
            }
        }
        SettingsRow {
            icon: "\u{f02fc}"
            title: "Good to know"
            subtitle: "A proportional font (Adwaita Sans, Ubuntu Sans…) for apps keeps terminals and code on AdwaitaMono. "
                    + "VS Code and Neovim keep their own editor fonts. Fonts come from build/fonts.sh."
            keywords: page.fontKeys
            last: true
        }
    }
}
