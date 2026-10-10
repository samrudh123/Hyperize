// A miniature desktop drawn in one theme's palette — the theme picker's card.
// `p` is a palette from rice-theme.py (role -> "#hex", plus id/name/accent).
import QtQuick

Item {
    id: root
    property var p: ({})
    property string accentRole: "blue"
    // the card is a parallelogram over this item: the top edge shows x from
    // `slant` to the right edge, the bottom edge from 0 to width - slant —
    // the layout keeps clear of the two cut-off corners
    property real slant: height * 0.30
    readonly property color accent: p[accentRole] || p.blue || "#89b4fa"
    readonly property real s: height / 408            // designed at 408 px tall

    function c(role) { return p[role] || "#000000"; }

    clip: true

    // desktop: a soft gradient with an accent glow
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: root.c("crust") }
            GradientStop { position: 1; color: root.c("base") }
        }
    }
    Rectangle {
        width: root.width * 0.9
        height: width
        radius: width / 2
        x: root.width * 0.45
        y: root.height * 0.25
        color: root.accent
        opacity: 0.16
    }
    Rectangle {
        width: root.width * 0.6
        height: width
        radius: width / 2
        x: -root.width * 0.2
        y: -root.height * 0.6
        color: root.c("mauve")
        opacity: 0.10
    }

    // top bar
    Rectangle {
        x: root.slant * 0.95 + 8 * root.s; y: 10 * root.s
        width: root.width - root.slant * 0.95 - 22 * root.s
        height: 24 * root.s
        radius: 8 * root.s
        color: root.c("mantle")
        opacity: 0.95
        Row {
            x: 10 * root.s
            anchors.verticalCenter: parent.verticalCenter
            spacing: 5 * root.s
            Repeater {
                model: 5
                Rectangle {
                    required property int index
                    width: (index === 1 ? 22 : 10) * root.s
                    height: 10 * root.s
                    radius: 5 * root.s
                    color: index === 1 ? root.accent : root.c("surface1")
                }
            }
        }
        Text {
            anchors.centerIn: parent
            text: "21:40"
            color: root.c("text")
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 12 * root.s
            font.bold: true
        }
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 10 * root.s
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6 * root.s
            Repeater {
                model: ["yellow", "blue", "green", "peach", "red"]
                Rectangle {
                    required property string modelData
                    width: 9 * root.s; height: 9 * root.s; radius: 4.5 * root.s
                    color: root.c(modelData)
                }
            }
        }
    }

    // terminal: highlighted code
    Rectangle {
        id: term
        x: root.width * 0.17
        y: 46 * root.s
        width: root.width * 0.38
        height: root.height - 92 * root.s
        radius: 10 * root.s
        color: root.c("base")
        border.width: 2 * root.s
        border.color: root.accent
        Row {
            x: 10 * root.s; y: 9 * root.s
            spacing: 5 * root.s
            Repeater {
                model: ["red", "yellow", "green"]
                Rectangle {
                    required property string modelData
                    width: 8 * root.s; height: 8 * root.s; radius: 4 * root.s
                    color: root.c(modelData)
                }
            }
        }
        Column {
            x: 12 * root.s; y: 28 * root.s
            spacing: 7 * root.s
            Repeater {
                // each line: [role, width] pieces — a little syntax highlighting
                model: [
                    [["mauve", 30], ["blue", 46], ["overlay2", 8], ["peach", 20]],
                    [["overlay0", 90]],
                    [["mauve", 24], ["text", 30], ["sky", 10], ["green", 56]],
                    [["text", 18], ["blue", 40], ["overlay2", 6], ["yellow", 26], ["overlay2", 6]],
                    [["red", 34], ["text", 52]],
                    [["mauve", 28], ["teal", 36], ["peach", 18]],
                    [["overlay0", 70]],
                    [["green", 22], ["text", 40], ["pink", 30]],
                    [["blue", 52], ["overlay2", 6], ["lavender", 34]],
                    [["yellow", 28], ["text", 60]]
                ]
                Row {
                    required property var modelData
                    spacing: 5 * root.s
                    Repeater {
                        model: parent.modelData
                        Rectangle {
                            required property var modelData
                            width: modelData[1] * root.s
                            height: 6 * root.s
                            radius: 3 * root.s
                            color: root.c(modelData[0])
                        }
                    }
                }
            }
        }
        // prompt
        Row {
            x: 12 * root.s
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 12 * root.s
            spacing: 4 * root.s
            Rectangle { width: 40 * root.s; height: 12 * root.s; radius: 3 * root.s; color: root.c("peach") }
            Rectangle { width: 26 * root.s; height: 12 * root.s; radius: 3 * root.s; color: root.c("sky") }
            Rectangle { width: 6 * root.s; height: 12 * root.s; color: root.c("rosewater") }
        }
    }

    // a window: sidebar + cards
    Rectangle {
        x: term.x + term.width + 12 * root.s
        y: 46 * root.s
        width: root.width * 0.27
        height: root.height * 0.50
        radius: 10 * root.s
        color: root.c("mantle")
        border.width: 1.5 * root.s
        border.color: root.c("surface1")
        Rectangle {
            x: 8 * root.s; y: 8 * root.s
            width: parent.width * 0.28
            height: parent.height - 16 * root.s
            radius: 6 * root.s
            color: root.c("surface0")
            Column {
                x: 8 * root.s; y: 10 * root.s
                spacing: 8 * root.s
                Repeater {
                    model: 5
                    Rectangle {
                        required property int index
                        width: (index === 0 ? 40 : 30) * root.s
                        height: 6 * root.s
                        radius: 3 * root.s
                        color: index === 0 ? root.accent : root.c("overlay1")
                    }
                }
            }
        }
        Grid {
            x: parent.width * 0.28 + 16 * root.s
            y: 10 * root.s
            columns: 2
            spacing: 8 * root.s
            Repeater {
                model: ["blue", "green", "peach", "mauve"]
                Rectangle {
                    required property string modelData
                    width: 54 * root.s
                    height: 40 * root.s
                    radius: 6 * root.s
                    color: root.c("surface0")
                    Rectangle {
                        x: 6 * root.s; y: 6 * root.s
                        width: 16 * root.s; height: 16 * root.s; radius: 4 * root.s
                        color: root.c(parent.modelData)
                    }
                    Rectangle {
                        x: 6 * root.s; y: 28 * root.s
                        width: 36 * root.s; height: 5 * root.s; radius: 2.5 * root.s
                        color: root.c("subtext0")
                    }
                }
            }
        }
    }

    // the 14 accents
    Rectangle {
        x: term.x + term.width + 12 * root.s
        y: root.height * 0.50 + 58 * root.s
        width: root.width * 0.27
        height: 54 * root.s
        radius: 10 * root.s
        color: root.c("crust")
        opacity: 0.95
        Grid {
            anchors.centerIn: parent
            columns: 7
            spacing: 6 * root.s
            Repeater {
                model: ["rosewater", "flamingo", "pink", "mauve", "red", "maroon", "peach",
                        "yellow", "green", "teal", "sky", "sapphire", "blue", "lavender"]
                Rectangle {
                    required property string modelData
                    width: 13 * root.s; height: 13 * root.s; radius: 6.5 * root.s
                    color: root.c(modelData)
                    border.width: modelData === root.accentRole ? 2 * root.s : 0
                    border.color: root.c("text")
                }
            }
        }
    }

    // notification toast
    Rectangle {
        x: term.x + term.width + 12 * root.s
        y: root.height - 46 * root.s - 34 * root.s + 14 * root.s
        width: root.width * 0.27
        height: 34 * root.s
        radius: 8 * root.s
        color: root.c("base")
        border.width: 1.5 * root.s
        border.color: root.accent
        Rectangle {
            x: 8 * root.s; anchors.verticalCenter: parent.verticalCenter
            width: 18 * root.s; height: 18 * root.s; radius: 9 * root.s
            color: root.accent
        }
        Column {
            x: 34 * root.s; anchors.verticalCenter: parent.verticalCenter
            spacing: 4 * root.s
            Rectangle { width: 70 * root.s; height: 5 * root.s; radius: 2.5 * root.s; color: root.c("text") }
            Rectangle { width: 110 * root.s; height: 5 * root.s; radius: 2.5 * root.s; color: root.c("subtext0") }
        }
    }
}
