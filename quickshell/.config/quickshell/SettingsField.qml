// A one-line text field for the settings panel: dim box, accent border while
// focused, placeholder. Esc in it emits `escaped` (and doesn't close the
// panel); Enter emits `accepted`.
//
//     SettingsField { placeholder: "Name"; text: x; onEdited: t => x = t }
import QtQuick

Rectangle {
    id: f

    property alias text: input.text
    property string placeholder
    property bool mono: false
    readonly property alias input: input

    signal edited(string text)
    signal accepted()
    signal escaped()

    implicitWidth: 240
    implicitHeight: 34
    radius: 9
    color: Theme.alpha(Theme.surface0, 0.8)
    border.width: 1
    border.color: input.activeFocus ? Theme.alpha(Theme.accent, 0.8) : Theme.alpha(Theme.surface1, 0.8)
    Behavior on border.color { ColorAnimation { duration: Theme.fast } }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.IBeamCursor
        onClicked: input.forceActiveFocus()
    }

    TextInput {
        id: input
        anchors { left: parent.left; right: parent.right; leftMargin: 11; rightMargin: 11; verticalCenter: parent.verticalCenter }
        color: Theme.text
        selectionColor: Theme.alpha(Theme.accent, 0.4)
        selectByMouse: true
        activeFocusOnTab: f.visible
        clip: true
        font.family: Theme.font
        font.pixelSize: 12
        onTextEdited: f.edited(text)
        // see BarState.typing: in a bar popup the keys arrive at a bar
        onFocusChanged: if (focus) BarState.typing = input
        cursorVisible: activeFocus || (focus && BarState.typing === input)
        Keys.onEscapePressed: ev => { ev.accepted = true; focus = false; f.escaped(); }
        Keys.onReturnPressed: f.accepted()
        Keys.onEnterPressed: f.accepted()

        Text {
            visible: !input.text
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            elide: Text.ElideRight
            text: f.placeholder
            color: Theme.overlay0
            font: input.font
        }
    }
}
