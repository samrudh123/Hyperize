// Tailscale: up/down and who is online on the tailnet.
//
//   click: the Tailscale panel (TailscalePopup: connect switch, each machine
//          with SSH in · send files with Taildrop · copy IP; exit node) ·
//          middle-click: connect/disconnect
//
// Read from `tailscale status --json` every 5 s. The local user is the
// tailscale operator, so up/down need no sudo.
import QtQuick
import Quickshell
import Quickshell.Io

Pill {
    id: ts

    property var st: ({})
    readonly property string backend: st.BackendState || ""
    readonly property bool running: backend === "Running"
    readonly property var self: st.Self || ({})
    readonly property var peers: {
        const out = [];
        for (const k in (st.Peer || {})) out.push(st.Peer[k]);
        // online first, then by name
        out.sort((a, b) => (b.Online - a.Online) || a.HostName.localeCompare(b.HostName));
        return out;
    }
    readonly property int online: peers.filter(p => p.Online).length
    readonly property var exitNode: peers.find(p => p.ExitNode) || null
    readonly property var exitOptions: peers.filter(p => p.ExitNodeOption)

    function host(p) { return (p.DNSName || p.HostName).replace(/\.$/, ""); }
    function shortName(p) { return host(p).split(".")[0]; }
    function ip(p) { return (p.TailscaleIPs || [""])[0]; }
    function osGlyph(p) {
        return p.OS === "android" ? "\u{f0032}" : p.OS === "linux" ? "\u{f033d}"
             : p.OS === "windows" ? "\u{f05b3}" : p.OS === "macOS" || p.OS === "iOS" ? "\u{f0035}" : "\u{f0322}";
    }
    function seen(p) {
        // Active = traffic lately; an idle peer has no path yet, so no direct/relay
        if (p.Online) return !p.Active ? "online, idle" : p.CurAddr ? "direct" : "relay " + (p.Relay || "");
        const t = Date.parse(p.LastSeen || "");
        if (!t || t < 0 || new Date(t).getFullYear() < 2000) return "offline";
        const m = Math.round((Date.now() - t) / 60000);
        return "seen " + (m < 60 ? m + " min" : m < 2880 ? Math.round(m / 60) + " h" : Math.round(m / 1440) + " d") + " ago";
    }
    function run(cmd) { Theme.exec(cmd); poke.restart(); }
    function toggle() {
        if (backend === "NeedsLogin")       // prints a login URL: needs a terminal
            Theme.exec("ghostty --gtk-single-instance=false -e sh -c 'tailscale up; echo; read -p \"Enter to close\" _'");
        else
            run("tailscale " + (running ? "down" : "up"));
    }

    shown: backend !== ""
    label: running ? "\u{f0582}" + (online ? " " + online : "") + (exitNode ? " \u{f01e7}" : "")
         : "\u{f0582}"
    fg: !running ? Theme.overlay0 : exitNode ? Theme.crust : Theme.teal
    bg: running && exitNode ? Theme.teal : "transparent"
    fillHover: true
    padLeft: 10
    padRight: 10
    marginH: 2
    tipEdge: Edges.Top
    tip: {
        const dim = s => "<font color='" + Theme.overlay2 + "'>" + s + "</font>";
        if (!running)
            return "Tailscale " + (backend === "NeedsLogin" ? "needs login" : backend.toLowerCase())
                 + "<br>" + dim(PillClicks.hint("tailscale"));
        let t = "<b>Tailscale</b>&nbsp;&nbsp;" + dim(((st.CurrentTailnet || {}).Name || "")) + "<br>"
              + "This machine&nbsp;&nbsp;" + ip(self);
        if (exitNode) t += "<br>\u{f01e7} exit node: " + shortName(exitNode);
        t += "<br>";
        for (const p of peers)
            t += "<br>" + (p.Online ? "<font color='" + Theme.green + "'>●</font>" : dim("○")) + " "
               + osGlyph(p) + " " + shortName(p) + "&nbsp;&nbsp;" + dim(ip(p) + " · " + seen(p));
        return t + "<br><br>" + dim(PillClicks.hint("tailscale"));
    }

    function toggleMenu() { menu.toggle(); }

    pillId: "tailscale"                    // wheel: Settings › Pills
    onClicked: button => {
        PillClicks.dispatch("tailscale", button, {
            panel: () => menu.toggle(),
            connect: () => toggle(),
            settings: () => BarState.panelRequested("settings", "tailscale")
        });
    }

    Process {
        id: proc
        command: ["tailscale", "status", "--json"]
        stdout: StdioCollector {
            onStreamFinished: { try { ts.st = JSON.parse(text); } catch (e) {} }
        }
    }
    Timer {
        running: true
        repeat: true
        triggeredOnStart: true
        interval: menu.isOpen ? 2000 : 5000
        onTriggered: if (!proc.running) proc.running = true
    }
    // re-read soon after an action (up/down take a moment)
    Timer { id: poke; interval: 1500; onTriggered: if (!proc.running) proc.running = true }

    // the panel (TailscalePopup.qml) — was a MenuPopup
    TailscalePopup {
        id: menu
        pill: ts
        tsp: ts
    }
}
