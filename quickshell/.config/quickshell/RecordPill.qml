// Screenshots and screen recording (hypr/screen-record.py).
//
//   idle       click: region screenshot · middle: start recording · right: menu
//   recording  red, with the running time; click (or middle) stops it
//
// Recording goes through OBS when OBS is open (its scenes, folder and format;
// "OBS" shows in the pill) and through wf-recorder otherwise (screen, region
// or window, with desktop sound / microphone / none, to ~/Videos/Recordings).
// State comes from `screen-record.py watch`, one JSON line per change.
import QtQuick
import Quickshell
import Quickshell.Io

Pill {
    id: rec

    property var st: ({ state: "idle", backend: "", elapsed: 0, obs: false, audio: "desktop", wf: true })
    readonly property bool recording: st.state !== "idle"
    readonly property string script: "/usr/bin/python3 " + Theme.hypr + "/screen-record.py"

    function run(args) { Theme.exec(script + " " + args); }
    function shot(mode) { Theme.exec(Theme.hypr + "/screenshot.sh " + mode); }
    function clock(s) {
        const h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60, sec = s % 60;
        return (h > 0 ? h + ":" + String(m).padStart(2, "0") : String(m).padStart(2, "0")) + ":" + String(sec).padStart(2, "0");
    }

    label: recording
        // the dot blinks with the seconds (a colour pulse would fight Pill's
        // colour Behavior, which restarts on every change)
        ? (st.state === "paused" ? "\u{f03e4} " : st.elapsed % 2 ? "\u{f0ec3} " : "\u{f044a} ") + clock(st.elapsed) + (st.backend === "obs" ? "  OBS" : "")
        : "\u{f0d5d}"                                   // md-camera_outline
    fg: recording ? Theme.crust : Theme.flamingo
    bg: recording ? (st.state === "paused" ? Theme.yellow : Theme.red) : "transparent"
    hoverFg: recording ? Theme.crust : Theme.flamingo
    hoverBg: recording ? (st.state === "paused" ? Theme.yellow : Theme.red) : Theme.alpha(Theme.surface0, 0.9)
    fontSize: recording ? 13 : 15
    padLeft: recording ? 10 : 9
    padRight: recording ? 10 : 10
    tip: recording
        ? "Recording" + (st.backend === "obs" ? " in OBS" : "") + " · " + clock(st.elapsed)
          + "<br><font color='" + Theme.overlay2 + "'>Click: stop · Right-click: menu</font>"
        : "Screenshot & screen recording"
          + "<br><font color='" + Theme.overlay2 + "'>Click: region screenshot · Middle-click: record "
          + (st.obs ? "in OBS" : "screen") + " · Right-click: more</font>"

    onClicked: button => {
        if (button === Qt.RightButton) { menu.isOpen ? menu.close() : menu.open(rec); return; }
        if (recording) { run("stop"); return; }
        if (button === Qt.LeftButton) shot("region");
        else if (button === Qt.MiddleButton) run("toggle");
    }

    Process {
        id: watcher
        running: true
        command: ["/usr/bin/python3", Theme.hypr + "/screen-record.py", "watch"]
        stdout: SplitParser {
            onRead: line => {
                try { rec.st = JSON.parse(line); } catch (e) {}
            }
        }
        onExited: again.restart()
    }
    Timer {
        id: again
        interval: 3000
        onTriggered: watcher.running = true
    }

    MenuPopup {
        id: menu
        minWidth: 230

        MenuRow {
            visible: rec.recording
            danger: true
            text: "Stop recording  ·  " + rec.clock(rec.st.elapsed)
            glyph: "\u{f04db}"                          // md-stop
            onActivated: { rec.run("stop"); menu.close(); }
        }
        MenuRow { separator: true; visible: rec.recording }

        MenuRow { header: true; text: "SCREENSHOT" }
        MenuRow {
            text: "Region"
            glyph: "\u{f019f}"                          // md-crop_free
            onActivated: { menu.close(); rec.shot("region"); }
        }
        MenuRow {
            text: "Window"
            glyph: "\u{f05b2}"                          // md-window_restore
            onActivated: { menu.close(); rec.shot("window"); }
        }
        MenuRow {
            text: "Screen"
            glyph: "\u{f0379}"                          // md-monitor
            onActivated: { menu.close(); rec.shot("screen"); }
        }

        MenuRow { separator: true; visible: !rec.recording }
        MenuRow { header: true; visible: !rec.recording; text: "RECORD" }
        MenuRow {
            visible: !rec.recording && rec.st.obs
            text: "Record in OBS"
            glyph: "\u{f0bdc}"                          // md-video_outline
            glyphColor: Theme.red
            enabled: rec.st.obsReachable === true
            onActivated: { menu.close(); rec.run("obs start"); }
        }
        MenuRow {
            visible: !rec.recording
            enabled: rec.st.wf
            text: "Record screen"
            glyph: "\u{f0379}"
            onActivated: { menu.close(); rec.run("start screen"); }
        }
        MenuRow {
            visible: !rec.recording
            enabled: rec.st.wf
            text: "Record region"
            glyph: "\u{f019f}"
            onActivated: { menu.close(); rec.run("start region"); }
        }
        MenuRow {
            visible: !rec.recording
            enabled: rec.st.wf
            text: "Record window"
            glyph: "\u{f05b2}"
            onActivated: { menu.close(); rec.run("start window"); }
        }

        MenuRow { separator: true; visible: !rec.recording }
        MenuRow { header: true; visible: !rec.recording; text: "SOUND" }       // wf-recorder only; OBS uses its own mixer
        Repeater {
            model: [["desktop", "Desktop sound"], ["mic", "Microphone"], ["none", "No sound"]]
            MenuRow {
                required property var modelData
                visible: !rec.recording
                text: modelData[1]
                check: rec.st.audio === modelData[0] ? 1 : 0
                onActivated: {
                    rec.st = Object.assign({}, rec.st, { audio: modelData[0] });
                    rec.run("audio " + modelData[0]);
                }
            }
        }

        MenuRow { separator: true }
        MenuRow {
            visible: !rec.st.obs
            text: "Open OBS"
            glyph: "\u{f0bdc}"
            onActivated: { menu.close(); Theme.exec(Theme.hypr + "/focus-or-launch.sh obsproject /usr/bin/obs"); }
        }
        MenuRow {
            text: "Open recordings folder"
            glyph: "\u{f19fb}"                          // md-folder_play_outline
            // yazi in grid view (thumbnails); q there gives the yazi list
            onActivated: { menu.close(); Theme.exec(Theme.home + "/.config/yazi/grid-open.sh " + Theme.home + "/Videos/Recordings"); }
        }
    }
}
