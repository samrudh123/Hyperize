// The opacity OSD — SUPER+SHIFT+Scroll over a window (opacity.sh calls
// `qs ipc call osd opacity <class> <pct> <appDefault> <globalDefault>`).
// Replaces the mako progress-bar notification.
//
// Top right, under the bar, where the notification used to be. It shows the
// app, the level, a bar with the app's default marked on it, and — only while
// the level differs from that default — a "Make default" button. One click
// saves it for the app (opacity.sh set-default → opacity-defaults.conf) and
// moves the app's other windows that were still at the old default. Hovering
// keeps the OSD up; otherwise it fades after a moment. Nothing else pops up.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

PanelWindow {
    id: osd

    property string cls
    property int pct: 92
    property int appDefault: 92
    property int globalDefault: 92
    property bool saved: false
    property bool shown: false

    readonly property string appName: {
        DesktopEntries.applications.values;
        const e = cls ? DesktopEntries.heuristicLookup(cls) : null;
        if (e && e.name) return e.name;
        const tail = cls.split(".").pop() || cls;
        return tail.charAt(0).toUpperCase() + tail.slice(1);
    }
    readonly property bool isDefault: pct === appDefault

    IpcHandler {
        target: "osd"
        function opacity(cls: string, pct: int, appDefault: int, globalDefault: int): void {
            osd.cls = cls;
            osd.pct = pct;
            osd.appDefault = appDefault;
            osd.globalDefault = globalDefault;
            osd.saved = false;
            osd.shown = true;
            // longer while the button is offered: time to reach it
            hide.interval = pct === appDefault ? 1500 : 3000;
            if (!hover.hovered) hide.restart();
        }
    }

    function makeDefault() {
        Theme.exec(Theme.hypr + "/opacity.sh set-default " + cls + " " + pct);
        appDefault = pct;
        saved = true;
        hide.interval = 1600;
        if (!hover.hovered) hide.restart();
    }

    Timer {
        id: hide
        interval: 1500
        onTriggered: osd.shown = false
    }

    anchors { top: true; right: true }
    margins { top: 10; right: 10 }
    exclusiveZone: 0                     // sits under the bar, reserves nothing
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "qs-osd"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    color: "transparent"

    implicitWidth: 340
    implicitHeight: card.height
    visible: shown || card.opacity > 0

    Rectangle {
        id: card
        width: parent.width
        height: col.implicitHeight + 2 * 14
        radius: 12
        color: Theme.alpha(Theme.mantle, 0.97)
        border.width: 1
        border.color: Theme.surface1

        opacity: osd.shown ? 1 : 0
        y: osd.shown ? 0 : -8
        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        HoverHandler {
            id: hover
            onHoveredChanged: {
                if (hovered) hide.stop();
                else if (osd.shown) { hide.interval = 900; hide.restart(); }
            }
        }

        Column {
            id: col
            x: 14
            y: 14
            width: parent.width - 28
            spacing: 10

            // app + level
            Item {
                width: parent.width
                height: 20
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u{f05af}  " + osd.appName      // md-window_maximize
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    width: parent.width - pctText.width - 10
                }
                Text {
                    id: pctText
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: osd.pct + "%"
                    color: Theme.accent
                    font.family: Theme.font
                    font.pixelSize: 14
                    font.weight: Font.Bold
                }
            }

            // the bar: 70..100 is the whole range opacity.sh allows
            Item {
                width: parent.width
                height: 8
                readonly property real lo: 70
                readonly property real hi: 100
                function pos(v) { return width * Math.max(0, Math.min(1, (v - lo) / (hi - lo))); }

                Rectangle {
                    anchors.fill: parent
                    radius: 4
                    color: Theme.surface0
                }
                Rectangle {
                    width: Math.max(8, parent.pos(osd.pct))
                    height: parent.height
                    radius: 4
                    color: Theme.accent
                    Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                }
                // the app's default
                Rectangle {
                    x: parent.pos(osd.appDefault) - 1
                    y: -3
                    width: 2
                    height: parent.height + 6
                    radius: 1
                    color: osd.isDefault ? Theme.crust : Theme.text
                    opacity: 0.85
                    Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                }
            }

            // default line: a label, or the button
            Item {
                width: parent.width
                height: 28

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: osd.saved ? "\u{f012c}  Saved — new " + osd.appName + " windows open at " + osd.pct + "%"
                        : osd.isDefault ? "\u{f012c}  " + osd.appName + "'s default"
                        : "Default " + osd.appDefault + "%"
                    color: osd.saved ? Theme.green : Theme.overlay2
                    font.family: Theme.font
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                    width: parent.width - (button.visible ? button.width + 10 : 0)
                }

                Rectangle {
                    id: button
                    visible: !osd.isDefault && !osd.saved
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: btnText.implicitWidth + 22
                    height: 28
                    radius: 8
                    color: btnMouse.containsMouse ? Theme.accent : Theme.alpha(Theme.surface0, 0.9)
                    Behavior on color { ColorAnimation { duration: Theme.fast } }

                    Text {
                        id: btnText
                        anchors.centerIn: parent
                        text: "\u{f0403}  Make " + osd.pct + "% default"
                        color: btnMouse.containsMouse ? Theme.crust : Theme.accent
                        font.family: Theme.font
                        font.pixelSize: 12
                        font.weight: Font.Bold
                    }
                    MouseArea {
                        id: btnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: osd.makeDefault()
                    }
                }
            }
        }
    }
}
