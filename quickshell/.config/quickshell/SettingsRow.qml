// One setting: icon · title / subtitle · the control on the right (children).
// Matches the panel's search (`query`, inherited from SettingsPanel through
// the page) on title, subtitle and `keywords`; non-matching rows hide.
//
//     SettingsRow { icon: "\u{f06e8}"; title: "Brightness"; Slider { … } }
import QtQuick

Item {
    id: row

    property string icon
    property color iconColor: Theme.accent
    property string title
    property string subtitle
    property string keywords
    property string query: SettingsState.query
    property bool last: false
    property bool hoverable: false
    default property alias control: right.data
    readonly property alias controlArea: right
    signal clicked()

    readonly property bool matches: {
        const q = query.trim().toLowerCase();
        return !q || (title + " " + subtitle + " " + keywords).toLowerCase().includes(q);
    }
    visible: matches
    width: parent ? parent.width : 400
    height: Math.max(58, texts.implicitHeight + 24)

    Rectangle {
        anchors.fill: parent
        anchors.margins: 3
        radius: 11
        color: row.hoverable && ma.containsMouse ? Theme.alpha(Theme.surface1, 0.45) : "transparent"
        Behavior on color { ColorAnimation { duration: Theme.fast } }
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        enabled: row.hoverable
        hoverEnabled: true
        cursorShape: row.hoverable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: row.clicked()
    }

    Rectangle {
        id: iconBox
        visible: row.icon !== ""
        x: 14
        anchors.verticalCenter: parent.verticalCenter
        width: 34
        height: 34
        radius: 10
        color: Theme.alpha(row.iconColor, 0.14)
        Text {
            anchors.centerIn: parent
            text: row.icon
            color: row.iconColor
            font.family: Theme.font
            font.pixelSize: 17
        }
    }

    Column {
        id: texts
        anchors.left: iconBox.visible ? iconBox.right : parent.left
        anchors.leftMargin: iconBox.visible ? 14 : 18
        anchors.right: right.left
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        spacing: 3
        Text {
            width: parent.width
            text: row.title
            color: Theme.text
            elide: Text.ElideRight
            font.family: Theme.font
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }
        Text {
            visible: text !== ""
            width: parent.width
            text: row.subtitle
            color: Theme.overlay1
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
            textFormat: Text.StyledText
            font.family: Theme.font
            font.pixelSize: 11
        }
    }

    Row {
        id: right
        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        layoutDirection: Qt.LeftToRight
    }

    Rectangle {
        visible: !row.last
        anchors.bottom: parent.bottom
        x: 16
        width: parent.width - 32
        height: 1
        color: Theme.alpha(Theme.surface1, 0.45)
    }
}
