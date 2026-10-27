// One settings tab's content: a big title + subtitle, then the cards,
// scrolling when they don't fit. Children go in the column.
//
//     SettingsPage { title: "Display"; subtitle: "…"; SettingsCard { … } }
import QtQuick

Flickable {
    id: page

    property string title
    property string subtitle
    property string query
    default property alias content: col.data
    readonly property alias column: col

    contentWidth: width
    contentHeight: col.y + col.height + 24
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    flickDeceleration: 4000
    maximumFlickVelocity: 3000

    // Faster wheel scrolling than Flickable's own (which crawled): a mouse
    // notch glides `wheelStep` px, a touchpad moves `touchpadGain` × its
    // distance. Sliders etc. inside still get the wheel first.
    property real wheelStep: 170
    property real touchpadGain: 2.2
    property real targetY: 0
    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: ev => {
            const max = Math.max(0, page.contentHeight - page.height);
            const touchpad = ev.pixelDelta.y !== 0;
            const dy = touchpad ? -ev.pixelDelta.y * page.touchpadGain : -ev.angleDelta.y / 120 * page.wheelStep;
            const from = glide.running ? page.targetY : page.contentY;
            page.targetY = Math.max(0, Math.min(max, from + dy));
            if (touchpad) { glide.stop(); page.contentY = page.targetY; }
            else { glide.to = page.targetY; glide.restart(); }
        }
    }
    NumberAnimation { id: glide; target: page; property: "contentY"; duration: 200; easing.type: Easing.OutCubic }

    Column {
        id: head
        x: 28
        y: 24
        width: page.width - 56
        spacing: 4
        Text {
            text: page.title
            color: Theme.text
            font.family: Theme.font
            font.pixelSize: 22
            font.weight: Font.Bold
        }
        Text {
            visible: text !== ""
            width: parent.width
            text: page.subtitle
            color: Theme.overlay1
            wrapMode: Text.Wrap
            font.family: Theme.font
            font.pixelSize: 12
        }
    }

    Column {
        id: col
        x: 28
        y: head.y + head.height + 18
        width: page.width - 56
        spacing: 14
    }

    // thin scroll indicator
    Rectangle {
        visible: page.contentHeight > page.height
        x: page.width - 7
        y: page.contentY + (page.height - height) * (page.contentY / Math.max(1, page.contentHeight - page.height))
        width: 3
        height: Math.max(30, page.height * page.height / page.contentHeight)
        radius: 2
        color: Theme.alpha(Theme.overlay0, page.moving ? 0.8 : 0.35)
        Behavior on color { ColorAnimation { duration: 200 } }
    }
}
