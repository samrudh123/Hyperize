#!/bin/bash
# Bottom-bar power profile widget (power-profiles-daemon).
#
#   power-profile.sh status   JSON for waybar (polled by custom/powerprofile)
#   power-profile.sh next     cycle power-saver -> balanced -> performance

cur=$(powerprofilesctl get 2>/dev/null)

case "$1" in
    next)
        case "$cur" in
            power-saver) powerprofilesctl set balanced ;;
            balanced)    powerprofilesctl set performance ;;
            *)           powerprofilesctl set power-saver ;;
        esac
        ;;
    status|*)
        case "$cur" in
            power-saver) icon="󰌪"; label="saver" ;;
            performance) icon="󰓅"; label="performance" ;;
            balanced)    icon="󰾅"; label="balanced" ;;
            *)           icon="?"; label="unknown"; cur="unknown" ;;
        esac
        printf '{"text":"%s  %s","class":"%s","tooltip":"Power profile: %s\\nClick to switch"}\n' \
            "$icon" "$label" "$cur" "$cur"
        ;;
esac
