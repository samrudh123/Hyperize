// The network panels (Serpantinum-style): one under the top bar's network
// pill (mode "wifi") and one under the Bluetooth pill (mode "bluetooth"),
// separate popups. Replaces network-panel.py's GTK window for everyday use
// (the script still works on its own).
//
//   tabs     mode "wifi": Wi-Fi (| Ethernet while a cable is connected);
//            mode "bluetooth": none; mode "all": Wi-Fi | Bluetooth (| Ethernet)
//   header   the orb (NetOrb.qml: ripples while connected, signal ring; hold
//            it 1 s to disconnect), what's connected, radio switch, scan
//   list     NetWifiCard / BtDeviceCard
//   footer   nm-connection-editor / blueman-manager
//
// Wi-Fi comes from Quickshell.Networking (NetworkManager over D-Bus: connect,
// connectWithPsk, disconnect, forget); Bluetooth from Quickshell.Bluetooth
// (BlueZ). Scanning runs only while the panel is open (Wi-Fi rescans every
// 10 s for 30 s after opening or Scan; Bluetooth discovers for 20 s), and the
// NM stage ("authenticating…") is read with nmcli only while connecting.
// mako's popups are hidden meanwhile (mode netpanel-open), as before.
//
// The bar (TopBar.qml) toggles them from the pills and from
// BarState.panelRequested("network", wifi|bluetooth), i.e.
// `qs ipc call panels toggle network wifi|bluetooth`.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import Quickshell.Bluetooth

PanelPopup {
    id: pop
    tabBar: menuTabs                          // Ctrl+Tab / Ctrl+Shift+Tab cycle it
    TabFade { id: tabFx; key: pop.tab; active: pop.isOpen }   // soft tab swap

    // the cards' `pop: pop` would bind to their own property
    readonly property var panelRef: pop

    panelWidth: 420

    property string mode: "all"               // wifi | bluetooth | all
    property string tab: mode === "bluetooth" ? "bluetooth" : "wifi"
    readonly property bool wired: !!Stats.wiredDev
    readonly property var tabIds: mode === "bluetooth" ? ["bluetooth"]
                                : mode === "wifi" ? (wired ? ["wifi", "ethernet"] : ["wifi"])
                                : wired ? ["wifi", "bluetooth", "ethernet"] : ["wifi", "bluetooth"]
    // tint (PanelPopup's default) = the pill's colour: Bluetooth on /
    // connected, Wi-Fi accent (red offline); greys (BT off) -> accent

    // open on that tab, or close if it is already showing
    function openTab(name) {
        if (!tabIds.includes(name)) name = tabIds[0];
        if (isOpen && tab === name) { close(); return; }
        tab = name;
        open();
    }

    // ── state the cards share (survives list rebuilds) ──────────────────────
    property string expanded: ""
    property string pwFor: ""
    property var errors: ({})
    property string forgetArmed: ""
    property string stage: ""
    property string pairing: ""               // address being paired by us

    function setError(k, msg) {
        const e = Object.assign({}, errors);
        if (msg) e[k] = msg; else delete e[k];
        errors = e;
    }
    function armForget(k) { forgetArmed = k; disarm.restart(); }
    Timer { id: disarm; interval: 4000; onTriggered: pop.forgetArmed = "" }
    function launch(cmd) { close(); Theme.exec(cmd); }

    // ── actions ─────────────────────────────────────────────────────────────
    function connectNet(net, psk) {
        if (!net) return;
        setError(net.name, "");
        expanded = "";
        if (psk) net.connectWithPsk(psk); else net.connect();
    }
    function disconnectNet(net) { if (net) net.disconnect(); expanded = ""; }
    function forgetNet(net) { forgetArmed = ""; expanded = ""; if (net) net.forget(); }

    function btConnect(d) { if (d) { setError("bt:" + d.address, ""); d.connect(); } }
    function btDisconnect(d) { if (d) d.disconnect(); expanded = ""; }
    function btForget(d) { forgetArmed = ""; expanded = ""; if (d) d.forget(); }
    function btPair(d) {
        if (!d) return;
        pairing = d.address;
        d.pair();                             // blueman's agent asks to confirm
    }

    // ── open / close ────────────────────────────────────────────────────────
    onOpened: {
        expanded = ""; pwFor = ""; errors = ({}); forgetArmed = "";
        makoMode.restart();
        startScan();
        refreshLists();
    }
    // a beat late, so the other network popup closing (same mako mode)
    // can't remove it after this one added it
    Timer {
        id: makoMode
        interval: 150
        onTriggered: if (pop.isOpen) Quickshell.execDetached(["makoctl", "mode", "-a", "netpanel-open"])
    }
    onClosed2: {
        makoMode.stop();
        pwFor = "";
        wifiScanning = false;
        setBtScan(false);
        Quickshell.execDetached(["makoctl", "mode", "-r", "netpanel-open"]);
    }
    Component.onDestruction: if (isOpen) Quickshell.execDetached(["makoctl", "mode", "-r", "netpanel-open"])
    onTabChanged: {
        expanded = ""; pwFor = "";
        if (isOpen) { startScan(); refreshLists(); }
    }

    function startScan() {
        if (tab === "wifi") { setBtScan(false); wifiScanning = true; wifiScanStop.restart(); }
        else if (tab === "bluetooth") { wifiScanning = false; setBtScan(true); }
        else { wifiScanning = false; setBtScan(false); }
    }

    // ── Wi-Fi ───────────────────────────────────────────────────────────────
    readonly property var wifiDev: Stats.wifiDev
    readonly property bool wifiOn: Networking.wifiEnabled
    readonly property var wifiNet: Stats.wifiNet
    property bool wifiScanning: false
    Timer { id: wifiScanStop; interval: 30000; onTriggered: pop.wifiScanning = false }
    Binding {
        target: pop.wifiDev
        property: "scannerEnabled"
        value: pop.wifiScanning && pop.isOpen && pop.wifiOn
        when: !!pop.wifiDev
    }

    property var wifiList: []
    property string wifiKey: ""
    readonly property var busyNet: wifiList.find(n => n.state === ConnectionState.Connecting) || null

    function refreshWifi() {
        if (!wifiDev || !wifiOn) { wifiList = []; wifiKey = ""; return; }
        if (pwFor !== "") return;             // never rebuild under the typing
        const nets = wifiDev.networks.values.filter(n => n.name);
        // signal in 20 % steps, so a flickering reading doesn't reshuffle
        const rank = n => n.connected ? 2 : n.known ? 1 : 0;
        nets.sort((a, b) => rank(b) - rank(a)
                         || Math.floor(b.signalStrength * 5) - Math.floor(a.signalStrength * 5)
                         || a.name.localeCompare(b.name));
        const key = nets.map(n => n.name + ":" + rank(n)).join("|");
        if (key !== wifiKey) { wifiKey = key; wifiList = nets; }
    }

    // where NM is with a connection: only while one is being made
    Process {
        id: stageProc
        command: ["nmcli", "-t", "-f", "GENERAL.STATE", "dev", "show", pop.wifiDev ? pop.wifiDev.name : "wlan0"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = /GENERAL\.STATE:(\d+)/.exec(text);
                const stages = { 30: "starting", 40: "preparing", 50: "configuring", 60: "authenticating",
                                 70: "getting an address", 80: "checking", 90: "finishing" };
                pop.stage = m && stages[m[1]] ? stages[m[1]] : "";
            }
        }
    }
    Timer {
        interval: 600
        repeat: true
        running: pop.isOpen && !!pop.busyNet
        triggeredOnStart: true
        onTriggered: if (!stageProc.running) stageProc.running = true
        onRunningChanged: if (!running) pop.stage = ""
    }

    // ── Bluetooth ───────────────────────────────────────────────────────────
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool btOn: !!adapter && adapter.enabled
    property bool btScanning: false
    property bool btStarted: false            // we own a discovery session (BlueZ is per client)
    function setBtScan(on) {
        if (on === btScanning) return;
        btScanning = on;
        if (on) btScanStop.restart(); else btScanStop.stop();
        if (!adapter || !adapter.enabled) { btStarted = false; return; }
        if (on && !adapter.discovering) { adapter.discovering = true; btStarted = true; }
        else if (!on && btStarted) { adapter.discovering = false; btStarted = false; }
    }
    Timer { id: btScanStop; interval: 20000; onTriggered: pop.setBtScan(false) }
    onBtOnChanged: if (btOn && isOpen && tab === "bluetooth") { btScanning = false; setBtScan(true); }

    readonly property var btConnected: (Bluetooth.devices ? Bluetooth.devices.values : []).filter(d => d.connected)
    property var btList: []
    property string btKey: ""
    function refreshBt() {
        if (!btOn) { btList = []; btKey = ""; return; }
        const all = Bluetooth.devices ? Bluetooth.devices.values : [];
        const mac = /^([0-9A-F]{2}[-:]){5}[0-9A-F]{2}$/i;
        const rank = d => d.connected ? 3 : (d.paired || d.bonded) ? 2 : 1;
        const devs = all.filter(d => d.connected || d.paired || d.bonded
                                 || (d.name && !mac.test(d.name) && (adapter.discovering || d.pairing)));
        devs.sort((a, b) => rank(b) - rank(a) || (a.name || "").localeCompare(b.name || ""));
        const key = devs.map(d => d.address + ":" + rank(d)).join("|");
        if (key !== btKey) { btKey = key; btList = devs; }
    }

    function refreshLists() {
        if (tabIds.includes("wifi")) refreshWifi();
        if (tabIds.includes("bluetooth")) refreshBt();
    }
    Timer {
        interval: 1500
        repeat: true
        running: pop.isOpen
        onTriggered: pop.refreshLists()
    }
    onPwForChanged: if (pwFor === "") refreshWifi()
    onWifiOnChanged: refreshWifi()

    // ── layout ──────────────────────────────────────────────────────────────
    Column {
        width: parent.width
        spacing: 12

        Segmented {
            id: menuTabs
            visible: pop.tabIds.length > 1
            width: parent.width
            readonly property var names: ({ wifi: "\u{f05a9}  Wi-Fi", bluetooth: "\u{f00af}  Bluetooth", ethernet: "\u{f0200}  Ethernet" })
            options: pop.tabIds.map(t => names[t])
            currentIndex: Math.max(0, pop.tabIds.indexOf(pop.tab))
            accent: pop.tint
            onSelected: i => pop.tab = pop.tabIds[i]
            opacity: Math.min(1, pop.intro * 2)
        }

        // ── header: orb + state + controls ──────────────────────────────────
        Item {
            id: header
            width: parent.width
            height: 120
            readonly property real t: Math.min(1, Math.max(0, pop.intro * 2 - 0.25))
            opacity: t
            transform: Translate { y: 12 * (1 - header.t) }

            readonly property var btFirst: pop.btConnected.length ? pop.btConnected[0] : null

            NetOrb {
                id: orb
                anchors.verticalCenter: parent.verticalCenter
                x: -4
                tint: pop.tint
                icon: pop.tab === "wifi" ? (!pop.wifiOn ? "\u{f092e}" : pop.wifiNet ? "\u{f0928}" : "\u{f092f}")
                    : pop.tab === "bluetooth" ? (!pop.btOn ? "\u{f00b2}" : header.btFirst ? "\u{f00b1}" : "\u{f00af}")
                    : "\u{f0200}"
                hoverIcon: pop.tab === "wifi" ? "\u{f05aa}" : pop.tab === "bluetooth" ? "\u{f00b2}" : ""
                active: pop.tab === "wifi" ? !!pop.wifiNet : pop.tab === "bluetooth" ? !!header.btFirst : pop.wired
                busy: pop.tab === "wifi" ? !!pop.busyNet
                    : pop.tab === "bluetooth" && pop.btList.some(d => d.pairing || d.state === BluetoothDeviceState.Connecting)
                level: pop.tab === "wifi" && pop.wifiNet ? Stats.signal / 100 : -1
                holdable: pop.tab === "wifi" ? !!pop.wifiNet : pop.tab === "bluetooth" && !!header.btFirst
                onHeld: {
                    if (pop.tab === "wifi") pop.disconnectNet(pop.wifiNet);
                    else if (pop.tab === "bluetooth") pop.btDisconnect(header.btFirst);
                }
            }

            Column {
                anchors { left: orb.right; leftMargin: 12; right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 3

                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: pop.tab === "wifi" ? (!pop.wifiOn ? "Wi-Fi is off" : Stats.essid || "Not connected")
                        : pop.tab === "bluetooth" ? (!pop.btOn ? "Bluetooth is off"
                                                    : header.btFirst ? header.btFirst.name : "Nothing connected")
                        : Stats.ifname
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: 16
                    font.weight: Font.Bold
                }
                Text {
                    width: parent.width
                    elide: Text.ElideRight
                    text: orb.hovered && orb.holdable ? "Hold the orb to disconnect"
                        : pop.tab === "wifi" ? (pop.busyNet ? "Connecting to " + pop.busyNet.name + "…"
                                               : pop.wifiNet ? "Connected · " + Stats.signal + "% signal"
                                               : pop.wifiOn ? "Pick a network below" : "Turn it on to connect")
                        : pop.tab === "bluetooth" ? (!pop.btOn ? "Turn it on to connect"
                                                    : pop.btConnected.length > 1 ? pop.btConnected.length + " devices connected"
                                                    : header.btFirst ? "Connected" + (header.btFirst.batteryAvailable
                                                        ? " · battery " + Math.round(header.btFirst.battery * 100) + "%" : "")
                                                    : "Pick a device below")
                        : "Connected" + (Stats.wiredDev && Stats.wiredDev.linkSpeed ? " · " + Stats.wiredDev.linkSpeed + " Mb/s" : "")
                    color: orb.hovered && orb.holdable ? Theme.red : pop.tint
                    font.family: Theme.font
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
                Text {
                    visible: pop.tab !== "bluetooth" && (pop.tab === "ethernet" || !!pop.wifiNet)
                    width: parent.width
                    elide: Text.ElideRight
                    text: "\u{f0a5f} " + (Stats.ipaddr || "no address yet")
                        + "   \u{f01da} " + Stats.bits(Stats.rxBps) + " \u{f0552} " + Stats.bits(Stats.txBps)
                    color: Theme.overlay1
                    font.family: Theme.font
                    font.pixelSize: 11
                }
                Text {
                    visible: pop.tab === "bluetooth" && pop.btOn
                    width: parent.width
                    elide: Text.ElideRight
                    text: "\u{f0322} " + (pop.adapter ? pop.adapter.name : "")
                    color: Theme.overlay1
                    font.family: Theme.font
                    font.pixelSize: 11
                }

                Item { width: 1; height: 5 }

                Row {
                    visible: pop.tab !== "ethernet"
                    spacing: 8
                    Toggle {
                        anchors.verticalCenter: parent.verticalCenter
                        accent: pop.tint
                        checked: pop.tab === "wifi" ? pop.wifiOn : pop.btOn
                        onToggled: v => {
                            if (pop.tab === "wifi") Networking.wifiEnabled = v;
                            else if (pop.adapter) pop.adapter.enabled = v;
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: pop.tab === "wifi" ? "Wi-Fi" : "Bluetooth"
                        color: Theme.subtext0
                        font.family: Theme.font
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                    }
                    Item { width: 6; height: 1 }
                    IconBtn {
                        id: scanBtn
                        anchors.verticalCenter: parent.verticalCenter
                        readonly property bool on: pop.tab === "wifi" ? pop.wifiScanning : pop.btScanning
                        enabled: pop.tab === "wifi" ? pop.wifiOn : pop.btOn
                        size: 30
                        icon: "\u{f0450}"              // md-refresh
                        text: on ? "Scanning" : "Scan"
                        active: on
                        activeFg: pop.tint
                        tip: pop.tab === "wifi" ? "Rescan (every 10 s for 30 s)" : "Look for devices (20 s)"
                        onClicked: {
                            if (pop.tab === "wifi") { pop.wifiScanning = true; wifiScanStop.restart(); }
                            else { pop.btScanning = false; pop.setBtScan(true); }
                        }
                    }
                }
            }
        }

        // ── list ────────────────────────────────────────────────────────────
        Item {
            id: listBox
            visible: pop.tab !== "ethernet"
            width: parent.width
            height: listHead.height + 6 + flick.height
            readonly property real t: Math.min(1, Math.max(0, pop.intro * 2 - 0.5))
            opacity: t * tabFx.value
            transform: Translate { y: 16 * (1 - listBox.t) + 8 * (1 - tabFx.value) }

            Row {
                id: listHead
                width: parent.width
                height: 18
                spacing: 8
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: (pop.tab === "wifi" ? "NETWORKS" : "DEVICES") + "  ·  "
                        + (pop.tab === "wifi" ? pop.wifiList.length : pop.btList.length)
                    color: Theme.overlay1
                    font.family: Theme.font
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    font.letterSpacing: 1.2
                }
                NetDots {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: scanBtn.on && scanBtn.enabled
                    color: Theme.overlay1
                    size: 3
                }
            }

            Flickable {
                id: flick
                y: listHead.height + 6
                width: parent.width
                height: Math.min(contentHeight, 330)
                contentHeight: list.height
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height

                Column {
                    id: list
                    width: flick.width
                    spacing: 7

                    Repeater {
                        model: pop.tab === "wifi" ? pop.wifiList : []
                        NetWifiCard {
                            required property var modelData
                            net: modelData
                            pop: panelRef
                        }
                    }
                    Repeater {
                        model: pop.tab === "bluetooth" ? pop.btList : []
                        BtDeviceCard {
                            id: btCard
                            required property var modelData
                            dev: modelData
                            pop: panelRef
                            // after a pairing we started: trust it, connect it
                            Connections {
                                target: btCard.dev
                                function onPairedChanged() {
                                    const d = btCard.dev;
                                    if (d && d.paired && pop.pairing === d.address) {
                                        pop.pairing = "";
                                        d.trusted = true;
                                        d.connect();
                                    }
                                }
                            }
                        }
                    }

                    // empty states
                    Text {
                        visible: (pop.tab === "wifi" ? pop.wifiList.length : pop.btList.length) === 0
                        width: parent.width
                        height: 60
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: pop.tab === "wifi" ? (!pop.wifiOn ? "Wi-Fi is off" : pop.wifiScanning ? "Looking for networks…" : "No networks — press Scan")
                            : !pop.btOn ? "Bluetooth is off" : pop.btScanning ? "Looking for devices…" : "No devices — press Scan"
                        color: Theme.overlay0
                        font.family: Theme.font
                        font.pixelSize: 12
                    }
                }
            }

            // more below: a fade at the bottom edge
            Rectangle {
                visible: flick.contentHeight > flick.height && !flick.atYEnd
                anchors { left: flick.left; right: flick.right; bottom: flick.bottom }
                height: 26
                gradient: Gradient {
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 1; color: Theme.panel(Theme.mantle) }
                }
            }
        }

        // ── footer ──────────────────────────────────────────────────────────
        Row {
            spacing: 8
            opacity: Math.min(1, Math.max(0, pop.intro * 2 - 0.7))
            IconBtn {
                icon: "\u{f0493}"                      // md-cog
                text: pop.tab === "bluetooth" ? "Bluetooth settings" : "Network settings"
                onClicked: pop.launch(pop.tab === "bluetooth" ? "blueman-manager" : "nm-connection-editor")
            }
            IconBtn {
                visible: pop.tab === "wifi"
                icon: "\u{f0415}"                      // md-plus
                text: "Hidden / enterprise"
                tip: "Set up a hidden or 802.1X network in the connection editor"
                onClicked: pop.launch("nm-connection-editor --create --type=802-11-wireless")
            }
        }
    }
}
