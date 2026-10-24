// A Pill fed by one of the existing waybar scripts ({"text", "class",
// "tooltip"} JSON, Pango markup). The scripts are unchanged, so they keep
// working from the command line and from their panels.
//
//   command   argv
//   interval  ms between polls; 0 = the script is long-running and prints a
//             line per change (restarted 5 s after it exits, like waybar's
//             restart-interval)
//   pokable   long-running script that re-polls on SIGUSR1 (hypr/barwatch.py),
//             so a click still refreshes it at once
//   colors    class -> text colour; bgs: class -> fill; first match wins,
//             in the order the script lists its classes
//   onLeft / onRight / onMiddle   shell commands (run via Hyprland exec)
//
// A click polls again straight away (waybar's exec-on-event), so the pill
// reflects what the click did without waiting a full interval.
import QtQuick
import Quickshell
import Quickshell.Io

Pill {
    id: sp

    required property var command
    property int interval: 2000
    property bool pokable: false
    property var colors: ({})
    property var bgs: ({})
    property color defaultFg: Theme.text
    property color defaultBg: "transparent"
    property string onLeft
    property string onRight
    property string onMiddle
    property int maxChars: 0
    property var textFilter: t => t

    // last output
    property string rawText
    property var classes: []
    property var json: ({})

    function pick(map, fallback) {
        for (const c of classes)
            if (map[c] !== undefined) return map[c];
        return fallback;
    }

    function apply(line) {
        line = line.trim();
        if (!line) return;
        try {
            const d = JSON.parse(line);
            json = d;
            rawText = d.text || "";
            classes = Array.isArray(d["class"]) ? d["class"] : (d["class"] ? [d["class"]] : []);
            tip = Theme.pango(d.tooltip || "");
        } catch (e) {
            console.warn(command[0], "bad JSON:", line);
        }
    }

    function refresh() {
        if (sp.interval > 0 && !proc.running) proc.running = true;
        else if (sp.interval === 0 && sp.pokable && proc.running) proc.signal(10);   // SIGUSR1
    }

    readonly property string shownText: textFilter(rawText)
    label: Theme.pango(maxChars > 0 && shownText.length > maxChars ? shownText.slice(0, maxChars - 1) + "…" : shownText)
    shown: rawText !== "" && !classes.includes("hidden")
    fg: pick(colors, defaultFg)
    bg: pick(bgs, defaultBg)

    onClicked: button => {
        const cmd = button === Qt.RightButton ? onRight : button === Qt.MiddleButton ? onMiddle : onLeft;
        if (!cmd) return;
        Theme.exec(cmd);
        again.restart();
    }

    Timer {
        id: again
        interval: 200
        onTriggered: sp.refresh()
    }

    Process {
        id: proc
        command: sp.command
        running: true
        stdout: SplitParser { onRead: line => sp.apply(line) }
        onExited: if (sp.interval === 0) restart.start()
    }

    Timer {
        id: poll
        running: sp.interval > 0
        repeat: true
        interval: Math.max(sp.interval, 250)
        onTriggered: sp.refresh()
    }

    Timer {
        id: restart
        interval: 5000
        onTriggered: proc.running = true
    }
}
