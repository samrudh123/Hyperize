// One dock icon: a pinned app, a running app or a place (disk / trash).
//
//   left click    focus the app; again to cycle its windows; launch if none
//   middle click  always launch a new instance
//   right click   the dock's menu (Dock.qml)
//   drag          reorder — pinned apps only; the dock does the bookkeeping
import QtQuick
import Quickshell

Item {
    id: btn

    required property string appId
    property bool pinned: false
    property bool place: false             // no running state, always launches
    property var windows: []               // Toplevels whose appId matches
    property string command: ""            // overrides the desktop entry
    property string iconDir
    property color accent

    // drag state, driven by the dock
    property bool dragging: false
    property real dragDy: 0
    property real shift: 0
    property bool animate: true

    // DesktopEntries fills in asynchronously; touching `applications` makes
    // this re-run once it has. Last resort is a loose id/name match: the pin
    // "JDownloader" only exists as install4j_1nco9fl-JDownloader2.desktop,
    // whose StartupWMClass is the updater's.
    readonly property var entry: {
        if (command) return null;
        const apps = DesktopEntries.applications.values;
        const exact = DesktopEntries.heuristicLookup(appId);
        if (exact) return exact;
        const key = appId.toLowerCase();
        return apps.find(a => a.id.toLowerCase().includes(key) || a.name.toLowerCase().startsWith(key)) ?? null;
    }
    property string label: entry ? entry.name : (windows.length > 0 ? windows[0].title : appId)

    readonly property bool running: windows.length > 0
    readonly property bool active: windows.some(w => w.activated)
    readonly property bool hovered: mouse.containsMouse

    signal launch(string cmd)
    signal menuRequested()
    signal dragMoved(real dy)
    signal dragEnded()

    function start() {
        if (command) launch(command);
        else if (entry) launch("gtk-launch " + entry.id);
        else launch(appId.toLowerCase());
    }

    // Focus the app; if one of its windows is already focused, move to the next.
    function focusNext() {
        const i = windows.findIndex(w => w.activated);
        windows[(i + 1) % windows.length].activate();
    }

    implicitWidth: 44
    implicitHeight: 44
    z: dragging ? 10 : 0

    // The dragged icon follows the pointer; the others slide out of its way.
    transform: Translate {
        y: btn.dragging ? btn.dragDy : btn.shift
        Behavior on y {
            enabled: btn.animate
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 12
        // surface0: 95% on hover / while dragged, a quieter 70% resting pill
        // for the focused app
        color: Theme.alpha(Theme.surface0, btn.dragging || mouse.containsMouse ? 0.95 : btn.active ? 0.70 : 0)
        border.width: btn.active || btn.dragging ? 1 : 0
        border.color: Theme.alpha(btn.accent, btn.dragging ? 0.6 : 0.35)
        Behavior on color { ColorAnimation { duration: Theme.fast; easing.type: Easing.OutQuint } }
    }

    // Running indicator: an accent bar in the slab's left padding, taller for
    // the focused app.
    Rectangle {
        visible: !btn.dragging
        x: -5
        anchors.verticalCenter: parent.verticalCenter
        width: 3
        radius: 1.5
        height: btn.active ? 20 : btn.running ? 8 : 0
        opacity: btn.running ? 1 : 0
        color: btn.accent
        Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 200 } }
    }

    Image {
        id: icon

        // Mocha glyph first; the app's own themed icon if there is none yet.
        property bool themed: true

        anchors.centerIn: parent
        width: 30
        height: 30
        sourceSize: Qt.size(30, 30)
        // ?theme: a theme switch redraws the icons (set-theme.sh) — new URL, new load
        source: themed ? "file://" + btn.iconDir + "/" + btn.appId + ".svg?" + Theme.themeId
                       : Quickshell.iconPath(btn.entry ? btn.entry.icon : btn.appId, "application-x-executable")
        onStatusChanged: if (status === Image.Error && themed) themed = false

        scale: btn.dragging ? 1.08 : mouse.pressed ? 0.86 : 1
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        cursorShape: btn.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor

        // in the column's coordinates: they do not move while this icon does
        property real pressY: 0
        property bool moved: false

        onPressed: ev => {
            moved = false;
            pressY = mapToItem(btn.parent, ev.x, ev.y).y;
        }
        onPositionChanged: ev => {
            if (!pressed || !(pressedButtons & Qt.LeftButton) || !btn.pinned) return;
            const dy = mapToItem(btn.parent, ev.x, ev.y).y - pressY;
            if (!moved && Math.abs(dy) < 6) return;
            moved = true;
            btn.dragMoved(dy);
        }
        onReleased: ev => {
            if (moved) {
                moved = false;
                btn.dragEnded();
                return;
            }
            if (!containsMouse) return;
            if (ev.button === Qt.RightButton) btn.menuRequested();
            else if (ev.button === Qt.MiddleButton || btn.place || !btn.running) btn.start();
            else btn.focusNext();
        }
        onCanceled: if (moved) { moved = false; btn.dragEnded(); }
    }
}
