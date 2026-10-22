// Workspaces 1–7 always (waybar's persistent-workspaces), plus any other
// that exists. The accent pill SLIDES to the focused workspace and stretches
// on the way, instead of jumping. Numbers are in the accent, faded when the
// workspace is empty; urgent ones turn red.
//
// Each number is followed by the icons of the apps open there (one per app,
// at most `maxIcons`, then "+n"), the dock's themed glyphs; on the focused
// workspace they are tinted to sit on the accent pill.
//
// Click = go there; click an app icon = focus that app's window there (again
// to cycle through them). Scroll = workspace-scroll.sh (the same stops as
// SUPER+scroll: occupied ones plus one empty).
//
// Hover, like the bar's pills: a workspace fills in the accent and the
// number and icons go dark; the focused (accent) and urgent (red) ones,
// already filled, just lighten.
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland

Item {
    id: root

    readonly property int persistent: 7
    readonly property var wsList: Hyprland.workspaces.values
    readonly property int focusedId: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1
    readonly property var ids: {
        const s = new Set();
        for (let i = 1; i <= persistent; i++) s.add(i);
        for (const w of wsList) if (w.id > 0) s.add(w.id);
        return Array.from(s).sort((a, b) => a - b);
    }

    function ws(id) {
        return wsList.find(w => w.id === id) || null;
    }

    readonly property int maxIcons: 3
    readonly property string iconDir: Theme.home + "/.local/share/nwg-dock-hyprland/mocha-icons"

    // The Wayland handle can lag a new window by a moment; Hyprland's class
    // is the same string.
    function appIdOf(t) {
        return (t.wayland && t.wayland.appId) || t.lastIpcObject["class"] || "";
    }

    // [{ id, wins }] — the workspace's windows grouped by app, in order
    function appsOn(w) {
        if (!w) return [];
        const out = [];
        for (const t of w.toplevels.values) {
            const id = appIdOf(t);
            if (!id) continue;
            const g = out.find(a => a.id.toLowerCase() === id.toLowerCase());
            if (g) g.wins.push(t);
            else out.push({ id: id, wins: [t] });
        }
        return out;
    }

    implicitWidth: row.width + 4
    implicitHeight: 32

    // The sliding accent pill. x/width follow the focused button.
    Rectangle {
        id: indicator
        readonly property Item btn: {
            for (let i = 0; i < rep.count; i++) {
                const b = rep.itemAt(i);
                if (b && b.wsId === root.focusedId) return b;
            }
            return null;
        }
        visible: btn !== null
        x: btn ? row.x + btn.x : 0
        width: btn ? btn.width : 0
        anchors.verticalCenter: parent.verticalCenter
        height: 32
        radius: 8
        color: btn && btn.hovered ? Qt.lighter(Theme.accent, 1.08) : Theme.accent
        Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutQuint } }
        Behavior on x { NumberAnimation { duration: 280; easing.type: Easing.OutBack; easing.overshoot: 0.9 } }
        Behavior on width { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
    }

    Row {
        id: row
        x: 2
        spacing: 4
        anchors.verticalCenter: parent.verticalCenter

        Repeater {
            id: rep
            model: root.ids

            Item {
                id: btn
                required property int modelData
                readonly property int wsId: modelData
                readonly property var w: root.ws(wsId)
                readonly property bool focused: wsId === root.focusedId
                readonly property bool occupied: w !== null && w.toplevels.values.length > 0
                readonly property bool urgent: w !== null && w.urgent
                readonly property var apps: root.appsOn(w)
                // the whole button, icons included (their MouseAreas take
                // the hover from `mouse`; a HoverHandler sees through them)
                readonly property bool hovered: hover.hovered
                // numbers in the accent: full when the workspace has windows,
                // faded when it is empty
                readonly property color rest: btn.occupied ? Theme.accent : Theme.alpha(Theme.accent, 0.45)
                readonly property bool filled: btn.focused || btn.urgent || btn.hovered

                HoverHandler { id: hover }

                width: content.implicitWidth + (focused ? 26 : 20)
                height: 32
                Behavior on width { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }

                Rectangle {
                    anchors.fill: parent
                    radius: 8
                    color: btn.focused ? Theme.alpha(Theme.surface0, 0)      // the indicator
                         : btn.urgent ? (btn.hovered ? Qt.lighter(Theme.red, 1.08) : Theme.red)
                         : btn.hovered ? Theme.accent
                         : Theme.alpha(btn.rest, 0)
                    Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutQuint } }
                }

                Row {
                    id: content
                    z: 1                    // the icons' clicks over the button's
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        id: label
                        anchors.verticalCenter: parent.verticalCenter
                        text: btn.wsId
                        font.family: Theme.font
                        font.pixelSize: 13
                        font.weight: btn.focused ? Font.Bold : Font.DemiBold
                        color: btn.filled ? Theme.crust : btn.rest
                        Behavior on color { ColorAnimation { duration: 200; easing.type: Easing.OutQuint } }
                    }

                    Row {
                        visible: btn.apps.length > 0
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3

                        Repeater {
                            model: btn.apps.slice(0, root.maxIcons)

                            Item {
                                id: app
                                required property var modelData
                                readonly property var entry: DesktopEntries.heuristicLookup(modelData.id)
                                readonly property bool active: modelData.wins.some(t => t.activated)
                                width: 16
                                height: 16

                                Image {
                                    id: glyph
                                    // the dock's themed glyph, else the app's own icon
                                    property bool themed: true
                                    anchors.fill: parent
                                    sourceSize: Qt.size(16, 16)
                                    source: themed ? "file://" + root.iconDir + "/" + app.modelData.id + ".svg?" + Theme.themeId
                                                   : Quickshell.iconPath(app.entry ? app.entry.icon : app.modelData.id, "application-x-executable")
                                    onStatusChanged: if (status === Image.Error && themed) themed = false
                                    opacity: btn.filled ? 1 : 0.75
                                    scale: appMouse.pressed ? 0.8 : appMouse.containsMouse ? 1.15 : 1
                                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                                    Behavior on opacity { NumberAnimation { duration: Theme.fast } }
                                    layer.enabled: btn.filled
                                    layer.effect: MultiEffect {
                                        colorization: 1
                                        colorizationColor: Theme.crust
                                        brightness: -0.6
                                    }
                                }

                                MouseArea {
                                    id: appMouse
                                    anchors.fill: parent
                                    anchors.margins: -2
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        const wins = app.modelData.wins;
                                        const i = wins.findIndex(t => t.activated);
                                        const t = wins[(i + 1) % wins.length];
                                        Hyprland.dispatch("focuswindow address:0x" + t.address);
                                    }
                                }

                                Tooltip {
                                    target: app
                                    shown: appMouse.containsMouse
                                    text: app.modelData.wins.map(t => (t.title || app.modelData.id).replace(/&/g, "&amp;").replace(/</g, "&lt;")).join("<br>")
                                }
                            }
                        }

                        Text {
                            visible: btn.apps.length > root.maxIcons
                            anchors.verticalCenter: parent.verticalCenter
                            text: "+" + (btn.apps.length - root.maxIcons)
                            font.family: Theme.font
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            color: label.color
                        }
                    }
                }

                // a small dot under numbers whose windows have no app id yet
                Rectangle {
                    visible: btn.occupied && !btn.focused && btn.apps.length === 0
                    width: 4
                    height: 2
                    radius: 1
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: parent.height - 7
                    color: btn.filled ? Theme.crust : Theme.alpha(Theme.accent, 0.6)
                }

                MouseArea {
                    id: mouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Hyprland.dispatch("workspace " + btn.wsId)
                }
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        property real acc: 0
        onWheel: wheel => {
            // raw, not Theme.wheelDelta(): this keeps the direction it had
            acc += wheel.angleDelta.y;
            if (Math.abs(acc) < 120) return;
            Theme.exec(Theme.hypr + "/workspace-scroll.sh " + (acc > 0 ? "prev" : "next"));
            acc = 0;
        }
    }
}
