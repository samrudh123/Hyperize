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

    signal dismiss()
    signal invoke(string action)              // "default" or an action key
    signal reply(string text)

    readonly property bool isPhone: n.kind === "phone"
    readonly property color tint: n.critical ? Theme.red : Theme.tintOf(parent)   // the popup's
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
            onTapped: {
                if (card.canClick) card.invoke("default");
                else card.expanded = !card.expanded;
            }
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
                    visible: card.n.dismissable !== false
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 22
                    height: 22
                    radius: 7
                    opacity: hover.hovered ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Theme.fast } }
                    color: xMa.containsMouse ? Theme.alpha(Theme.red, 0.9) : Theme.alpha(Theme.surface1, 0.8)
                    Text {
                        anchors.centerIn: parent
                        text: "\u{f0156}"
                        color: xMa.containsMouse ? Theme.crust : Theme.subtext0
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
                    Keys.onEscapePressed: { card.replying = false; text = ""; }
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
