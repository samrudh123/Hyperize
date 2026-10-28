// The music panel (Serpantinum's music popup) above a bottom-bar player:
// right-click the player's title (NowPlaying.qml) — or
// `qs ipc call mediapanel toggle` (laptop player) /
// `qs ipc call mediapanel-phone toggle` (phone player).
//
//   ┌────────────────────────────────────────────────┐
//   │  ◉ spinning cover    Title                     │
//   │    + spectrum ring   By Artist                 │
//   │                      [ Speaker ] [ Via Zen ]   │
//   │                      ━━━━━━━●──────  1:40 3:38 │
//   │                        ⇄  ⏮  ⏯  ⏭  ⟲         │
//   ├────────────────────────────────────────────────┤
//   │  [ Equalizer | Lyrics ]   (Lyrics: Spotify only) │
//   │  MediaEq / MediaLyrics                          │
//   └────────────────────────────────────────────────┘
//
// Position, length and playing come from the bar's now-playing.py feed (`np`,
// which already works around KDE Connect's wrong positions); title, artist,
// album, art and identity from MPRIS. Play/seek/skip use the bar's commands.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire

PanelPopup {
    id: pop
    tabBar: menuTabs                          // Ctrl+Tab / Ctrl+Shift+Tab cycle it
    TabFade { id: tabFx; key: pop.shownTab; active: pop.isOpen }   // soft tab swap

    property var np: null
    edge: Edges.Top
    panelWidth: 560
    pad: 16

    // ── the player ──────────────────────────────────────────────────────────
    readonly property string playerName: np ? np.player : ""
    readonly property var mp: {
        if (!playerName) return null;
        const want = "org.mpris.MediaPlayer2." + playerName;
        return Mpris.players.values.find(p => p.dbusName === want) || null;
    }
    readonly property bool phone: !!np && np.scope === "remote"
    // the player's colour, also while paused (np.tint greys out then)
    readonly property color col: {
        const c = np ? np.classes : [];
        return c.includes("spotify") ? Theme.green : c.includes("firefox") ? Theme.peach
             : c.includes("zen") ? Theme.mauve : c.includes("youtube") ? Theme.youtube
             : c.includes("ytmusic") ? Theme.pink : Theme.accent;
    }
    readonly property string title: mp && mp.trackTitle ? mp.trackTitle
                                   : np ? np.text.replace(/<[^>]*>/g, "").replace(/&nbsp;/g, " ").trim() : ""
    readonly property string artist: mp ? (mp.trackArtist || "") : ""
    readonly property string album: mp ? (mp.trackAlbum || "") : ""
    readonly property string art: mp ? (mp.trackArtUrl || "") : ""
    readonly property string via: {
        const id = mp ? mp.identity : "";
        return phone ? id.replace(/ - [^-]*$/, "") : id;     // "YouTube Morphe - My Phone" → "YouTube Morphe"
    }
    readonly property var sink: Pipewire.defaultAudioSink
    PwObjectTracker { objects: [pop.sink] }
    readonly property string output: phone ? "\u{f011c}  Phone"
        : sink ? ((sink.name || "").startsWith("bluez") ? "\u{f02cb}  " : "\u{f04c3}  ")
                 + (sink.nickname || sink.description || "Speaker") : ""

    function seekTo(us) {
        if (!np || !np.seekable) return;
        const target = Math.max(0, Math.min(np.lenUs, Math.round(us)));
        Theme.exec("/usr/bin/python3 " + Theme.hypr + "/now-playing.py seekto " + np.player + " " + target);
        np.posUs = target;
        np.posAt = Date.now();
        np.now = np.posAt;
        np.holdUntil = np.posAt + 2000;
    }

    // np's playhead only ticks while its pill is visible; keep it moving here
    Timer {
        interval: 250
        repeat: true
        running: pop.isOpen && !!pop.np && pop.np.playing
        onTriggered: pop.np.now = Date.now()
    }

    // keybind / testing hook: the laptop player's panel and the phone's,
    // on the focused screen's bar only
    readonly property var barWindow: anchor.window
    readonly property bool onActiveScreen: !!barWindow && !!barWindow.screen
                                           && barWindow.screen.name === BarState.active
    IpcHandler {
        target: pop.phone ? "mediapanel-phone" : "mediapanel"
        enabled: !!pop.np && pop.onActiveScreen
        function toggle(): void { if (pop.np && pop.np.visible) pop.toggle(); }
        function open(): void { if (pop.np && pop.np.visible) pop.open(); }
        function close(): void { pop.close(); }
        // equalizer | lyrics
        function tab(name: string): void { pop.tab = name === "equalizer" ? 0 : 1; }
    }
    // the player went away: nothing to show
    Connections {
        target: pop.np
        function onHiddenChanged() { if (pop.np.hidden) pop.close(); }
    }

    property int tab: 1                   // 0 equalizer, 1 lyrics (kept between opens)
    // lyrics only for Spotify (laptop app, phone app, the Web API bridge):
    // video titles from YouTube & co. rarely match a song on lrclib
    readonly property bool hasLyrics: !!np && np.classes.includes("spotify")
    // the equalizer only shapes THIS laptop's audio: no use for a phone player
    readonly property bool hasEq: !phone
    readonly property bool hasLower: hasEq || hasLyrics
    readonly property int shownTab: !hasLyrics ? 0 : !hasEq ? 1 : tab

    // staggered entrance: part k fades/slides in a little after part k-1
    function stage(k) { return Math.max(0, Math.min(1, (pop.intro - k * 0.12) / (1 - k * 0.12))); }

    Column {
        width: parent.width
        spacing: 14

        // ── now playing ─────────────────────────────────────────────────────
        Row {
            width: parent.width
            spacing: 14
            opacity: pop.stage(0)
            transform: Translate { y: 14 * (1 - pop.stage(0)) }

            MediaCover {
                id: cover
                art: pop.art
                tint: pop.col
                playing: !!pop.np && pop.np.playing
                listen: pop.isOpen
                fake: pop.phone
                coverSize: 150
            }

            Column {
                id: info
                width: parent.width - cover.width - parent.spacing
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                Item {
                    width: parent.width
                    height: titleText.implicitHeight
                    Text {
                        id: titleText
                        width: parent.width - playersBtn.width - 6
                        text: pop.title || "Nothing playing"
                        elide: Text.ElideRight
                        maximumLineCount: 2
                        wrapMode: Text.Wrap
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: 18
                        font.weight: Font.Bold
                    }
                    IconBtn {
                        id: playersBtn
                        anchors.right: parent.right
                        size: 26
                        iconSize: 14
                        icon: "\u{f0cb8}"                 // md-playlist_music
                        tip: "All players (SUPER+M)"
                        tipEdge: Edges.Top
                        onClicked: { pop.close(); BarState.panelRequested("players", ""); }
                    }
                }
                Text {
                    width: parent.width
                    visible: pop.artist !== ""
                    text: "By " + pop.artist
                    elide: Text.ElideRight
                    color: Theme.subtext0
                    font.family: Theme.font
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }

                // chips: where it plays, what plays it
                Flow {
                    width: parent.width
                    spacing: 6
                    Repeater {
                        model: [pop.output, pop.via ? "Via " + pop.via : ""].filter(s => s)
                        Rectangle {
                            required property string modelData
                            width: chip.implicitWidth + 16
                            height: 22
                            radius: 7
                            color: Theme.alpha(Theme.surface0, 0.9)
                            border.width: 1
                            border.color: Theme.alpha(pop.col, 0.25)
                            Text {
                                id: chip
                                anchors.centerIn: parent
                                text: parent.modelData.length > 34 ? parent.modelData.slice(0, 33) + "…" : parent.modelData
                                color: Theme.subtext1
                                font.family: Theme.font
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                            }
                        }
                    }
                }

                // seek
                Column {
                    width: parent.width
                    spacing: 2
                    visible: !!pop.np && pop.np.lenUs > 0
                    Slider {
                        id: seek
                        width: parent.width
                        color: pop.col
                        enabled: !!pop.np && pop.np.seekable
                        value: pop.np ? pop.np.frac : 0
                        // seek on release (one request), like the bar's seek zone
                        property real want: -1
                        onMoved: v => want = v
                        onDraggingChanged: if (!dragging && want >= 0) { pop.seekTo(want * pop.np.lenUs); want = -1; }
                        // a scroll notch = 5 s; it has no release, so the timer seeks
                        step: pop.np && pop.np.lenUs > 0 ? Math.min(0.5, 5e6 / pop.np.lenUs) : 0.05
                        Timer {
                            interval: 120
                            running: seek.want >= 0 && !seek.dragging
                            onTriggered: { pop.seekTo(seek.want * pop.np.lenUs); seek.want = -1; }
                        }
                    }
                    Item {
                        width: parent.width
                        height: 14
                        Text {
                            text: pop.np ? pop.np.fmt(seek.dragging ? seek.dragValue * pop.np.lenUs : pop.np.curUs) : ""
                            color: Theme.subtext0
                            font.family: Theme.font
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                        }
                        Text {
                            anchors.right: parent.right
                            text: pop.np ? pop.np.fmt(pop.np.lenUs) : ""
                            color: Theme.subtext0
                            font.family: Theme.font
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                        }
                    }
                }

                // controls
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 8
                    readonly property bool hasShuffle: !!pop.np && pop.np.shuffle !== ""
                    readonly property bool hasRepeat: !!pop.np && pop.np.loop !== ""
                    IconBtn {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: parent.hasShuffle
                        size: 32
                        icon: pop.np && pop.np.shuffle === "1" ? "\u{f049d}" : "\u{f049e}"
                        fg: pop.np && pop.np.shuffle === "1" ? pop.col : Theme.overlay1
                        tip: "Shuffle"
                        tipEdge: Edges.Top
                        opacity: pop.np && pop.np.pendingMode === "shuffle" ? 0.5 : 1
                        onClicked: pop.np.setMode("shuffle")
                    }
                    IconBtn {
                        anchors.verticalCenter: parent.verticalCenter
                        size: 36
                        icon: "\u{f04ae}"
                        tip: "Previous"
                        tipEdge: Edges.Top
                        onClicked: Theme.exec(Theme.hypr + "/media-skip.sh prev " + pop.np.player)
                    }
                    IconBtn {
                        anchors.verticalCenter: parent.verticalCenter
                        size: 46
                        iconSize: 22
                        radius: 14
                        active: true
                        activeFg: pop.col
                        icon: pop.np && pop.np.playing ? "\u{f03e4}" : "\u{f040a}"
                        tip: pop.np && pop.np.playing ? "Pause" : "Play"
                        tipEdge: Edges.Top
                        onClicked: {
                            Theme.exec("playerctl -p " + pop.np.player + " play-pause");
                            pop.np.posUs = pop.np.curUs;               // freeze/resume the playhead
                            pop.np.posAt = Date.now();
                            pop.np.playing = !pop.np.playing;          // the feed confirms it
                        }
                    }
                    IconBtn {
                        anchors.verticalCenter: parent.verticalCenter
                        size: 36
                        icon: "\u{f04ad}"
                        tip: "Next"
                        tipEdge: Edges.Top
                        onClicked: Theme.exec(Theme.hypr + "/media-skip.sh next " + pop.np.player)
                    }
                    IconBtn {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: parent.hasRepeat
                        size: 32
                        readonly property string l: pop.np ? pop.np.loop : ""
                        icon: l === "Track" ? "\u{f0458}" : l === "Playlist" ? "\u{f0456}" : "\u{f0457}"
                        fg: l === "Track" || l === "Playlist" ? pop.col : Theme.overlay1
                        tip: "Repeat: " + ({ None: "off", Playlist: "playlist", Track: "this track" }[l] ?? "off")
                        tipEdge: Edges.Top
                        opacity: pop.np && pop.np.pendingMode === "repeat" ? 0.5 : 1
                        onClicked: pop.np.setMode("repeat")
                    }
                }
            }
        }

        Rectangle {
            visible: pop.hasLower
            width: parent.width
            height: 1
            color: Theme.alpha(Theme.surface1, 0.7)
            opacity: pop.stage(1)
        }

        // ── equalizer | lyrics ──────────────────────────────────────────────
        Item {
            visible: pop.hasLower
            width: parent.width
            height: 30
            opacity: pop.stage(1)
            transform: Translate { y: 14 * (1 - pop.stage(1)) }
            Text {
                visible: !(pop.hasLyrics && pop.hasEq)
                anchors.verticalCenter: parent.verticalCenter
                text: pop.hasEq ? "\u{f0ea2}  Equalizer" : "\u{f0370}  Lyrics"
                color: pop.col
                font.family: Theme.font
                font.pixelSize: 13
                font.weight: Font.Bold
            }
            Segmented {
                id: menuTabs
                visible: pop.hasLyrics && pop.hasEq
                width: 240
                height: 30
                options: ["Equalizer", "Lyrics"]
                currentIndex: pop.tab
                accent: pop.col
                onSelected: i => pop.tab = i
            }
            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, parent.width - 260)
                elide: Text.ElideRight
                text: pop.shownTab === 0 ? (pop.phone ? "\u{f02fc}  applies to this laptop's audio only"
                                                 : "\u{f04c3}  " + (pop.sink ? (pop.sink.nickname || pop.sink.description || "") : ""))
                    : lyrics.state_ === "synced" ? "synced · lrclib.net"
                    : lyrics.state_ === "plain" ? "lrclib.net" : ""
                color: Theme.overlay1
                font.family: Theme.font
                font.pixelSize: 11
            }
        }

        // Lyrics take only what they need: 170 px when found (was 280), and
        // nothing at all while searching / when there are none — a one-line
        // note below says so instead of a big empty box
        readonly property bool lyricsShown: pop.shownTab === 1 && ["synced", "plain"].includes(lyrics.state_)
        Item {
            visible: pop.hasLower && height > 0
            width: parent.width
            height: pop.shownTab === 0 ? 280 : parent.lyricsShown ? 170 : 0
            Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            clip: true
            opacity: pop.stage(2) * tabFx.value
            transform: Translate { y: 14 * (1 - pop.stage(2)) + 8 * (1 - tabFx.value) }

            MediaEq {
                anchors.fill: parent
                visible: pop.shownTab === 0
                active: pop.isOpen
                tint: pop.col
            }
            MediaLyrics {
                id: lyrics
                anchors.fill: parent
                visible: pop.shownTab === 1
                active: pop.isOpen && pop.shownTab === 1
                artist: pop.artist
                title: pop.title
                album: pop.album
                lengthS: pop.np ? pop.np.lenUs / 1e6 : 0
                posS: pop.np ? pop.np.curUs / 1e6 : 0
                seekable: !!pop.np && pop.np.seekable
                tint: pop.col
                onSeekRequested: s => pop.seekTo(s * 1e6)
            }
        }
        Text {
            visible: pop.hasLower && pop.shownTab === 1 && !parent.lyricsShown
            width: parent.width
            text: lyrics.state_ === "searching" || lyrics.state_ === "idle" ? "\u{f0349}  Searching lyrics…"
                : lyrics.state_ === "error" ? "\u{f092d}  Couldn't reach lrclib.net for lyrics"
                : "\u{f075b}  No lyrics found for this track"
            color: Theme.overlay1
            font.family: Theme.font
            font.pixelSize: 11
            opacity: pop.stage(2)
        }
    }
}
