// Duplicate / extend state for the display pills (one per top bar):
// hypr/display-mode.py's status JSON, and the one place that runs it, so
// hotplug sync happens once however many bars there are.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Singleton {
    id: root

    property var st: ({})
    readonly property int count: st.count || 0
    readonly property string mode: st.mode || "single"
    readonly property string dir: st.dir || "right"
    readonly property var mons: st.monitors || []
    readonly property var externals: mons.filter(m => !m.main)
    readonly property bool mirror: mode === "mirror"

    property var pending: null
    function run(args) {
        if (proc.running) { pending = args; return; }
        proc.command = ["/usr/bin/python3", Theme.hypr + "/display-mode.py"].concat(args);
        proc.running = true;
    }
    function set(m, d) { run(["set", m].concat(d ? [d] : [])); }
    // notify: an OSD saying which (SUPER+P), or that there is no second screen
    function toggle(notify) { run(["toggle"].concat(notify ? ["--notify"] : [])); }

    Process {
        id: proc
        stdout: StdioCollector {
            onStreamFinished: { try { root.st = JSON.parse(text); } catch (e) {} }
        }
        onExited: if (root.pending) { const a = root.pending; root.pending = null; root.run(a); }
    }
    Component.onCompleted: run(["sync"])

    // Hotplug, and a config reload (which resets the runtime monitor rules).
    // Duplicate/extend switches themselves send no event: `set` prints the
    // new state.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name.startsWith("monitoradded") || event.name.startsWith("monitorremoved")
                || event.name === "configreloaded")
                settle.restart();
        }
    }
    Timer { id: settle; interval: 150; onTriggered: root.run(["sync"]) }
}
