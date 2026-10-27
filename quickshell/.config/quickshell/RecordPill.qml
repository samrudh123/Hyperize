// Screenshots and screen recording (hypr/screen-record.py).
//
//   click: the capture panel (RecordPopup.qml; `qs ipc call capture toggle`)
//   right-click: region screenshot · middle: start / stop recording
//   recording  red, with the running time (stop: middle-click, or the panel)
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
    fillHover: true
    fontSize: recording ? 13 : 15
    padLeft: recording ? 10 : 9
    padRight: recording ? 10 : 10
    tip: recording
        ? "Recording" + (st.backend === "obs" ? " in OBS" : "") + " · " + clock(st.elapsed)
          + PillClicks.hintLine("capture")
        : "Screenshot & screen recording"
          + PillClicks.hintLine("capture")

    pillId: "capture"                    // wheel: Settings › Pills
    onClicked: button => {
        // what each button does: PillClicks (Settings › Pills)
        PillClicks.dispatch("capture", button, {
            panel: () => panel.toggle(),
            region: () => shot("region"),
            window: () => shot("window"),
            screen: () => shot("screen"),
            record: () => run(recording ? "stop" : "toggle")
        });
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

    // `rec: rec` inside the panel would bind to its own `rec` property
    readonly property var selfRef: rec
    RecordPopup {
        id: panel
        pill: selfRef
        rec: selfRef
    }
    IpcHandler {
        target: "capture"
        enabled: !!panel.anchor.window && !!panel.anchor.window.screen && panel.anchor.window.screen.name === BarState.active
        function toggle(): void { panel.toggle(); }
        function open(): void { panel.open(); }
        function close(): void { panel.close(); }
    }
}
