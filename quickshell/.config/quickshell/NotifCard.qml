// One notification in the notifications panel (NotifPopup.qml): icon, app,
// time, summary, body (3 lines; click to expand), the app's buttons while
// mako still has it, Reply for phone messages. × on hover, or swipe it
// sideways, to dismiss.
import QtQuick
import Quickshell

Item {
    id: card

    required property var n                   // one entry of the panel's model
    property real now: Date.now() / 1000
    property bool expanded: false
    property bool leaving: false
    property bool replying: false
    // the PanelPopup (NotifPopup sets it): the reply box's ↑ ↓ move on
    property var panel: null
    // the ListView and this card's row in it, for ↑ ↓ between cards
    property var listView: null
    property int index: -1
    readonly property bool isNotifCard: true
    readonly property alias focusItem: body

    // ── keyboard ────────────────────────────────────────────────────────────
    // Tab reaches the list; on a card (or one of its buttons):
    //   ↑ ↓      the previous / next notification (round in a circle)
    //   ← →      this card's own stops: the card, ×, the app's buttons,
    //            Reply (or the reply box and Send)
    //   Enter    the card: what a click does (open it / expand) · a button: press it
    //   Delete   dismiss it
    // (PanelPopup.navKey asks kbKey of the focused control's card)
    readonly property bool kbIn: {
        for (let x = BarState.kbItem; x; x = x.parent) if (x === card) return true;
        return false;
    }
    function stops() {
        if (!panel) return [];
        return panel.focusables().filter(i => { for (let x = i; x; x = x.parent) if (x === card) return true; return false; });
    }
    function toCard(d) {
        if (!listView || !panel || index < 0 || listView.count < 2) return;
        const i = (index + d + listView.count) % listView.count;
        listView.positionViewAtIndex(i, ListView.Contain);
        const row = listView.itemAtIndex(i);
        if (!row) return;
        for (let j = 0; j < row.children.length; j++)
            if (row.children[j].isNotifCard) { panel.kbFocus(row.children[j].focusItem); return; }
    }
    function kbKey(key, mods) {
        if (mods & (Qt.ControlModifier | Qt.AltModifier)) return false;
        if (key === Qt.Key_Up || key === Qt.Key_Down) { toCard(key === Qt.Key_Down ? 1 : -1); return true; }
        if (key === Qt.Key_Left || key === Qt.Key_Right) {
            const l = stops();
            if (!l.length) return true;
            let cur = panel.current(), k = l.indexOf(cur);
            if (k < 0) k = 0;
            panel.kbFocus(l[(k + (key === Qt.Key_Right ? 1 : -1) + l.length) % l.length]);
            return true;
        }
        if (key === Qt.Key_Delete && n.dismissable !== false) { leave(); return true; }
        return false;
    }
    function activate() {
        if (card.canClick) card.invoke("default");
        else card.expanded = !card.expanded;
    }

    signal dismiss()
    signal invoke(string action)              // "default" or an action key
    signal reply(string text)

    readonly property bool isPhone: n.kind === "phone"
    readonly property color tint: n.critical ? Theme.red : Theme.tintOf(parent)   // the popup's
    // a critical card's ring / buttons / reply box are red too (Theme.tintOf)
    readonly property color panelTint: tint
    readonly property bool canClick: !!n.hasDefault

    function ago(t) {
        if (!t) return "";
        const d = now - t;
        if (d < 60) return "now";
        if (d < 3600) return Math.floor(d / 60) + "m";
        const lt = new Date(t * 1000), td = new Date(now * 1000);
        if (lt.toDateString() === td.toDateString()) return Qt.formatTime(lt, "hh:mm");
        if (d < 7 * 86400) return Qt.formatDateTime(lt, "ddd hh:mm");
        return Qt.formatDate(lt, "dd MMM");
    }

    function src(name) {
        if (!name) return "";
        if (name.startsWith("file://")) return name;
        if (name.startsWith("/")) return "file://" + name;
        return Quickshell.iconPath(name, true);
    }
    readonly property string iconSrc: {
        const cands = [n.image, n.icon];
        for (const c of cands) { const s = src(c); if (s) return s; }
        const de = DesktopEntries.heuristicLookup(n.desktop || n.app || "");
        return de && de.icon ? Quickshell.iconPath(de.icon, true) : "";
    }

    function leave() {
        if (leaving) return;
        leaving = true;
        slide.to = (dx < 0 ? -1 : 1) * (width + 20);
        outAnim.start();
    }

    implicitHeight: body.height
    clip: false

    property real dx: drag.active ? drag.translation.x : 0
    Behavior on dx { enabled: !drag.active && !card.leaving; NumberAnimation { duration: 260; easing.type: Easing.OutBack } }

    ParallelAnimation {
        id: outAnim
        NumberAnimation { id: slide; target: card; property: "dx"; duration: 220; easing.type: Easing.InCubic }
        NumberAnimation { target: body; property: "opacity"; to: 0; duration: 220 }
        onFinished: card.dismiss()
    }

    Rectangle {
        id: body
        x: card.dx
        width: parent.width
        height: col.height + 22
        radius: 14
        color: hover.hovered ? Theme.alpha(Theme.surface0, 0.95) : Theme.alpha(Theme.surface0, 0.55)
        border.width: 1
        border.color: card.n.critical ? Theme.alpha(Theme.red, 0.7)
                    : card.n.unread ? Theme.alpha(card.tint, 0.45) : Theme.alpha(Theme.surface1, 0.5)
        opacity: 1 - Math.min(0.7, Math.abs(card.dx) / (card.width * 0.9))
        Behavior on color { ColorAnimation { duration: Theme.fast } }

        // the card itself is a keyboard stop (see kbKey above)
        activeFocusOnTab: true
        readonly property string navKey: "notif:" + (card.n.uid || card.n.path || card.n.id || "")
        function kbActivate() { card.activate(); }
        Keys.onPressed: ev => {
            if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter || ev.key === Qt.Key_Space) { kbActivate(); ev.accepted = true; }
        }
        FocusRing {}

        // unread / critical marker
        Rectangle {
            visible: card.n.unread || card.n.critical
            x: 0
            y: 14
            width: 3
            height: 22
            radius: 2
            color: card.tint
        }

        HoverHandler { id: hover }
        DragHandler {
            id: drag
            target: null
            yAxis.enabled: false
            onActiveChanged: {
                if (active) return;
                if (Math.abs(translation.x) > card.width * 0.32) {
                    card.dx = translation.x;
                    card.leave();
                }
            }
        }
        TapHandler {
            onTapped: card.activate()
        }

        // icon
        Rectangle {
            id: badge
            x: 12
            y: 12
            width: 38
            height: 38
            radius: 12
            color: Theme.alpha(Theme.surface1, 0.7)
            Image {
                id: img
                anchors.centerIn: parent
                width: card.n.image || card.isPhone ? 38 : 26
                height: width
                sourceSize: Qt.size(76, 76)
                source: card.iconSrc
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: status === Image.Ready
            }
            Text {
                visible: img.status !== Image.Ready
                anchors.centerIn: parent
                text: card.isPhone ? "\u{f011c}" : "\u{f009a}"
                color: Theme.subtext0
                font.family: Theme.font
                font.pixelSize: 18
            }
        }

        Column {
            id: col
            anchors { left: badge.right; leftMargin: 12; right: parent.right; rightMargin: 12 }
            y: 11
            spacing: 3

            // app · time   (×)
            Item {
                width: parent.width
                height: 16
                Text {
                    id: appName
                    width: Math.min(implicitWidth, parent.width - when.width - 34)
                    text: card.n.app || "Notification"
                    elide: Text.ElideRight
                    color: Theme.subtext0
                    font.family: Theme.font
                    font.pixelSize: 11
                    font.weight: Font.Bold
                }
                Text {
                    id: when
                    anchors.left: appName.right
                    anchors.leftMargin: 6
                    text: card.isPhone ? "· " + (card.n.device || "phone") : "· " + card.ago(card.n.time)
                    color: Theme.overlay0
                    font.family: Theme.font
                    font.pixelSize: 11
                }
                Rectangle {
                    id: xBtn
                    visible: card.n.dismissable !== false
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 22
                    height: 22
                    radius: 7
                    // a keyboard stop too (shown while the keyboard is on the card)
                    activeFocusOnTab: true
                    readonly property string navKey: "notif:x:" + (card.n.uid || card.n.path || card.n.id || "")
                    function kbActivate() { card.leave(); }
                    Keys.onPressed: ev => {
                        if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter || ev.key === Qt.Key_Space) { kbActivate(); ev.accepted = true; }
                    }
                    readonly property bool kbHot: activeFocus || BarState.kbItem === xBtn
                    opacity: hover.hovered || card.kbIn ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.fast } }
                    color: xMa.containsMouse || kbHot ? Theme.alpha(Theme.red, 0.9) : Theme.alpha(Theme.surface1, 0.8)
                    FocusRing {}
                    Text {
                        anchors.centerIn: parent
                        text: "\u{f0156}"
                        color: xMa.containsMouse || xBtn.kbHot ? Theme.crust : Theme.subtext0
                        font.family: Theme.font
                        font.pixelSize: 13
                    }
                    MouseArea {
                        id: xMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: card.leave()
                    }
                }
            }

            Text {
                width: parent.width
                visible: text !== ""
                text: card.n.summary || ""
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                maximumLineCount: card.expanded ? 6 : 2
                elide: Text.ElideRight
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 13
                font.weight: Font.Bold
            }
            Text {
                id: bodyText
                width: parent.width
                visible: text !== ""
                text: card.n.body || ""
                textFormat: Text.StyledText
                wrapMode: Text.Wrap
                maximumLineCount: card.expanded ? 40 : 3
                elide: Text.ElideRight
                color: Theme.subtext0
                linkColor: card.tint
                font.family: Theme.font
                font.pixelSize: 12
                lineHeight: 1.1
                onLinkActivated: link => Qt.openUrlExternally(link)
            }

            // buttons: the app's actions (live only) and Reply
            Flow {
                width: parent.width
                spacing: 6
                topPadding: 5
                visible: (card.n.actions || []).length > 0 || !!card.n.replyable
                Repeater {
                    model: card.n.actions || []
                    delegate: IconBtn {
                        required property var modelData
                        required property int index
                        size: 26
                        text: card.isPhone ? modelData : modelData[1]
                        active: index === 0
                        activeFg: card.tint
                        onClicked: card.invoke(card.isPhone ? modelData : modelData[0])
                    }
                }
                IconBtn {
                    id: replyBtn
                    visible: !!card.n.replyable && !card.replying
                    size: 26
                    icon: "\u{f045a}"                 // md-reply
                    iconSize: 13
                    text: "Reply"
                    onClicked: { card.replying = true; field.forceActiveFocus(); }
                }
            }

            Rectangle {
                visible: card.replying
                width: parent.width
                height: 32
                radius: 9
                color: Theme.alpha(Theme.surface1, 0.7)
                border.width: 1
                border.color: Theme.alpha(card.tint, field.typing ? 0.7 : 0.3)
                TextInput {
                    id: field
                    anchors { left: parent.left; leftMargin: 10; right: send.left; rightMargin: 6; verticalCenter: parent.verticalCenter }
                    color: Theme.text
                    selectionColor: Theme.alpha(card.tint, 0.4)
                    font.family: Theme.font
                    font.pixelSize: 12
                    clip: true
                    // keys come from a bar (BarState.typing, see SettingsField)
                    readonly property bool typing: activeFocus || (focus && BarState.typing === field)
                    onFocusChanged: if (focus) BarState.typing = field
                    cursorVisible: typing
                    // in the Tab / arrow round and findable by name: when the
                    // popup window loses the keyboard to a bar, PanelPopup
                    // puts it back on this box (not the list's first button)
                    activeFocusOnTab: true
                    readonly property string navKey: "notif:reply:" + (card.n.uid || card.n.path || card.n.id || "")
                    // Esc: cancel the reply, not close the panel (PanelPopup
                    // asks the box being typed in first) — back to Reply
                    function textEscape() {
                        card.replying = false;
                        text = "";
                        if (card.panel) Qt.callLater(() => { if (replyBtn.visible) card.panel.kbFocus(replyBtn); });
                    }
                    Keys.onEscapePressed: ev => { ev.accepted = true; textEscape(); }
                    // ↑ = back to the card, ↓ = Send (from there ↑ ↓ are the
                    // notifications again); ← → still move the text cursor
                    Keys.onUpPressed: if (card.panel) card.panel.kbFocus(body)
                    Keys.onDownPressed: if (card.panel) card.panel.kbFocus(send)
                    onAccepted: if (text.trim()) { card.reply(text); text = ""; card.replying = false; }
                    Text {
                        visible: !parent.text
                        text: "Reply…"
                        color: Theme.overlay0
                        font: parent.font
                    }
                }
                IconBtn {
                    id: send
                    anchors { right: parent.right; rightMargin: 3; verticalCenter: parent.verticalCenter }
                    size: 26
                    icon: "\u{f048a}"                 // md-send
                    iconSize: 13
                    active: field.text.trim() !== ""
                    onClicked: if (field.text.trim()) { card.reply(field.text); field.text = ""; card.replying = false; }
                }
            }
        }
    }
}
