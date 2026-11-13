// The news panel (Serpantinum-style) above the bottom bar's news pill, next
// to the weather. Headlines from RSS feeds through hypr/news.py (cached; a
// stale category is re-fetched while the panel shows the cached one):
//
//   header   category ▾ (Indian · International · Sports · Anime · AI
//            research · whatever was added · More) · how fresh · Refresh
//   chips    the category's sub-categories — click = show / hide, right-click
//            = only this one (again = all), "All" = everything back on.
//            Remembered per category (news.py set; ~/.local/state/news).
//            Ctrl+Tab / Ctrl+Shift+Tab open the category list and step
//            through it; Enter picks.
//   keys     Tab / Shift+Tab jump section to section (PanelPopup's
//            sections; navSection marks them here): category ▾ → Refresh →
//            chips → headlines → category; More: category ▾ → more
//            categories → built-in. Arrows move inside the section only.
//            Headlines: Tab lands on the one last used if still in view,
//            else the topmost in view.
//   list     newest first: title, sub-category dot, source, age. Click =
//            open in the browser (and close); middle-click = open, stay.
//            Right of the source: FREE · LIMITED (metered — a few free
//            articles a month) · PAID (subscribers only); hover = why.
//            Sites that flag it per article get checked in the background
//            (news.py paywall CAT, when json says "unchecked").
//   More     (last entry of the category list) a card per category — the
//            extra ones (news.py EXTRA: tech, programming, Linux, science,
//            space, gaming, …) then the built-in ones — icon, name and a few
//            of its sub-categories. + / ✓ = add to / remove from the list
//            (news.py add|remove, prefs "shown"); a click on the card opens
//            that category (adding it if needed).
//
// `qs ipc call news toggle|open|close|more`
import QtQuick
import Quickshell
import Quickshell.Io

PanelPopup {
    id: pop

    property var pillRef: null                // the ScriptPill, re-polled after changes
    edge: Edges.Top
    panelWidth: 540
    pad: 16

    readonly property string script: Theme.hypr + "/news.py"
    property var d: null                      // news.py json
    property string cat: d ? d.cat : ""
    property var off: ({})                    // sub id → true = hidden
    property string fetching: ""              // the category being refreshed
    readonly property var subs: d ? d.subs : []
    readonly property var cats: d ? d.cats : []
    readonly property var items: d ? d.items.filter(i => !pop.off[i.sub]) : []
    readonly property bool allOn: subs.every(s => !pop.off[s.id])
    // the "More" tab
    property bool more: false
    readonly property var catalog: d && d.more ? d.more : []
    readonly property var extras: catalog.filter(c => c.extra)
    readonly property int shownCount: cats.length
    readonly property int notAdded: extras.filter(c => !c.on).length
    readonly property int onCount: subs.filter(s => !pop.off[s.id]).length

    readonly property var palette: [Theme.blue, Theme.green, Theme.peach, Theme.mauve, Theme.pink,
                                    Theme.teal, Theme.yellow, Theme.sky, Theme.red, Theme.lavender]
    function subIndex(id) { for (let i = 0; i < subs.length; i++) if (subs[i].id === id) return i; return 0; }
    function subColor(id) { return palette[subIndex(id) % palette.length]; }
    function esc(s) { return String(s || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); }
    // free / paid badge: colour, text, glyph
    readonly property var accStyle: ({
        free: { c: Theme.green, t: "FREE", g: "\u{f0fc6}" },        // md-lock_open_variant
        limited: { c: Theme.yellow, t: "LIMITED", g: "\u{f097f}" }, // md-lock_clock
        paid: { c: Theme.red, t: "PAID", g: "\u{f033e}" }           // md-lock
    })
    function subLabel(id) { const s = subs[subIndex(id)]; return s ? s.label : id; }

    // ── news.py ─────────────────────────────────────────────────────────────
    function load(c) {
        jsonProc.want = c || "";
        if (jsonProc.running) { jsonProc.again = true; return; }
        jsonProc.command = [script, "json", jsonProc.want];
        jsonProc.running = true;
    }
    Process {
        id: jsonProc
        property string want: ""
        property bool again: false
        stdout: StdioCollector {
            onStreamFinished: {
                let j = null;
                try { j = JSON.parse(text); } catch (e) { return; }
                // a reply for a category we've since left: ignore it
                if (jsonProc.want && j.cat !== jsonProc.want) return;
                // mid fade-out: it goes in at the bottom of the fade
                if (fadeOut.running && j.cat === pop.cat) { pop.swapNext = j; return; }
                pop.applyJson(j);
            }
        }
        onExited: if (again) { again = false; pop.load(want); }
    }
    function applyJson(j) {
        // the cards come in one after another when this replaces the
        // loading state of a category switch
        const fresh = !!(d && d.loadingCat && d.cat === j.cat);
        const o = {};
        for (const s of j.subs) if (!s.on) o[s.id] = true;
        pop.off = o;
        pop.d = j;
        if (fresh) cascade();
        if (j.stale && pop.fetching !== j.cat) pop.fetch(j.cat);
        else if (j.unchecked > 0 && pop.fetching !== j.cat) pop.checkPaywalls(j.cat);
    }

    // ── switching category / More: a soft cross-fade ─────────────────────────
    // The old chips and headlines fade out (and stay put) while news.py
    // answers; at the bottom of the fade the new ones go in, the list starts
    // at the top and fades back in, its cards rising one after another.
    // A slow answer (feeds being fetched) shows the loading state meanwhile.
    property real swapFade: 1                 // the chips / list / More opacity
    property bool moreShown: false            // what's on screen; `more` = what's picked
    property var swapNext: null               // json that came during the fade-out
    property bool rising: false               // new cards: rise in one by one
    onMoreChanged: { if (isOpen) swap(); else moreShown = more; }
    function swap() { fadeIn.stop(); fadeOut.restart(); }
    function swapBottom() {
        moreShown = more;
        if (swapNext && swapNext.cat === cat) { const j = swapNext; swapNext = null; applyJson(j); }
        else if (d && d.loadingCat) { off = ({}); d = Object.assign({}, d, { items: [], subs: [] }); }
        list.positionViewAtBeginning();
        moreFlick.contentY = 0;
        fadeIn.restart();
    }
    function cascade() { rising = true; risingOff.restart(); }
    Timer { id: risingOff; interval: 800; onTriggered: pop.rising = false }
    NumberAnimation { id: fadeOut; target: pop; property: "swapFade"; to: 0; duration: 130; easing.type: Easing.InQuad; onFinished: pop.swapBottom() }
    NumberAnimation { id: fadeIn; target: pop; property: "swapFade"; to: 1; duration: 260; easing.type: Easing.OutCubic }

    function fetch(c) {
        if (fetchProc.running) return;
        pop.fetching = c;
        fetchProc.command = [script, "refresh", c];
        fetchProc.running = true;
    }
    Process {
        id: fetchProc
        onExited: {
            const c = pop.fetching;
            pop.fetching = "";
            if (c === pop.cat) pop.load(c);
            pillPoke.restart();
        }
    }
    // free / paid per article for the sites that say so (news.py paywall):
    // at most once a minute per category, then re-read the json
    property var pwAt: ({})
    function checkPaywalls(c) {
        if (pwProc.running || !c || Date.now() - (pwAt[c] || 0) < 60000) return;
        const o = Object.assign({}, pwAt);
        o[c] = Date.now();
        pwAt = o;
        pwProc.cat = c;
        pwProc.command = [script, "paywall", c];
        pwProc.running = true;
    }
    Process {
        id: pwProc
        property string cat: ""
        onExited: if (cat === pop.cat && !pop.more && !fadeOut.running) pop.load(cat)
    }

    // the pill's tooltip / glow follow the panel's changes
    Timer { id: pillPoke; interval: 300; onTriggered: if (pop.pillRef) pop.pillRef.refresh() }

    // prefs writes (set / add / remove) one after another, so two quick
    // clicks can't overwrite each other's prefs.json; reload = re-read the
    // panel's json once they're all done
    property var queue: []
    property bool reloadAfter: false
    function prefsCmd(args, reload) {
        queue = queue.concat([args]);
        if (reload) reloadAfter = true;
        runQueue();
    }
    function runQueue() {
        if (prefsProc.running || !queue.length) return;
        prefsProc.command = [script].concat(queue[0]);
        queue = queue.slice(1);
        prefsProc.running = true;
    }
    Process {
        id: prefsProc
        onExited: {
            if (pop.queue.length) { pop.runQueue(); return; }
            if (pop.reloadAfter) { pop.reloadAfter = false; pop.load(""); }
            pillPoke.restart();
        }
    }

    // the category list ▾: the shown categories, then More
    function pickTab(i) {
        if (i >= cats.length) { more = true; return; }
        more = false;                           // (fades, see swap)
        setCat(cats[i].id);
    }
    // add / remove a category locally (instant), then in news.py
    function applyShown(id, on) {
        if (!d || !d.more) return;
        const c = d.more.find(x => x.id === id);
        if (!c) return;
        let cl = d.cats.filter(x => x.id !== id);
        if (on) cl = d.cats.some(x => x.id === id) ? d.cats : d.cats.concat([{ id: c.id, label: c.label, icon: c.icon }]);
        d = Object.assign({}, d, { cats: cl, more: d.more.map(x => x.id === id ? Object.assign({}, x, { on: on }) : x) });
    }
    function setShown(id, on) {
        if (!on && shownCount <= 1) return;
        applyShown(id, on);
        prefsCmd([on ? "add" : "remove", id], true);
    }
    // a card's click: that category's headlines (news.py set adds it)
    function openCat(id) {
        const c = catalog.find(x => x.id === id);
        more = false;
        if (c && !c.on) {
            applyShown(id, true);
            setCat(id, true);
        } else setCat(id);
    }

    function setCat(c, reload) {
        if (!c || c === cat) return;
        prefsCmd(["set", c], !!reload);
        // the old cards stay (fading out) until the new ones are here
        swapNext = null;
        pop.d = Object.assign({}, pop.d, { cat: c, loadingCat: true });
        load(c);
        if (isOpen) swap(); else swapBottom();
        pillPoke.restart();
    }
    function save() {
        prefsCmd(["set", cat, Object.keys(off).filter(k => off[k]).join(",")], false);
    }
    function toggleSub(id) {
        const o = Object.assign({}, off);
        if (o[id]) delete o[id]; else o[id] = true;
        cascade();
        off = o;
        save();
    }
    // only this one; on the one already alone: everything back
    function solo(id) {
        const alone = !off[id] && onCount === 1;
        const o = {};
        if (!alone) for (const s of subs) if (s.id !== id) o[s.id] = true;
        cascade();
        off = o;
        save();
    }
    function allSubs() { cascade(); off = ({}); save(); }
    function openItem(it, stay) {
        if (!it || !it.link) return;
        Quickshell.execDetached(["xdg-open", it.link]);
        if (!stay) pop.close();
    }

    onOpened: {
        more = false;
        moreShown = false;
        fadeOut.stop();
        fadeIn.stop();
        swapFade = 1;
        load("");
        Quickshell.execDetached([script, "seen"]);
        pillPoke.restart();
    }
    IpcHandler {
        target: "news"
        enabled: !!pop.anchor.window && !!pop.anchor.window.screen && pop.anchor.window.screen.name === BarState.active
        function toggle(): void { BarState.bottomShown = true; pop.toggle(); }
        function open(): void { BarState.bottomShown = true; pop.open(); }
        function close(): void { pop.close(); }
        // straight to the More tab
        function more(): void { BarState.bottomShown = true; if (!pop.isOpen) pop.open(); pop.more = true; }
    }

    // Ctrl+Tab / Ctrl+Shift+Tab (PanelPopup.cycleTab): open the category
    // list and walk its highlight (wrapping); Enter / Space / a click picks,
    // Esc closes the list
    tabBar: QtObject {
        readonly property bool visible: true
        readonly property var options: catDd.options
        readonly property int shownIndex: catDd.open ? catDd.hi : catDd.currentIndex
        function pick(i) {
            const n = catDd.options.length;
            if (n < 2) return;
            const t = ((i % n) + n) % n;
            if (!catDd.open) catDd.openList();
            if (catDd.open) catDd.moveHi(t - catDd.hi);
        }
    }

    function stage(k) { return Math.max(0, Math.min(1, (pop.intro - k * 0.12) / (1 - k * 0.12))); }

    // ── a sub-category chip ─────────────────────────────────────────────────
    component SubChip: Rectangle {
        id: chip
        property string label
        property int count: -1
        property color c: pop.tint
        readonly property color panelTint: c      // its keyboard ring (FocusRing)
        property bool on: true
        property bool isAll: false
        signal toggled()
        signal soloed()
        readonly property bool kb: activeFocus || BarState.kbItem === chip
        readonly property bool lit: cma.containsMouse || kb
        activeFocusOnTab: true
        function kbActivate() { toggled(); }
        Keys.onPressed: ev => {
            if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter || ev.key === Qt.Key_Space) { kbActivate(); ev.accepted = true; }
        }
        width: chipRow.implicitWidth + 20
        height: 28
        radius: 9
        color: on ? Theme.alpha(c, lit ? 0.28 : 0.17) : lit ? Theme.alpha(Theme.surface1, 0.7) : Theme.alpha(Theme.surface0, 0.5)
        border.width: 1
        border.color: on ? Theme.alpha(c, 0.6) : Theme.alpha(Theme.surface1, 0.5)
        Behavior on color { ColorAnimation { duration: Theme.fast } }
        Behavior on border.color { ColorAnimation { duration: Theme.fast } }
        scale: cma.pressed ? 0.95 : 1
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }
        Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: 6
            Rectangle {
                visible: !chip.isAll
                anchors.verticalCenter: parent.verticalCenter
                width: 8
                height: 8
                radius: 4
                color: chip.on ? chip.c : "transparent"
                border.width: chip.on ? 0 : 1.5
                border.color: Theme.overlay0
            }
            Text {
                visible: chip.isAll
                anchors.verticalCenter: parent.verticalCenter
                text: "\u{f0e1e}"                         // md-check_bold
                color: chip.on ? chip.c : Theme.overlay0
                font.family: Theme.font
                font.pixelSize: 11
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: chip.label
                color: chip.on ? Theme.text : Theme.overlay1
                font.family: Theme.font
                font.pixelSize: 11
                font.weight: Font.DemiBold
                font.strikeout: !chip.on && !chip.isAll
            }
            Text {
                visible: chip.count >= 0
                anchors.verticalCenter: parent.verticalCenter
                text: chip.count
                color: chip.on ? Theme.alpha(chip.c, 0.9) : Theme.overlay0
                font.family: Theme.font
                font.pixelSize: 9
                font.weight: Font.Bold
            }
        }
        MouseArea {
            id: cma
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: m => { if (m.button === Qt.RightButton) chip.soloed(); else chip.toggled(); }
        }
        Tooltip {
            target: chip
            text: chip.isAll ? "Show every sub-category" : "Click: show / hide  ·  Right-click: only this"
            shown: cma.containsMouse
            edge: Edges.Top
        }
        FocusRing {}
    }

    // ── a category card (More tab) ──────────────────────────────────────────
    component CatCard: Rectangle {
        id: card
        required property var modelData
        readonly property bool on: modelData.on
        readonly property var subs: modelData.subs || []
        readonly property int preview: 4               // sub-categories shown
        readonly property bool kb: activeFocus || BarState.kbItem === card
        readonly property bool lit: cardMa.containsMouse || kb
        activeFocusOnTab: true
        // the keyboard finds it again after + rebuilds the grid (PanelPopup.noteKb)
        readonly property string navKey: "cat:" + modelData.id
        function kbActivate() { pop.openCat(modelData.id); }
        Keys.onPressed: ev => {
            if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter || ev.key === Qt.Key_Space) { kbActivate(); ev.accepted = true; }
        }
        // keep the keyboard's card in view
        onKbChanged: if (kb) {
            const y = card.mapToItem(moreCol, 0, 0).y;
            if (y < moreFlick.contentY) moreFlick.contentY = y;
            else if (y + height > moreFlick.contentY + moreFlick.height) moreFlick.contentY = y + height - moreFlick.height;
        }
        width: (moreCol.width - 8) / 2
        height: 98
        radius: 12
        color: on ? Theme.alpha(pop.tint, lit ? 0.17 : 0.1)
             : lit ? Theme.alpha(Theme.surface1, 0.65) : Theme.alpha(Theme.surface0, 0.42)
        border.width: 1
        border.color: on ? Theme.alpha(pop.tint, 0.45) : Theme.alpha(Theme.surface1, lit ? 0.8 : 0.4)
        Behavior on color { ColorAnimation { duration: Theme.fast } }
        Behavior on border.color { ColorAnimation { duration: Theme.fast } }
        scale: cardMa.pressed ? 0.98 : 1
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutBack } }

        MouseArea {
            id: cardMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pop.openCat(card.modelData.id)
        }
        Tooltip {
            target: card
            text: card.on ? "Open " + card.modelData.label
                          : "Open " + card.modelData.label + " (adds it to the list)"
            shown: cardMa.containsMouse && !addBtn.hovered
            edge: Edges.Top
        }
        Rectangle {
            id: badge
            x: 12
            y: 12
            width: 32
            height: 32
            radius: 10
            color: Theme.alpha(card.on ? pop.tint : Theme.overlay0, card.on ? 0.22 : 0.16)
            Text {
                anchors.centerIn: parent
                text: card.modelData.icon
                color: card.on ? pop.tint : Theme.subtext0
                font.family: Theme.font
                font.pixelSize: 17
            }
        }
        Column {
            anchors.left: badge.right
            anchors.leftMargin: 10
            anchors.right: addBtn.left
            anchors.rightMargin: 6
            anchors.verticalCenter: badge.verticalCenter
            spacing: 1
            Text {
                width: parent.width
                text: card.modelData.label
                elide: Text.ElideRight
                color: card.lit || card.on ? Theme.text : Theme.subtext1
                font.family: Theme.font
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }
            Text {
                width: parent.width
                text: card.on ? "In your list" : card.subs.length + " sub-categories"
                elide: Text.ElideRight
                color: card.on ? Theme.alpha(pop.tint, 0.85) : Theme.overlay1
                font.family: Theme.font
                font.pixelSize: 9
            }
        }
        IconBtn {
            id: addBtn
            readonly property string navKey: "cat:" + card.modelData.id + ":add"
            anchors.right: parent.right
            anchors.rightMargin: 10
            y: 14
            size: 28
            iconSize: 14
            active: card.on
            enabled: !card.on || pop.shownCount > 1
            icon: !card.on ? "\u{f0415}" : hovered ? "\u{f0156}" : "\u{f012c}"     // plus · close · check
            tip: !card.on ? "Add to the list" : pop.shownCount > 1 ? "Remove from the list" : "The last one stays"
            tipEdge: Edges.Top
            onClicked: pop.setShown(card.modelData.id, !card.on)
        }
        // a few of its sub-categories
        Flow {
            x: 12
            y: 54
            width: parent.width - 24
            height: 36
            clip: true
            spacing: 4
            Repeater {
                model: card.subs.slice(0, card.preview)
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    readonly property color c: pop.palette[index % pop.palette.length]
                    height: 16
                    width: subT.implicitWidth + 16
                    radius: 5
                    color: Theme.alpha(c, card.on ? 0.17 : 0.11)
                    Rectangle {
                        x: 5
                        anchors.verticalCenter: parent.verticalCenter
                        width: 4
                        height: 4
                        radius: 2
                        color: parent.c
                    }
                    Text {
                        id: subT
                        x: 12
                        anchors.verticalCenter: parent.verticalCenter
                        text: parent.modelData
                        color: Theme.subtext1
                        font.family: Theme.font
                        font.pixelSize: 9
                    }
                }
            }
            Text {
                visible: card.subs.length > card.preview
                height: 16
                verticalAlignment: Text.AlignVCenter
                text: "+" + (card.subs.length - card.preview)
                color: Theme.overlay1
                font.family: Theme.font
                font.pixelSize: 9
                font.weight: Font.Bold
            }
        }
        FocusRing {}
    }

    component SectionLabel: Text {
        color: Theme.overlay1
        font.family: Theme.font
        font.pixelSize: 10
        font.weight: Font.Bold
        font.letterSpacing: 0.6
    }

    Column {
        width: parent.width
        spacing: 12

        // ── header ──────────────────────────────────────────────────────────
        Item {
            width: parent.width
            height: 34
            opacity: pop.stage(0)
            transform: Translate { y: 10 * (1 - pop.stage(0)) }
            Dropdown {
                id: catDd
                property bool navSection: true
                width: 210
                anchors.verticalCenter: parent.verticalCenter
                options: pop.cats.map(c => ({ label: c.label, icon: c.icon }))
                         .concat([{ label: "More", icon: "\u{f0f8d}",          // md-view_grid_plus
                                    hint: pop.notAdded > 0 && !pop.more ? "+" + pop.notAdded : "" }])
                currentIndex: pop.more ? pop.cats.length : pop.cats.findIndex(c => c.id === pop.cat)
                wrap: true                      // ← → go round: More → the first category
                maxRows: 12
                placeholder: "News"
                tip: "Category"
                onSelected: i => pop.pickTab(i)
            }
            Text {
                visible: pop.more
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: pop.shownCount + " of " + pop.catalog.length + " in your list"
                color: Theme.overlay0
                font.family: Theme.font
                font.pixelSize: 10
            }
            Row {
                visible: !pop.more
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    readonly property bool busy: pop.fetching !== "" && pop.fetching === pop.cat
                    text: busy ? "updating…"
                         : !pop.d || pop.d.age < 0 ? ""
                         : (pop.d.failed ? pop.d.failed + "/" + pop.d.feeds + " feeds failed · " : "")
                           + (pop.d.age === 0 ? "just now" : pop.d.age + " min ago")
                    color: busy ? pop.tint : pop.d && pop.d.failed ? Theme.peach : Theme.overlay0
                    font.family: Theme.font
                    font.pixelSize: 10
                }
                IconBtn {
                    id: refreshBtn
                    property bool navSection: true
                    size: 30
                    icon: "\u{f0450}"
                    tip: "Refresh " + (catDd.cur ? catDd.cur.label : "")
                    tipEdge: Edges.Top
                    enabled: pop.fetching === "" && pop.cat !== ""
                    onClicked: pop.fetch(pop.cat)
                }
            }
        }

        // ── sub-category chips ──────────────────────────────────────────────
        Flow {
            id: chips
            property bool navSection: true
            visible: !pop.moreShown
            width: parent.width
            spacing: 6
            opacity: pop.stage(1) * pop.swapFade
            transform: Translate { y: 10 * (1 - pop.stage(1)) + 4 * (1 - pop.swapFade) }
            SubChip {
                id: allChip
                visible: pop.subs.length > 0
                isAll: true
                label: "All"
                on: pop.allOn
                c: pop.tint
                onToggled: pop.allSubs()
                onSoloed: pop.allSubs()
            }
            Repeater {
                model: pop.subs
                delegate: SubChip {
                    required property var modelData
                    label: modelData.label
                    count: modelData.count
                    c: pop.subColor(modelData.id)
                    on: !pop.off[modelData.id]
                    onToggled: pop.toggleSub(modelData.id)
                    onSoloed: pop.solo(modelData.id)
                }
            }
        }

        // ── More: every category, + to add ──────────────────────────────────
        Item {
            visible: pop.moreShown
            width: parent.width
            // the chips row + the list's room, so the panel keeps its size
            height: 430 + 12 + Math.max(28, chips.height)
            opacity: pop.stage(1) * pop.swapFade
            transform: Translate { y: 8 * (1 - pop.swapFade) }
            Flickable {
                id: moreFlick
                anchors.fill: parent
                anchors.rightMargin: 8
                clip: true
                contentHeight: moreCol.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: moreCol
                    width: moreFlick.width
                    spacing: 8
                    // every category in one grid; the ones in your list are
                    // highlighted with a ✓ (click it to take one out)
                    SectionLabel { text: "ALL CATEGORIES" }
                    Grid {
                        property bool navSection: true
                        columns: 2
                        spacing: 8
                        Repeater { model: pop.catalog; delegate: CatCard {} }
                    }
                }
            }
            Rectangle {
                visible: moreFlick.contentHeight > moreFlick.height
                x: parent.width - 4
                y: moreFlick.visibleArea.yPosition * moreFlick.height
                width: 3
                height: Math.max(20, moreFlick.visibleArea.heightRatio * moreFlick.height)
                radius: 2
                color: Theme.alpha(pop.tint, 0.5)
            }
        }

        // ── headlines ───────────────────────────────────────────────────────
        Item {
            visible: !pop.moreShown
            width: parent.width
            // a section (PanelPopup): Tab lands on the headline last used if
            // it's still in view, else the topmost one in view — no jumping
            property bool navSection: true
            function navEnter(last) {
                const inView = it => it && it.y >= list.contentY - 1 && it.y + it.height <= list.contentY + list.height + 1;
                if (last && inView(last)) return last;
                let i = list.indexAt(20, list.contentY + 6);
                return list.itemAtIndex(i < 0 ? 0 : i);
            }
            height: 430
            opacity: pop.stage(2) * pop.swapFade
            transform: Translate { y: 12 * (1 - pop.stage(2)) + 8 * (1 - pop.swapFade) }

            ListView {
                id: list
                anchors.fill: parent
                anchors.rightMargin: 8
                clip: true
                spacing: 5
                cacheBuffer: 600
                boundsBehavior: Flickable.StopAtBounds
                model: pop.items
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property color sc: pop.subColor(modelData.sub)
                    readonly property color panelTint: sc      // its keyboard ring
                    readonly property bool kb: activeFocus || BarState.kbItem === row
                    readonly property bool lit: rma.containsMouse || kb
                    activeFocusOnTab: true
                    function kbActivate() { pop.openItem(modelData, false); }
                    Keys.onPressed: ev => {
                        if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter || ev.key === Qt.Key_Space) { kbActivate(); ev.accepted = true; }
                    }
                    onKbChanged: if (kb) list.positionViewAtIndex(index, ListView.Contain)
                    // a new list's first rows rise in one after another
                    property real rise: 1
                    opacity: rise
                    transform: Translate { y: 14 * (1 - row.rise) }
                    Component.onCompleted: if (pop.rising && index < 9) { rise = 0; riseAnim.start(); }
                    SequentialAnimation {
                        id: riseAnim
                        PauseAnimation { duration: 40 + Math.min(row.index, 8) * 32 }
                        NumberAnimation { target: row; property: "rise"; to: 1; duration: 280; easing.type: Easing.OutCubic }
                    }
                    width: list.width
                    height: col.implicitHeight + 16
                    radius: 10
                    color: lit ? Theme.alpha(Theme.surface1, 0.65) : Theme.alpha(Theme.surface0, 0.42)
                    Behavior on color { ColorAnimation { duration: 90 } }
                    // the sub-category's colour down the left edge
                    Rectangle {
                        x: 0
                        width: 3
                        height: parent.height - 14
                        anchors.verticalCenter: parent.verticalCenter
                        radius: 2
                        color: row.sc
                        opacity: row.lit ? 1 : 0.7
                    }
                    Column {
                        id: col
                        x: 13
                        y: 8
                        width: parent.width - 26
                        spacing: 4
                        Text {
                            width: parent.width
                            text: row.modelData.t
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            color: row.lit ? Theme.text : Theme.subtext1
                            font.family: Theme.uiFont
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                            lineHeight: 1.1
                        }
                        Item {
                            width: parent.width
                            height: Math.max(meta.implicitHeight, accBadge.height)
                            Text {
                                id: meta
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - accBadge.width - 8
                                elide: Text.ElideRight
                                textFormat: Text.StyledText
                                text: "<font color='" + row.sc + "'>" + pop.esc(pop.subLabel(row.modelData.sub)) + "</font>"
                                      + "&nbsp;&nbsp;·&nbsp;&nbsp;" + pop.esc(row.modelData.src)
                                      + (row.modelData.age ? "&nbsp;&nbsp;·&nbsp;&nbsp;" + row.modelData.age : "")
                                color: Theme.overlay1
                                font.family: Theme.font
                                font.pixelSize: 10
                            }
                            // free / limited / paid
                            Rectangle {
                                id: accBadge
                                readonly property var st: pop.accStyle[row.modelData.acc || "free"] || pop.accStyle.free
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                width: accRow.implicitWidth + 12
                                height: 16
                                radius: 5
                                color: Theme.alpha(st.c, row.lit ? 0.24 : 0.14)
                                border.width: 1
                                border.color: Theme.alpha(st.c, 0.45)
                                Row {
                                    id: accRow
                                    anchors.centerIn: parent
                                    spacing: 3
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: accBadge.st.g
                                        color: accBadge.st.c
                                        font.family: Theme.font
                                        font.pixelSize: 9
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: accBadge.st.t
                                        color: accBadge.st.c
                                        font.family: Theme.font
                                        font.pixelSize: 8
                                        font.weight: Font.Bold
                                        font.letterSpacing: 0.5
                                    }
                                }
                                Tooltip {
                                    target: accBadge
                                    text: row.modelData.accWhy || ""
                                    shown: rma.containsMouse && accBadge.contains(accBadge.mapFromItem(rma, rma.mouseX, rma.mouseY))
                                    edge: Edges.Top
                                }
                            }
                        }
                    }
                    MouseArea {
                        id: rma
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: m => pop.openItem(row.modelData, m.button === Qt.MiddleButton)
                    }
                    FocusRing {}
                }
            }
            // scroll thumb
            Rectangle {
                visible: list.contentHeight > list.height
                x: parent.width - 4
                y: list.visibleArea.yPosition * list.height
                width: 3
                height: Math.max(20, list.visibleArea.heightRatio * list.height)
                radius: 2
                color: Theme.alpha(pop.tint, 0.5)
            }
            // empty / loading
            Column {
                id: emptyCol
                visible: pop.items.length === 0
                anchors.centerIn: parent
                spacing: 8
                readonly property bool busy: !pop.d || pop.d.loadingCat || (pop.fetching !== "" && !pop.d.cached)
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: parent.busy ? "\u{f1004}" : pop.d && pop.subs.length && pop.onCount === 0 ? "\u{f0209}" : "\u{f1944}"
                    color: Theme.alpha(pop.tint, 0.7)
                    font.family: Theme.font
                    font.pixelSize: 40
                    SequentialAnimation on opacity {
                        running: emptyCol.busy && pop.isOpen
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.35; duration: 600; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1; duration: 600; easing.type: Easing.InOutSine }
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: parent.busy ? "Fetching headlines…"
                         : pop.subs.length && pop.onCount === 0 ? "Everything here is switched off — pick a chip above"
                         : pop.d && pop.d.failed ? "Couldn't reach the feeds — offline?"
                         : "No headlines"
                    color: Theme.overlay1
                    font.family: Theme.font
                    font.pixelSize: 12
                }
            }
        }
    }
}
