// One task in the tasks panel (TasksPopup.qml): ○ tick · !! priority (click
// cycles) · text · due / repeat / age · on hover ↑ ↓ (manual order), ✎ edit
// (text + deadline, with quick picks), 🗑 delete (click twice).
//
//     TaskCard { pop: panel; t: task; up: prevTask; down: nextTask }
import QtQuick
import Quickshell

Rectangle {
    id: card

    // keyboard: Tab to the task, Enter / Space ticks it (or unticks)
    activeFocusOnTab: !editingMe
    function kbActivate() { if (pop) pop.op([t.done ? "undone" : "done", String(t.i), t.text]); }
    Keys.onPressed: ev => {
        if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter || ev.key === Qt.Key_Space) { kbActivate(); ev.accepted = true; }
    }

    property var pop: null
    property var t: ({})
    property var up: null                     // neighbours for ↑ ↓ (null = none)
    property var down: null
    readonly property string k: pop ? pop.key(t) : ""
    readonly property bool editingMe: !!pop && pop.editing === k

    width: parent ? parent.width : 400
    height: editingMe ? editCol.height + 22 : Math.max(52, info.height + 20)
    radius: 12
    color: cardMa.containsMouse || editingMe ? Theme.alpha(Theme.surface1, 0.5) : Theme.alpha(Theme.surface0, 0.55)
    border.width: 1
    border.color: t.level === "overdue" && !t.done ? Theme.alpha(Theme.red, 0.45)
                : editingMe ? Theme.alpha(Theme.accent, 0.6) : Theme.alpha(Theme.surface1, 0.4)
    Behavior on color { ColorAnimation { duration: Theme.fast } }
    Behavior on height { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    function startEdit() {
        pop.delArmed = "";
        pop.editing = k;
        editText.text = t.text;
        editDue.text = t.due && !t.every ? t.due : "";
        editText.input.forceActiveFocus();
    }
    function save() {
        const newText = editText.text.trim();
        const newDue = editDue.text.trim();
        const dueChanged = t.every ? newDue !== "" : newDue !== t.due;
        const doDue = () => { if (dueChanged) pop.op(["due", String(t.i), newText || t.text, newDue]); };
        pop.editing = "";
        if (newText && newText !== t.text) pop.op(["rename", String(t.i), t.text, newText], doDue);
        else doDue();
    }

    MouseArea {
        id: cardMa
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        onDoubleClicked: if (!card.editingMe) card.startEdit()
    }

    // tick
    Rectangle {
        id: tick
        visible: !card.editingMe
        x: 12
        anchors.verticalCenter: parent.verticalCenter
        width: 24
        height: 24
        radius: 12
        color: card.t.done ? Theme.green : tickMa.containsMouse ? Theme.alpha(Theme.green, 0.25) : "transparent"
        border.width: 2
        border.color: card.t.done ? Theme.green : tickMa.containsMouse ? Theme.green : Theme.overlay1
        Behavior on color { ColorAnimation { duration: Theme.fast } }
        Text {
            anchors.centerIn: parent
            visible: card.t.done || tickMa.containsMouse
            text: "\u{f012c}"
            color: card.t.done ? Theme.crust : Theme.green
            font.family: Theme.font
            font.pixelSize: 13
            font.weight: Font.Bold
        }
        MouseArea {
            id: tickMa
            anchors.fill: parent
            anchors.margins: -4
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: card.pop.op([card.t.done ? "undone" : "done", String(card.t.i), card.t.text])
        }
    }

    // text + meta
    Column {
        id: info
        visible: !card.editingMe
        anchors.left: tick.right
        anchors.leftMargin: 12
        anchors.right: btns.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3
        Row {
            width: parent.width
            spacing: 6
            Rectangle {
                id: prio
                visible: !card.t.done
                anchors.verticalCenter: parent.verticalCenter
                width: prioText.implicitWidth + 10
                height: 18
                radius: 5
                color: card.t.prio ? Theme.alpha(card.pop.prioColor(card.t.prio), 0.2)
                     : prioMa.containsMouse ? Theme.alpha(Theme.surface1, 0.8) : "transparent"
                Text {
                    id: prioText
                    anchors.centerIn: parent
                    text: card.t.prio ? "!".repeat(card.t.prio) : "!"
                    color: card.t.prio ? card.pop.prioColor(card.t.prio) : Theme.alpha(Theme.overlay1, prioMa.containsMouse ? 1 : 0.45)
                    font.family: Theme.font
                    font.pixelSize: 11
                    font.weight: Font.Black
                }
                MouseArea {
                    id: prioMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: card.pop.op(["prio", String(card.t.i), card.t.text, String((card.t.prio + 1) % 4)])
                }
                Tooltip { target: prio; text: "Priority — click to cycle"; shown: prioMa.containsMouse; edge: Edges.Top }
            }
            Text {
                width: parent.width - (prio.visible ? prio.width + 6 : 0)
                text: card.t.text || ""
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                color: card.t.done ? Theme.overlay1 : Theme.text
                font.strikeout: !!card.t.done
                font.family: Theme.font
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }
        }
        Text {
            width: parent.width
            visible: text !== ""
            elide: Text.ElideRight
            text: card.t.done ? "done at " + card.t.doneAt
                : [card.t.due ? "\u{f00f0}  " + card.t.label : "",
                   card.t.rule ? "\u{f0456} " + card.t.rule : "",
                   card.t.age > 0 ? "carried " + card.t.age + "d" : ""].filter(s => s).join("   ")
            color: card.t.done ? Theme.overlay0 : card.pop.levelColor(card.t)
            font.family: Theme.font
            font.pixelSize: 11
        }
    }

    // hover buttons
    Row {
        id: btns
        visible: !card.editingMe
        anchors.right: parent.right
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4
        opacity: cardMa.containsMouse || card.pop.delArmed === card.k ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.fast } }
        IconBtn {
            visible: !!card.up
            size: 26
            iconSize: 13
            icon: "\u{f0143}"
            tip: "Move up"
            tipEdge: Edges.Top
            onClicked: card.pop.op(["move", String(card.t.i), card.t.text, String(card.up.i), card.up.text])
        }
        IconBtn {
            visible: !!card.down
            size: 26
            iconSize: 13
            icon: "\u{f0140}"
            tip: "Move down"
            tipEdge: Edges.Top
            onClicked: card.pop.op(["move", String(card.t.i), card.t.text, String(card.down.i), card.down.text])
        }
        IconBtn {
            size: 26
            iconSize: 13
            icon: "\u{f03eb}"
            tip: card.t.done ? "Edit text (or double-click)" : "Edit text / deadline (or double-click)"
            tipEdge: Edges.Top
            onClicked: card.startEdit()
        }
        IconBtn {
            readonly property bool armed: card.pop.delArmed === card.k
            size: 26
            iconSize: 13
            icon: "\u{f0a7a}"
            text: armed ? "Delete?" : ""
            fg: Theme.red
            active: armed
            activeFg: Theme.red
            tip: armed ? "Click again to delete (Undo brings it back)" : "Delete"
            tipEdge: Edges.Top
            onClicked: {
                if (!armed) { card.pop.armDelete(card.k); return; }
                card.pop.delArmed = "";
                card.pop.op(["delete", String(card.t.i), card.t.text]);
            }
        }
    }

    // inline editor
    Column {
        id: editCol
        visible: card.editingMe
        x: 12
        y: 11
        width: parent.width - 24
        spacing: 8
        SettingsField {
            id: editText
            width: parent.width
            placeholder: "Task text (! / !! / !!! and @when work here too)"
            onAccepted: card.save()
            onEscaped: card.pop.editing = ""
        }
        Row {
            visible: !card.t.done
            width: parent.width
            spacing: 8
            SettingsField {
                id: editDue
                width: parent.width
                placeholder: card.t.every ? "repeats " + card.t.rule + " — type to change (@every …)"
                                          : "deadline: fri 5pm · tomorrow · 20/10 · every mon · empty = none"
                onAccepted: card.save()
                onEscaped: card.pop.editing = ""
            }
        }
        Flow {
            visible: !card.t.done
            width: parent.width
            spacing: 6
            Repeater {
                model: [["today", "Today"], ["tomorrow", "Tomorrow"], ["mon", "Monday"], ["+1w", "In a week"], ["", "No deadline"]]
                delegate: IconBtn {
                    required property var modelData
                    size: 24
                    text: modelData[1]
                    onClicked: editDue.text = modelData[0]
                }
            }
        }
        Row {
            spacing: 8
            IconBtn {
                size: 32
                icon: "\u{f012c}"
                text: "Save"
                active: true
                onClicked: card.save()
            }
            IconBtn {
                size: 32
                icon: "\u{f0156}"
                text: "Cancel"
                onClicked: card.pop.editing = ""
            }
        }
    }
    FocusRing {}
}
