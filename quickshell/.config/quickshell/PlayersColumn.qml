// One column of the players deck (PlayersPopup.qml): THIS LAPTOP or the
// PHONE. Its own controls, separate from the other column's:
//
//   header   laptop / phone · device · "Pause all" (this column's players)
//   hero     the player this column's bottom-bar pill shows (else the first
//            playing one): spinning cover, title, seek, ⇄ ⏮ ⏯ ⏭ ⟲
//   also     the column's other players, each with its own ⏯ (and "show
//            tab" for a Zen / Firefox YouTube tab)
//   footer   launchers (laptop) / the phone's menu; Spotify "Resume" when the
//            last-played offer belongs to this side
//
// Clicking the column anywhere that isn't a button / slider / row opens that
// side's music panel (MediaPopup — the bar pill's right-click panel).
//
// The hero's position, shuffle and repeat come from the bar's now-playing.py
// feed (`np`) when the hero is that pill's player — it already works around
// KDE Connect's wrong positions; anything else is live MPRIS + playerctl.
import QtQuick
import Quickshell
import Quickshell.Services.Mpris

Rectangle {
    id: col

    property var deck: null
    property string scope: "local"            // local | remote
    property var np: null
    property var players: []
    property var last: null                   // Spotify's resume offer, if it is this side's
    property string device: ""
    property real reveal: 1
    readonly property bool phone: scope === "remote"
    // what this column needs; the deck makes both columns the taller one
    readonly property real contentH: inner.implicitHeight + footer.height + 14 + 14 + 16

    // ── the hero ────────────────────────────────────────────────────────────
    readonly property bool npLive: !!np && !np.hidden && np.player !== ""
    readonly property var hero: {
        const want = npLive ? np.player : "";
        return players.find(p => p.inst === want) || players.find(p => playingOf(p)) || players[0] || null;
    }
    readonly property bool heroIsNp: !!hero && npLive && np.player === hero.inst
    readonly property var others: players.filter(p => !hero || p.inst !== hero.inst)
    readonly property var mp: hero ? mprisOf(hero.inst) : null

    function mprisOf(inst) {
        const want = "org.mpris.MediaPlayer2." + inst;
        return Mpris.players.values.find(m => m.dbusName === want) || null;
    }
    function playingOf(p) {
        const m = mprisOf(p.inst);
        return m ? m.isPlaying : p.state === "playing";
    }
    function colourOf(key) {
        return ({ spotify: Theme.green, youtube: Theme.youtube, firefox: Theme.peach,
                  zen: Theme.mauve, ytmusic: Theme.pink })[key] || Theme.accent;
    }
    function glyphOf(key) {
        return ({ spotify: "\u{f04c7}", youtube: "\u{f05c3}", ytmusic: "\u{f05c3}",
                  firefox: "\u{f0239}", zen: "\u{f059f}" })[key] || "\u{f075a}";
    }

    readonly property bool heroPlaying: heroIsNp ? np.playing : mp ? mp.isPlaying : !!hero && hero.state === "playing"
    readonly property bool anyPlaying: heroPlaying || others.some(p => playingOf(p))
    readonly property color tint: hero ? colourOf(hero.colour) : Theme.overlay1
    readonly property string title: (mp && mp.trackTitle) || (hero ? hero.title : "")
    readonly property string artist: (mp && mp.trackArtist) || (hero ? hero.artist : "")
    readonly property string art: mp ? (mp.trackArtUrl || "") : ""

    function playPause(inst) {
        if (heroIsNp && inst === np.player) {
            np.posUs = np.curUs;                  // freeze/resume the playhead
            np.posAt = Date.now();
            np.playing = !np.playing;             // the feed confirms it
        }
        deck.run(["playerctl", "-p", inst, "play-pause"]);
    }
    function skip(dir) { if (hero) deck.run([Theme.hypr + "/media-skip.sh", dir, hero.inst]); }
    function raise(inst) {
        deck.run(["busctl", "--user", "call", "org.mpris.MediaPlayer2." + inst, "/org/mpris/MediaPlayer2",
                  "org.mpris.MediaPlayer2", "Raise"]);
    }
    function seekTo(us) {
        if (!heroIsNp || !np.seekable) return;
        np.seekTo(us);                            // NowPlaying: instant playhead + stdin
    }

    // ── look: a card washed in the hero's colour from the top ───────────────
    radius: 16
    color: Theme.alpha(Theme.surface0, 0.32)
    border.color: Theme.alpha(tint, colMa.containsMouse && canOpen ? 0.7 : hero ? 0.32 : 0.15)
    Behavior on border.color { ColorAnimation { duration: 320 } }
    clip: true
    opacity: reveal
    transform: Translate { y: 18 * (1 - col.reveal) }

    // the column itself: open this side's music panel
    readonly property bool canOpen: heroIsNp
    MouseArea {
        id: colMa
        anchors.fill: parent
        hoverEnabled: true
        enabled: col.canOpen
        cursorShape: Qt.PointingHandCursor
        onClicked: col.deck.openPanel(col.np)
    }
    border.width: colMa.containsMouse && canOpen ? 2 : 1

    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        gradient: Gradient {
            GradientStop { position: 0; color: Theme.alpha(col.tint, col.heroPlaying ? 0.2 : 0.1) }
            GradientStop { position: 0.6; color: "transparent" }
        }
    }

    Column {
        id: inner
        x: 14
        y: 14
        width: parent.width - 28
        spacing: 12

        // ── header ──────────────────────────────────────────────────────────
        Item {
            width: parent.width
            height: 30
            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 9
                Rectangle {
                    width: 30
                    height: 30
                    radius: 9
                    color: Theme.alpha(col.tint, 0.18)
                    Text {
                        anchors.centerIn: parent
                        text: col.phone ? "\u{f011c}" : "\u{f0322}"
                        color: col.hero ? col.tint : Theme.overlay1
                        font.family: Theme.font
                        font.pixelSize: 16
                    }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        text: col.phone ? "PHONE" : "THIS LAPTOP"
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: 12
                        font.weight: Font.Bold
                        font.letterSpacing: 1.4
                    }
                    Text {
                        // hovering the column: say what a click does
                        text: colMa.containsMouse && col.canOpen ? "click: music panel — equalizer & lyrics"
                            : (col.phone ? (col.device || "via KDE Connect") : "speakers & headphones")
                              + "  ·  " + col.players.length + (col.players.length === 1 ? " player" : " players")
                        color: colMa.containsMouse && col.canOpen ? col.tint : Theme.overlay1
                        font.family: Theme.font
                        font.pixelSize: 10
                    }
                }
            }
            IconBtn {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: col.anyPlaying
                size: 26
                iconSize: 13
                icon: "\u{f03e4}"
                text: "Pause all"
                tip: col.phone ? "Pause everything on the phone" : "Pause everything on this laptop"
                tipEdge: Edges.Top
                onClicked: col.deck.pauseAll(col.players)
            }
        }

        // ── hero ────────────────────────────────────────────────────────────
        Row {
            visible: !!col.hero
            width: parent.width
            spacing: 6

            MediaCover {
                id: cover
                anchors.verticalCenter: parent.verticalCenter
                coverSize: 84
                bars: 44
                art: col.art
                tint: col.tint
                playing: col.heroPlaying
                listen: !col.phone && col.heroPlaying && !!col.deck && col.deck.isOpen
                fake: col.phone
            }

            Column {
                width: parent.width - cover.width - parent.spacing
                anchors.verticalCenter: parent.verticalCenter
                spacing: 5

                Row {
                    spacing: 6
                    Rectangle {
                        width: via.implicitWidth + 14
                        height: 20
                        radius: 6
                        color: Theme.alpha(col.tint, 0.16)
                        Text {
                            id: via
                            anchors.centerIn: parent
                            text: col.hero ? col.glyphOf(col.hero.colour) + "  " + col.hero.name.replace(/ · Phone$/, "") : ""
                            color: col.tint
                            font.family: Theme.font
                            font.pixelSize: 10
                            font.weight: Font.Bold
                        }
                    }
                    IconBtn {
                        visible: !!col.hero && col.hero.tab
                        size: 20
                        iconSize: 11
                        icon: "\u{f04e9}"                 // md-tab
                        tip: "Show this tab"
                        tipEdge: Edges.Top
                        onClicked: col.raise(col.hero.inst)
                    }
                }
                Text {
                    width: parent.width
                    text: col.title || "—"
                    elide: Text.ElideRight
                    maximumLineCount: 2
                    wrapMode: Text.Wrap
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 14
                    font.weight: Font.Bold
                }
                Text {
                    width: parent.width
                    visible: col.artist !== ""
                    text: col.artist
                    elide: Text.ElideRight
                    color: Theme.subtext0
                    font.family: Theme.font
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
            }
        }

        // seek: only for the pill's own player (its position is trustworthy)
        Column {
            width: parent.width
            spacing: 2
            visible: col.heroIsNp && col.np.lenUs > 0
            Slider {
                id: seek
                width: parent.width
                color: col.tint
                thickness: 5
                enabled: col.heroIsNp && col.np.seekable
                value: col.heroIsNp ? col.np.frac : 0
                property real want: -1
                onMoved: v => want = v
                onDraggingChanged: if (!dragging && want >= 0) { col.seekTo(want * col.np.lenUs); want = -1; }
                step: col.heroIsNp && col.np.lenUs > 0 ? Math.min(0.5, 5e6 / col.np.lenUs) : 0.05
                Timer {
                    interval: 120
                    running: seek.want >= 0 && !seek.dragging
                    onTriggered: { col.seekTo(seek.want * col.np.lenUs); seek.want = -1; }
                }
            }
            Item {
                width: parent.width
                height: 13
                Text {
                    text: col.heroIsNp ? col.np.fmt(seek.dragging ? seek.dragValue * col.np.lenUs : col.np.curUs) : ""
                    color: Theme.subtext0
                    font.family: Theme.font
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                }
                Text {
                    anchors.right: parent.right
                    text: col.heroIsNp ? col.np.fmt(col.np.lenUs) : ""
                    color: Theme.subtext0
                    font.family: Theme.font
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                }
            }
        }

        // controls
        Row {
            visible: !!col.hero
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8
            readonly property bool hasShuffle: col.heroIsNp && col.np.shuffle !== ""
            readonly property bool hasRepeat: col.heroIsNp && col.np.loop !== ""
            IconBtn {
                anchors.verticalCenter: parent.verticalCenter
                visible: parent.hasShuffle
                size: 30
                icon: col.heroIsNp && col.np.shuffle === "1" ? "\u{f049d}" : "\u{f049e}"
                fg: col.heroIsNp && col.np.shuffle === "1" ? col.tint : Theme.overlay1
                tip: "Shuffle"
                tipEdge: Edges.Top
                opacity: col.heroIsNp && col.np.pendingMode === "shuffle" ? 0.5 : 1
                onClicked: col.np.setMode("shuffle")
            }
            IconBtn {
                anchors.verticalCenter: parent.verticalCenter
                size: 34
                icon: "\u{f04ae}"
                tip: "Previous"
                tipEdge: Edges.Top
                onClicked: col.skip("prev")
            }
            IconBtn {
                anchors.verticalCenter: parent.verticalCenter
                size: 44
                iconSize: 21
                radius: 14
                active: true
                activeFg: col.tint
                icon: col.heroPlaying ? "\u{f03e4}" : "\u{f040a}"
                tip: col.heroPlaying ? "Pause" : "Play"
                tipEdge: Edges.Top
                onClicked: col.playPause(col.hero.inst)
            }
            IconBtn {
                anchors.verticalCenter: parent.verticalCenter
                size: 34
                icon: "\u{f04ad}"
                tip: "Next"
                tipEdge: Edges.Top
                onClicked: col.skip("next")
            }
            IconBtn {
                anchors.verticalCenter: parent.verticalCenter
                visible: parent.hasRepeat
                size: 30
                readonly property string l: col.heroIsNp ? col.np.loop : ""
                icon: l === "Track" ? "\u{f0458}" : l === "Playlist" ? "\u{f0456}" : "\u{f0457}"
                fg: l === "Track" || l === "Playlist" ? col.tint : Theme.overlay1
                tip: "Repeat: " + ({ None: "off", Playlist: "playlist", Track: "this track" }[l] ?? "off")
                tipEdge: Edges.Top
                opacity: col.heroIsNp && col.np.pendingMode === "repeat" ? 0.5 : 1
                onClicked: col.np.setMode("repeat")
            }
        }

        // nothing here
        Column {
            visible: !col.hero
            width: parent.width
            topPadding: 18
            bottomPadding: 10
            spacing: 6
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "\u{f075b}"                         // md-music_off
                color: Theme.alpha(Theme.overlay0, 0.7)
                font.family: Theme.font
                font.pixelSize: 44
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: col.phone ? "Nothing on the phone" : "Nothing on this laptop"
                color: Theme.subtext0
                font.family: Theme.font
                font.pixelSize: 13
                font.weight: Font.Bold
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: col.phone ? "Play something there and it shows up here" : "Start something below"
                color: Theme.overlay0
                font.family: Theme.font
                font.pixelSize: 11
            }
        }

        // ── the column's other players ──────────────────────────────────────
        Text {
            visible: col.others.length > 0
            text: "ALSO HERE  ·  " + col.others.length
            color: Theme.overlay1
            font.family: Theme.font
            font.pixelSize: 10
            font.weight: Font.Bold
            font.letterSpacing: 1.2
        }
        Repeater {
            model: col.others
            Rectangle {
                id: mini
                required property var modelData
                readonly property var mm: col.mprisOf(modelData.inst)
                readonly property bool playing: mm ? mm.isPlaying : modelData.state === "playing"
                readonly property color c: col.colourOf(modelData.colour)
                width: inner.width
                height: 46
                radius: 11
                color: rowMa.containsMouse ? Theme.alpha(Theme.surface1, 0.55) : Theme.alpha(Theme.surface0, 0.55)
                border.width: 1
                border.color: Theme.alpha(c, mini.playing ? 0.35 : 0.12)
                Behavior on color { ColorAnimation { duration: Theme.fast } }

                MouseArea {
                    id: rowMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    // a tab: switch to it (the bar then shows it); else play/pause
                    onClicked: mini.modelData.tab ? col.raise(mini.modelData.inst) : col.playPause(mini.modelData.inst)
                }
                Rectangle {
                    id: badge
                    x: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: 30
                    height: 30
                    radius: 15
                    color: Theme.alpha(mini.c, 0.18)
                    Text {
                        anchors.centerIn: parent
                        text: col.glyphOf(mini.modelData.colour)
                        color: mini.c
                        font.family: Theme.font
                        font.pixelSize: 15
                    }
                }
                Column {
                    anchors.left: badge.right
                    anchors.leftMargin: 10
                    anchors.right: miniBtns.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                        width: parent.width
                        text: mini.modelData.name.replace(/ · Phone$/, "")
                        elide: Text.ElideRight
                        color: mini.c
                        font.family: Theme.font
                        font.pixelSize: 11
                        font.weight: Font.Bold
                    }
                    Text {
                        width: parent.width
                        text: ((mini.mm && mini.mm.trackTitle) || mini.modelData.title || "—")
                            + ((mini.mm && mini.mm.trackArtist) || mini.modelData.artist ? "  ·  " + ((mini.mm && mini.mm.trackArtist) || mini.modelData.artist) : "")
                        elide: Text.ElideRight
                        color: Theme.subtext0
                        font.family: Theme.font
                        font.pixelSize: 10
                        font.italic: !mini.playing
                    }
                }
                Row {
                    id: miniBtns
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4
                    IconBtn {
                        visible: mini.modelData.tab
                        size: 28
                        iconSize: 13
                        icon: "\u{f04e9}"
                        tip: "Show this tab"
                        tipEdge: Edges.Top
                        onClicked: col.raise(mini.modelData.inst)
                    }
                    IconBtn {
                        size: 28
                        iconSize: 14
                        active: mini.playing
                        activeFg: mini.c
                        icon: mini.playing ? "\u{f03e4}" : "\u{f040a}"
                        tip: mini.playing ? "Pause" : "Play"
                        tipEdge: Edges.Top
                        onClicked: col.playPause(mini.modelData.inst)
                    }
                }
            }
        }
    }

    // ── footer, pinned to the bottom so both columns' line up ──────────────
    Flow {
        id: footer
        x: 14
        width: parent.width - 28
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 14
        spacing: 6

        IconBtn {
            visible: !!col.last
            size: 28
            iconSize: 13
            icon: "\u{f0450}"
            fg: Theme.green
            text: col.last ? "Resume  " + (col.last.title.length > 22 ? col.last.title.slice(0, 21) + "…" : col.last.title) : ""
            tip: col.last ? "Spotify, last played on the " + col.last.where.toLowerCase() + ": " + col.last.title
                            + (col.last.artists.length ? " · " + col.last.artists.join(", ") : "") : ""
            tipEdge: Edges.Top
            onClicked: col.deck.launch("/usr/bin/python3 " + Theme.hypr + "/spotify-remote.py resume")
        }
        IconBtn {
            visible: !col.phone
            size: 28
            iconSize: 13
            icon: "\u{f04c7}"
            fg: Theme.green
            text: "Spotify"
            tipEdge: Edges.Top
            onClicked: col.deck.launch(Theme.hypr + "/focus-or-launch.sh spotify /usr/bin/spotify")
        }
        IconBtn {
            visible: !col.phone
            size: 28
            iconSize: 13
            icon: "\u{f05c3}"
            fg: Theme.mauve
            text: "YouTube"
            tip: "A new Zen tab"
            tipEdge: Edges.Top
            onClicked: col.deck.launch(Theme.home + "/.local/opt/zen/zen --new-tab https://www.youtube.com")
        }
        IconBtn {
            visible: !col.phone
            size: 28
            iconSize: 13
            icon: "\u{f075a}"
            fg: Theme.pink
            text: "YT Music"
            tipEdge: Edges.Top
            onClicked: col.deck.launch(Theme.hypr + "/focus-or-launch.sh youtube-music /usr/bin/youtube-music")
        }
        IconBtn {
            visible: col.phone
            size: 28
            iconSize: 13
            icon: "\u{f011c}"
            text: "Phone menu"
            tip: "Ring, send files, clipboard… (the bottom bar's phone pill)"
            tipEdge: Edges.Top
            onClicked: col.deck.launch(Theme.home + "/.local/bin/qs ipc call bottombar menu phone")
        }
    }
}
