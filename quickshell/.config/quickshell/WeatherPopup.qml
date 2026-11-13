// The weather panel (Serpantinum-style) above the bottom bar's weather pill —
// click it. Open-Meteo through weather.py (`weather.py json`, the same 15 min
// cache the pill uses):
//
//   hero     the sky's glyph in a glowing orb · temperature · what it is ·
//            the place · feels like
//   chips    humidity · wind · UV · sunrise · sunset (+ rain soon)
//   hours    the next 12, scrollable sideways: glyph, temperature, rain %
//   days     4 days: glyph, what, high / low bar, rain %
//   footer   Refresh · Change place · age
//
// Change place (or right-click the pill) swaps chips / hours / days for the
// place picker, in the panel itself: type → `weather.py search` (Open-Meteo
// geocoding, debounced) → ↑ ↓ / hover, Enter / click → `weather.py set`.
// Esc steps back to the forecast; a panel with no place set opens on it.
//
// `qs ipc call weather toggle|open|close|place`
import QtQuick
import Quickshell
import Quickshell.Io

PanelPopup {
    id: pop

    property var pillRef: null                // the ScriptPill, refreshed after a change
    edge: Edges.Top
    panelWidth: 480
    pad: 16

    property var w: null
    readonly property bool ok: !!w && w.ok
    tint: !ok ? Theme.overlay1 : Theme.pillTint(pill)          // = the pill (accent)
    initialFocus: picking ? placeInput : null   // keyboard-opened on the picker: type

    function load() { if (!jsonProc.running) jsonProc.running = true; }
    Process {
        id: jsonProc
        command: [Theme.hypr + "/weather.py", "json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { pop.w = JSON.parse(text); } catch (e) { pop.w = { ok: false, why: "error" }; }
                // nowhere to show the weather for yet: straight to the picker
                if (pop.isOpen && !pop.picking && pop.w.why === "unset") pop.startPicking();
            }
        }
    }
    Process {
        id: refreshProc
        command: [Theme.hypr + "/weather.py", "refresh"]
        onExited: { pop.load(); if (pop.pillRef) pop.pillRef.refresh(); }
    }
    onOpened: { picking = false; load(); }

    // ── the place picker ────────────────────────────────────────────────────
    property bool picking: false
    property string query: ""
    property var hits: []
    property int sel: 0
    property string searchErr: ""
    property string searched: ""              // the query `hits` answer
    property var chosen: null                 // the hit being saved
    function startPicking() {
        picking = true;
        placeInput.text = "";
        query = "";
        hits = [];
        searched = "";
        searchErr = "";
        sel = 0;
        pickIn.restart();
        focusLater.restart();
    }
    function stopPicking() {
        picking = false;
        pop.card.forceActiveFocus();
    }
    function togglePlace() {
        if (!isOpen) { open(); startPicking(); }
        else if (picking) close();
        else startPicking();
    }
    function choose(h) {
        if (!h || setProc.running) return;
        chosen = h;
        setProc.command = [Theme.hypr + "/weather.py", "set", h.name, String(h.lat), String(h.lon)];
        setProc.running = true;
    }
    escapeAction: () => {
        if (!picking) return false;
        if (!setProc.running) stopPicking();
        return true;
    }
    Timer { id: focusLater; interval: 60; onTriggered: placeInput.forceActiveFocus() }
    Timer {
        id: searchLater
        interval: 280
        onTriggered: pop.search()
    }
    function search() {
        const q = query.trim();
        if (q.length < 2) { hits = []; searched = q; searchErr = ""; return; }
        if (searchProc.running) return;           // its onExited asks again
        searchProc.command = [Theme.hypr + "/weather.py", "search", q];
        searchProc.running = true;
    }
    Process {
        id: searchProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const r = JSON.parse(text);
                    pop.searched = r.query;
                    pop.searchErr = r.ok ? "" : (r.why || "error");
                    pop.hits = r.ok ? r.hits : [];
                } catch (e) { pop.searchErr = "error"; pop.hits = []; }
                pop.sel = 0;
            }
        }
        onExited: if (pop.picking && pop.searched !== pop.query.trim()) pop.search()
    }
    Process {
        id: setProc
        onExited: {
            pop.chosen = null;
            pop.load();
            if (pop.pillRef) pop.pillRef.refresh();
            if (pop.picking) pop.stopPicking();
        }
    }
    property real pickFade: 1
    NumberAnimation { id: pickIn; target: pop; property: "pickFade"; from: 0; to: 1; duration: 260; easing.type: Easing.OutCubic }
    function fmtPop(n) {
        return n >= 1e6 ? (n / 1e6).toFixed(n >= 1e7 ? 0 : 1) + " M"
             : n >= 1e3 ? Math.round(n / 1e3) + " k" : String(n);
    }
    function fmtCoord(v, pos, neg) { return Math.abs(v).toFixed(2) + "°" + (v >= 0 ? pos : neg); }
    IpcHandler {
        target: "weather"
        enabled: !!pop.anchor.window && !!pop.anchor.window.screen && pop.anchor.window.screen.name === BarState.active
        function toggle(): void { BarState.bottomShown = true; pop.toggle(); }
        function open(): void { BarState.bottomShown = true; pop.open(); }
        function close(): void { pop.close(); }
        function place(): void { BarState.bottomShown = true; pop.togglePlace(); }
    }

    function stage(k) { return Math.max(0, Math.min(1, (pop.intro - k * 0.12) / (1 - k * 0.12))); }

    component Chip: Rectangle {
        property string glyph
        property string label
        property color tint: Theme.subtext0
        width: chipRow.implicitWidth + 18
        height: 28
        radius: 9
        color: Theme.alpha(Theme.surface0, 0.75)
        Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: 6
            Text { text: parent.parent.glyph; color: parent.parent.tint; font.family: Theme.font; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter }
            Text { text: parent.parent.label; color: Theme.subtext1; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
        }
    }

    Column {
        width: parent.width
        spacing: 14

        // ── hero ────────────────────────────────────────────────────────────
        Row {
            width: parent.width
            spacing: 16
            opacity: pop.stage(0)
            transform: Translate { y: 12 * (1 - pop.stage(0)) }
            Item {
                width: 104
                height: 104
                Rectangle {
                    anchors.centerIn: parent
                    width: 96
                    height: 96
                    radius: 48
                    color: Theme.alpha(pop.tint, 0.16)
                    border.width: 2
                    border.color: Theme.alpha(pop.tint, 0.4)
                    SequentialAnimation on scale {
                        running: pop.isOpen
                        loops: Animation.Infinite
                        NumberAnimation { to: 1.05; duration: 2200; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1.0; duration: 2200; easing.type: Easing.InOutSine }
                    }
                }
                Text {
                    anchors.centerIn: parent
                    text: pop.ok ? pop.w.glyph : "\u{f0590}"
                    color: pop.tint
                    font.family: Theme.font
                    font.pixelSize: 50
                }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                Row {
                    spacing: 10
                    Text {
                        text: pop.ok ? pop.w.temp + "°" : "–"
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: 44
                        font.weight: Font.Bold
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            text: pop.ok ? pop.w.desc : pop.w && pop.w.why === "unset" ? "No place set" : "Weather unavailable"
                            color: pop.tint
                            font.family: Theme.font
                            font.pixelSize: 14
                            font.weight: Font.Bold
                        }
                        Text {
                            text: pop.ok ? "feels like " + pop.w.feels + "°" : pop.w && pop.w.why === "unset" ? "Pick a place below" : "offline?"
                            color: Theme.overlay1
                            font.family: Theme.font
                            font.pixelSize: 11
                        }
                    }
                }
                Text {
                    text: "\u{f034e}  " + (pop.ok ? pop.w.place : "—")
                    color: Theme.subtext0
                    font.family: Theme.font
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }
            }
        }

        // ── chips ───────────────────────────────────────────────────────────
        Flow {
            visible: pop.ok && !pop.picking
            width: parent.width
            spacing: 6
            opacity: pop.stage(1)
            Chip { glyph: "\u{f058e}"; label: pop.ok ? pop.w.humidity + "%" : ""; tint: Theme.sapphire }
            Chip { glyph: "\u{f059d}"; label: pop.ok ? pop.w.wind + " km/h" : ""; tint: Theme.teal }
            Chip { visible: pop.ok && pop.w.uv !== null; glyph: "\u{f0599}"; label: pop.ok ? "UV " + pop.w.uv : ""; tint: Theme.peach }
            Chip { glyph: "\u{f059c}"; label: pop.ok ? pop.w.sunrise : ""; tint: Theme.yellow }
            Chip { glyph: "\u{f059b}"; label: pop.ok ? pop.w.sunset : ""; tint: Theme.mauve }
        }
        Text {
            visible: pop.ok && !pop.picking && pop.w.soon !== ""
            width: parent.width
            wrapMode: Text.Wrap
            text: "\u{f054a}  " + (pop.ok ? pop.w.soon : "")
            color: Theme.sapphire
            font.family: Theme.font
            font.pixelSize: 12
            font.weight: Font.DemiBold
        }

        // ── next hours ──────────────────────────────────────────────────────
        Column {
            visible: pop.ok && !pop.picking
            width: parent.width
            spacing: 6
            opacity: pop.stage(2)
            transform: Translate { y: 12 * (1 - pop.stage(2)) }
            Text {
                text: "NEXT HOURS"
                color: Theme.overlay1
                font.family: Theme.font
                font.pixelSize: 10
                font.weight: Font.Bold
                font.letterSpacing: 1.2
            }
            Flickable {
                width: parent.width
                height: 84
                contentWidth: hoursRow.width
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.HorizontalFlick
                WheelHandler {
                    onWheel: ev => parent.contentX = Math.max(0, Math.min(parent.contentWidth - parent.width,
                                                       parent.contentX - (ev.angleDelta.y || ev.angleDelta.x) / 2))
                }
                Row {
                    id: hoursRow
                    spacing: 6
                    Repeater {
                        model: pop.ok ? pop.w.hours : []
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            width: 56
                            height: 84
                            radius: 12
                            color: index === 0 ? Theme.alpha(pop.tint, 0.16) : Theme.alpha(Theme.surface0, 0.55)
                            Column {
                                anchors.centerIn: parent
                                spacing: 3
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.time; color: Theme.overlay1; font.family: Theme.font; font.pixelSize: 10; font.weight: Font.DemiBold }
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.glyph; color: Theme.subtext1; font.family: Theme.font; font.pixelSize: 20 }
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.temp !== null ? modelData.temp + "°" : "–"; color: Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Bold }
                                Text { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.rain ? modelData.rain + "%" : " "; color: Theme.sapphire; font.family: Theme.font; font.pixelSize: 9 }
                            }
                        }
                    }
                }
            }
        }

        // ── days ────────────────────────────────────────────────────────────
        Column {
            visible: pop.ok && !pop.picking
            width: parent.width
            spacing: 5
            opacity: pop.stage(3)
            transform: Translate { y: 12 * (1 - pop.stage(3)) }
            readonly property int lo: pop.ok ? Math.min.apply(null, pop.w.days.map(d => d.min)) : 0
            readonly property int hi: pop.ok ? Math.max.apply(null, pop.w.days.map(d => d.max)) : 1
            Repeater {
                model: pop.ok ? pop.w.days : []
                delegate: Rectangle {
                    id: drow
                    required property var modelData
                    width: parent.width
                    height: 38
                    radius: 10
                    color: Theme.alpha(Theme.surface0, 0.45)
                    readonly property real span: Math.max(1, parent.hi - parent.lo)
                    Text { id: dn; x: 12; width: 52; anchors.verticalCenter: parent.verticalCenter; text: drow.modelData.name; color: Theme.text; font.family: Theme.font; font.pixelSize: 12; font.weight: Font.Bold }
                    Text { id: dg; anchors.left: dn.right; anchors.verticalCenter: parent.verticalCenter; text: drow.modelData.glyph; color: Theme.subtext1; font.family: Theme.font; font.pixelSize: 17 }
                    Text {
                        id: dd
                        anchors.left: dg.right; anchors.leftMargin: 10
                        width: 120
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        text: drow.modelData.desc + (drow.modelData.rain ? "  ·  " + drow.modelData.rain + "%" : "")
                        color: drow.modelData.rain >= 50 ? Theme.sapphire : Theme.overlay1
                        font.family: Theme.font
                        font.pixelSize: 11
                    }
                    Text { id: dmin; anchors.left: dd.right; anchors.leftMargin: 6; anchors.verticalCenter: parent.verticalCenter; text: drow.modelData.min + "°"; color: Theme.overlay1; font.family: Theme.font; font.pixelSize: 11 }
                    // the day's range on the week's scale
                    Rectangle {
                        id: track
                        anchors.left: dmin.right; anchors.leftMargin: 8
                        anchors.right: dmax.left; anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        height: 5
                        radius: 3
                        color: Theme.alpha(Theme.surface1, 0.8)
                        Rectangle {
                            x: track.width * (drow.modelData.min - drow.parent.lo) / drow.span
                            width: Math.max(6, track.width * (drow.modelData.max - drow.modelData.min) / drow.span)
                            height: parent.height
                            radius: 3
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0; color: Theme.sapphire }
                                GradientStop { position: 1; color: Theme.peach }
                            }
                        }
                    }
                    Text { id: dmax; anchors.right: parent.right; anchors.rightMargin: 12; anchors.verticalCenter: parent.verticalCenter; text: drow.modelData.max + "°"; color: Theme.text; font.family: Theme.font; font.pixelSize: 11; font.weight: Font.Bold }
                }
            }
        }

        // ── place picker ────────────────────────────────────────────────────
        Column {
            id: picker
            visible: pop.picking
            width: parent.width
            spacing: 8
            opacity: pop.stage(1) * pop.pickFade
            transform: Translate { y: 10 * (1 - pop.pickFade) }
            Text {
                text: "CHANGE PLACE"
                color: Theme.overlay1
                font.family: Theme.font
                font.pixelSize: 10
                font.weight: Font.Bold
                font.letterSpacing: 1.2
            }
            Rectangle {
                id: field
                width: parent.width
                height: 42
                radius: 12
                color: Theme.alpha(Theme.surface0, 0.8)
                border.width: 1
                border.color: placeInput.typing ? Theme.alpha(pop.tint, 0.8) : Theme.alpha(Theme.surface1, 0.8)
                Behavior on border.color { ColorAnimation { duration: Theme.fast } }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.IBeamCursor
                    onClicked: placeInput.forceActiveFocus()
                }
                Text {
                    id: lens
                    x: 13
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u{f0349}"                     // magnify
                    color: placeInput.typing ? pop.tint : Theme.overlay1
                    font.family: Theme.font
                    font.pixelSize: 16
                }
                TextInput {
                    id: placeInput
                    anchors { left: lens.right; leftMargin: 10; right: busy.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    color: Theme.text
                    selectionColor: Theme.alpha(pop.tint, 0.4)
                    selectByMouse: true
                    clip: true
                    font.family: Theme.font
                    font.pixelSize: 13
                    // in the Tab / arrow round, and findable again by name:
                    // PanelPopup puts the keyboard back on the control it
                    // last saw focused when the popup window loses the
                    // keyboard to a bar — a box outside the focus chain was
                    // swapped for the first button there, so typing died
                    activeFocusOnTab: true
                    readonly property string navKey: "weather:place"
                    // the popup never holds the keyboard — a bar does and
                    // forwards keys to BarState.typing (see SettingsField)
                    readonly property bool typing: activeFocus || (focus && BarState.typing === placeInput)
                    onFocusChanged: if (focus) BarState.typing = placeInput
                    cursorVisible: typing
                    onTextEdited: { pop.query = text; searchLater.restart(); }
                    Text {
                        visible: !placeInput.text
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        elide: Text.ElideRight
                        text: "City, town or area…"
                        color: Theme.overlay0
                        font: placeInput.font
                    }
                    Keys.onDownPressed: if (pop.hits.length) pop.sel = (pop.sel + 1) % pop.hits.length
                    Keys.onUpPressed: if (pop.hits.length) pop.sel = (pop.sel - 1 + pop.hits.length) % pop.hits.length
                    Keys.onReturnPressed: pop.choose(pop.hits[pop.sel])
                    Keys.onEnterPressed: pop.choose(pop.hits[pop.sel])
                    Keys.onEscapePressed: ev => { ev.accepted = true; pop.escapeKey(); }
                }
                Text {
                    id: busy
                    anchors { right: parent.right; rightMargin: 13; verticalCenter: parent.verticalCenter }
                    text: "\u{f0772}"                     // loading
                    visible: searchProc.running || searchLater.running
                    color: pop.tint
                    font.family: Theme.font
                    font.pixelSize: 14
                    RotationAnimation on rotation {
                        running: busy.visible
                        loops: Animation.Infinite
                        from: 0; to: 360; duration: 900
                    }
                }
            }
            // the matches
            Column {
                width: parent.width
                spacing: 4
                opacity: setProc.running ? 0.5 : 1
                Behavior on opacity { NumberAnimation { duration: Theme.fast } }
                Repeater {
                    model: pop.hits
                    delegate: Rectangle {
                        id: hrow
                        required property var modelData
                        required property int index
                        readonly property bool on: index === pop.sel
                        width: parent.width
                        height: 46
                        radius: 11
                        color: on ? Theme.alpha(pop.tint, 0.16) : Theme.alpha(Theme.surface0, 0.45)
                        border.width: on ? 1 : 0
                        border.color: Theme.alpha(pop.tint, 0.45)
                        Behavior on color { ColorAnimation { duration: Theme.fast } }
                        Text {
                            id: pin
                            x: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: "\u{f034e}"
                            color: hrow.on ? pop.tint : Theme.overlay1
                            font.family: Theme.font
                            font.pixelSize: 17
                        }
                        Column {
                            anchors { left: pin.right; leftMargin: 11; right: where.left; rightMargin: 8; verticalCenter: parent.verticalCenter }
                            spacing: 1
                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                text: hrow.modelData.name
                                color: Theme.text
                                font.family: Theme.font
                                font.pixelSize: 13
                                font.weight: Font.Bold
                            }
                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                text: hrow.modelData.region + (hrow.modelData.pop ? "  ·  " + pop.fmtPop(hrow.modelData.pop) : "")
                                color: Theme.overlay1
                                font.family: Theme.font
                                font.pixelSize: 10
                            }
                        }
                        Column {
                            id: where
                            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                            spacing: 1
                            Text {
                                anchors.right: parent.right
                                text: hrow.modelData.cc
                                color: hrow.on ? pop.tint : Theme.subtext0
                                font.family: Theme.font
                                font.pixelSize: 10
                                font.weight: Font.Bold
                            }
                            Text {
                                anchors.right: parent.right
                                text: pop.fmtCoord(hrow.modelData.lat, "N", "S") + " " + pop.fmtCoord(hrow.modelData.lon, "E", "W")
                                color: Theme.overlay0
                                font.family: Theme.font
                                font.pixelSize: 9
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: pop.sel = hrow.index
                            onClicked: pop.choose(hrow.modelData)
                        }
                    }
                }
            }
            Text {
                visible: text !== ""
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                topPadding: 4
                bottomPadding: 4
                readonly property string q: pop.query.trim()
                text: setProc.running && pop.chosen ? "Fetching the weather for " + pop.chosen.name + "…"
                    : q.length < 2 ? "Type a place — ↑ ↓ to choose, Enter to pick"
                    : pop.searched !== q ? ""
                    : pop.searchErr ? "Couldn't look that up (offline?)"
                    : !pop.hits.length ? "No place called “" + q + "”"
                    : ""
                color: pop.searchErr ? Theme.peach : Theme.overlay1
                font.family: Theme.font
                font.pixelSize: 11
            }
        }

        // ── footer ──────────────────────────────────────────────────────────
        Item {
            width: parent.width
            height: 32
            opacity: pop.stage(3)
            Row {
                spacing: 8
                anchors.verticalCenter: parent.verticalCenter
                IconBtn {
                    visible: !pop.picking
                    size: 30
                    icon: "\u{f0450}"
                    text: refreshProc.running ? "Updating…" : "Refresh"
                    enabled: !refreshProc.running
                    onClicked: refreshProc.running = true
                }
                IconBtn {
                    size: 30
                    icon: pop.picking ? "\u{f004d}" : "\u{f034e}"      // arrow-left / map-marker
                    text: pop.picking ? "Forecast" : "Change place"
                    tip: pop.picking ? "Back to the forecast (Esc)" : "Search for a place, right here"
                    tipEdge: Edges.Top
                    enabled: !setProc.running
                    onClicked: if (pop.picking) pop.stopPicking(); else pop.startPicking()
                }
            }
            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: pop.picking ? "Open-Meteo geocoding"
                    : pop.ok ? (pop.w.stale ? "stale · " : "") + "updated " + pop.w.age + " min ago · Open-Meteo" : ""
                color: pop.ok && pop.w.stale ? Theme.peach : Theme.overlay0
                font.family: Theme.font
                font.pixelSize: 10
            }
        }
    }
}
