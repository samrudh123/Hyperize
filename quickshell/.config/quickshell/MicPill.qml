// Microphone, plus a privacy light for the mic, the camera and screen capture.
//
//   click: mute / unmute the default source · right-click: mixer (inputs)
//   scroll: mic level ±5 %
//
// Turns red while any app records from a microphone (tooltip says which),
// and shows a camera / screen glyph while a camera or screen is being
// captured (OBS, browsers, screen sharing through xdg-desktop-portal-hyprland).
// Read from PipeWire's links, so nothing is polled.
import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

Pill {
    id: mic

    readonly property var src: Pipewire.defaultAudioSource
    readonly property bool ok: src !== null && src.audio !== null
    readonly property int pct: ok ? Math.round(src.audio.volume * 100) : 0
    readonly property bool muted: ok && src.audio.muted

    PwObjectTracker { objects: [mic.src] }

    function appName(n) {
        return n.nickname || n.description || n.name || "?";
    }
    function isDevice(n, kind) {                // a real capture device, not a stream
        return n !== null && !n.isStream && !n.isSink && (n.type & kind) === kind;
    }

    // who is listening: links from a capture device into an app's stream
    // (pavucontrol's level meters and Bluetooth's internal plumbing aside)
    readonly property var usage: {
        const out = { mic: [], camera: [], screen: [] };
        for (const g of Pipewire.linkGroups.values) {
            const s = g.source, t = g.target;
            if (!s || !t || !t.isStream) continue;
            const who = appName(t);
            if (/Volume Control|pavucontrol|^bluez_|peak/i.test(t.name + " " + who)) continue;
            if (isDevice(s, PwNodeType.AudioSource)) out.mic.push(who);
            else if ((s.type & PwNodeType.VideoSource) === PwNodeType.VideoSource)
                (s.name.startsWith("xdph") ? out.screen : out.camera).push(who);
        }
        for (const k in out) out[k] = Array.from(new Set(out[k]));
        return out;
    }
    readonly property bool live: usage.mic.length > 0

    shown: ok
    label: (muted ? "\u{f036d}" : "\u{f036c}")
         + (usage.camera.length > 0 ? " \u{f05a0}" : "")       // md-webcam
         + (usage.screen.length > 0 ? " \u{f1483}" : "")       // md-monitor_share
    fg: live && !muted ? Theme.crust : muted ? (live ? Theme.red : Theme.overlay0) : Theme.flamingo
    bg: live && !muted ? Theme.red : "transparent"
    fillHover: true
    fontSize: 14
    tip: {
        if (!ok) return "";
        const dim = s => "<font color='" + Theme.overlay2 + "'>" + s + "</font>";
        let t = (src.description || src.name) + "  ·  " + (muted ? "muted" : pct + "%");
        if (usage.mic.length) t += "<br>\u{f036c} " + (muted ? "muted for " : "in use by ") + usage.mic.join(", ");
        if (usage.camera.length) t += "<br>\u{f05a0} camera in use by " + usage.camera.join(", ");
        if (usage.screen.length) t += "<br>\u{f1483} screen captured by " + usage.screen.join(", ");
        return t + "<br>" + dim("Click: mute · Right-click: mixer · Scroll: level");
    }

    onClicked: button => {
        if (button === Qt.LeftButton && ok) src.audio.muted = !src.audio.muted;
        else if (button === Qt.RightButton) Theme.exec("pavucontrol -t 4");
    }
    onScrolled: dir => {
        if (ok) src.audio.volume = Math.max(0, Math.min(1, Math.round(src.audio.volume * 20 + dir) / 20));
    }
}
