// Settings — a Serpantinum-style settings panel: a big centred card over a
// dimmed screen, tabs down the left (with a search that filters tabs and
// rows), the tab's page on the right.
//
//   open:   top bar ⚙ pill · `qs ipc call settings toggle|open TAB` (TAB "" = the last one; the arg is required) ·
//           BarState.panelRequested("settings", TAB)
//   close:  Esc · click outside the card · ⚙ again
//
// TAB = keybinds pills display appearance sound network kdeconnect tailscale
//       notifications power about. Each page is its own Settings<Tab>.qml,
//       loaded only while shown (nothing runs while the panel is closed).
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: root

    property bool isOpen: false
    property bool shown: false              // stays true through the closing fade
    property string tab: "keybinds"

    readonly property var tabs: [
        { id: "keybinds",      name: "Keybindings",   icon: "\u{f030c}", keys: "keyboard shortcuts hyprland neovim nvim vim binds hotkeys key combo workspace window focus move resize screenshot terminal browser launcher leader" },
        { id: "pills",         name: "Pills",         icon: "\u{f037d}", keys: "pills pill bar click right-click middle-click mouse buttons left right middle top bottom panel action" },
        { id: "display",       name: "Display",       icon: "\u{f0379}", keys: "monitor screen resolution refresh scale brightness night light kelvin mirror extend duplicate external bar bottom bar islands classic dock" },
        { id: "appearance",    name: "Appearance",    icon: "\u{f03d8}", keys: "theme accent colour color wallpaper lock screen font typeface look transparency opacity blur glass" },
        { id: "sound",         name: "Sound",         icon: "\u{f057e}", keys: "audio volume output input speaker microphone mic headphones mute mixer pavucontrol" },
        { id: "network",       name: "Network",       icon: "\u{f05a9}", keys: "wifi wi-fi bluetooth internet wireless ethernet wired ip address devices pair blueman" },
        { id: "kdeconnect",    name: "KDE Connect",   icon: "\u{f011c}", keys: "phone android ring ping send files clipboard" },
        { id: "tailscale",     name: "Tailscale",     icon: "\u{f0317}", keys: "vpn tailnet ssh peers machines" },
        { id: "notifications", name: "Notifications", icon: "\u{f009a}", keys: "do not disturb dnd mako alerts popups history phone notifications" },
        { id: "power",         name: "Power",         icon: "\u{f0425}", keys: "battery charge profile performance saver balanced keep awake caffeine idle lock suspend sleep shutdown power off restart reboot logout" },
        { id: "about",         name: "About",         icon: "\u{f02fd}", keys: "system version kernel host info os cpu processor memory ram disk storage gpu graphics" }
    ]

    function open(t) {
        if (t && tabs.some(x => x.id === t)) tab = t;
        hideTimer.stop();
        shown = true;
        isOpen = true;
    }
    function close() {
        if (!isOpen) return;
        isOpen = false;
        hideTimer.restart();
    }
    function toggle(t) {
        if (isOpen && (!t || t === tab)) close();
        else open(t);
    }

    Timer { id: hideTimer; interval: 220; onTriggered: { root.shown = false; SettingsState.query = ""; } }

    Connections {
        target: BarState
        function onPanelRequested(name, arg) {
            if (name === "settings") root.toggle(arg);
            else root.close();               // another panel: get out of its way
        }
    }
    Connections {
        target: SettingsState
        function onCloseRequested() { root.close(); }
    }

    IpcHandler {
        target: "settings"
        function toggle(tab: string): void { root.toggle(tab); }
        function open(tab: string): void { root.open(tab); }
        function close(): void { root.close(); }
        // open with the search filled in (also handy for testing)
        function search(text: string): void { root.open(""); SettingsState.query = text; }
    }

    LazyLoader {
        active: root.shown

        PanelWindow {
            id: win

            screen: Quickshell.screens.find(s => s.name === BarState.active) || Quickshell.screens[0]
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "qs-settings"
            WlrLayershell.keyboardFocus: root.isOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            color: "transparent"

            // dim + click outside closes
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, root.isOpen ? 0.38 : 0)
                Behavior on color { ColorAnimation { duration: 200 } }
                MouseArea {
                    anchors.fill: parent
                    onClicked: root.close()
                }
            }

            Rectangle {
                id: card
                width: Math.min(1120, parent.width - 80)
                height: Math.min(740, parent.height - 100)
                anchors.centerIn: parent
                radius: 20
                color: Theme.panel(Theme.base)
                border.width: 1
                border.color: Theme.alpha(Theme.surface1, 0.9)
                clip: true

                opacity: root.isOpen ? 1 : 0
                scale: root.isOpen ? 1 : 0.95
                Behavior on opacity { NumberAnimation { duration: root.isOpen ? 240 : 160; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: root.isOpen ? 420 : 160; easing.type: root.isOpen ? Easing.OutBack : Easing.InCubic; easing.overshoot: 0.8 } }

                // swallow clicks so they don't reach the dim layer
                MouseArea { anchors.fill: parent }

                focus: true
                Component.onCompleted: forceActiveFocus()
                Keys.onPressed: ev => {
                    if (ev.key === Qt.Key_Escape) { root.close(); ev.accepted = true; }
                    else if ((ev.modifiers & Qt.ControlModifier) && ev.key === Qt.Key_F) { search.forceActiveFocus(); ev.accepted = true; }
                    else if ((ev.modifiers & Qt.ControlModifier) && (ev.key === Qt.Key_Tab || ev.key === Qt.Key_Backtab)) {
                        const vis = sidebar.visibleTabs;
                        const i = vis.findIndex(t => t.id === root.tab);
                        const d = ev.key === Qt.Key_Backtab || (ev.modifiers & Qt.ShiftModifier) ? -1 : 1;
                        if (vis.length) root.tab = vis[(i + d + vis.length) % vis.length].id;
                        ev.accepted = true;
                    }
                }

                // ── sidebar ─────────────────────────────────────────────
                Rectangle {
                    id: sidebar
                    width: 270
                    height: parent.height
                    color: "transparent"

                    readonly property var visibleTabs: {
                        const q = SettingsState.query.trim().toLowerCase();
                        if (!q) return root.tabs;
                        const hit = root.tabs.filter(t => (t.name + " " + t.keys).toLowerCase().includes(q));
                        // no tab mentions it: keep them all (the page's rows still filter)
                        return hit.length ? hit : root.tabs;
                    }
                    onVisibleTabsChanged: {
                        if (visibleTabs.length && !visibleTabs.some(t => t.id === root.tab))
                            root.tab = visibleTabs[0].id;
                    }

                    // the tint: rounded on the left only (a wider rectangle,
                    // clipped) — an overlapping square-off strip would show
                    // as a darker band once the panel is translucent
                    Item {
                        width: parent.width
                        height: parent.height
                        clip: true
                        Rectangle {
                            width: parent.width + card.radius
                            height: parent.height
                            radius: card.radius
                            color: Theme.alpha(Theme.mantle, Theme.panelOpacity > 0.999 ? 0.9 : 0.35)
                        }
                    }
                    Rectangle {
                        anchors.right: parent.right
                        width: 1
                        height: parent.height
                        color: Theme.alpha(Theme.surface1, 0.6)
                    }

                    Column {
                        x: 18
                        y: 22
                        width: parent.width - 36
                        spacing: 16

                        Row {
                            spacing: 10
                            Rectangle {
                                width: 36
                                height: 36
                                radius: 11
                                color: Theme.accent
                                anchors.verticalCenter: parent.verticalCenter
                                Text {
                                    anchors.centerIn: parent
                                    text: "\u{f0493}"
                                    color: Theme.crust
                                    font.family: Theme.font
                                    font.pixelSize: 19
                                }
                            }
                            Text {
                                text: "Settings"
                                anchors.verticalCenter: parent.verticalCenter
                                color: Theme.text
                                font.family: Theme.font
                                font.pixelSize: 21
                                font.weight: Font.Bold
                            }
                        }

                        // search
                        Rectangle {
                            width: parent.width
                            height: 38
                            radius: 11
                            color: Theme.alpha(Theme.surface0, 0.8)
                            border.width: search.activeFocus ? 1 : 0
                            border.color: Theme.alpha(Theme.accent, 0.7)

                            Text {
                                id: lens
                                x: 12
                                anchors.verticalCenter: parent.verticalCenter
                                text: "\u{f0349}"
                                color: search.activeFocus ? Theme.accent : Theme.overlay1
                                font.family: Theme.font
                                font.pixelSize: 15
                            }
                            TextInput {
                                id: search
                                anchors { left: lens.right; leftMargin: 9; right: clear.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
                                color: Theme.text
                                selectionColor: Theme.alpha(Theme.accent, 0.4)
                                font.family: Theme.font
                                font.pixelSize: 13
                                clip: true
                                text: SettingsState.query
                                onTextChanged: if (SettingsState.query !== text) SettingsState.query = text
                                Keys.onEscapePressed: ev => {
                                    if (text) { text = ""; ev.accepted = true; }
                                    else { card.forceActiveFocus(); root.close(); }
                                }
                                Keys.onReturnPressed: card.forceActiveFocus()
                                Text {
                                    visible: !search.text
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "Search settings"
                                    color: Theme.overlay0
                                    font: search.font
                                }
                            }
                            Text {
                                id: clear
                                visible: search.text !== ""
                                anchors.right: parent.right
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                text: "\u{f0156}"
                                color: Theme.overlay1
                                font.family: Theme.font
                                font.pixelSize: 14
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: search.text = ""
                                }
                            }
                        }

                        Column {
                            width: parent.width
                            spacing: 3

                            Repeater {
                                model: sidebar.visibleTabs
                                delegate: Rectangle {
                                    id: tabItem
                                    required property var modelData
                                    readonly property bool sel: modelData.id === root.tab
                                    width: parent.width
                                    height: 42
                                    radius: 12
                                    color: sel ? Theme.accent : tabMa.containsMouse ? Theme.alpha(Theme.surface0, 0.9) : "transparent"
                                    Behavior on color { ColorAnimation { duration: Theme.fast; easing.type: Easing.OutQuint } }

                                    Rectangle {
                                        x: 6
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 30
                                        height: 30
                                        radius: 9
                                        color: tabItem.sel ? Theme.alpha(Theme.crust, 0.18) : "transparent"
                                        Text {
                                            anchors.centerIn: parent
                                            text: tabItem.modelData.icon
                                            color: tabItem.sel ? Theme.crust : Theme.subtext0
                                            font.family: Theme.font
                                            font.pixelSize: 16
                                        }
                                    }
                                    Text {
                                        x: 46
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: tabItem.modelData.name
                                        color: tabItem.sel ? Theme.crust : tabMa.containsMouse ? Theme.text : Theme.subtext1
                                        font.family: Theme.font
                                        font.pixelSize: 13
                                        font.weight: tabItem.sel ? Font.Bold : Font.Medium
                                    }
                                    MouseArea {
                                        id: tabMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: { root.tab = tabItem.modelData.id; card.forceActiveFocus(); }
                                    }
                                }
                            }

                            Text {
                                visible: SettingsState.query !== "" && sidebar.visibleTabs.length === root.tabs.length
                                topPadding: 10
                                leftPadding: 8
                                width: parent.width
                                wrapMode: Text.Wrap
                                text: "No tab is about “" + SettingsState.query + "” — filtering this page's settings"
                                color: Theme.overlay0
                                font.family: Theme.font
                                font.pixelSize: 12
                            }
                        }
                    }

                    Text {
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 16
                        x: 22
                        text: "Ctrl+F search · Ctrl+Tab next · Esc close"
                        color: Theme.overlay0
                        font.family: Theme.font
                        font.pixelSize: 10
                    }
                }

                // ── page ────────────────────────────────────────────────
                Item {
                    id: pageArea
                    anchors { left: sidebar.right; right: parent.right; top: parent.top; bottom: parent.bottom }
                    clip: true

                    // components, not file names: Quickshell then knows the
                    // page files (hot reload follows them)
                    Component { id: pKeybinds; SettingsKeybinds {} }
                    Component { id: pPills; SettingsPills {} }
                    Component { id: pDisplay; SettingsDisplay {} }
                    Component { id: pAppearance; SettingsAppearance {} }
                    Component { id: pSound; SettingsSound {} }
                    Component { id: pNetwork; SettingsNetwork {} }
                    Component { id: pKdeConnect; SettingsKdeConnect {} }
                    Component { id: pTailscale; SettingsTailscale {} }
                    Component { id: pNotifications; SettingsNotifications {} }
                    Component { id: pPower; SettingsPower {} }
                    Component { id: pAbout; SettingsAbout {} }
                    readonly property var pages: ({
                        keybinds: pKeybinds, pills: pPills, display: pDisplay, appearance: pAppearance, sound: pSound,
                        network: pNetwork, kdeconnect: pKdeConnect, tailscale: pTailscale,
                        notifications: pNotifications, power: pPower, about: pAbout
                    })

                    Loader {
                        id: pageLoader
                        width: parent.width
                        height: parent.height
                        sourceComponent: pageArea.pages[root.tab] || null
                        onLoaded: enter.restart()
                    }

                    // the new page slides up and fades in
                    ParallelAnimation {
                        id: enter
                        NumberAnimation { target: pageLoader; property: "opacity"; from: 0; to: 1; duration: 260; easing.type: Easing.OutCubic }
                        NumberAnimation { target: pageLoader; property: "y"; from: 18; to: 0; duration: 380; easing.type: Easing.OutExpo }
                    }
                }

                // close button
                Rectangle {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 14
                    width: 32
                    height: 32
                    radius: 10
                    color: closeMa.containsMouse ? Theme.red : Theme.alpha(Theme.surface0, 0.8)
                    Behavior on color { ColorAnimation { duration: Theme.fast } }
                    Text {
                        anchors.centerIn: parent
                        text: "\u{f0156}"
                        color: closeMa.containsMouse ? Theme.crust : Theme.subtext0
                        font.family: Theme.font
                        font.pixelSize: 15
                    }
                    MouseArea {
                        id: closeMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.close()
                    }
                }
            }
        }
    }
}
