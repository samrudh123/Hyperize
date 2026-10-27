// The players deck — SUPER+M and the bottom bar's ⌃ chevron. Every player,
// in two columns: THIS LAPTOP and the PHONE (KDE Connect), each with its own
// controls (PlayersColumn.qml: hero player with cover, seek and ⇄ ⏮ ⏯ ⏭ ⟲,
// the side's other players, its own "Pause all", launchers).
//
//   ┌──────────────────────────────────────────────────────────────┐
//   │ ♫ Players   2 playing                   [⏸ Pause everything] │
//   │ ┌─ THIS LAPTOP ─────────────┐  ┌─ PHONE · My Phone ────────┐ │
//   │ │ ◉ cover   Title / artist  │  │ ◉ cover   Title / artist  │ │
//   │ │ ━━━━━━●────── 1:20  3:30  │  │ ━━━━●──────── 0:40  2:58  │ │
//   │ │      ⇄  ⏮  ⏯  ⏭  ⟲       │  │      ⏮  ⏯  ⏭              │ │
//   │ │ ALSO HERE: rows with ⏯    │  │                           │ │
//   │ │ [Spotify][YouTube][YT Mu] │  │ [Resume …][Phone menu]    │ │
//   │ └───────────────────────────┘  └───────────────────────────┘ │
//   └──────────────────────────────────────────────────────────────┘
//
// Which players exist: `media-menu.py --json` (the GTK menu's own filtering —
// Spotify mirrors, superseded KDE Connect copies, browser tab duplicates),
// every 2 s while open. Titles / art / playing are live MPRIS; the heroes'
// position, shuffle and repeat are the bar's now-playing.py feeds (npLocal /
// npRemote). media-menu.sh (GTK) still works, and is SUPER+M's fallback when
// the shell isn't running.
//
//   `qs ipc call players toggle|open|close` · BarState.panelRequested("players", "")
import QtQuick
import Quickshell
import Quickshell.Io

PanelPopup {
    id: pop

    property var npLocal: null
    property var npRemote: null
    edge: Edges.Top
    alignLeft: true                           // bottom-left, over the players
    leftMargin: Theme.islands ? 10 : 6
    panelWidth: 860
    pad: 16

    property var players: []
    property var last: null
    readonly property var localPlayers: players.filter(p => p.scope === "local")
    readonly property var remotePlayers: players.filter(p => p.scope === "remote")
    readonly property string device: {
        const r = remotePlayers.find(p => p.device);
        return r ? r.device : "";
    }
    readonly property int playingCount: localPlayers.filter(p => lcol.playingOf(p)).length
                                      + remotePlayers.filter(p => rcol.playingOf(p)).length

    function refresh() { if (!lister.running) lister.running = true; }
    Timer { id: soon; interval: 500; onTriggered: pop.refresh() }
    // run a command, then look again a moment later (the player list changes)
    function run(cmd) { Quickshell.execDetached(cmd); soon.restart(); }
    function launch(cmd) { close(); Theme.exec(cmd); }
    // a column clicked: swap the deck for that side's music panel (MediaPopup:
    // cover, controls, equalizer, lyrics) once the deck's focus grab is gone
    property var panelFor: null
    function openPanel(np) { panelFor = np; close(); panelTimer.restart(); }
    Timer {
        id: panelTimer
        interval: 190
        onTriggered: { if (pop.panelFor) pop.panelFor.openPanel(); pop.panelFor = null; }
    }
    function pauseAll(list) {
        const names = list.map(p => p.inst).filter(n => /^[\w.\-]+$/.test(n));
        if (names.length) run(["sh", "-c", names.map(n => "playerctl -p " + n + " pause").join("; ")]);
    }

    Process {
        id: lister
        command: ["/usr/bin/python3", Theme.hypr + "/media-menu.py", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    pop.players = d.players || [];
                    pop.last = d.last || null;
                } catch (e) {}
            }
        }
    }
    Timer {
        interval: 2000
        repeat: true
        running: pop.isOpen
        triggeredOnStart: true
        onTriggered: pop.refresh()
    }
    // the bar's playheads only tick while their pills are visible
    Timer {
        interval: 250
        repeat: true
        running: pop.isOpen
        onTriggered: {
            if (pop.npLocal) pop.npLocal.now = Date.now();
            if (pop.npRemote) pop.npRemote.now = Date.now();
        }
    }

    // staggered entrance: part k a little after part k-1
    function stage(k) { return Math.max(0, Math.min(1, (pop.intro - k * 0.14) / (1 - k * 0.14))); }

    Column {
        width: parent.width
        spacing: 14

        // ── header ──────────────────────────────────────────────────────────
        Item {
            width: parent.width
            height: 40
            opacity: pop.stage(0)
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12
                Rectangle {
                    width: 40
                    height: 40
                    radius: 12
                    color: Theme.alpha(Theme.accent, 0.18)
                    Text {
                        anchors.centerIn: parent
                        text: "\u{f0cb8}"                 // md-playlist_music
                        color: Theme.accent
                        font.family: Theme.font
                        font.pixelSize: 20
                    }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        text: "Players"
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: 18
                        font.weight: Font.Bold
                    }
                    Text {
                        text: pop.players.length === 0 ? "Nothing open anywhere"
                            : pop.playingCount === 0 ? "All paused"
                            : pop.playingCount + " playing"
                        color: pop.playingCount ? Theme.accent : Theme.overlay1
                        font.family: Theme.font
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }
                }
            }
            IconBtn {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: pop.playingCount > 0
                icon: "\u{f03e4}"
                text: "Pause everything"
                tipEdge: Edges.Top
                onClicked: pop.run(["playerctl", "-a", "pause"])
            }
        }

        // ── the two sides ───────────────────────────────────────────────────
        Row {
            id: cols
            width: parent.width
            spacing: 14
            readonly property real colW: (width - spacing) / 2
            readonly property real colH: Math.max(lcol.contentH, rcol.contentH)

            PlayersColumn {
                id: lcol
                deck: pop
                scope: "local"
                np: pop.npLocal
                players: pop.localPlayers
                last: pop.last && pop.last.scope === "local" ? pop.last : null
                width: cols.colW
                height: cols.colH
                reveal: pop.stage(1)
            }
            PlayersColumn {
                id: rcol
                deck: pop
                scope: "remote"
                np: pop.npRemote
                players: pop.remotePlayers
                last: pop.last && pop.last.scope === "remote" ? pop.last : null
                device: pop.device
                width: cols.colW
                height: cols.colH
                reveal: pop.stage(2)
            }
        }
    }
}
