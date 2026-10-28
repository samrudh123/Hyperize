// System tray (StatusNotifierItem). Left click activates the app (or opens
// its menu if that is all it has), middle click is the secondary action,
// right click opens the app's menu — drawn as a themed card rather than a
// stock Qt menu. Submenus open in place, with a back row.
//
// Hover, like the bar's pills: the icon's square fills in the accent and the
// icon is tinted dark (icons have no text colour of their own).
//
// Vesktop's icon has a panel of its own (VesktopPopup.qml): left click opens
// it (and it is in the Ctrl+← / → round), middle click shows Vesktop, right
// click is still its menu.
//
// nm-applet and blueman's icons are hidden: the network / Bluetooth pills and
// their panels do that job. The applets keep running for what they do
// behind the scenes (Wi-Fi password and Bluetooth pairing prompts).
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.SystemTray

Item {
    id: tray

    readonly property var hidden: ["nm-applet", "blueman"]

    implicitWidth: row.width > 0 ? row.width + 16 : 0
    implicitHeight: 32
    visible: SystemTray.items.values.some(i => !hidden.includes(i.id))

    Row {
        id: row
        x: 8
        spacing: 10
        anchors.verticalCenter: parent.verticalCenter

        Repeater {
            id: rep
            model: SystemTray.items

            Item {
                id: icon
                required property SystemTrayItem modelData
                visible: !tray.hidden.includes(modelData.id)
                readonly property bool isVesktop: /vesktop/i.test(modelData.id)
                readonly property var panel: panelLoader.item
                // its panel is open from the keyboard: look hovered (Pill.navHot)
                readonly property bool hot: mouse.containsMouse
                    || (!!panel && panel.isOpen && BarState.kbMode && BarState.activePopup === panel)

                LazyLoader {
                    id: panelLoader
                    active: icon.isVesktop
                    VesktopPopup { pill: icon; item: icon.modelData }
                }
                width: 22
                height: 32

                Rectangle {
                    anchors.centerIn: parent
                    width: 26
                    height: 26
                    radius: 7
                    color: icon.hot ? Theme.accent : Theme.alpha(Theme.accent, 0)
                    Behavior on color { ColorAnimation { duration: Theme.fast } }
                }

                IconImage {
                    anchors.centerIn: parent
                    implicitSize: 15
                    source: icon.modelData.icon
                    // Passive items are dimmed (waybar: -gtk-icon-effect: dim)
                    opacity: icon.modelData.status === Status.Passive && !icon.hot ? 0.55 : 1
                    layer.enabled: icon.hot
                    layer.effect: MultiEffect {
                        colorization: 1
                        colorizationColor: Theme.crust
                        brightness: -0.6
                    }
                }

                MouseArea {
                    id: mouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: ev => {
                        const item = icon.modelData;
                        if (icon.panel && ev.button === Qt.LeftButton) icon.panel.toggle();
                        else if (icon.panel && ev.button === Qt.MiddleButton) item.activate();
                        else if (ev.button === Qt.MiddleButton) item.secondaryActivate();
                        else if (ev.button === Qt.RightButton || item.onlyMenu) {
                            if (item.hasMenu) menu.openFor(icon, item.menu);
                        } else item.activate();
                    }
                    onWheel: wheel => icon.modelData.scroll(wheel.angleDelta.y / 120, false)
                }

                Tooltip {
                    target: icon
                    text: icon.modelData.tooltipTitle || icon.modelData.title || icon.modelData.id
                    shown: mouse.containsMouse && !menu.isOpen && !(icon.panel && icon.panel.isOpen)
                }
            }
        }
    }

    MenuPopup {
        id: menu

        // the stack of open (sub)menus; the last one is shown
        property var stack: []

        function openFor(item, handle) {
            if (isOpen && anchor.item === item) { close(); return; }
            stack = [handle];
            open(item);
        }

        onDismissed: stack = []

        QsMenuOpener {
            id: opener
            menu: menu.stack.length ? menu.stack[menu.stack.length - 1] : null
        }

        MenuRow {
            visible: menu.stack.length > 1
            text: "Back"
            glyph: "\u{f0141}"          // md-chevron_left
            onActivated: menu.stack = menu.stack.slice(0, -1)
        }
        MenuRow {
            visible: menu.stack.length > 1
            separator: true
        }

        Repeater {
            model: opener.children

            MenuRow {
                required property QsMenuEntry modelData
                text: modelData.text.replace(/_(?!_)/g, "")   // strip mnemonics
                separator: modelData.isSeparator
                enabled: modelData.enabled
                iconSource: modelData.icon
                submenu: modelData.hasChildren
                check: modelData.buttonType === QsMenuButtonType.None ? -1
                     : modelData.checkState === Qt.Checked ? 1 : 0
                onActivated: {
                    if (modelData.hasChildren) {
                        menu.stack = menu.stack.concat([modelData]);
                    } else {
                        modelData.triggered();
                        menu.close();
                    }
                }
            }
        }
    }
}
