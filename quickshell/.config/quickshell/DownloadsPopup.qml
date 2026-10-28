// The downloads panel (Serpantinum-style) above the bottom bar's downloads
// pill — what `dl-popup status` (fuzzel) did, as a panel:
//
//   header   liquid orb with the overall progress · "2 active · 1 queued ·
//            3.2 MB/s" · Pause all / Resume all
//   tabs     Downloading · Finished (aria2's last 30 done / failed)
//   cards    name, progress line, done of total, speed, time left, where from
//            (aria2 · JD · curl / wget · pip / uv …); aria2 ones have pause /
//            resume, retry (failed), open file + show in folder (done), copy
//            URL, remove (click twice — a partial file stays)
//   footer   Open ~/Downloads · Clear finished · JDownloader
//
// Data: `dl-popup json` every 1.5 s while open (never starts aria2 or JD);
// changes: `dl-popup act …`. `qs ipc call downloads toggle|open|close|demo`
// (demo: sample cards, to see the panel without a download; acts do nothing).
import QtQuick
import Quickshell
import Quickshell.Io

PanelPopup {
    id: pop
    tabBar: menuTabs                          // Ctrl+Tab / Ctrl+Shift+Tab cycle it
    TabFade { id: tabFx; key: pop.tab; active: pop.isOpen }   // soft tab swap

    edge: Edges.Top
    panelWidth: 470
    pad: 16

    property var scriptPill: null             // the bar pill, poked after a change
    readonly property string bin: Theme.home + "/.local/bin/dl-popup"
    property var data: ({ items: [], aria2: true, speed: 0, active: 0, waiting: 0, dir: "~/Downloads" })
    property bool demo: false
    property int tab: 0                       // 0 downloading, 1 finished
    property string msg: ""
    property bool msgBad: false
    property string armed: ""                 // id armed for remove

    readonly property var demoData: ({
        aria2: true, speed: 3355443, active: 2, waiting: 1, dir: "~/Downloads",
        items: [
            { id: "d1", name: "ubuntu-24.04.1-desktop-amd64.iso", done: 2684354560, total: 6114656256, speed: 2621440, state: "active", via: "aria2", eta: 1308, path: "", url: "x" },
            { id: "d2", name: "dataset-part-03.tar.zst", done: 157286400, total: 943718400, speed: 734003, state: "active", via: "JD", eta: 1071, path: "", url: "" },
            { id: "d3", name: "lecture-12.mp4", done: 0, total: 734003200, speed: 0, state: "waiting", via: "aria2", eta: -1, path: "", url: "x" },
            { id: "d4", name: "uv add torch", done: 412090368, total: 0, speed: 1048576, state: "active", via: "uv", kind: "pkg", eta: -1, path: "", url: "" },
            { id: "d5", name: "paper.pdf", done: 2411724, total: 2411724, speed: 0, state: "complete", via: "aria2", eta: -1, path: "/tmp/paper.pdf", url: "x" },
            { id: "d6", name: "broken-link.zip", done: 0, total: 0, speed: 0, state: "error", via: "aria2", error: "404 Not Found", eta: -1, path: "", url: "x" }
        ]
    })
    readonly property var d: demo ? demoData : data
    readonly property var running: d.items.filter(i => !["complete", "error", "removed"].includes(i.state))
    readonly property var finished: d.items.filter(i => ["complete", "error", "removed"].includes(i.state))
    readonly property var shown_: tab === 0 ? running : finished
    readonly property real overall: {
        const s = running.filter(i => i.total > 0);
        const t = s.reduce((a, i) => a + i.total, 0);
        return t ? s.reduce((a, i) => a + i.done, 0) / t : 0;
    }
    readonly property bool anyActive: running.some(i => i.state === "active")
    readonly property color tint: anyActive ? Theme.sapphire : Theme.subtext0

    function human(n) {
        const u = ["B", "KB", "MB", "GB", "TB"];
        let i = 0;
        while (n >= 1024 && i < u.length - 1) { n /= 1024; i++; }
        return (i ? n.toFixed(n < 10 ? 1 : 0) : Math.round(n)) + " " + u[i];
    }
    function eta(s) {
        if (s < 0) return "";
        return s >= 3600 ? Math.floor(s / 3600) + "h" + String(Math.floor(s / 60) % 60).padStart(2, "0") + "m"
             : s >= 60 ? Math.floor(s / 60) + "m" + String(s % 60).padStart(2, "0") + "s" : s + "s";
    }

    // ── data ────────────────────────────────────────────────────────────────
    function refresh() { if (!lister.running) lister.running = true; }
    Process {
        id: lister
        command: [pop.bin, "json"]
        stdout: StdioCollector {
            onStreamFinished: { try { pop.data = JSON.parse(text); } catch (e) {} }
        }
    }
    Timer { interval: 1500; repeat: true; running: pop.isOpen && !pop.demo; triggeredOnStart: true; onTriggered: pop.refresh() }
    onOpened: { msg = ""; armed = ""; refresh(); }
    onClosed2: demo = false

    Process {
        id: act
        stdout: StdioCollector {
            onStreamFinished: {
                let r = {};
                try { r = JSON.parse(text); } catch (e) { r = { ok: false, msg: text.trim() || "dl-popup failed" }; }
                pop.msg = r.ok ? "" : (r.msg || "didn't work");
                pop.msgBad = !r.ok;
                pop.refresh();
                if (pop.scriptPill && pop.scriptPill.poke) pop.scriptPill.poke();
            }
        }
    }
    function run(args) {
        if (demo) { msg = "demo — nothing changed"; msgBad = false; return; }
        if (act.running) return;
        act.command = [bin, "act"].concat(args);
        act.running = true;
    }
    function launch(args) { close(); run(args); }

    function stage(k) { return Math.max(0, Math.min(1, (pop.intro - k * 0.12) / (1 - k * 0.12))); }

    Column {
        width: parent.width
        spacing: 12

        // ── header ──────────────────────────────────────────────────────────
        Row {
            width: parent.width
            spacing: 14
            opacity: pop.stage(0)
            transform: Translate { y: 12 * (1 - pop.stage(0)) }
            AudioOrb {
                id: orb
                implicitWidth: 84
                implicitHeight: 84
                running: pop.isOpen && pop.anyActive
                tint: pop.tint
                level: pop.overall
                label: pop.running.some(i => i.total > 0) ? Math.round(pop.overall * 100) + "%" : "\u{f01da}"
            }
            Column {
                width: parent.width - orb.width - parent.spacing
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                Text {
                    text: "Downloads" + (pop.demo ? "  ·  demo" : "")
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 17
                    font.weight: Font.Bold
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: pop.running.length === 0 ? "Nothing downloading"
                        : [pop.running.filter(i => i.state === "active").length + " active",
                           pop.running.filter(i => i.state !== "active").length ? pop.running.filter(i => i.state !== "active").length + " waiting" : "",
                           pop.d.speed ? pop.human(pop.d.speed) + "/s" : ""].filter(s => s).join("  ·  ")
                    color: pop.tint
                    font.family: Theme.font
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
                Text {
                    visible: !pop.d.aria2
                    text: "\u{f0028}  aria2 isn't running (it starts with the next download)"
                    color: Theme.overlay1
                    font.family: Theme.font
                    font.pixelSize: 10
                }
                Row {
                    spacing: 6
                    topPadding: 4
                    IconBtn {
                        size: 28
                        iconSize: 13
                        icon: "\u{f03e4}"
                        text: "Pause all"
                        enabled: pop.d.aria2
                        tip: "Pause every aria2 download"
                        tipEdge: Edges.Top
                        onClicked: pop.run(["pauseall"])
                    }
                    IconBtn {
                        size: 28
                        iconSize: 13
                        icon: "\u{f040a}"
                        text: "Resume all"
                        enabled: pop.d.aria2
                        tipEdge: Edges.Top
                        onClicked: pop.run(["resumeall"])
                    }
                }
            }
        }

        Text {
            visible: pop.msg !== ""
            width: parent.width
            wrapMode: Text.Wrap
            text: (pop.msgBad ? "\u{f0028}  " : "") + pop.msg
            color: pop.msgBad ? Theme.red : Theme.overlay1
            font.family: Theme.font
            font.pixelSize: 11
        }

        Segmented {
            id: menuTabs
            width: parent.width
            height: 32
            opacity: pop.stage(1)
            accent: pop.tint
            options: ["Downloading · " + pop.running.length, "Finished · " + pop.finished.length]
            currentIndex: pop.tab
            onSelected: i => { pop.tab = i; pop.armed = ""; }
        }

        // ── cards ───────────────────────────────────────────────────────────
        Item {
            width: parent.width
            height: Math.max(pop.shown_.length ? 0 : 80, Math.min(list.height, 380))
            Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            opacity: pop.stage(2) * tabFx.value
            transform: Translate { y: 14 * (1 - pop.stage(2)) + 8 * (1 - tabFx.value) }

            Flickable {
                id: flick
                anchors.fill: parent
                contentHeight: list.height
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height

                Column {
                    id: list
                    width: flick.width
                    spacing: 7

                    Repeater {
                        model: pop.shown_
                        delegate: Rectangle {
                            id: card
                            required property var modelData
                            readonly property var it: modelData
                            readonly property bool a2: it.via === "aria2" && it.id !== ""
                            readonly property real frac: it.total > 0 ? it.done / it.total : 0
                            readonly property color c: it.state === "error" ? Theme.red
                                                     : it.state === "complete" ? Theme.green
                                                     : it.state === "active" ? Theme.sapphire : Theme.overlay1
                            width: list.width
                            height: col.implicitHeight + 20
                            radius: 12
                            color: cardMa.containsMouse ? Theme.alpha(Theme.surface1, 0.5) : Theme.alpha(Theme.surface0, 0.55)
                            border.width: 1
                            border.color: Theme.alpha(c, it.state === "active" ? 0.35 : 0.15)
                            Behavior on color { ColorAnimation { duration: Theme.fast } }
                            MouseArea { id: cardMa; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }

                            Column {
                                id: col
                                x: 12
                                y: 10
                                width: parent.width - 24
                                spacing: 6
                                Row {
                                    width: parent.width
                                    spacing: 9
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: ({ active: "\u{f01da}", waiting: "\u{f051f}", paused: "\u{f03e4}",
                                                 complete: "\u{f05e0}", error: "\u{f0028}", removed: "\u{f0156}" })[card.it.state] || "\u{f051f}"
                                        color: card.c
                                        font.family: Theme.font
                                        font.pixelSize: 15
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - 24 - btns.width - 18
                                        text: card.it.name
                                        elide: Text.ElideMiddle
                                        color: Theme.text
                                        font.family: Theme.font
                                        font.pixelSize: 12
                                        font.weight: Font.DemiBold
                                    }
                                    Row {
                                        id: btns
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 3
                                        IconBtn {
                                            visible: card.a2 && ["active", "waiting"].includes(card.it.state)
                                            size: 24; iconSize: 12; icon: "\u{f03e4}"; tip: "Pause"; tipEdge: Edges.Top
                                            onClicked: pop.run(["pause", card.it.id])
                                        }
                                        IconBtn {
                                            visible: card.a2 && card.it.state === "paused"
                                            size: 24; iconSize: 12; icon: "\u{f040a}"; tip: "Resume"; tipEdge: Edges.Top
                                            onClicked: pop.run(["resume", card.it.id])
                                        }
                                        IconBtn {
                                            visible: card.a2 && card.it.state === "error" && card.it.url !== ""
                                            size: 24; iconSize: 12; icon: "\u{f0450}"; tip: "Retry"; tipEdge: Edges.Top
                                            onClicked: pop.run(["retry", card.it.id])
                                        }
                                        IconBtn {
                                            visible: card.a2 && card.it.state === "complete" && card.it.path !== ""
                                            size: 24; iconSize: 12; icon: "\u{f03cc}"; tip: "Open file"; tipEdge: Edges.Top
                                            onClicked: pop.launch(["open", card.it.id])
                                        }
                                        IconBtn {
                                            visible: card.a2
                                            size: 24; iconSize: 12; icon: "\u{f0770}"; tip: "Show in folder"; tipEdge: Edges.Top
                                            onClicked: pop.launch(["folder", card.it.id])
                                        }
                                        IconBtn {
                                            visible: card.a2 && card.it.url !== ""
                                            size: 24; iconSize: 12; icon: "\u{f018f}"; tip: "Copy URL"; tipEdge: Edges.Top
                                            onClicked: pop.run(["copy", card.it.id])
                                        }
                                        IconBtn {
                                            readonly property bool isArmed: pop.armed === card.it.id
                                            visible: card.a2
                                            size: 24; iconSize: 12; icon: "\u{f09e7}"
                                            text: isArmed ? "Remove?" : ""
                                            fg: Theme.red
                                            active: isArmed
                                            activeFg: Theme.red
                                            tip: isArmed ? "Click again to remove" + (["complete", "error"].includes(card.it.state) ? "" : " (the partial file stays)")
                                                         : "Remove from the list"
                                            tipEdge: Edges.Top
                                            onClicked: {
                                                if (!isArmed) { pop.armed = card.it.id; disarm.restart(); return; }
                                                pop.armed = "";
                                                pop.run(["remove", card.it.id]);
                                            }
                                        }
                                    }
                                }
                                // progress line
                                Rectangle {
                                    visible: card.it.state !== "complete" && card.it.state !== "error"
                                    width: parent.width
                                    height: 5
                                    radius: 3
                                    color: Theme.alpha(Theme.surface1, 0.9)
                                    Rectangle {
                                        // unknown size (curl / pip): a short moving stripe
                                        width: card.it.total > 0 ? Math.max(height, parent.width * card.frac) : parent.width * 0.25
                                        x: card.it.total > 0 ? 0 : stripe.pos * (parent.width - width)
                                        height: parent.height
                                        radius: 3
                                        color: card.c
                                        Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                                    }
                                    QtObject { id: stripe; property real pos: 0 }
                                    SequentialAnimation {
                                        running: card.it.total <= 0 && card.it.state === "active" && pop.isOpen
                                        loops: Animation.Infinite
                                        NumberAnimation { target: stripe; property: "pos"; from: 0; to: 1; duration: 1100; easing.type: Easing.InOutSine }
                                        NumberAnimation { target: stripe; property: "pos"; from: 1; to: 0; duration: 1100; easing.type: Easing.InOutSine }
                                    }
                                }
                                Text {
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: card.it.state === "error" ? (card.it.error || "failed") + "  ·  " + card.it.via
                                        : [card.it.total > 0 ? Math.round(card.frac * 100) + "%" : "",
                                           card.it.total > 0 ? pop.human(card.it.done) + " of " + pop.human(card.it.total) : pop.human(card.it.done),
                                           card.it.state === "active" && card.it.speed ? pop.human(card.it.speed) + "/s" : card.it.state === "active" ? "" : card.it.state,
                                           card.it.eta > 0 ? pop.eta(card.it.eta) + " left" : "",
                                           card.it.via].filter(s => s).join("  ·  ")
                                    color: card.it.state === "error" ? Theme.red : Theme.subtext0
                                    font.family: Theme.font
                                    font.pixelSize: 10
                                }
                            }
                        }
                    }

                    Column {
                        visible: pop.shown_.length === 0
                        width: parent.width
                        topPadding: 14
                        spacing: 6
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: pop.tab === 0 ? "\u{f01da}" : "\u{f05e0}"
                            color: Theme.alpha(Theme.overlay0, 0.8)
                            font.family: Theme.font
                            font.pixelSize: 30
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: pop.tab === 0 ? "Nothing downloading" : "Nothing finished recently"
                            color: Theme.subtext0
                            font.family: Theme.font
                            font.pixelSize: 12
                            font.weight: Font.Bold
                        }
                    }
                }
            }
        }

        // ── footer ──────────────────────────────────────────────────────────
        Row {
            spacing: 6
            opacity: pop.stage(2)
            IconBtn {
                size: 30; iconSize: 14; icon: "\u{f0770}"
                text: "Open " + pop.d.dir
                onClicked: pop.launch(["dir"])
            }
            IconBtn {
                size: 30; iconSize: 14; icon: "\u{f00e2}"
                text: "Clear finished"
                enabled: pop.d.aria2 && pop.finished.length > 0
                tip: "Drop finished / failed downloads from aria2's list (files stay)"
                tipEdge: Edges.Top
                onClicked: pop.run(["purge"])
            }
            IconBtn {
                size: 30; iconSize: 14; icon: "\u{f048b}"
                text: "JDownloader"
                tip: "Open JDownloader (starts it if needed)"
                tipEdge: Edges.Top
                onClicked: pop.launch(["jd"])
            }
        }
    }
    Timer { id: disarm; interval: 4000; onTriggered: pop.armed = "" }
}
