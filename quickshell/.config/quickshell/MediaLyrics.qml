// The music panel's lyrics (hypr/lyrics.py → lrclib.net, cached in
// ~/.cache/lyrics). Synced lyrics follow the song: the line being sung is
// kept in the middle, bold and in the player's colour; click a line to jump
// there. Unsynced lyrics are a plain scrollable text.
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: ly

    property bool active: false             // panel open + this tab shown
    property string artist
    property string title
    property string album
    property real lengthS: 0
    property real posS: 0                   // playhead, seconds
    property bool seekable: false
    property color tint: Theme.accent

    signal seekRequested(real seconds)

    property string state_: "idle"          // idle | searching | synced | plain | none | error
    property var lines: []
    property string plain
    property string loadedKey
    readonly property string key: artist + "\x1f" + title

    // fetch lazily: when shown, for a track not fetched yet
    function maybeFetch() {
        if (!active || !title || key === loadedKey || proc.running) return;
        loadedKey = key;
        state_ = "searching";
        lines = [];
        plain = "";
        proc.command = ["/usr/bin/python3", Theme.hypr + "/lyrics.py", artist, title,
                        String(Math.round(lengthS)), album];
        proc.running = true;
    }
    onActiveChanged: maybeFetch()
    onKeyChanged: settle.restart()
    // metadata arrives a field at a time on a track change
    Timer { id: settle; interval: 350; onTriggered: ly.maybeFetch() }

    Process {
        id: proc
        stdout: StdioCollector {
            onStreamFinished: {
                let r;
                try { r = JSON.parse(text); } catch (e) { r = { error: "bad reply" }; }
                if (r.synced && r.synced.length) { ly.lines = r.synced; ly.plain = r.plain || ""; ly.state_ = "synced"; }
                else if (r.plain) { ly.plain = r.plain; ly.state_ = "plain"; }
                else if (r.error) { ly.state_ = "error"; ly.loadedKey = ""; }
                else ly.state_ = "none";
            }
        }
        // the track changed while this one was being fetched
        onExited: if (ly.key !== ly.loadedKey && ly.loadedKey !== "") ly.maybeFetch()
    }

    // the line being sung (a quarter second early, so it lights on the word)
    readonly property int current: {
        const t = posS + 0.25;
        let lo = 0, hi = lines.length - 1, ans = -1;
        while (lo <= hi) {
            const mid = (lo + hi) >> 1;
            if (lines[mid][0] <= t) { ans = mid; lo = mid + 1; } else hi = mid - 1;
        }
        return ans;
    }

    // ── synced ──────────────────────────────────────────────────────────────
    ListView {
        id: list
        anchors.fill: parent
        visible: ly.state_ === "synced"
        model: ly.lines
        clip: true
        spacing: 6
        currentIndex: Math.max(0, ly.current)
        highlightRangeMode: ListView.ApplyRange
        preferredHighlightBegin: height / 2 - 18
        preferredHighlightEnd: height / 2 + 18
        highlightMoveDuration: 420
        highlightMoveVelocity: -1
        boundsBehavior: Flickable.StopAtBounds
        header: Item { width: 1; height: list.height / 2 - 18 }
        footer: Item { width: 1; height: list.height / 2 - 18 }

        delegate: Item {
            id: row
            required property var modelData
            required property int index
            readonly property bool isCur: index === ly.current
            readonly property int dist: Math.abs(index - ly.current)
            width: list.width
            height: txt.implicitHeight + 6

            Text {
                id: txt
                x: 4
                width: parent.width - 8
                anchors.verticalCenter: parent.verticalCenter
                text: row.modelData[1] || "♪"
                wrapMode: Text.Wrap
                color: row.isCur ? ly.tint : lma.containsMouse ? Theme.text : row.index < ly.current ? Theme.overlay1 : Theme.subtext0
                opacity: row.isCur ? 1 : Math.max(0.35, 1 - row.dist * 0.14)
                font.family: Theme.font
                font.pixelSize: row.isCur ? 17 : 14
                font.weight: row.isCur ? Font.Bold : Font.Medium
                Behavior on color { ColorAnimation { duration: 260 } }
                Behavior on font.pixelSize { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            }
            MouseArea {
                id: lma
                anchors.fill: parent
                hoverEnabled: true
                enabled: ly.seekable
                cursorShape: Qt.PointingHandCursor
                onClicked: ly.seekRequested(row.modelData[0])
            }
        }
    }

    // ── plain ───────────────────────────────────────────────────────────────
    Flickable {
        anchors.fill: parent
        visible: ly.state_ === "plain"
        clip: true
        contentHeight: plainText.implicitHeight + 20
        boundsBehavior: Flickable.StopAtBounds
        Text {
            id: plainText
            x: 4
            y: 6
            width: parent.width - 8
            text: ly.plain
            wrapMode: Text.Wrap
            color: Theme.subtext0
            font.family: Theme.font
            font.pixelSize: 14
            lineHeight: 1.35
        }
    }

    // ── states ──────────────────────────────────────────────────────────────
    Column {
        anchors.centerIn: parent
        spacing: 10
        visible: ["searching", "none", "error", "idle"].includes(ly.state_)
        Text {
            id: stateIcon
            anchors.horizontalCenter: parent.horizontalCenter
            text: ly.state_ === "searching" ? "\u{f0349}" : ly.state_ === "error" ? "\u{f092d}" : "\u{f075b}"
            color: Theme.surface2
            font.family: Theme.font
            font.pixelSize: 30
            SequentialAnimation on opacity {
                running: ly.state_ === "searching"
                loops: Animation.Infinite
                onRunningChanged: if (!running) stateIcon.opacity = 1
                NumberAnimation { to: 0.3; duration: 500 }
                NumberAnimation { to: 1; duration: 500 }
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: ly.state_ === "searching" ? "Searching lyrics…"
                : ly.state_ === "error" ? "Couldn't reach lrclib.net"
                : ly.state_ === "none" ? "No lyrics found" : "Nothing playing"
            color: Theme.overlay1
            font.family: Theme.font
            font.pixelSize: 13
        }
        IconBtn {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: ly.state_ === "error"
            size: 28
            icon: "\u{f0450}"
            text: "Retry"
            tipEdge: Edges.Top
            onClicked: { ly.loadedKey = ""; ly.maybeFetch(); }
        }
    }
}
