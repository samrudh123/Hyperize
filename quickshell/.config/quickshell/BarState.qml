// What the per-screen bars share. shell.qml makes one top bar and one bottom
// bar for every screen (a duplicated screen isn't one: Hyprland withdraws
// its output while it mirrors).
//
//   primary  the laptop panel (else the first screen): side effects that
//            must happen once (the focus timer's phase change) run there
//   active   the focused monitor's screen (else the primary): its bars own
//            the IPC targets, so `qs ipc call …` opens menus where you are
//
// The bottom bar's shown state and keep-awake live here so every screen
// follows one switch; both survive config reloads.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland

Singleton {
    readonly property string primary: {
        const s = Quickshell.screens;
        const main = s.find(x => /^(eDP|LVDS|DSI)/.test(x.name)) || s[0];
        return main ? main.name : "";
    }
    readonly property string active: {
        const f = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        return Quickshell.screens.some(x => x.name === f) ? f : primary;
    }

    property alias bottomShown: state.bottomShown
    property alias keepAwake: state.keepAwake
    PersistentProperties {
        id: state
        reloadableId: "barState"
        property bool bottomShown: true
        property bool keepAwake: false
    }
}
