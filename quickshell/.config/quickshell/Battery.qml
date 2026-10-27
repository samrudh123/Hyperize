// Battery (UPower's display device). Same thresholds as waybar: warning at
// 25 % (peach), critical at 12 % (red pill, pulsing). Charging always wins
// over the low-battery colours — the alarm is for draining batteries only.
// Click: the battery panel (BatteryPopup.qml — health, cycles, power mode,
// brightness); `qs ipc call sysinfo toggle battery`.
import QtQuick
import Quickshell
import Quickshell.Services.UPower

Pill {
    id: bat

    readonly property var dev: UPower.displayDevice
    readonly property bool present: dev !== null && dev.ready && dev.isPresent
    readonly property int pct: present ? Math.round(dev.percentage * 100) : 0
    readonly property int st: present ? dev.state : UPowerDeviceState.Unknown
    readonly property bool charging: st === UPowerDeviceState.Charging
    readonly property bool plugged: st === UPowerDeviceState.FullyCharged || st === UPowerDeviceState.PendingCharge
    readonly property bool critical: !charging && !plugged && pct <= 12
    readonly property bool warning: !charging && !plugged && pct <= 25

    readonly property var icons: ["\u{f007a}", "\u{f007b}", "\u{f007c}", "\u{f007d}", "\u{f007e}",
                                  "\u{f007f}", "\u{f0080}", "\u{f0081}", "\u{f0082}", "\u{f0079}"]

    function hm(sec) {
        if (!sec || sec <= 0) return "";
        const h = Math.floor(sec / 3600), m = Math.round(sec % 3600 / 60);
        return h > 0 ? h + " h " + m + " min" : m + " min";
    }

    shown: present
    label: (charging ? "\u{f0084}" : plugged ? "\u{f0085}" : icons[Math.min(9, Math.floor(pct / 10))]) + " " + pct + "%"
    fg: critical ? Theme.crust : charging ? Theme.green : warning ? Theme.peach : Theme.lavender
    bg: critical ? Theme.red : "transparent"
    fillHover: true
    tip: {
        if (!present) return "";
        const t = charging ? hm(dev.timeToFull) : hm(dev.timeToEmpty);
        const what = charging ? (t ? t + " until full" : "Charging")
                   : plugged ? "Plugged in" : (t ? t + " left" : "On battery");
        return what + "  ·  " + Math.abs(dev.changeRate).toFixed(1) + " W"
             + PillClicks.hintLine("battery");
    }

    function toggleMenu() { batPop.toggle(); }
    pillId: "battery"                    // wheel: Settings › Pills
    onClicked: button => PillClicks.dispatch("battery", button, {
        panel: () => batPop.toggle(),
        profile: () => Theme.exec(Theme.hypr + "/power-profile.sh next"),
        settings: () => BarState.panelRequested("settings", "power")
    })
    BatteryPopup { id: batPop; pill: bat }

    // the critical pulse: a soft breathe rather than waybar's hard blink
    SequentialAnimation on opacity {
        running: bat.critical
        loops: Animation.Infinite
        NumberAnimation { to: 0.45; duration: 700; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
        onRunningChanged: if (!running) bat.opacity = 1
    }
}
