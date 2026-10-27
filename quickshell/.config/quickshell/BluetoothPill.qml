// Bluetooth in the top bar: off / on / connected (the first connected
// device's name, and its battery when it reports one). Clicks are handled
// by the bar (TopBar.qml: click opens the Bluetooth panel).
import QtQuick
import Quickshell.Bluetooth

Pill {
    id: bt

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool on: !!adapter && adapter.enabled
    readonly property var connected: (Bluetooth.devices ? Bluetooth.devices.values : []).filter(d => d.connected)
    readonly property var first: connected.length ? connected[0] : null

    shown: !!adapter
    label: !on ? "\u{f00b2}"
         : first ? "\u{f00b1} " + (first.name.length > 12 ? first.name.slice(0, 11) + "…" : first.name)
                   + (first.batteryAvailable ? " " + Math.round(first.battery * 100) + "%" : "")
         : "\u{f00af}"
    fg: !on ? Theme.overlay0 : first ? Theme.sapphire : Theme.blue
    fillHover: true
    tip: (!on ? "Bluetooth off"
          : connected.length ? connected.map(d => d.name + (d.batteryAvailable ? "  ·  " + Math.round(d.battery * 100) + "%" : "")).join("<br>")
          : "Bluetooth on  ·  nothing connected")
         + PillClicks.hintLine("bluetooth")
}
