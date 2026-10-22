// One player group on the bottom bar: [⏮  pill  ⏭]. Replaces the waybar
// CFFI plugin (waybar/modules/nowplaying.c) — same data, same gestures.
//
// All the logic stays in ~/.config/hypr/now-playing.py, run exactly as the
// plugin ran it (`/usr/bin/python3 …/now-playing.py --cffi --scope X`, so
// nudge_bars()' pkill pattern still finds it). One line per change, fields
// joined by \x1f:
//     text  classes  tooltip(\n -> \x1e)  pos_us  len_us  player  playing
//
//   pill            click: play/pause · right: media-menu · scroll: ±5 s
//   bottom 11 px    the seek zone: line thickens, knob + time bubble;
//                   click = jump, drag = seek on release (one request)
//   ⏮ ⏭            media-skip.sh prev|next <player>
import QtQuick
import Quickshell
import Quickshell.Io

Row {
    id: np

    required property string scope            // "local" | "remote"

    // last state from now-playing.py
    property string text
    property var classes: []
    property string tipText
    property real posUs: 0
    property real lenUs: 0
    property real posAt: 0                    // Date.now() of posUs
    property string player
    property bool playing: false
    property real holdUntil: 0                // optimistic seek, until data catches up

    readonly property bool hidden: classes.includes("hidden") || text === ""
    readonly property bool seekable: lenUs > 0 && player !== ""

    readonly property color tint: classes.includes("paused") ? Theme.subtext0
                                : classes.includes("spotify") ? Theme.green
                                : classes.includes("firefox") ? Theme.peach
                                : classes.includes("youtube") ? Theme.youtube
                                : classes.includes("ytmusic") ? Theme.pink : Theme.accent

    property real now: Date.now()
    readonly property real curUs: Math.min(lenUs, posUs + (playing ? (now - posAt) * 1000 : 0))
    readonly property real frac: lenUs > 0 ? curUs / lenUs : 0

    function fmt(us) {
        const s = Math.max(0, Math.floor(us / 1e6));
        const two = n => String(n).padStart(2, "0");
        return s >= 3600 ? Math.floor(s / 3600) + ":" + two(Math.floor(s / 60) % 60) + ":" + two(s % 60)
                         : Math.floor(s / 60) + ":" + two(s % 60);
    }

    function apply(line) {
        const f = line.split("\x1f");
        if (f.length < 7) return;
        text = Theme.pango(f[0]);
        classes = f[1].split(" ").filter(c => c);
        tipText = Theme.pango(f[2].replace(/\x1e/g, "\n"));
        if (Date.now() >= holdUntil) {
            posUs = Number(f[3]);
            posAt = Date.now();
        }
        lenUs = Number(f[4]);
        player = f[5];
        playing = f[6] === "1";
    }

    visible: !hidden
    spacing: 0

    Process {
        id: proc
        command: ["/usr/bin/python3", Theme.hypr + "/now-playing.py", "--cffi", "--scope", np.scope]
        running: true
        stdout: SplitParser { onRead: line => np.apply(line) }
        onExited: respawn.start()
    }
    Timer { id: respawn; interval: 3000; onTriggered: proc.running = true }

    // smooth playhead between updates
    Timer {
        interval: 250
        repeat: true
        running: np.playing && np.visible
        onTriggered: np.now = Date.now()
    }

    component SkipButton: Pill {
        required property string dir
        label: dir === "prev" ? "\u{f04ae}" : "\u{f04ad}"
        fg: Theme.subtext0
        hoverFg: Theme.text
        hoverBg: Theme.alpha(Theme.surface0, 0.8)
        fontSize: 15
        padLeft: 8
        padRight: 8
        tipEdge: Edges.Top
        tip: dir === "prev" ? "Previous (restarts if it can't go back)" : "Next"
        onClicked: button => {
            if (button === Qt.LeftButton && np.player)
                Theme.exec(Theme.hypr + "/media-skip.sh " + dir + " " + np.player);
        }
    }

    SkipButton { dir: "prev" }

    // ── the pill ────────────────────────────────────────────────────────────
    Item {
        id: pill
        width: body.width + 4
        height: 32

        Rectangle {
            id: body
            x: 2
            width: label.implicitWidth + 24
            height: 32
            radius: 8
            color: mouse.containsMouse && !mouse.inZone ? Theme.alpha(Theme.surface0, 0.9) : Theme.alpha(Theme.surface0, 0)
            Behavior on color { ColorAnimation { duration: Theme.fast; easing.type: Easing.OutQuint } }
            Behavior on width { NumberAnimation { duration: Theme.normal; easing.type: Easing.OutCubic } }

            Text {
                id: label
                x: 12
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -1
                text: np.text
                textFormat: Text.StyledText
                color: np.tint
                font.family: Theme.font
                font.pixelSize: 13
                font.weight: Font.DemiBold
                Behavior on color { ColorAnimation { duration: Theme.normal } }
            }

            // progress line: dim track + elapsed in the player's colour;
            // 5 px with a knob while the pointer is in the seek zone
            Item {
                id: line
                visible: np.seekable
                readonly property bool big: mouse.inZone || mouse.dragging
                x: 7
                width: parent.width - 14
                height: big ? 5 : 2
                y: parent.height - 3 - height
                Behavior on height { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                readonly property real shownFrac: mouse.dragging ? mouse.dragFrac : np.frac

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: Theme.alpha(Theme.surface1, 0.9)
                }
                Rectangle {
                    width: parent.width * line.shownFrac
                    height: parent.height
                    radius: height / 2
                    color: np.tint
                }
                Rectangle {
                    visible: line.big
                    width: 10
                    height: 10
                    radius: 5
                    x: parent.width * line.shownFrac - 5
                    anchors.verticalCenter: parent.verticalCenter
                    color: np.tint
                    border.width: 2
                    border.color: Theme.base
                }
            }

            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton

                readonly property int zone: 11
                property bool inZone: false
                property bool pressInZone: false
                property bool dragging: false
                property real pressX: 0
                property real dragFrac: 0
                property real ptrX: 0

                function frac(x) {
                    return Math.max(0, Math.min(1, (x - line.x) / line.width));
                }
                function updateZone(y) {
                    inZone = np.seekable && containsMouse && y >= height - zone;
                }

                cursorShape: inZone || dragging ? Qt.SizeHorCursor : Qt.PointingHandCursor
                onPositionChanged: ev => {
                    ptrX = ev.x;
                    if (pressed && pressInZone) {
                        if (Math.abs(ev.x - pressX) > 3) dragging = true;
                        dragFrac = frac(ev.x);
                    }
                    updateZone(ev.y);
                }
                onExited: if (!pressed) inZone = false
                onPressed: ev => {
                    if (ev.button !== Qt.LeftButton) return;
                    pressX = ev.x;
                    pressInZone = inZone;
                    dragging = false;
                    if (pressInZone) dragFrac = frac(ev.x);
                }
                onReleased: ev => {
                    if (ev.button === Qt.RightButton) {
                        Theme.exec(Theme.hypr + "/media-menu.sh");
                        return;
                    }
                    if (pressInZone && np.seekable) {
                        const f = dragging ? dragFrac : frac(ev.x);
                        const target = Math.round(f * np.lenUs);
                        Theme.exec("/usr/bin/python3 " + Theme.hypr + "/now-playing.py seekto " + np.player + " " + target);
                        np.posUs = target;
                        np.posAt = Date.now();
                        np.now = np.posAt;
                        np.holdUntil = np.posAt + 2000;
                    } else if (np.player && containsMouse) {
                        Theme.exec("playerctl -p " + np.player + " play-pause");
                    }
                    dragging = false;
                    pressInZone = false;
                    updateZone(ev.y);
                }

                property real acc: 0
                onWheel: wheel => {
                    acc += Theme.wheelDelta(wheel);
                    while (Math.abs(acc) >= 120) {
                        Theme.exec(Theme.hypr + "/media-seek.sh " + (acc > 0 ? "5+" : "5-") + " " + np.player);
                        acc -= acc > 0 ? 120 : -120;
                    }
                }
            }
        }

        Tooltip {
            target: body
            text: np.tipText
            shown: mouse.containsMouse && !mouse.inZone && !mouse.dragging
            edge: Edges.Top
        }

        // time under the pointer, above the line
        PopupWindow {
            visible: (mouse.inZone || mouse.dragging) && np.seekable
            color: "transparent"
            anchor.item: body
            anchor.rect.x: line.x + line.width * (mouse.dragging ? mouse.dragFrac : mouse.frac(mouse.ptrX))
            anchor.rect.y: -6
            anchor.gravity: Edges.Top
            implicitWidth: bubble.implicitWidth + 16
            implicitHeight: 24

            Rectangle {
                anchors.fill: parent
                radius: 8
                color: Theme.alpha(Theme.mantle, 0.97)
                border.width: 1
                border.color: np.tint
                Text {
                    id: bubble
                    anchors.centerIn: parent
                    text: np.fmt((mouse.dragging ? mouse.dragFrac : mouse.frac(mouse.ptrX)) * np.lenUs) + " / " + np.fmt(np.lenUs)
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
            }
        }
    }

    SkipButton { dir: "next" }
}
