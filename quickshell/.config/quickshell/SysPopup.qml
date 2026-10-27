// The top bar's system panels (Serpantinum-style), under the CPU, memory
// and temperature pills — one file, `kind` picks which:
//
//   cpu    orb = total use · CORES grid (one bar per thread, /proc/stat via
//          Stats) · PROCESSES by CPU % (of one core, like top) descending
//   mem    orb = used % · used / available / cached / swap · PROGRAMS by
//          memory descending (grouped by executable, PSS — see sysinfo.py)
//   temp   orb = CPU package · CPU cores grid · storage, Wi-Fi, board
//          sensors · fans (none exposed on this laptop) · hottest marked
//
// Live numbers from ~/.config/hypr/sysinfo.py `watch KIND`, which runs ONLY
// while the panel is open; Stats is polled faster meanwhile. btop and
// Resources are a button away. `qs ipc call sysinfo toggle cpu|mem|temp|battery`.
import QtQuick
import Quickshell
import Quickshell.Io

PanelPopup {
    id: pop

    property string kind: "cpu"               // cpu | mem | temp
    panelWidth: kind === "temp" ? 440 : 470
    pad: 16

    readonly property color tint: kind === "cpu" ? Theme.green : kind === "mem" ? Theme.teal : tempColor(pkgC)
    function tempColor(c) { return Stats.tempColor(c); }
    function loadColor(p) { return p >= 85 ? Theme.red : p >= 60 ? Theme.peach : p >= 30 ? Theme.yellow : Theme.green; }
    function size(kib) {
        return kib >= 1048576 ? (kib / 1048576).toFixed(kib >= 10485760 ? 1 : 2) + " GiB" : Math.round(kib / 1024) + " MiB";
    }
    function stage(k) { return Math.max(0, Math.min(1, (pop.intro - k * 0.12) / (1 - k * 0.12))); }

    // ── live data, only while open ──────────────────────────────────────────
    property var procs: []
    property int procCount: 0
    property var programs: []
    property var meminfo: ({})
    property var sensors: []
    property var fans: []
    property bool gotData: false
    onOpened: gotData = false
    Process {
        running: pop.isOpen
        command: ["/usr/bin/python3", Theme.hypr + "/sysinfo.py", "watch", pop.kind]
        stdout: SplitParser {
            onRead: line => {
                let d;
                try { d = JSON.parse(line); } catch (e) { return; }
                if (d.procs) { pop.procs = d.procs; pop.procCount = d.count || 0; }
                if (d.programs) { pop.programs = d.programs; pop.meminfo = d.meminfo || {}; }
                if (d.sensors) { pop.sensors = d.sensors; pop.fans = d.fans || []; }
                pop.gotData = true;
            }
        }
    }
    // the bar's own numbers, faster while looking at them
    Timer {
        interval: pop.kind === "cpu" ? 1500 : 2000
        repeat: true
        running: pop.isOpen
        onTriggered: { if (pop.kind === "cpu") Stats._readCpu(); else if (pop.kind === "mem") Stats._readMem(); else Stats._readTemp(); }
    }

    // temperatures
    readonly property var cpuSensors: sensors.filter(s => s.group === "CPU")
    readonly property real pkgC: { const p = cpuSensors.find(s => s.label === "Package"); return p ? p.c : Stats.tempC; }
    readonly property var coreTemps: cpuSensors.filter(s => s.label !== "Package")
    readonly property var otherSensors: sensors.filter(s => s.group === "Storage" || s.group === "Wi-Fi")
    readonly property var boardSensors: sensors.filter(s => s.group === "Board")
    readonly property real hottest: sensors.reduce((m, s) => Math.max(m, s.c), 0)

    // memory
    readonly property real memTotalK: meminfo.MemTotal || Stats.memTotalGiB * 1048576
    readonly property real memAvailK: meminfo.MemAvailable || 0
    readonly property real swapTotalK: meminfo.SwapTotal || 0
    readonly property real swapUsedK: swapTotalK - (meminfo.SwapFree || 0)
    readonly property real topProgK: programs.length ? programs[0].kib : 1

    function launch(cmd) { close(); Theme.exec(cmd); }

    component Head: Text {
        color: Theme.overlay1
        font.family: Theme.font
        font.pixelSize: 10
        font.weight: Font.Bold
        font.letterSpacing: 1.2
    }

    Column {
        width: parent.width
        spacing: 12

        // ── hero: orb + numbers ─────────────────────────────────────────────
        Row {
            width: parent.width
            spacing: 14
            opacity: pop.stage(0)
            transform: Translate { y: 12 * (1 - pop.stage(0)) }

            AudioOrb {
                id: orb
                implicitWidth: 104
                implicitHeight: 104
                running: pop.isOpen
                tint: pop.tint
                level: pop.kind === "cpu" ? Stats.cpu / 100 : pop.kind === "mem" ? Stats.memPct / 100 : Math.min(1, pop.pkgC / 100)
                label: pop.kind === "temp" ? Math.round(pop.pkgC) + "°" : Math.round(level * 100) + "%"
            }

            Column {
                width: parent.width - orb.width - parent.spacing
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                Text {
                    text: pop.kind === "cpu" ? "Processor" : pop.kind === "mem" ? "Memory" : "Temperature"
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 18
                    font.weight: Font.Bold
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: pop.kind === "cpu" ? Stats.cores.length + " threads  ·  " + (pop.procCount ? pop.procCount + " processes" : "…")
                        : pop.kind === "mem" ? Stats.memUsedGiB.toFixed(1) + " of " + Stats.memTotalGiB.toFixed(1) + " GiB in use"
                        : "CPU package" + (pop.hottest > pop.pkgC ? "  ·  hottest " + Math.round(pop.hottest) + "°" : "  ·  the hottest")
                    color: pop.tint
                    font.family: Theme.font
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: pop.kind === "cpu" ? "load  " + Stats.load
                        : pop.kind === "mem" ? (pop.memAvailK ? pop.size(pop.memAvailK) + " available  ·  " + pop.size((pop.meminfo.Cached || 0) + (pop.meminfo.Buffers || 0)) + " cache" : "")
                        : (Math.round(pop.pkgC) >= Stats.tempCritical ? "Hot — over " + Stats.tempCritical + "°" : "Throttles at 110°  ·  alarm at " + Stats.tempCritical + "°")
                    color: Theme.overlay1
                    font.family: Theme.font
                    font.pixelSize: 11
                }
                // swap, as a thin bar
                Item {
                    visible: pop.kind === "mem" && pop.swapTotalK > 0
                    width: parent.width
                    height: 24
                    Text {
                        y: 2
                        text: "swap  " + pop.size(pop.swapUsedK) + " / " + pop.size(pop.swapTotalK)
                        color: Theme.overlay1
                        font.family: Theme.font
                        font.pixelSize: 10
                    }
                    Rectangle {
                        y: 18
                        width: parent.width
                        height: 4
                        radius: 2
                        color: Theme.alpha(Theme.surface1, 0.9)
                        Rectangle {
                            width: parent.width * (pop.swapTotalK ? pop.swapUsedK / pop.swapTotalK : 0)
                            height: parent.height
                            radius: 2
                            color: Theme.mauve
                        }
                    }
                }
                Row {
                    topPadding: 4
                    spacing: 6
                    IconBtn {
                        size: 26
                        iconSize: 12
                        icon: "\u{f018d}"
                        text: "btop"
                        tip: "Open btop in a terminal"
                        onClicked: pop.launch("ghostty -e btop")
                    }
                    IconBtn {
                        size: 26
                        iconSize: 12
                        icon: "\u{f04c5}"
                        text: "Resources"
                        tip: "The Resources app" + (pop.kind === "mem" ? "" : ", with its graphs")
                        onClicked: pop.launch("resources --open-tab-id " + (pop.kind === "mem" ? "memory" : "cpu"))
                    }
                }
            }
        }

        // ── CPU: cores ──────────────────────────────────────────────────────
        Column {
            visible: pop.kind === "cpu"
            width: parent.width
            spacing: 6
            opacity: pop.stage(1)
            transform: Translate { y: 12 * (1 - pop.stage(1)) }
            Head { text: "CORES" }
            Grid {
                id: coreGrid
                columns: 11
                columnSpacing: 5
                rowSpacing: 6
                readonly property real cell: (parent.width - 10 * columnSpacing) / 11
                Repeater {
                    model: Stats.cores
                    delegate: Column {
                        required property int index
                        required property var modelData
                        spacing: 2
                        Rectangle {
                            width: coreGrid.cell
                            height: 34
                            radius: 6
                            color: Theme.alpha(Theme.surface0, 0.8)
                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width
                                height: Math.max(3, parent.height * modelData / 100)
                                radius: 6
                                color: pop.loadColor(modelData)
                                Behavior on height { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                            }
                            Text {
                                anchors.centerIn: parent
                                text: modelData
                                color: modelData >= 45 ? Theme.crust : Theme.subtext1
                                font.family: Theme.font
                                font.pixelSize: 9
                                font.weight: Font.Bold
                            }
                        }
                        Text {
                            width: coreGrid.cell
                            horizontalAlignment: Text.AlignHCenter
                            text: index
                            color: Theme.overlay0
                            font.family: Theme.font
                            font.pixelSize: 8
                        }
                    }
                }
            }
        }

        // ── CPU: processes · MEM: programs ──────────────────────────────────
        Column {
            visible: pop.kind !== "temp"
            width: parent.width
            spacing: 6
            opacity: pop.stage(2)
            transform: Translate { y: 12 * (1 - pop.stage(2)) }
            Item {
                width: parent.width
                height: 14
                Head { text: pop.kind === "cpu" ? "PROCESSES  ·  BY CPU" : "PROGRAMS  ·  BY MEMORY" }
                Text {
                    anchors.right: parent.right
                    text: pop.kind === "cpu" ? "% of one core" : "PSS, all processes of a program"
                    color: Theme.overlay0
                    font.family: Theme.font
                    font.pixelSize: 9
                }
            }
            Text {
                visible: !pop.gotData
                topPadding: 10
                bottomPadding: 10
                text: "Measuring…"
                color: Theme.overlay0
                font.family: Theme.font
                font.pixelSize: 12
            }
            Repeater {
                model: pop.kind === "cpu" ? pop.procs : pop.kind === "mem" ? pop.programs : []
                delegate: Rectangle {
                    id: prow
                    required property var modelData
                    required property int index
                    readonly property real frac: pop.kind === "cpu" ? Math.min(1, modelData.pct / 100) : modelData.kib / pop.topProgK
                    width: parent.width
                    height: 34
                    radius: 9
                    color: index === 0 ? Theme.alpha(pop.tint, 0.12) : Theme.alpha(Theme.surface0, 0.5)
                    // the share, as a soft fill behind the row
                    Rectangle {
                        width: parent.width * prow.frac
                        height: parent.height
                        radius: parent.radius
                        color: Theme.alpha(pop.tint, 0.13)
                        Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                    }
                    Text {
                        id: pname
                        x: 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 12 - pval.width - pmeta.width - 28
                        elide: Text.ElideRight
                        text: prow.modelData.name
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }
                    Text {
                        id: pmeta
                        anchors.right: pval.left
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: pop.kind === "cpu" ? prow.modelData.user + "  ·  " + prow.modelData.pid
                            : prow.modelData.procs + (prow.modelData.procs === 1 ? " process" : " processes") + (prow.modelData.rss ? " · rss" : "")
                        color: Theme.overlay1
                        font.family: Theme.font
                        font.pixelSize: 10
                    }
                    Text {
                        id: pval
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: 70
                        horizontalAlignment: Text.AlignRight
                        text: pop.kind === "cpu" ? prow.modelData.pct.toFixed(1) + "%" : pop.size(prow.modelData.kib)
                        color: pop.kind === "cpu" ? pop.loadColor(prow.modelData.pct) : pop.tint
                        font.family: Theme.font
                        font.pixelSize: 12
                        font.weight: Font.Bold
                    }
                }
            }
        }

        // ── TEMP ────────────────────────────────────────────────────────────
        Column {
            visible: pop.kind === "temp"
            width: parent.width
            spacing: 6
            opacity: pop.stage(1)
            transform: Translate { y: 12 * (1 - pop.stage(1)) }
            Head { text: "CPU CORES" }
            Text {
                visible: !pop.gotData
                text: "Reading sensors…"
                color: Theme.overlay0
                font.family: Theme.font
                font.pixelSize: 12
            }
            Flow {
                width: parent.width
                spacing: 6
                Repeater {
                    model: pop.coreTemps
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool hot: modelData.c >= pop.hottest && pop.hottest > 0
                        width: (parent.width - 3 * 6) / 4
                        height: 30
                        radius: 8
                        color: Theme.alpha(pop.tempColor(modelData.c), hot ? 0.28 : 0.12)
                        border.width: hot ? 1 : 0
                        border.color: Theme.red
                        Text {
                            x: 9
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.label.replace("Core ", "")
                            color: Theme.overlay1
                            font.family: Theme.font
                            font.pixelSize: 10
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 9
                            anchors.verticalCenter: parent.verticalCenter
                            text: Math.round(modelData.c) + "°"
                            color: pop.tempColor(modelData.c)
                            font.family: Theme.font
                            font.pixelSize: 12
                            font.weight: Font.Bold
                        }
                    }
                }
            }
        }
        Column {
            visible: pop.kind === "temp" && pop.sensors.length > 0
            width: parent.width
            spacing: 5
            opacity: pop.stage(2)
            transform: Translate { y: 12 * (1 - pop.stage(2)) }
            Head { visible: pop.otherSensors.length > 0; text: "STORAGE & WI-FI" }
            Repeater {
                model: pop.otherSensors
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool hot: modelData.c >= pop.hottest
                    width: parent.width
                    height: 30
                    radius: 8
                    color: Theme.alpha(Theme.surface0, 0.5)
                    border.width: hot ? 1 : 0
                    border.color: Theme.red
                    Text {
                        x: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: (modelData.group === "Storage" ? "\u{f02ca}  " : "\u{f05a9}  ")
                              + modelData.label
                        color: Theme.subtext1
                        font.family: Theme.font
                        font.pixelSize: 11
                    }
                    // a little gauge to its critical point (or 100°)
                    Rectangle {
                        anchors.right: tval.left
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: 90
                        height: 4
                        radius: 2
                        color: Theme.alpha(Theme.surface1, 0.9)
                        Rectangle {
                            width: parent.width * Math.min(1, modelData.c / (modelData.crit || 100))
                            height: parent.height
                            radius: 2
                            color: pop.tempColor(modelData.c)
                        }
                    }
                    Text {
                        id: tval
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        width: 40
                        horizontalAlignment: Text.AlignRight
                        text: Math.round(modelData.c) + "°"
                        color: pop.tempColor(modelData.c)
                        font.family: Theme.font
                        font.pixelSize: 12
                        font.weight: Font.Bold
                    }
                }
            }
            Head { visible: pop.boardSensors.length > 0; topPadding: 4; text: "BOARD  ·  ACPI ZONES" }
            Flow {
                width: parent.width
                spacing: 6
                Repeater {
                    model: pop.boardSensors
                    delegate: Rectangle {
                        required property var modelData
                        readonly property bool hot: modelData.c >= pop.hottest
                        width: (parent.width - 2 * 6) / 3
                        height: 28
                        radius: 8
                        color: Theme.alpha(pop.tempColor(modelData.c), hot ? 0.28 : 0.1)
                        border.width: hot ? 1 : 0
                        border.color: Theme.red
                        Text {
                            x: 9
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 50
                            elide: Text.ElideRight
                            text: modelData.label.replace("ACPI zone ", "zone ").replace("Board sensor ", "sensor ")
                            color: Theme.overlay1
                            font.family: Theme.font
                            font.pixelSize: 10
                        }
                        Text {
                            anchors.right: parent.right
                            anchors.rightMargin: 9
                            anchors.verticalCenter: parent.verticalCenter
                            text: Math.round(modelData.c) + "°"
                            color: pop.tempColor(modelData.c)
                            font.family: Theme.font
                            font.pixelSize: 12
                            font.weight: Font.Bold
                        }
                    }
                }
            }
            Text {
                topPadding: 2
                text: pop.fans.length ? pop.fans.map(f => f.label + " " + f.rpm + " rpm").join("  ·  ")
                                      : "\u{f0210}  No fan speed is exposed on this laptop"
                color: Theme.overlay0
                font.family: Theme.font
                font.pixelSize: 10
            }
        }
    }
}
