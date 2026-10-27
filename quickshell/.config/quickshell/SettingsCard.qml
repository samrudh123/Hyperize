// A group of settings rows on a rounded surface, with an optional heading
// above it. Rows are separated by hairlines. Hidden when every row is
// filtered out by the search.
import QtQuick

Column {
    id: card

    property string title
    property string icon
    default property alias rows: body.data
    spacing: 8
    width: parent ? parent.width : 400
    visible: {
        for (const c of body.children) if (c.visible) return true;
        return false;
    }

    Row {
        visible: card.title !== ""
        spacing: 8
        leftPadding: 4
        Text {
            visible: card.icon !== ""
            text: card.icon
            color: Theme.accent
            font.family: Theme.font
            font.pixelSize: 14
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            text: card.title
            color: Theme.subtext0
            font.family: Theme.font
            font.pixelSize: 12
            font.weight: Font.Bold
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 1
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    Rectangle {
        width: parent.width
        height: body.height
        radius: 14
        color: Theme.alpha(Theme.surface0, 0.45)
        border.width: 1
        border.color: Theme.alpha(Theme.surface1, 0.5)

        Column {
            id: body
            width: parent.width
        }
    }
}
