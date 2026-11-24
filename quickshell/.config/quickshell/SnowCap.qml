// Snow lying on a ledge (shaders/snowcap.frag) — the winter theme's caps on
// windows (WinterOverlay), bar popups (PanelPopup) and the bottom bar's
// islands. Place it with its BOTTOM on the ledge: the item is `maxDepth`
// + `base` tall and the pile rises `depth` px above the ledge. `base` px
// of it hang below the ledge, over the border it lies on.
import QtQuick

ShaderEffect {
    id: cap

    property real depth: 0                    // px of snow
    property real maxDepth: 10
    property real base: 2
    property real gx: 0                       // x in the ledge (lumps line up across segments)
    property real seed: 0
    property real taperL: 12
    property real taperR: 12

    // white snow with a cool shade; on light paper an outline so it reads
    readonly property color snowColor: Theme.light ? "#ffffff" : "#f4f8ff"
    readonly property color shadeColor: Theme.light ? "#c9d6ea" : Qt.rgba(0.70, 0.78, 0.92, 1)
    readonly property color rimColor: Theme.light ? Theme.alpha(Theme.overlay1, 0.55) : Qt.rgba(1, 1, 1, 0)

    height: Math.ceil(maxDepth * 1.25) + base + 2
    visible: depth > 0.3
    blending: true
    fragmentShader: Qt.resolvedUrl("shaders/snowcap.frag.qsb")
    property size itemSize: Qt.size(width, height)
}
