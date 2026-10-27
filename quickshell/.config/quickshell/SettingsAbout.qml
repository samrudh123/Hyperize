// Settings › About: this machine and the software the desktop runs on.
import QtQuick
import Quickshell
import Quickshell.Io

SettingsPage {
    id: page
    title: "About"
    subtitle: "This machine and the pieces of the desktop."

    property var info: ({})

    Process {
        running: true
        command: ["sh", "-c",
            "echo \"host=$(hostname)\"; echo \"user=$USER\"; " +
            ". /etc/os-release; echo \"os=$PRETTY_NAME\"; echo \"kernel=$(uname -r)\"; " +
            "echo \"hypr=$(hyprctl version -j | python3 -c 'import json,sys;print(json.load(sys.stdin)[\"tag\"])' 2>/dev/null)\"; " +
            "echo \"qs=$(~/.local/bin/qs --version 2>/dev/null | head -1 | sed 's/ (.*//')\"; " +
            "echo \"up=$(uptime -p | sed 's/^up //')\"; " +
            "echo \"cpu=$(sed -n 's/^model name\\s*: //p' /proc/cpuinfo | head -1) ($(nproc) threads)\"; " +
            "echo \"mem=$(free -h --si | awk '/^Mem/{print $3\" used of \"$2}')\"; " +
            "echo \"disk=$(df -h --output=used,size / | tail -1 | awk '{print $1\" used of \"$2}')\"; " +
            "echo \"gpu=$(lspci 2>/dev/null | sed -n 's/.*VGA compatible controller: //p' | head -1 | sed 's/ (.*//')\"; " +
            "echo \"model=$(cat /sys/class/dmi/id/product_name 2>/dev/null)\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const o = {};
                for (const l of text.split("\n")) { const i = l.indexOf("="); if (i > 0) o[l.slice(0, i)] = l.slice(i + 1); }
                page.info = o;
            }
        }
    }

    // hero
    Rectangle {
        width: parent.width
        height: 120
        radius: 16
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Theme.alpha(Theme.accent, 0.35) }
            GradientStop { position: 1; color: Theme.alpha(Theme.surface0, 0.3) }
        }
        border.width: 1
        border.color: Theme.alpha(Theme.accent, 0.35)
        Row {
            x: 22
            anchors.verticalCenter: parent.verticalCenter
            spacing: 18
            Rectangle {
                width: 70; height: 70; radius: 20
                color: Theme.accent
                Text { anchors.centerIn: parent; text: "\u{f359}"; color: Theme.crust; font.family: Theme.font; font.pixelSize: 38 }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4
                Text { text: page.info.host || "…"; color: Theme.text; font.family: Theme.font; font.pixelSize: 20; font.weight: Font.Bold }
                Text { text: (page.info.model || "") ; color: Theme.subtext0; font.family: Theme.font; font.pixelSize: 12 }
                Text { text: (page.info.os || "") + "  ·  Hyprland " + (page.info.hypr || "") + "  ·  up " + (page.info.up || ""); color: Theme.overlay1; font.family: Theme.font; font.pixelSize: 11 }
            }
        }
    }

    SettingsCard {
        title: "System"
        icon: "\u{f035b}"
        SettingsRow { icon: "\u{f0548}"; title: "Operating system"; subtitle: page.info.os || "" ; keywords: "os distro" }
        SettingsRow { icon: "\u{f033d}"; title: "Kernel"; subtitle: page.info.kernel || "" }
        SettingsRow { icon: "\u{f0ee0}"; title: "Processor"; subtitle: page.info.cpu || "" ; keywords: "cpu" }
        SettingsRow { icon: "\u{f035b}"; title: "Memory"; subtitle: page.info.mem || ""; keywords: "ram" }
        SettingsRow { icon: "\u{f02ca}"; title: "Storage (/)"; subtitle: page.info.disk || ""; keywords: "disk" }
        SettingsRow { icon: "\u{f0379}"; title: "Graphics"; subtitle: page.info.gpu || ""; keywords: "gpu"; last: true }
    }

    SettingsCard {
        title: "Desktop"
        icon: "\u{f03d8}"
        SettingsRow { icon: "\u{f359}"; title: "Compositor"; subtitle: "Hyprland " + (page.info.hypr || "") }
        SettingsRow { icon: "\u{f0c8b}"; title: "Shell"; subtitle: (page.info.qs || "Quickshell") + "  ·  ~/.config/quickshell" }
        SettingsRow { icon: "\u{f03d8}"; title: "Theme"; subtitle: Theme.themeName + "  ·  accent " + Theme.accent }
        SettingsRow { icon: "\u{f06d6}"; title: "Shell font"; subtitle: Theme.font + "  ·  apps: Settings › Appearance › Font"; keywords: "typeface"; last: true }
    }
}
