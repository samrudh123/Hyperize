// A snow cap: snow lying on a ledge — the top edge of a window, a bar popup's
// card, a bottom-bar island (SnowCap.qml). The item's bottom is the ledge;
// the pile rises `depth` px (lumpy along x, the lumps continuous across
// segments via `gx`), with round pillow ends (`taperL` / `taperR`, 0 = cut
// straight: the cap continues under a window above it).
// Compile: /usr/lib/qt6/bin/qsb --qt6 -o snowcap.frag.qsb snowcap.frag
#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;
    float depth;         // px of snow on top of the ledge
    float base;          // px at the item's bottom that overlap the ledge (its border)
    float gx;            // the item's x in its ledge (continuity of the lumps)
    float seed;
    float taperL;
    float taperR;
    vec4 snowColor;
    vec4 shadeColor;
    vec4 rimColor;       // outline (light mode)
};

float hash1(float n) { return fract(sin(n) * 43758.5453); }
float noise1(float x) {
    float i = floor(x), f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    return mix(hash1(i), hash1(i + 1.0), f);
}
float hash2(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

void main() {
    vec2 px = qt_TexCoord0 * itemSize;
    float x = px.x;
    float hb = itemSize.y - px.y;            // height above the item's bottom
    float g = x + gx + seed * 13.0;
    // big soft mounds, smaller lumps, a ripple
    float prof = 0.52 * noise1(g * 0.018) + 0.32 * noise1(g * 0.065 + 5.0) + 0.16 * noise1(g * 0.19 + 11.0);
    float h = depth * (0.4 + 0.8 * prof);
    float tl = taperL > 0.0 ? clamp(x / taperL, 0.0, 1.0) : 1.0;
    float tr = taperR > 0.0 ? clamp((itemSize.x - x) / taperR, 0.0, 1.0) : 1.0;
    tl = sqrt(tl * (2.0 - tl));
    tr = sqrt(tr * (2.0 - tr));
    float hh = h * min(tl, tr);
    float top = base + hh;
    float inside = smoothstep(top + 0.7, top - 0.7, hb);
    if (hh < 0.25) inside = 0.0;
    float below = top - hb;                  // px under the surface
    // light from above: bright crust, cooler toward the ledge and in the
    // hollows between mounds, a darker contact line where it meets the ledge
    float t = clamp((hb - base) / max(hh, 1.0), 0.0, 1.0);
    vec3 col = mix(shadeColor.rgb, snowColor.rgb, smoothstep(-0.25, 0.85, t));
    col = mix(col, shadeColor.rgb, (1.0 - prof) * 0.25 * (1.0 - t));
    col += vec3(0.06) * exp(-below / 1.2);
    col = mix(col, shadeColor.rgb * 0.82, smoothstep(base + 1.2, base - 0.5, hb) * 0.6);
    float sp = hash2(floor(px / 1.5) + seed);
    col += (sp > 0.982 && below > 1.0) ? vec3(0.22) : vec3(0.0);
    float a = inside * snowColor.a;
    // outline just outside the surface (shows the cap on white paper)
    float rim = smoothstep(top + 1.6, top + 0.6, hb) * (1.0 - inside) * rimColor.a;
    if (hh < 0.25) rim = 0.0;
    vec3 outc = col * a + rimColor.rgb * rim;
    fragColor = vec4(outc, clamp(a + rim, 0.0, 1.0)) * qt_Opacity;
}
