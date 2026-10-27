// Settings › Tailscale: connect / disconnect and the machines on the tailnet
// (`tailscale status --json`, every 5 s while this page is open). The user
// is the tailscale operator, so up/down need no sudo.
import QtQuick
import Quickshell
import Quickshell.Io

SettingsPage {
    id: page
    title: "Tailscale"
    subtitle: "Your private network: this laptop, the phone and anything else you add."

    property var st: ({})
    property bool busy: false
    readonly property string backend: st.BackendState || ""
    readonly property bool running: backend === "Running"
    readonly property var self: st.Self || ({})
    readonly property var peers: {
        const out = [];
        for (const k in (st.Peer || {})) out.push(st.Peer[k]);
        out.sort((a, b) => (b.Online - a.Online) || a.HostName.localeCompare(b.HostName));
        return out;
    }

    function host(p) { return (p.DNSName || p.HostName || "").replace(/\.$/, ""); }
    function shortName(p) { return host(p).split(".")[0] || p.HostName || ""; }
    function ip(p) { return (p.TailscaleIPs || [""])[0]; }
    function osGlyph(p) {
        return p.OS === "android" ? "\u{f0032}" : p.OS === "linux" ? "\u{f033d}"
             : p.OS === "windows" ? "\u{f05b3}" : p.OS === "macOS" || p.OS === "iOS" ? "\u{f0035}" : "\u{f0322}";
    }
    function seen(p) {
        if (p.Online) return !p.Active ? "online, idle" : p.CurAddr ? "online, direct" : "online, relay " + (p.Relay || "");
        const t = Date.parse(p.LastSeen || "");
        if (!t || t < 0 || new Date(t).getFullYear() < 2000) return "offline";
        const m = Math.round((Date.now() - t) / 60000);
        return "seen " + (m < 60 ? m + " min" : m < 2880 ? Math.round(m / 60) + " h" : Math.round(m / 1440) + " d") + " ago";
    }

    Process {
        id: poll
        running: true
        command: ["tailscale", "status", "--json"]
        stdout: StdioCollector {
            onStreamFinished: { try { page.st = JSON.parse(text); } catch (e) {} page.busy = false; }
        }
    }
    Timer { interval: 5000; repeat: true; running: true; onTriggered: if (!poll.running) poll.running = true }
    Process {
        id: upDown
        onExited: poll.running = true
    }
    function toggle(on) {
        if (backend === "NeedsLogin") {
            Theme.exec("ghostty --gtk-single-instance=false -e sh -c 'tailscale up; echo; read -p \"Enter to close\" _'");
            return;
        }
        busy = true;
        upDown.command = ["tailscale", on ? "up" : "down"];
        upDown.running = true;
    }

    SettingsCard {
        title: "This machine"
        icon: "\u{f0582}"
        SettingsRow {
            icon: "\u{f0582}"
            iconColor: Theme.teal
            title: "Tailscale"
            subtitle: page.busy ? "Working…" : page.running ? "Connected to " + ((page.st.CurrentTailnet || {}).Name || "the tailnet")
                    : page.backend === "NeedsLogin" ? "Needs login — switch on to sign in"
                    : page.backend ? page.backend : "Not running"
            keywords: "vpn connect disconnect up down"
            Toggle {
                anchors.verticalCenter: parent.verticalCenter
                accent: Theme.teal
                busy: page.busy
                checked: page.running
                onToggled: v => page.toggle(v)
            }
        }
        SettingsRow {
            visible: page.running && matches
            icon: "\u{f0322}"
            title: page.shortName(page.self)
            subtitle: page.ip(page.self) + "  ·  " + page.host(page.self)
            keywords: "ip address hostname magicdns"
            last: true
            IconBtn {
                icon: "\u{f018f}"
                text: "Copy IP"
                onClicked: Theme.exec("wl-copy " + page.ip(page.self))
            }
        }
    }

    SettingsCard {
        visible: page.running && page.peers.length > 0
        title: "Machines  ·  " + page.peers.filter(p => p.Online).length + " online"
        icon: "\u{f0317}"
        Repeater {
            model: page.peers
            delegate: SettingsRow {
                id: pr
                required property var modelData
                required property int index
                readonly property var p: modelData
                icon: page.osGlyph(p)
                iconColor: p.Online ? Theme.teal : Theme.overlay0
                title: page.shortName(p) + (p.ExitNode ? "  ·  exit node" : "")
                subtitle: page.ip(p) + "  ·  " + page.seen(p)
                keywords: "peer machine device " + (p.OS || "")
                last: index === page.peers.length - 1
                IconBtn {
                    anchors.verticalCenter: parent.verticalCenter
                    size: 30; iconSize: 14
                    icon: "\u{f018f}"
                    tip: "Copy IP"
                    onClicked: Theme.exec("wl-copy " + page.ip(pr.p))
                }
                IconBtn {
                    anchors.verticalCenter: parent.verticalCenter
                    size: 30; iconSize: 14
                    icon: "\u{f022a}"
                    tip: "Send files (Taildrop)"
                    enabled: pr.p.Online
                    onClicked: { SettingsState.closeRequested(); Theme.exec(Theme.hypr + "/tailscale-send.sh " + page.host(pr.p)); }
                }
                IconBtn {
                    anchors.verticalCenter: parent.verticalCenter
                    size: 30; iconSize: 14
                    icon: "\u{f08c0}"
                    tip: "SSH"
                    // phones / tablets run no SSH server
                    visible: !/^(android|ios)$/i.test(pr.p.OS || "")
                    enabled: pr.p.Online
                    onClicked: {
                        SettingsState.closeRequested();
                        Theme.exec("ghostty --gtk-single-instance=false --title=ssh-" + page.shortName(pr.p) + " -e ssh " + page.host(pr.p));
                    }
                }
            }
        }
    }

    SettingsCard {
        title: "More"
        icon: "\u{f03cc}"
        SettingsRow {
            icon: "\u{f01e7}"
            title: "Admin console"
            subtitle: "Machines, keys, DNS, sharing — login.tailscale.com"
            keywords: "web admin dns acl"
            last: true
            IconBtn {
                text: "Open"
                icon: "\u{f03cc}"
                onClicked: { SettingsState.closeRequested(); Theme.exec("xdg-open https://login.tailscale.com/admin/machines"); }
            }
        }
    }
}
