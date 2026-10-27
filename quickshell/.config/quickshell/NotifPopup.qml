// The notifications panel under the bell (replaces notif-center.py's GTK
// panel, which stays as `notif-center.py toggle` for the fallback bar).
//
//   System   history from notif-log.py: New (unread when opened) · Today ·
//            Earlier. Buttons work while mako still has the notification.
//   Phone    KDE Connect: what is in the phone's shade now (dismiss on the
//            phone, actions, Reply), then "Earlier". Hidden while no phone
//            is reachable and nothing is logged.
//
// While open, `notif-center.py serve` runs: it marks everything read (the
// bell's count), hides mako's popups (mode panel-open), streams a JSON
// snapshot per change and takes commands on stdin; closing stops it, which
// undoes the mode. × or a sideways swipe dismisses a card; Clear asks twice.
import QtQuick
import Quickshell
import Quickshell.Io

PanelPopup {
    id: pop
    tabBar: menuTabs                          // Ctrl+Tab / Ctrl+Shift+Tab cycle it
    TabFade { id: tabFx; key: pop.tab; active: pop.isOpen }   // soft tab swap

    panelWidth: 430

    property string tab: "system"             // system | phone
    function openTab(name) {
        if (isOpen && name === tab) { close(); return; }
        tab = name === "phone" ? "phone" : "system";
        open();
    }

    property var snap: ({ dnd: false, system: [], earlier: [], phone: [] })
    property var gone: ({})                   // uids dismissed, until the next snapshot drops them
    property bool dnd: false
    property real now: Date.now() / 1000

    function send(line) { if (proc.running) proc.write(line + "\n"); }

    function isToday(t) { return new Date(t * 1000).toDateString() === new Date().toDateString(); }

    readonly property var devices: snap.phone || []
    readonly property var reachable: devices.filter(d => d.reachable)
    readonly property bool phoneTab: reachable.length > 0 || (snap.earlier || []).length > 0

    readonly property var sysItems: (snap.system || []).map(e => Object.assign({
        kind: "sys", uid: "s" + e.key + (e.unread ? "u" : ""),
        group: e.unread ? "New" : isToday(e.time) ? "Today" : "Earlier"
    }, e)).filter(e => !gone[e.uid])

    readonly property var phoneItems: {
        const out = [];
        for (const d of reachable)
            for (const n of d.notes)
                out.push(Object.assign({ kind: "phone", uid: n.path, group: "On " + d.name + " now",
                                         device: d.name, unread: false, critical: false }, n));
        for (const e of snap.earlier || [])
            out.push(Object.assign({ kind: "log", uid: "s" + e.key + (e.unread ? "u" : ""), group: "Earlier" }, e));
        return out.filter(e => !gone[e.uid]);
    }
    readonly property var items: tab === "phone" ? phoneItems : sysItems
    readonly property int sysNew: sysItems.filter(e => e.unread).length
    readonly property int phoneNew: phoneItems.filter(e => e.kind === "phone" || e.unread).length

    function dismiss(n) {
        const g = Object.assign({}, gone);
        g[n.uid] = true;
        gone = g;
        if (n.kind === "phone") send("phone-dismiss " + n.path);
        else send("remove " + n.key);
    }
    function invoke(n, action) {
        if (n.kind === "phone") { send("phone-action " + n.path + " " + action); return; }
        if (!n.live || !n.id) return;
        send("invoke " + n.id + " " + action);
        close();                              // it usually opens something
    }

    Process {
        id: proc
        command: ["/usr/bin/python3", Theme.hypr + "/notif-center.py", "serve"]
        running: pop.isOpen
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => {
                try {
                    const s = JSON.parse(line);
                    pop.snap = s;
                    pop.dnd = s.dnd;
                    // forget dismissals the snapshot has caught up with
                    const live = new Set();
                    for (const e of s.system.concat(s.earlier)) { live.add("s" + e.key); live.add("s" + e.key + "u"); }
                    for (const d of s.phone) for (const n of d.notes) live.add(n.path);
                    const g = {};
                    for (const k in pop.gone) if (live.has(k)) g[k] = true;
                    pop.gone = g;
                } catch (e) {
                    console.warn("notif-center serve: bad JSON");
                }
            }
        }
    }
    onOpened: { now = Date.now() / 1000; clearArmed = false; }
    onPhoneTabChanged: if (!phoneTab && tab === "phone") tab = "system"

    Timer {
        interval: 30000
        repeat: true
        running: pop.isOpen
        onTriggered: pop.now = Date.now() / 1000
    }

    // Clear: first click arms it (red, "Clear?"), a second within 3 s clears
    property bool clearArmed: false
    Timer { id: disarm; interval: 3000; onTriggered: pop.clearArmed = false }

    Column {
        width: parent.width
        spacing: 12

        // ── header ──────────────────────────────────────────────────────
        Item {
            width: parent.width
            height: 34
            opacity: pop.intro
            transform: Translate { y: 12 * (1 - pop.intro) }

            Rectangle {
                id: bellBadge
                width: 34
                height: 34
                radius: 11
                color: pop.dnd ? Theme.alpha(Theme.surface1, 0.8) : Theme.accent
                Text {
                    anchors.centerIn: parent
                    text: pop.dnd ? "\u{f009b}" : "\u{f009a}"
                    color: pop.dnd ? Theme.overlay1 : Theme.crust
                    font.family: Theme.font
                    font.pixelSize: 17
                }
            }
            Column {
                anchors { left: bellBadge.right; leftMargin: 10; verticalCenter: parent.verticalCenter }
                spacing: 1
                Text {
                    text: "Notifications"
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 15
                    font.weight: Font.Bold
                }
                Text {
                    text: pop.dnd ? "Do not disturb — popups hidden"
                        : pop.sysItems.length + (pop.sysItems.length === 1 ? " notification" : " notifications")
                    color: Theme.overlay1
                    font.family: Theme.font
                    font.pixelSize: 11
                }
            }

            Row {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 8
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "DND"
                    color: pop.dnd ? Theme.accent : Theme.overlay1
                    font.family: Theme.font
                    font.pixelSize: 11
                    font.weight: Font.Bold
                }
                Toggle {
                    anchors.verticalCenter: parent.verticalCenter
                    checked: pop.dnd
                    onToggled: v => { pop.dnd = v; pop.send("dnd " + (v ? "on" : "off")); }
                }
                Item { width: 2; height: 1 }
                IconBtn {
                    anchors.verticalCenter: parent.verticalCenter
                    size: 30
                    iconSize: 14
                    icon: "\u{f05e9}"                 // md-delete_sweep
                    text: pop.clearArmed ? "Clear?" : "Clear"
                    active: pop.clearArmed
                    activeFg: Theme.red
                    enabled: pop.items.some(e => e.kind !== "phone")
                    tip: pop.clearArmed ? "" : "Clear this tab's history (phone: only Earlier)"
                    onClicked: {
                        if (!pop.clearArmed) { pop.clearArmed = true; disarm.restart(); return; }
                        pop.clearArmed = false;
                        const g = Object.assign({}, pop.gone);
                        for (const e of pop.items) if (e.kind !== "phone") g[e.uid] = true;
                        pop.gone = g;
                        pop.send("clear " + pop.tab);
                    }
                }
            }
        }

        Segmented {
            id: menuTabs
            visible: pop.phoneTab
            width: parent.width
            options: ["\u{f0379}  System" + (pop.sysNew ? "  " + pop.sysNew : ""),
                      "\u{f011c}  Phone" + (pop.phoneNew ? "  " + pop.phoneNew : "")]
            currentIndex: pop.tab === "phone" ? 1 : 0
            opacity: pop.intro
            transform: Translate { y: 16 * (1 - pop.intro) }
            onSelected: i => { pop.tab = i ? "phone" : "system"; pop.clearArmed = false; }
        }

        // phones that are paired but away
        Repeater {
            model: pop.tab === "phone" ? pop.devices.filter(d => !d.reachable) : []
            delegate: Text {
                required property var modelData
                text: "\u{f011c}  " + modelData.name + " — not connected"
                color: Theme.overlay0
                font.family: Theme.font
                font.pixelSize: 11
            }
        }

        // ── the list ────────────────────────────────────────────────────
        Item {
            id: listBox
            width: parent.width
            readonly property real maxH: (pop.screen ? pop.screen.height : 1080) * 0.7 - 150
            height: list.count ? Math.min(list.contentHeight, maxH) : 170
            Behavior on height { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            opacity: pop.intro * tabFx.value
            transform: Translate { y: 22 * (1 - pop.intro) + 8 * (1 - tabFx.value) }

            ListView {
                id: list
                anchors.fill: parent
                clip: true
                spacing: 8
                boundsBehavior: Flickable.StopAtBounds
                model: ScriptModel { values: pop.items; objectProp: "uid" }

                add: Transition {
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 300; easing.type: Easing.OutQuint }
                    NumberAnimation { property: "scale"; from: 0.94; to: 1; duration: 340; easing.type: Easing.OutBack }
                }
                remove: Transition {
                    NumberAnimation { property: "opacity"; to: 0; duration: 160 }
                }
                displaced: Transition {
                    NumberAnimation { property: "y"; duration: 280; easing.type: Easing.OutCubic }
                }

                // each card carries its group's heading when it starts one
                // (ListView sections need model roles; ScriptModel has none)
                delegate: Column {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool heads: index === 0 || (pop.items[index - 1] || {}).group !== modelData.group
                    width: list.width
                    spacing: 0

                    Text {
                        visible: row.heads
                        height: 24
                        topPadding: row.index === 0 ? 0 : 6
                        text: row.modelData.group.toUpperCase()
                        color: row.modelData.group === "New" ? Theme.accent : Theme.overlay1
                        font.family: Theme.font
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        font.letterSpacing: 1.2
                    }
                    NotifCard {
                        width: parent.width
                        n: row.modelData
                        now: pop.now
                        onDismiss: pop.dismiss(row.modelData)
                        onInvoke: action => pop.invoke(row.modelData, action)
                        onReply: text => pop.send("phone-reply " + row.modelData.path + " " + text.replace(/\n/g, " "))
                    }
                }
            }

            Column {
                visible: list.count === 0
                anchors.centerIn: parent
                spacing: 8
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "\u{f009b}"
                    color: Theme.surface2
                    font.family: Theme.font
                    font.pixelSize: 34
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: pop.tab === "phone" ? "Nothing from the phone" : "You're all caught up"
                    color: Theme.overlay0
                    font.family: Theme.font
                    font.pixelSize: 12
                }
            }
        }
    }
}
