pragma Singleton
// (pragma first: Quickshell stops scanning for it at the first "{", and
// the notes below have braces)

// What each mouse button does on each bar pill — Settings › Pills edits it.
//
//   catalog   every clickable pill: id, name, icon, bar, the actions it can
//             do ([[actionId, label], …], "none" included) and its default
//             { left, right, middle } (what it did before this existed)
//   overrides ~/.config/quickshell/pill-clicks.json — only the differences
//             from the defaults, { pill: { left|right|middle: actionId } };
//             watched, so a change applies at once (no restart)
//
//   PillClicks.action("cpu", Qt.RightButton)        -> "btop"
//   PillClicks.dispatch("cpu", button, { panel: () => …, btop: () => … })
//   PillClicks.hint("cpu")   -> "Click: CPU panel · Right-click: btop"
//   PillClicks.set(pill, "left", id) · reset(pill) · resetAll()
//
// SCROLL too (key "scroll"): every pill can take one of the shared scroll
// actions (volume, mic level, brightness, workspace — run here) or one of
// its own (`scroll: [[id, label]]` in the catalog, e.g. the player's seek,
// run from the pill's table). Pill.qml calls scroll(pillId, dir, table).
//
// Each pill keeps its own action table (id -> function); this only decides
// which id a button means.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

Singleton {
    id: root

    readonly property var buttons: ["left", "right", "middle"]
    readonly property var keys: ["left", "right", "middle", "scroll"]
    readonly property var buttonNames: ({ left: "Click", right: "Right-click", middle: "Middle-click", scroll: "Scroll" })
    // what scrolling can do, PER PILL — only what fits the pill (no volume
    // on the clipboard); a pill not listed scrolls nothing and Settings ›
    // Pills hides its Scroll row
    readonly property var scrollOptions: ({
        audio: [["volume", "Volume ±5 %"]],
        mic: [["mic", "Mic level ±5 %"]],
        brightness: [["brightness", "Brightness ±5 %"], ["nightk", "Night light warmer / cooler"]],
        player: [["seek", "Seek ±5 s"], ["volume", "Volume ±5 %"]],
        players: [["volume", "Volume ±5 %"]],
        clock: [["month", "Page the calendar (while open)"]],
        window: [["workspace", "Switch workspace"]],
        battery: [["profile", "Power profile up / down"]],
        profile: [["profile", "Power profile up / down"]]
    })
    function hasScroll(pill) { return (scrollOptions[pill] || []).length > 0; }
    // per pill: what it scrolled before this existed
    readonly property var scrollDefaults: ({ audio: "volume", mic: "mic", brightness: "brightness",
                                             clock: "month", player: "seek" })


    readonly property var catalog: [
        // ── top bar ──
        { id: "apps", bar: "top", name: "Apps", icon: "\u{f003b}",
          actions: [["grid", "App grid"], ["run", "Run by name (fuzzel)"], ["none", "Nothing"]],
          def: { left: "grid", right: "run", middle: "none" } },
        { id: "capture", bar: "top", name: "Camera (screenshots & recording)", icon: "\u{f0d5d}",
          actions: [["panel", "Capture panel"], ["region", "Region screenshot"], ["window", "Window screenshot"],
                    ["screen", "Screen screenshot"], ["record", "Start / stop recording"], ["none", "Nothing"]],
          def: { left: "panel", right: "region", middle: "record" } },
        { id: "clipboard", bar: "top", name: "Clipboard", icon: "\u{f0a38}",
          actions: [["panel", "Clipboard panel"], ["none", "Nothing"]],
          def: { left: "panel", right: "none", middle: "none" } },
        { id: "cpu", bar: "top", name: "CPU", icon: "\u{f0ee0}",
          actions: [["panel", "CPU panel"], ["btop", "btop"], ["resources", "Resources app"], ["none", "Nothing"]],
          def: { left: "panel", right: "btop", middle: "none" } },
        { id: "mem", bar: "top", name: "Memory", icon: "\u{f035b}",
          actions: [["panel", "Memory panel"], ["btop", "btop"], ["resources", "Resources app"], ["none", "Nothing"]],
          def: { left: "panel", right: "btop", middle: "none" } },
        { id: "temp", bar: "top", name: "Temperature", icon: "\u{f050f}",
          actions: [["panel", "Temperature panel"], ["btop", "btop"], ["resources", "Resources app"], ["none", "Nothing"]],
          def: { left: "panel", right: "btop", middle: "none" } },
        { id: "window", bar: "top", name: "Window state", icon: "\u{f10ac}",
          actions: [["float", "Float / tile"], ["pin", "Pin / unpin"], ["fullscreen", "Fullscreen"],
                    ["maximise", "Maximise"], ["close", "Close the window"], ["panel", "Window panel"], ["none", "Nothing"]],
          def: { left: "float", right: "panel", middle: "fullscreen" } },
        { id: "audio", bar: "top", name: "Sound", icon: "\u{f057e}",
          actions: [["panel", "Sound panel"], ["mute", "Mute / unmute"], ["mixer", "Mixer (pavucontrol)"], ["none", "Nothing"]],
          def: { left: "panel", right: "mute", middle: "none" } },
        { id: "mic", bar: "top", name: "Microphone", icon: "\u{f036c}",
          actions: [["panel", "Microphone panel"], ["mute", "Mute / unmute"], ["mixer", "Mixer — inputs"], ["none", "Nothing"]],
          def: { left: "panel", right: "mute", middle: "mixer" } },
        { id: "brightness", bar: "top", name: "Brightness", icon: "\u{f06e8}",
          actions: [["panel", "Brightness panel"], ["night", "Night light on / off"], ["nightcycle", "Night light warmer / cooler"],
                    ["half", "Set 50 %"], ["none", "Nothing"]],
          def: { left: "panel", right: "night", middle: "nightcycle" } },
        { id: "display", bar: "top", name: "Display (external screen)", icon: "\u{f0379}",
          actions: [["menu", "Display menu"], ["toggle", "Duplicate ⇄ extend"], ["settings", "Display settings"], ["none", "Nothing"]],
          def: { left: "menu", right: "none", middle: "toggle" } },
        { id: "network", bar: "top", name: "Wi-Fi", icon: "\u{f0928}",
          actions: [["panel", "Wi-Fi panel"], ["editor", "Connection editor"], ["settings", "Network settings"], ["none", "Nothing"]],
          def: { left: "panel", right: "none", middle: "none" } },
        { id: "bluetooth", bar: "top", name: "Bluetooth", icon: "\u{f00af}",
          actions: [["panel", "Bluetooth panel"], ["blueman", "Blueman"], ["power", "Bluetooth on / off"], ["none", "Nothing"]],
          def: { left: "panel", right: "none", middle: "none" } },
        { id: "battery", bar: "top", name: "Battery", icon: "\u{f0079}",
          actions: [["panel", "Battery panel"], ["profile", "Next power profile"], ["settings", "Power settings"], ["none", "Nothing"]],
          def: { left: "panel", right: "none", middle: "none" } },
        { id: "clock", bar: "top", name: "Clock", icon: "\u{f0954}",
          actions: [["calendar", "Calendar"], ["date", "Time ⇄ date"], ["tasks", "Tasks panel"], ["none", "Nothing"]],
          def: { left: "calendar", right: "date", middle: "none" } },
        { id: "bell", bar: "top", name: "Notifications", icon: "\u{f009a}",
          actions: [["panel", "Notifications"], ["dnd", "Do not disturb"], ["phone", "Phone notifications"], ["none", "Nothing"]],
          def: { left: "panel", right: "dnd", middle: "none" } },
        { id: "settings", bar: "top", name: "Settings", icon: "\u{f0493}",
          actions: [["settings", "Settings"], ["gnome", "GNOME Settings"], ["none", "Nothing"]],
          def: { left: "settings", right: "gnome", middle: "none" } },
        { id: "power", bar: "top", name: "Power", icon: "\u{f0425}",
          actions: [["panel", "Power panel"], ["lock", "Lock"], ["none", "Nothing"]],
          def: { left: "panel", right: "none", middle: "none" } },
        // ── bottom bar ──
        { id: "player", bar: "bottom", name: "Player (laptop & phone)", icon: "\u{f075a}",
          actions: [["playpause", "Play / pause"], ["panel", "Music panel"], ["players", "Players deck"],
                    ["next", "Next track"], ["prev", "Previous track"], ["none", "Nothing"]],
          def: { left: "playpause", right: "panel", middle: "none" } },
        { id: "players", bar: "bottom", name: "Players (⌃)", icon: "\u{f0cb8}",
          actions: [["deck", "Players deck"], ["pauseall", "Pause everything"], ["none", "Nothing"]],
          def: { left: "deck", right: "none", middle: "none" } },
        { id: "spotify", bar: "bottom", name: "Spotify login", icon: "\u{f04c7}",
          actions: [["login", "Log in"], ["none", "Nothing"]],
          def: { left: "login", right: "none", middle: "none" } },
        { id: "focus", bar: "bottom", name: "Focus timer", icon: "\u{f13ab}",
          actions: [["panel", "Timer panel"], ["toggle", "Start / pause / resume"], ["stop", "Stop"], ["none", "Nothing"]],
          def: { left: "panel", right: "toggle", middle: "stop" } },
        { id: "weather", bar: "bottom", name: "Weather", icon: "\u{f0599}",
          actions: [["panel", "Weather panel"], ["place", "Change place"], ["refresh", "Refresh"], ["none", "Nothing"]],
          def: { left: "panel", right: "place", middle: "none" } },
        { id: "phone", bar: "bottom", name: "Phone", icon: "\u{f011c}",
          actions: [["panel", "Phone panel"], ["ring", "Ring the phone"], ["notifs", "Phone notifications"], ["none", "Nothing"]],
          def: { left: "panel", right: "panel", middle: "ring" } },
        { id: "phonenotifs", bar: "bottom", name: "Phone notification count", icon: "\u{f009e}",
          actions: [["notifs", "Phone notifications"], ["panel", "Phone panel"], ["none", "Nothing"]],
          def: { left: "notifs", right: "panel", middle: "none" } },
        { id: "tailscale", bar: "bottom", name: "Tailscale", icon: "\u{f0317}",
          actions: [["panel", "Tailscale panel"], ["connect", "Connect / disconnect"], ["settings", "Tailscale settings"], ["none", "Nothing"]],
          def: { left: "panel", right: "panel", middle: "connect" } },
        { id: "downloads", bar: "bottom", name: "Downloads", icon: "\u{f01da}",
          actions: [["menu", "Downloads panel"], ["pause", "Pause / resume all"], ["fuzzel", "Downloads menu (fuzzel)"], ["none", "Nothing"]],
          def: { left: "menu", right: "pause", middle: "none" } },
        { id: "tasks", bar: "bottom", name: "Tasks", icon: "\u{f0131}",
          actions: [["panel", "Tasks panel"], ["add", "New task"], ["none", "Nothing"]],
          def: { left: "panel", right: "add", middle: "none" } },
        { id: "awake", bar: "bottom", name: "Keep awake", icon: "\u{f0176}",
          actions: [["toggle", "Keep awake on / off"], ["none", "Nothing"]],
          def: { left: "toggle", right: "none", middle: "none" } },
        { id: "profile", bar: "bottom", name: "Power profile", icon: "\u{f05d1}",
          actions: [["next", "Next profile"], ["battery", "Battery panel"], ["none", "Nothing"]],
          def: { left: "next", right: "none", middle: "none" } },
        { id: "wallpaper", bar: "bottom", name: "Wallpaper", icon: "\u{f02e9}",
          actions: [["toggle", "Pause / play (live wallpaper)"], ["picker", "Wallpaper picker"], ["none", "Nothing"]],
          def: { left: "toggle", right: "picker", middle: "none" } }
    ]

    // ── the user's changes ──────────────────────────────────────────────────
    FileView {
        id: file
        path: Quickshell.env("HOME") + "/.config/quickshell/pill-clicks.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }
    readonly property var overrides: {
        try {
            const d = JSON.parse(file.text() || "{}");
            return d && typeof d === "object" ? d : {};
        } catch (e) {
            return {};
        }
    }

    function entry(pill) { return catalog.find(c => c.id === pill) || null; }
    function buttonKey(b) {
        if (typeof b === "string") return b;
        return b === Qt.RightButton ? "right" : b === Qt.MiddleButton ? "middle" : "left";
    }
    function scrollActions(pill) {
        return (scrollOptions[pill] || []).concat([["none", "Nothing"]]);
    }
    function scrollAction(pill) {
        const o = overrides[pill];
        const d = scrollDefaults[pill] || "none";
        if (o && o.scroll !== undefined && scrollActions(pill).some(a => a[0] === o.scroll)) return o.scroll;
        return d;
    }
    function defaultOf(pill, key) {
        if (key === "scroll") return scrollDefaults[pill] || "none";
        const e = entry(pill);
        return e ? e.def[key] : "none";
    }
    // one wheel step (dir: +1 up / -1 down) on a pill
    function scroll(pill, dir, table) {
        const id = scrollAction(pill);
        if (table && typeof table[id] === "function") table[id](dir);
        else runScroll(id, dir);
    }
    PwObjectTracker { objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource] }
    function step(node, dir) {
        if (node && node.audio) node.audio.volume = Math.max(0, Math.min(1, Math.round(node.audio.volume * 20 + dir) / 20));
    }
    function runScroll(id, dir) {
        if (id === "volume") step(Pipewire.defaultAudioSink, dir);
        else if (id === "mic") step(Theme.micSource(Pipewire.defaultAudioSource), dir);
        else if (id === "brightness") {
            Theme.exec(Theme.hypr + "/brightness.sh " + (dir > 0 ? "up" : "down") + " 5");
            Stats.refreshBacklight();
        } else if (id === "workspace")
            Quickshell.execDetached([Theme.hypr + "/workspace-scroll.sh", dir > 0 ? "prev" : "next"]);
        else if (id === "nightk") {
            // up = cooler, down = warmer, 250 K a notch (only while it is on)
            const n = (nightFile.text() || "off 3500").trim().split(/\s+/);
            if (n[0] !== "on") return;
            const k = Math.max(1500, Math.min(6500, (Number(n[1]) || 3500) + (dir > 0 ? 250 : -250)));
            Theme.exec(Theme.hypr + "/night-light.sh set " + k);
        } else if (id === "profile") {
            // up = more power, down = more saving (power-profiles-daemon)
            const bus = "org.freedesktop.UPower.PowerProfiles /org/freedesktop/UPower/PowerProfiles org.freedesktop.UPower.PowerProfiles ActiveProfile";
            const pick = dir > 0 ? "power-saver) t=balanced;; *) t=performance;;"
                                 : "performance) t=balanced;; *) t=power-saver;;";
            Quickshell.execDetached(["sh", "-c", "c=$(busctl --system get-property " + bus + " | cut -d'\"' -f2); "
                                     + "case \"$c\" in " + pick + " esac; busctl --system set-property " + bus + " s \"$t\""]);
        }
    }
    FileView {
        id: nightFile
        path: Theme.hypr + "/night-light"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
    }

    function action(pill, button) {
        const b = buttonKey(button);
        const o = overrides[pill];
        const e = entry(pill);
        if (o && o[b] !== undefined && (!e || e.actions.some(a => a[0] === o[b]))) return o[b];
        return e ? e.def[b] : "none";
    }
    function label(pill, id, key) {
        if (key === "scroll") {
            const s = scrollActions(pill).find(x => x[0] === id);
            return s ? s[1] : id;
        }
        const e = entry(pill);
        const a = e ? e.actions.find(x => x[0] === id) : null;
        return a ? a[1] : id;
    }
    // run the pill's function for what `button` means now
    function dispatch(pill, button, table) {
        const f = table[action(pill, button)];
        if (typeof f === "function") f();
    }
    // "Click: CPU panel · Right-click: btop" (buttons that do nothing left out)
    function hint(pill) {
        const parts = buttons.filter(b => action(pill, b) !== "none")
                             .map(b => buttonNames[b] + ": " + label(pill, action(pill, b)));
        const s = scrollAction(pill);
        if (s !== "none") parts.push("Scroll: " + label(pill, s, "scroll").replace(/ ±.*$/, "").toLowerCase());
        return parts.join(" · ");
    }
    // the same, dimmed, after a <br> — for the pills' tooltips
    function hintLine(pill) {
        const h = hint(pill);
        return h ? "<br><font color='" + Theme.overlay2 + "'>" + h + "</font>" : "";
    }
    function changed(pill) {
        const o = overrides[pill];
        return !!o && Object.keys(o).some(b => o[b] !== defaultOf(pill, b));
    }

    function write(all) {
        const clean = {};
        for (const p in all) {
            const e = entry(p);
            if (!e) continue;
            const keep = {};
            for (const b of keys)
                if (all[p][b] !== undefined && all[p][b] !== defaultOf(p, b)) keep[b] = all[p][b];
            if (Object.keys(keep).length) clean[p] = keep;
        }
        file.setText(JSON.stringify(clean, null, 2) + "\n");
    }
    function set(pill, button, id) {
        const all = JSON.parse(JSON.stringify(overrides));
        const b = buttonKey(button);
        all[pill] = Object.assign({}, all[pill] || {});
        all[pill][b] = id;
        write(all);
    }
    function reset(pill) {
        const all = JSON.parse(JSON.stringify(overrides));
        delete all[pill];
        write(all);
    }
    function resetAll() { write({}); }

    // `qs ipc call pillclicks …` — for testing / scripts
    IpcHandler {
        target: "pillclicks"
        function get(pill: string, button: string): string { return button === "scroll" ? root.scrollAction(pill) : root.action(pill, button); }
        function hint(pill: string): string { return root.hint(pill); }
        function set(pill: string, button: string, id: string): void { root.set(pill, button, id); }
        function reset(pill: string): void { root.reset(pill); }
        function resetAll(): void { root.resetAll(); }
    }
}
