// Quickshell entry point — the whole desktop shell: top bar and bottom bar
// (on every screen) and sidebar dock. Replaces waybar (both instances) and
// nwg-dock-hyprland.
//
//   start:    exec-once in hyprland.conf (~/.local/bin/qs)
//   restart:  ~/.config/hypr/reload.sh bar
//   IPC:      qs ipc show            (dock / bottombar: toggle, open, close;
//                                     osd: opacity — from opacity.sh;
//                                     wspicker: toggle — SUPER+Tab;
//                                     wallpicker: toggle desktop|lock — SUPER+W;
//                                     themepicker: toggle — SUPER+SHIFT+T;
//                                     clipboard: toggle — the clipboard pill;
//                                     display: toggle, menu, set mirror|extend|DIR)
//   logs:     qs log
//
// Saving any file here hot-reloads the shell.
import Quickshell

ShellRoot {
    // both bars on every screen (BarState.qml: what they share)
    Variants {
        model: Quickshell.screens
        TopBar {
            required property var modelData
            screen: modelData
        }
    }
    Variants {
        model: Quickshell.screens
        BottomBar {
            required property var modelData
            screen: modelData
        }
    }
    Dock {}
    OpacityOsd {}
    WallpaperTransition {}
    WorkspacePicker {}
    WallpaperPicker {}
    ThemePicker {}
}
