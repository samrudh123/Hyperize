// Quickshell entry point — the whole desktop shell: top bar, bottom bar and
// sidebar dock. Replaces waybar (both instances) and nwg-dock-hyprland.
//
//   start:    exec-once in hyprland.conf (~/.local/bin/qs)
//   restart:  ~/.config/hypr/reload.sh bar
//   IPC:      qs ipc show            (dock / bottombar: toggle, open, close;
//                                     osd: opacity — from opacity.sh;
//                                     wspicker: toggle — SUPER+Tab;
//                                     wallpicker: toggle desktop|lock — SUPER+W;
//                                     themepicker: toggle — SUPER+SHIFT+T;
//                                     clipboard: toggle — the clipboard pill)
//   logs:     qs log
//
// Saving any file here hot-reloads the shell.
import Quickshell

ShellRoot {
    TopBar {}
    BottomBar {}
    Dock {}
    OpacityOsd {}
    WallpaperTransition {}
    WorkspacePicker {}
    WallpaperPicker {}
    ThemePicker {}
}
