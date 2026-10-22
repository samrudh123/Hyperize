// Focus timer (pomodoro, hypr/focus.py), tied to the tasks in ~/notes.
//
//   idle      click: start a session (do not disturb on) · right-click: menu
//             (task: one from ~/notes/tasks.md, or "Something else…" to type any;
//             typed ones stay listed until their trash button is clicked)
//   running   time left, the task, a line that drains; click pauses / resumes,
//             middle-click stops, right-click: +5 min, skip, task, lengths
//   break     green, counts down the break; notifications are back
//
// The state is focus.py's JSON file, watched; the countdown is this pill's
// own clock against its `ends`, so nothing polls. At zero the pill calls
// `focus.py next` (once per phase), which notifies, logs the session to
// today's notes and starts the break.
import QtQuick
import Quickshell
import Quickshell.Io

Pill {
    id: fp

    readonly property string script: Theme.hypr + "/focus.py"
    // with a bar per screen, only one pill may advance the phase at zero
    property bool primary: true
    readonly property var st: {
        try { return JSON.parse(stateFile.text() || "{}"); } catch (e) { return {}; }
    }
    readonly property string phase: st.phase || "idle"
    readonly property bool idle: phase === "idle"
    readonly property bool paused: st.paused === true
    readonly property int workMin: st.work || 25
    readonly property int brkMin: st.brk || 5
    readonly property string task: st.task || ""
    readonly property var recent: (st.recent || []).filter(t => fp.tasks.slice(0, 8).indexOf(t) < 0)

    property real now: Date.now() / 1000
    readonly property real remain: idle ? 0 : paused ? st.left : Math.max(0, st.ends - now)
    readonly property real frac: !idle && st.total > 0 ? remain / st.total : -1

    // open tasks, straight from ~/notes/tasks.md ("- [ ] text <!-- … -->")
    readonly property var tasks: {
        const out = [];
        for (const l of (tasksFile.text() || "").split("\n")) {
            const m = l.match(/^- \[ \] (.*?)\s*(<!--.*-->)?\s*$/);
            if (m && m[1]) out.push(m[1]);
        }
        return out;
    }

    function run(args) { Quickshell.execDetached(["/usr/bin/python3", script].concat(args)); }
    function clock(s) {
        s = Math.ceil(s);
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
    }
    function trim(t, n) { return t.length > n ? t.slice(0, n - 1) + "…" : t; }
    function esc(t) { return t.replace(/&/g, "&amp;").replace(/</g, "&lt;"); }

    readonly property color tint: phase === "break" ? Theme.green : paused ? Theme.yellow : Theme.red

    label: idle ? "\u{f051b}"                                               // md-timer_outline
         : (paused ? "\u{f03e4}" : phase === "break" ? "\u{f0d9e}" : "\u{f051b}")   // pause / tea / timer
           + " " + clock(remain)
           + (phase === "work" && task ? "&nbsp;&nbsp;<font color='" + (hovered ? Theme.mantle : Theme.subtext0) + "'>" + esc(trim(task, 22)) + "</font>" : "")
    // hover fills the pill in its colour (accent when idle) with dark text,
    // like the power / keep-awake pills
    fg: idle ? Theme.accent : tint
    hoverFg: Theme.crust
    hoverBg: fg
    fontSize: idle ? 15 : 13
    padLeft: idle ? 10 : 12
    padRight: idle ? 10 : 12
    marginH: 2
    progress: frac >= 0 ? frac : -1
    progressColor: hovered ? Theme.crust : tint
    tipEdge: Edges.Top
    tip: {
        const dim = s => "<font color='" + Theme.overlay2 + "'>" + s + "</font>";
        const round = st.round || 0;
        const today = round ? dim(round + " session" + (round > 1 ? "s" : "") + " today") : "";
        if (idle)
            return "<b>Focus timer</b>" + (today ? "&nbsp;&nbsp;" + today : "")
                 + "<br>" + workMin + " min focus (do not disturb), then a " + brkMin + " min break"
                 + (task ? "<br>Task: " + esc(task) : "")
                 + "<br>" + dim("Click: start · Right-click: task & length");
        const what = phase === "break" ? "Break" : "Focus" + (task ? ": " + esc(task) : "");
        return "<b>" + what + "</b>" + (paused ? " — paused" : "")
             + "<br>" + clock(remain) + " left of " + Math.round(st.total / 60) + " min"
             + (today ? "<br>" + today : "")
             + "<br>" + dim("Click: " + (paused ? "resume" : "pause") + " · Middle-click: stop · Right-click: more");
    }

    function toggleMenu() { menu.isOpen ? menu.close() : menu.open(fp); }

    onClicked: button => {
        if (button === Qt.RightButton) { menu.isOpen ? menu.close() : menu.open(fp); return; }
        if (button === Qt.MiddleButton) { if (!idle) run(["stop"]); return; }
        run(["toggle"]);
    }

    Timer {
        running: !fp.idle && !fp.paused
        repeat: true
        interval: 1000
        triggeredOnStart: true
        onTriggered: {
            fp.now = Date.now() / 1000;
            if (fp.primary && fp.remain <= 0 && fp.handled !== fp.st.ends) {
                fp.handled = fp.st.ends;
                fp.run(["next"]);
            }
        }
    }
    property real handled: 0

    FileView {
        id: stateFile
        path: Quickshell.env("XDG_STATE_HOME") ? Quickshell.env("XDG_STATE_HOME") + "/focus/state.json"
                                               : Theme.home + "/.local/state/focus/state.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }
    FileView {
        id: tasksFile
        path: Theme.home + "/notes/tasks.md"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }

    MenuPopup {
        id: menu
        edge: Edges.Top
        minWidth: 250

        MenuRow {
            header: true
            text: "FOCUS" + (fp.st.round ? "  ·  " + fp.st.round + " TODAY" : "")
        }
        MenuRow {
            visible: fp.idle
            text: "Start " + fp.workMin + " min focus"
            glyph: "\u{f051b}"
            glyphColor: Theme.red
            onActivated: { menu.close(); fp.run(["start"]); }
        }
        MenuRow {
            visible: !fp.idle
            text: fp.paused ? "Resume" : "Pause"
            glyph: fp.paused ? "\u{f040a}" : "\u{f03e4}"
            onActivated: { menu.close(); fp.run(["toggle"]); }
        }
        MenuRow {
            visible: !fp.idle
            text: "+5 min"
            glyph: "\u{f0415}"                          // md-plus
            onActivated: { menu.close(); fp.run(["add", "5"]); }
        }
        MenuRow {
            visible: !fp.idle
            text: fp.phase === "break" ? "End break" : "Finish now — take the break"
            glyph: "\u{f04ad}"                          // md-skip_next
            onActivated: { menu.close(); fp.run(["skip"]); }
        }
        MenuRow {
            visible: !fp.idle
            danger: true
            text: "Stop"
            glyph: "\u{f04db}"
            onActivated: { menu.close(); fp.run(["stop"]); }
        }

        MenuRow { separator: true }
        MenuRow { header: true; text: "TASK" }
        MenuRow {
            text: "No particular task"
            check: fp.task === "" ? 1 : 0
            onActivated: { menu.close(); fp.run(["task"]); }
        }
        Repeater {
            model: fp.tasks.slice(0, 8)
            MenuRow {
                required property var modelData
                text: modelData
                check: fp.task === modelData ? 1 : 0
                // picking a task while idle starts the session on it
                onActivated: {
                    menu.close();
                    fp.run(fp.idle ? ["start", String(fp.workMin), modelData] : ["task", modelData]);
                }
            }
        }
        // tasks typed via "Something else…" (focus.py keeps the last 4), unless
        // they are in the list above anyway; the trash button forgets one
        Repeater {
            model: fp.recent
            MenuRow {
                required property var modelData
                text: modelData
                check: fp.task === modelData ? 1 : 0
                removable: true
                onRemoved: fp.run(["forget", modelData])
                onActivated: {
                    menu.close();
                    fp.run(fp.idle ? ["start", String(fp.workMin), modelData] : ["task", modelData]);
                }
            }
        }
        MenuRow {
            // set some other way (focus.py task TEXT): still show what it is
            visible: fp.task !== "" && fp.tasks.slice(0, 8).indexOf(fp.task) < 0
                     && fp.recent.indexOf(fp.task) < 0
            text: fp.task
            check: 1
            onActivated: menu.close()
        }
        MenuRow {
            // any other task or chore, typed into a fuzzel prompt (focus.py
            // pick); while idle it starts the session on it
            text: "Something else…"
            glyph: "\u{f03eb}"                          // md-pencil
            onActivated: { menu.close(); fp.run(["pick"]); }
        }

        MenuRow { separator: true }
        MenuRow { header: true; text: "LENGTH" }
        Repeater {
            model: [[25, 5], [50, 10], [90, 15]]
            MenuRow {
                required property var modelData
                text: modelData[0] + " min focus  ·  " + modelData[1] + " min break"
                check: fp.workMin === modelData[0] && fp.brkMin === modelData[1] ? 1 : 0
                onActivated: fp.run(["lengths", String(modelData[0]), String(modelData[1])])
            }
        }
    }
}
