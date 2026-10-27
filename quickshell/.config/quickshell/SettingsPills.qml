// Settings › Pills: what a left / right / middle click — and the scroll
// wheel — does on each bar pill.
// Every clickable pill on both bars is a card with four rows of choices
// (PillClicks.qml's catalog: what that pill can do, "Nothing" included);
// the current choice is filled, a pick applies at once (pill-clicks.json,
// watched by the bars), and the pills' tooltips follow. Reset per pill, or
// Reset all. Search filters by pill, button or action.
import QtQuick
import Quickshell

SettingsPage {
    id: page
    title: "Pills"
    subtitle: "What a click, right-click, middle-click and scrolling do on each pill of the bars. Changes apply at once; the pills' tooltips follow."

    readonly property string q: SettingsState.query.trim().toLowerCase()
    readonly property int changedCount: PillClicks.catalog.filter(p => PillClicks.changed(p.id)).length
    function pillMatches(p) {
        if (!q) return true;
        const hay = (p.name + " " + p.id + " " + (p.bar === "top" ? "top bar" : "bottom bar") + " "
                     + p.actions.map(a => a[1]).join(" ") + " " + PillClicks.scrollActions(p.id).map(a => a[1]).join(" ")
                     + " click right-click middle-click left right middle scroll wheel mouse button pill").toLowerCase();
        return hay.includes(q);
    }

    // toolbar
    Item {
        width: parent.width
        height: 34
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: PillClicks.catalog.length + " pills" + (page.changedCount ? "  ·  " + page.changedCount + " changed" : "  ·  all as shipped")
            color: Theme.overlay1
            font.family: Theme.font
            font.pixelSize: 12
        }
        IconBtn {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: page.changedCount > 0
            icon: "\u{f0450}"
            text: "Reset all"
            fg: Theme.peach
            tip: "Every pill back to its original clicks"
            onClicked: PillClicks.resetAll()
        }
    }

    Repeater {
        model: [["top", "Top bar", "\u{f1513}"], ["bottom", "Bottom bar", "\u{f10a9}"]]
        delegate: Column {
            id: section
            required property var modelData
            readonly property var pills: PillClicks.catalog.filter(p => p.bar === modelData[0] && page.pillMatches(p))
            visible: pills.length > 0
            width: page.column.width
            spacing: 14

            Text {
                topPadding: 6
                text: section.modelData[2] + "  " + section.modelData[1].toUpperCase()
                color: Theme.accent
                font.family: Theme.font
                font.pixelSize: 12
                font.weight: Font.Bold
                font.letterSpacing: 1.2
            }

            Repeater {
                model: section.pills
                delegate: SettingsCard {
                    id: pcard
                    required property var modelData
                    readonly property var p: modelData
                    readonly property bool isChanged: PillClicks.changed(p.id)
                    width: section.width
                    title: p.name
                    icon: p.icon

                    // a Scroll row only where scrolling can do something that fits
                    readonly property var pillRows: PillClicks.keys.filter(k => k !== "scroll" || PillClicks.hasScroll(p.id))
                    Repeater {
                        model: pcard.pillRows
                        delegate: Item {
                            id: brow
                            required property string modelData
                            required property int index
                            readonly property string btn: modelData
                            readonly property bool isScroll: btn === "scroll"
                            readonly property string cur: isScroll ? PillClicks.scrollAction(pcard.p.id) : PillClicks.action(pcard.p.id, btn)
                            readonly property string def: PillClicks.defaultOf(pcard.p.id, btn)
                            readonly property bool isDefault: cur === def
                            width: parent ? parent.width : 400
                            height: Math.max(54, chips.implicitHeight + 24)

                            Column {
                                id: lbl
                                x: 18
                                width: 132
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2
                                Text {
                                    text: ({ left: "Left click", right: "Right click", middle: "Middle click", scroll: "Scroll" })[brow.btn]
                                    color: Theme.text
                                    font.family: Theme.font
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                }
                                Text {
                                    text: brow.isDefault ? "as shipped" : "was: " + PillClicks.label(pcard.p.id, brow.def, brow.btn)
                                    color: brow.isDefault ? Theme.overlay0 : Theme.peach
                                    elide: Text.ElideRight
                                    width: parent.width
                                    font.family: Theme.font
                                    font.pixelSize: 10
                                }
                            }
                            Flow {
                                id: chips
                                anchors.left: lbl.right
                                anchors.leftMargin: 10
                                anchors.right: parent.right
                                anchors.rightMargin: 16
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 6
                                Repeater {
                                    model: brow.isScroll ? PillClicks.scrollActions(pcard.p.id) : pcard.p.actions
                                    delegate: IconBtn {
                                        required property var modelData
                                        size: 28
                                        text: modelData[1]
                                        active: brow.cur === modelData[0]
                                        fg: modelData[0] === "none" ? Theme.overlay1 : Theme.subtext0
                                        onClicked: PillClicks.set(pcard.p.id, brow.btn, modelData[0])
                                    }
                                }
                            }
                            Rectangle {
                                visible: brow.index < pcard.pillRows.length - 1 || pcard.isChanged
                                anchors.bottom: parent.bottom
                                x: 16
                                width: parent.width - 32
                                height: 1
                                color: Theme.alpha(Theme.surface1, 0.5)
                            }
                        }
                    }
                    Item {
                        visible: pcard.isChanged
                        width: parent ? parent.width : 400
                        height: 46
                        Text {
                            x: 18
                            anchors.verticalCenter: parent.verticalCenter
                            text: PillClicks.hint(pcard.p.id) || "Does nothing on any button"
                            color: Theme.overlay1
                            elide: Text.ElideRight
                            width: parent.width - resetBtn.width - 50
                            font.family: Theme.font
                            font.pixelSize: 11
                        }
                        IconBtn {
                            id: resetBtn
                            anchors.right: parent.right
                            anchors.rightMargin: 16
                            anchors.verticalCenter: parent.verticalCenter
                            size: 28
                            icon: "\u{f0450}"
                            text: "Reset"
                            fg: Theme.peach
                            tip: "Back to: " + pcard.pillRows.map(b => PillClicks.buttonNames[b] + " " + PillClicks.label(pcard.p.id, PillClicks.defaultOf(pcard.p.id, b), b)).join(" · ")
                            onClicked: PillClicks.reset(pcard.p.id)
                        }
                    }
                }
            }
        }
    }

    Text {
        visible: PillClicks.catalog.every(p => !page.pillMatches(p))
        topPadding: 30
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        text: "No pills match “" + SettingsState.query + "”"
        color: Theme.overlay0
        font.family: Theme.font
        font.pixelSize: 13
    }
}
