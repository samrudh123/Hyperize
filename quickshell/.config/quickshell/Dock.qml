// Sidebar dock — replaces nwg-dock-hyprland. SUPER+A (dock-toggle.sh) shows
// and hides it: `qs ipc call dock toggle|open|close`.
//
// Same data nwg-dock used, so nothing else had to change:
//   ~/.cache/nwg-dock-pinned        pinned entries (bare window classes), live.
//                                   dock-places.sh appends dock-disk-* /
//                                   dock-trash (the bottom group); nwg-drawer's
//                                   "Pin to sidebar" (dock-pin.sh) writes here.
//   nwg-dock-hyprland/mocha-icons   the Mocha glyph icons (dock-theme-icons.py,
//                                   re-run at start and whenever pins change)
//
// Same shape: a content-sized pill on the left edge, vertically centred in
// the space the bars leave, `top` layer, no exclusive zone.
//
//   drag a pinned icon      reorder (written back to the pinned file)
//   right-click             menu: windows, new window, pin/unpin, close
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

PanelWindow {
    id: dock

    readonly property string iconDir: Theme.home + "/.local/share/nwg-dock-hyprland/mocha-icons"
    readonly property int step: 48            // button 44 + spacing 4

    // Starts hidden, like nwg-dock at login. Kept across config reloads
    // (quickshell hot-reloads on every save).
    property alias shown: state.shown
    PersistentProperties {
        id: state
        reloadableId: "dockState"
        property bool shown: false
    }

    readonly property var pinnedLines: pinnedFile.text().split("\n").map(l => l.trim()).filter(l => l.length > 0)
    readonly property var places: pinnedLines.filter(l => /^dock-disk-|^dock-trash$/.test(l))
    readonly property var pinned: pinnedLines.filter(l => !places.includes(l))

    readonly property var toplevels: ToplevelManager.toplevels.values

    // Pinned first, in file order, then running apps that are not pinned.
    // Case-insensitive: the pin says "spotify", the window "Spotify".
    readonly property var appIds: {
        const out = pinned.slice();
        const seen = new Set(pinned.map(id => id.toLowerCase()));
        for (const t of toplevels) {
            const key = t.appId.toLowerCase();
            if (!key || seen.has(key)) continue;
            seen.add(key);
            out.push(t.appId);
        }
        return out;
    }

    function windowsFor(appId) {
        const key = appId.toLowerCase();
        return toplevels.filter(t => t.appId.toLowerCase() === key);
    }

    function isPinned(appId) {
        return pinned.some(p => p.toLowerCase() === appId.toLowerCase());
    }

    // The file keeps its layout: pins in order, then the places.
    function writePins(list) {
        pinnedFile.setText(list.concat(places).join("\n") + "\n");
    }
    function pin(appId) {
        if (!isPinned(appId)) writePins(pinned.concat([appId]));
    }
    function unpin(appId) {
        writePins(pinned.filter(p => p.toLowerCase() !== appId.toLowerCase()));
    }

    // ── drag to reorder (pinned icons only) ─────────────────────────────────
    property int dragFrom: -1
    property int dragTo: -1
    property real dragDy: 0

    function dragMove(index, dy) {
        dragFrom = index;
        dragDy = dy;
        dragTo = Math.max(0, Math.min(pinned.length - 1, index + Math.round(dy / step)));
    }
    // On drop the icon is shown in its new slot; once the pinned list has
    // changed (and the column re-laid out) every offset snaps back to 0 with
    // animations off, so nothing visibly moves twice.
    property bool dropping: false
    property bool noAnim: false

    function dragEnd() {
        if (dragFrom >= 0 && dragTo >= 0 && dragTo !== dragFrom) {
            dropping = true;
            dragDy = (dragTo - dragFrom) * step;
            const list = pinned.slice();
            list.splice(dragTo, 0, list.splice(dragFrom, 1)[0]);
            dropTimer.restart();
            writePins(list);
        } else {
            resetDrag();
        }
    }
    function resetDrag() {
        noAnim = true;
        dropping = false;
        dragFrom = dragTo = -1;
        dragDy = 0;
        Qt.callLater(() => noAnim = false);
    }
    // same event-loop turn as the re-layout, so one frame shows both
    onPinnedChanged: if (dropping) resetDrag()
    Timer { id: dropTimer; interval: 1500; onTriggered: if (dock.dropping) dock.resetDrag() }

    // where icon `i` should sit while another one is being dragged
    function shiftFor(i) {
        if (dragFrom < 0 || i === dragFrom) return 0;
        if (dragFrom < dragTo && i > dragFrom && i <= dragTo) return -step;
        if (dragFrom > dragTo && i >= dragTo && i < dragFrom) return step;
        return 0;
    }

    FileView {
        id: pinnedFile
        path: Theme.home + "/.cache/nwg-dock-pinned"
        watchChanges: true
        onFileChanged: { reload(); icons.running = true; }
    }

    // Mocha icons for anything new (fast: unchanged files are not rewritten).
    Process {
        id: icons
        running: true
        command: ["/usr/bin/python3", Theme.hypr + "/dock-theme-icons.py"]
    }

    IpcHandler {
        target: "dock"
        function toggle(): void { dock.shown = !dock.shown; }
        function open(): void { dock.shown = true; }
        function close(): void { dock.shown = false; }
    }

    anchors.left: true
    margins.left: 6
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "qs-dock"     // layerrule blur-qs-dock in hyprland.conf
    color: "transparent"

    implicitWidth: slab.width
    implicitHeight: slab.height
    // Stay mapped until the slide-out has finished.
    visible: shown || slab.x > -slab.width

    onShownChanged: if (!shown) { tooltip.target = null; menu.close(); }

    Rectangle {
        id: slab

        x: dock.shown ? 0 : -width
        Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

        width: column.width + 2 * 5
        height: column.height + 2 * 9
        radius: 16
        color: Theme.alpha(Theme.base, 0.80)
        border.width: 1
        border.color: Theme.alpha(Theme.surface1, 0.70)

        Column {
            id: column
            anchors.centerIn: parent
            spacing: 4

            Repeater {
                model: ScriptModel { values: dock.appIds }
                delegate: DockButton {
                    id: app
                    required property string modelData
                    required property int index
                    appId: modelData
                    pinned: dock.isPinned(modelData)
                    windows: dock.windowsFor(modelData)
                    iconDir: dock.iconDir
                    accent: Theme.accent
                    dragging: dock.dragFrom === index
                    dragDy: dock.dragFrom === index ? dock.dragDy : 0
                    shift: dock.shiftFor(index)
                    animate: !dock.noAnim && (!dragging || dock.dropping)
                    onLaunch: cmd => Theme.exec(cmd)
                    onHoveredChanged: tooltip.track(app, hovered)
                    onMenuRequested: menu.openFor(app)
                    onDragMoved: dy => dock.dragMove(index, dy)
                    onDragEnded: dock.dragEnd()
                }
            }

            // Bottom group: places (disks, trash), under a painted separator
            // (inset 8px either side, as in nwg-dock's style.css). The app
            // grid button moved to the top bar's left corner.
            Item {
                visible: dock.places.length > 0
                width: 44
                height: 13
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    x: 8
                    width: parent.width - 16
                    height: 1
                    color: Theme.alpha(Theme.surface1, 0.9)
                }
            }

            Repeater {
                model: ScriptModel { values: dock.places }
                delegate: DockButton {
                    id: placeBtn
                    required property string modelData
                    appId: modelData
                    place: true
                    iconDir: dock.iconDir
                    accent: Theme.accent
                    onLaunch: cmd => Theme.exec(cmd)
                    onHoveredChanged: tooltip.track(placeBtn, hovered)
                    onMenuRequested: menu.openFor(placeBtn)
                }
            }
        }
    }

    // ── right-click menu ────────────────────────────────────────────────────
    MenuPopup {
        id: menu

        property Item btn: null
        readonly property var wins: btn ? btn.windows : []

        function openFor(b) {
            tooltip.target = null;
            if (isOpen && btn === b) { close(); return; }
            btn = b;
            open(b);
        }

        edge: Edges.Right
        minWidth: 210
        onDismissed: btn = null

        MenuRow {
            header: true
            text: menu.btn ? menu.btn.label : ""
        }

        // one row per open window: click focuses it
        Repeater {
            model: menu.wins.length > 1 ? menu.wins.slice(0, 8) : []
            MenuRow {
                required property var modelData
                text: modelData.title || "(untitled)"
                glyph: modelData.activated ? "\u{f09de}" : "\u{f05b2}"    // md-circle_medium / md-window_restore
                glyphColor: modelData.activated ? Theme.accent : Theme.overlay2
                onActivated: { modelData.activate(); menu.close(); }
            }
        }
        MenuRow { separator: true; visible: menu.wins.length > 1 }

        MenuRow {
            visible: menu.btn !== null && !menu.btn.place
            text: menu.wins.length > 0 ? "New window" : "Open"
            glyph: "\u{f0415}"                  // md-plus
            onActivated: { menu.btn.start(); menu.close(); }
        }
        MenuRow {
            visible: menu.btn !== null && menu.btn.place
            text: "Open"
            glyph: "\u{f03cc}"                  // md-open_in_new
            onActivated: { menu.btn.start(); menu.close(); }
        }
        MenuRow {
            visible: menu.btn !== null && !menu.btn.place
            readonly property bool isPin: menu.btn !== null && dock.isPinned(menu.btn.appId)
            text: isPin ? "Unpin from dock" : "Pin to dock"
            glyph: isPin ? "\u{f0404}" : "\u{f0403}"    // md-pin_off / md-pin
            onActivated: {
                const id = menu.btn.appId;
                if (isPin) dock.unpin(id); else dock.pin(id);
                menu.close();
            }
        }

        MenuRow { separator: true; visible: menu.wins.length > 0 }
        MenuRow {
            visible: menu.wins.length > 0
            danger: true
            text: menu.wins.length > 1 ? "Close " + menu.wins.length + " windows" : "Close window"
            glyph: "\u{f0156}"                  // md-close
            onActivated: {
                for (const w of menu.wins) w.close();
                menu.close();
            }
        }
    }

    // ── one tooltip for every button, opened beside whichever is hovered ────
    PopupWindow {
        id: tooltip

        property Item target: null
        property Item pending: null

        function track(btn, hovered) {
            if (menu.isOpen || dock.dragFrom >= 0) return;
            if (hovered) {
                pending = btn;
                if (target) target = btn;      // already showing: follow at once
                else delay.restart();
            } else if (pending === btn) {
                pending = null;
                target = null;
                delay.stop();
            }
        }

        Timer {
            id: delay
            interval: 450
            onTriggered: tooltip.target = tooltip.pending
        }

        visible: target !== null && dock.shown && dock.dragFrom < 0
        anchor.item: target
        anchor.rect.x: target ? target.width + 14 : 0
        anchor.rect.y: target ? target.height / 2 : 0
        anchor.gravity: Edges.Right
        color: "transparent"

        implicitWidth: tipText.implicitWidth + 2 * 10
        implicitHeight: tipText.implicitHeight + 2 * 6

        Rectangle {
            anchors.fill: parent
            radius: 9
            color: Theme.alpha(Theme.crust, 0.97)
            border.width: 1
            border.color: Theme.surface1

            Text {
                id: tipText
                anchors.centerIn: parent
                text: tooltip.target ? tooltip.target.label : ""
                color: Theme.text
                font.family: Theme.uiFont
                font.pixelSize: 12
                font.weight: Font.Medium
            }
        }
    }
}
