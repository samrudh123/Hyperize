#!/bin/bash
# Night light — a warm screen filter. Right-click the brightness pill on the
# top bar toggles it; middle-click cycles its strength.
#
#   night-light.sh toggle | on | off
#   night-light.sh cycle          strength 4500 K → 3500 K → 2700 K → 4500 K …
#   night-light.sh set <kelvin>   any temperature 1500–6500 (turns it on)
#   night-light.sh status         "on 3500" / "off 3500"
#
# No extra package: it is a Hyprland SCREEN SHADER that multiplies the picture
# by the white point of a <kelvin> light (Tanner Helland's blackbody fit), so
# blue drops first, then green. (hyprsunset / wlsunset / gammastep would need
# installing; this needs nothing.) The shader is written per temperature to
# ~/.cache/night-light/.
#
# State lives in ~/.config/hypr/night-light.conf, which hyprland.conf SOURCES:
# a `hyprctl reload` (set-accent.sh, config edits) or a new login therefore
# keeps the night light as it was, instead of silently dropping a keyword.
# The bar reads ~/.config/hypr/night-light ("on|off <kelvin>").

set -u

HYPR="$HOME/.config/hypr"
STATE="$HYPR/night-light"
CONF="$HYPR/night-light.conf"
SHADERS="$HOME/.cache/night-light"
DEFAULT_K=3500
STEPS=(4500 3500 2700)

read -r on kelvin < "$STATE" 2>/dev/null
[ "${on:-}" = on ] || on=off
[[ "${kelvin:-}" =~ ^[0-9]+$ ]] || kelvin=$DEFAULT_K

shader_for() {   # $1 = kelvin -> prints the shader path (written if missing)
    local k=$1 out="$SHADERS/night-light-$1K.frag"
    if [ ! -s "$out" ]; then
        mkdir -p "$SHADERS"
        read -r r g b < <(awk -v k="$k" 'BEGIN {
            t = k / 100
            if (t <= 66) r = 255; else r = 329.698727446 * (t - 60) ^ -0.1332047592
            if (t <= 66) g = 99.4708025861 * log(t) - 161.1195681661
            else g = 288.1221695283 * (t - 60) ^ -0.0755148492
            if (t >= 66) b = 255; else if (t <= 19) b = 0
            else b = 138.5177312231 * log(t - 10) - 305.0447927307
            if (r > 255) r = 255; if (g > 255) g = 255; if (b > 255) b = 255
            if (r < 0) r = 0; if (g < 0) g = 0; if (b < 0) b = 0
            printf "%.4f %.4f %.4f\n", r / 255, g / 255, b / 255 }')
        # #version first; 300 es = Hyprland's tex300.vert (OpenGL.cpp
        # applyScreenShader picks the 320 vertex shader only for "320 es")
        cat > "$out" <<EOF
#version 300 es
// night-light.sh: ${k} K. Generated — edit the script, not this file.
precision highp float;
in vec2 v_texcoord;
uniform sampler2D tex;
out vec4 fragColor;
void main() {
    vec4 c = texture(tex, v_texcoord);
    fragColor = vec4(c.rgb * vec3($r, $g, $b), c.a);
}
EOF
    fi
    printf '%s\n' "$out"
}

apply() {   # $1 = on|off, $2 = kelvin
    printf '%s %s\n' "$1" "$2" > "$STATE"
    if [ "$1" = on ]; then
        local s; s=$(shader_for "$2")
        printf '# night-light.sh (on, %s K) — generated, sourced by hyprland.conf\ndecoration {\n    screen_shader = %s\n}\n' "$2" "$s" > "$CONF"
        hyprctl keyword decoration:screen_shader "$s" >/dev/null
    else
        printf '# night-light.sh (off) — generated, sourced by hyprland.conf\n' > "$CONF"
        hyprctl keyword decoration:screen_shader "[[EMPTY]]" >/dev/null
    fi
}

case "${1:-}" in
    toggle) [ "$on" = on ] && apply off "$kelvin" || apply on "$kelvin" ;;
    on)     apply on "$kelvin" ;;
    off)    apply off "$kelvin" ;;
    cycle)
        next=${STEPS[0]}
        for i in "${!STEPS[@]}"; do
            if [ "${STEPS[$i]}" = "$kelvin" ]; then
                next=${STEPS[$(( (i + 1) % ${#STEPS[@]} ))]}
            fi
        done
        apply on "$next" ;;
    set)
        k=${2:-}
        [[ "$k" =~ ^[0-9]+$ ]] && (( k >= 1500 && k <= 6500 )) || { echo "kelvin 1500-6500" >&2; exit 2; }
        apply on "$k" ;;
    status) echo "$on $kelvin" ;;
    *) echo "usage: night-light.sh toggle|on|off|cycle|set <kelvin>|status" >&2; exit 2 ;;
esac
