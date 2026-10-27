// Catppuccin Mocha + the live accent, and the few helpers every module uses.
//
// The accent is read from ~/.config/hypr/theme/accent and followed live, so
// set-accent.sh (SUPER+ALT+C) recolours the whole shell without a template.
// Where waybar's CSS said `@mauve` it meant the accent (set-accent.sh rewrote
// that define); here that is `accent`. Real Mocha mauve is `mauve`.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string hypr: home + "/.config/hypr"

    // The palette: theme/palette.json (set-theme.sh, SUPER+SHIFT+T), watched, so a
    // theme switch recolours the shell live. Defaults are Catppuccin Mocha.
    readonly property var pal: {
        try { return JSON.parse(paletteFile.text() || "{}"); } catch (e) { return {}; }
    }
    readonly property string themeId: pal.id || "mocha"
    readonly property string themeName: pal.name || "Catppuccin Mocha"
    function role(name, dflt) { return pal[name] || dflt; }

    readonly property color base: role("base", "#1e1e2e")
    readonly property color mantle: role("mantle", "#181825")
    readonly property color crust: role("crust", "#11111b")
    readonly property color surface0: role("surface0", "#313244")
    readonly property color surface1: role("surface1", "#45475a")
    readonly property color surface2: role("surface2", "#585b70")
    readonly property color overlay0: role("overlay0", "#6c7086")
    readonly property color overlay2: role("overlay2", "#9399b2")
    readonly property color overlay1: role("overlay1", "#7f849c")
    readonly property color subtext0: role("subtext0", "#a6adc8")
    readonly property color subtext1: role("subtext1", "#bac2de")
    readonly property color text: role("text", "#cdd6f4")
    readonly property color rosewater: role("rosewater", "#f5e0dc")
    readonly property color flamingo: role("flamingo", "#f2cdcd")
    readonly property color pink: role("pink", "#f5c2e7")
    readonly property color mauve: role("mauve", "#cba6f7")
    readonly property color red: role("red", "#f38ba8")
    readonly property color maroon: role("maroon", "#eba0ac")
    readonly property color peach: role("peach", "#fab387")
    readonly property color yellow: role("yellow", "#f9e2af")
    readonly property color green: role("green", "#a6e3a1")
    readonly property color teal: role("teal", "#94e2d5")
    readonly property color sky: role("sky", "#89dceb")
    readonly property color sapphire: role("sapphire", "#74c7ec")
    readonly property color blue: role("blue", "#89b4fa")
    readonly property color lavender: role("lavender", "#b4befe")
    // YouTube apps: dimmed red on purpose — Mocha red reads as the YT Music
    // pink, brighter reds were too loud (user's choice, see bottom.css).
    readonly property color youtube: "#bf616a"

    readonly property color accent: {
        const hex = accentFile.text().trim();
        return /^[0-9a-fA-F]{6}$/.test(hex) ? "#" + hex : blue;
    }

    // The default MICROPHONE — never a sink. With Bluetooth headphones on
    // A2DP (no usable headset mic) WirePlumber can name the HEADPHONES' sink
    // as default.audio.source (its monitor); muting "the mic" then muted the
    // headphones. Fall back to no source rather than that.
    function micSource(d) { return d && !d.isSink ? d : null; }

    // How solid the big panels are (Settings, and the audio / network /
    // notification / music popups): theme/panel-opacity, a percent written by
    // Settings › Appearance › Transparency, watched like the accent. Hyprland
    // blurs what shows through (layerrules qs-settings / qs-bar popups).
    readonly property real panelOpacity: {
        const n = parseInt(panelOpacityFile.text().trim());
        return isNaN(n) ? 1 : Math.max(0.35, Math.min(1, n / 100));
    }
    function setPanelOpacity(pct) {
        panelOpacityFile.setText(Math.round(Math.max(35, Math.min(100, pct))) + "\n");
    }
    // a panel surface at that opacity (k scales it for layered surfaces)
    function panel(c, k) {
        return alpha(c, Math.min(1, panelOpacity * (k === undefined ? 1 : k)));
    }

    // AdwaitaMono Nerd Font (Iosevka-based) — Serpantinum's face, used for
    // everything; build/fonts.sh installs it. Was JetBrainsMono + IBM Plex Sans.
    // Switchable in Settings › Appearance › Font (hypr/set-font.py writes
    // theme/font-shell; followed live like the accent).
    readonly property string font: (fontShellFile.text() || "").trim() || "AdwaitaMono Nerd Font"
    readonly property string uiFont: font

    // Shared motion: one easing for every hover / state change.
    readonly property int fast: 160
    readonly property int normal: 220

    function alpha(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    // Run a command the way waybar's on-click did, but through Hyprland so it
    // lands in the session scope, not as a child of quickshell (landmine 12).
    function exec(cmd) {
        Hyprland.dispatch("exec " + cmd);
    }

    // Script text and tooltips are Pango markup (waybar). Text.StyledText
    // knows <b>/<i> and <font>, not <span>/<tt>, wants <br> for line breaks,
    // and collapses runs of spaces — the scripts align with them ("󰄱  4",
    // the tasks tooltip's indents), so those become non-breaking spaces.
    function pango(s) {
        if (!s) return "";
        return s.replace(/ {2,}/g, m => "&nbsp;".repeat(m.length))
                .replace(/<span[^>]*(?:color|foreground)='([^']+)'[^>]*>/g, "<font color='$1'>")
                .replace(/<span[^>]*(?:color|foreground)="([^"]+)"[^>]*>/g, "<font color=\"$1\">")
                .replace(/<\/span>/g, "</font>")
                .replace(/<\/?tt>/g, "")
                .replace(/\n/g, "<br>");
    }

    // Natural scrolling is touchpad-only here (Hyprland natural_scroll), and
    // waybar's "reverse-scrolling" undid it so a swipe up = up, like the wheel.
    // Hyprland does not send wl_pointer.axis_relative_direction, so Qt never
    // sets `inverted`: the touchpad has to be recognised instead. Qt gives a
    // mouse wheel no pixelDelta and no scroll phase, and a touchpad (axis
    // source "finger") both — see qwaylandinputdevice.cpp, hasPixelDelta().
    // Returns the vertical delta (120 = one wheel notch, up positive).
    function wheelDelta(wheel) {
        const touchpad = wheel.pixelDelta.y !== 0 || wheel.phase !== Qt.NoScrollPhase;
        return wheel.inverted || touchpad ? -wheel.angleDelta.y : wheel.angleDelta.y;
    }

    // Bar style: "classic" (edge-to-edge panels) or "islands" (floating
    // rounded groups) — theme/bar-style, toggled with `b` in the theme picker.
    readonly property string barStyle: (barStyleFile.text() || "classic").trim()
    readonly property bool islands: barStyle === "islands"

    FileView {
        id: barStyleFile
        path: root.hypr + "/theme/bar-style"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }

    FileView {
        id: paletteFile
        path: root.hypr + "/theme/palette.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }

    FileView {
        id: accentFile
        path: root.hypr + "/theme/accent"
        watchChanges: true
        onFileChanged: reload()
    }

    FileView {
        id: panelOpacityFile
        path: root.hypr + "/theme/panel-opacity"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }

    FileView {
        id: fontShellFile
        path: root.hypr + "/theme/font-shell"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }
}
