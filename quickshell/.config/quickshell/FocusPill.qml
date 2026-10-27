// Focus timer (pomodoro, hypr/focus.py), tied to the tasks in ~/notes.
//
//   click: the panel (FocusPopup.qml: ring, controls, length, task, today)
//   idle      right-click: start a session (do not disturb on)
//             (task: one from ~/notes/tasks.md, or "Something else…" to type any;
//             typed ones stay listed until their trash button is clicked)
//   running   time left, the task, a line that drains; right-click pauses /
//             resumes, middle-click stops; +5 min, skip, task, lengths: the panel
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
    // the session's task — unless it has been ticked off in tasks.md since
    // (focus.py also drops it while idle); typed ones (`recent`) always count
    readonly property string task: {
        const t = st.task || "";
        return !t || tasks.includes(t) || (st.recent || []).includes(t) || (tasksFile.text() || "") === "" ? t : "";
    }
    readonly property var recent: (st.recent || []).filter(t => fp.tasks.slice(0, 10).indexOf(t) < 0)

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
                 + "<br>" + dim(PillClicks.hint("focus"));
        const what = phase === "break" ? "Break" : "Focus" + (task ? ": " + esc(task) : "");
        return "<b>" + what + "</b>" + (paused ? " — paused" : "")
             + "<br>" + clock(remain) + " left of " + Math.round(st.total / 60) + " min"
             + (today ? "<br>" + today : "")
             + "<br>" + dim(PillClicks.hint("focus"));
    }

    function toggleMenu() { panel.toggle(); }

    pillId: "focus"                    // wheel: Settings › Pills
    onClicked: button => {
        PillClicks.dispatch("focus", button, {
            panel: () => panel.toggle(),
            toggle: () => run(["toggle"]),          // start / pause / resume
            stop: () => { if (!idle) run(["stop"]); }
        });
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

    // the cards' / panel's `x: fp` would bind to their own `fp` property
    readonly property var selfRef: fp
    FocusPopup {
        id: panel
        pill: selfRef
        fp: selfRef
    }
}
