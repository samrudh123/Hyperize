// Frost on a panel (PanelPopup's card, winter theme): ice feathers growing in
// from the corners and along the edges, faint in the middle. Static.
// Compile: /usr/lib/qt6/bin/qsb --qt6 -o frost.frag.qsb frost.frag
#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;
    float seed;
    float strength;      // 0..1
    float radius;        // the card's corner radius (nothing outside it)
    vec4 frostColor;
};

// "hash without sine" (Dave Hoskins): no visible grid at screen-size coords
float hash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}
float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash(i), b = hash(i + vec2(1.0, 0.0)), c = hash(i + vec2(0.0, 1.0)), d = hash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
float fbm(vec2 p) {
    float v = 0.0, a = 0.5;
    for (int i = 0; i < 4; i++) { v += a * noise(p); p *= 2.07; a *= 0.5; }
    return v;
}

// ice needles: one per cell, pointing away from the nearest corner (±45°),
// a thin bright line with a fainter barb across it
float needles(vec2 p, float cell, float sd, vec2 corner) {
    float a = 0.0;
    vec2 id = floor(p / cell);
    for (int dy = -1; dy <= 1; dy++)
    for (int dx = -1; dx <= 1; dx++) {
        vec2 cid = id + vec2(float(dx), float(dy));
        float h = hash(cid + sd);
        vec2 c = (cid + vec2(hash(cid + sd + 1.3), hash(cid + sd + 2.7))) * cell;
        vec2 rd = c - corner;
        float ang = atan(rd.y, rd.x) + (h - 0.5) * 1.6;
        vec2 d = vec2(cos(ang), sin(ang));
        float L = cell * (0.7 + 1.1 * hash(cid + sd + 4.1));
        vec2 pa = p - (c - d * L * 0.5);
        float t = clamp(dot(pa, d), 0.0, L);
        float dist = length(pa - d * t);
        float line = smoothstep(1.0, 0.15, dist) * (1.0 - 0.6 * t / L);
        // a barb at 60° from the needle's middle
        vec2 d2 = vec2(cos(ang + 1.05), sin(ang + 1.05));
        vec2 pb = p - (c - d * L * 0.1);
        float t2 = clamp(dot(pb, d2), 0.0, L * 0.35);
        float barb = smoothstep(0.8, 0.1, length(pb - d2 * t2)) * 0.6;
        a = max(a, max(line, barb) * (0.45 + 0.55 * h));
    }
    return a;
}

void main() {
    vec2 px = qt_TexCoord0 * itemSize;
    // the nearest corner and how far in the frost reaches there
    vec2 corner = vec2(px.x < itemSize.x * 0.5 ? 0.0 : itemSize.x, px.y < itemSize.y * 0.5 ? 0.0 : itemSize.y);
    vec2 dc = min(px, itemSize - px);
    float cd = length(dc);
    float edge = min(dc.x, dc.y);
    float n = fbm(px * 0.02 + seed);
    float reachC = 85.0 + 55.0 * n;
    float reachE = 6.0 + 16.0 * n;
    float zone = max(smoothstep(reachC, 0.0, cd), smoothstep(reachE, 0.0, edge) * 0.6);
    // a soft frosted haze with a fine grain …
    float grain = noise(px * 0.9 + seed) * 0.5 + 0.5;
    float haze = zone * zone * (0.30 + 0.12 * grain);
    // … and needles, denser toward the corner
    float nd = needles(px, 15.0, seed, corner) * smoothstep(0.15, 0.75, zone)
             + needles(px, 7.0, seed + 9.0, corner) * smoothstep(0.35, 0.95, zone) * 0.7;
    float a = clamp(haze + nd * 0.75, 0.0, 1.0) * strength * frostColor.a;
    // inside the rounded card only
    vec2 hs = itemSize * 0.5;
    vec2 q = abs(px - hs) - (hs - vec2(radius));
    float sdf = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
    a *= smoothstep(0.5, -0.8, sdf);
    fragColor = vec4(frostColor.rgb * a, a) * qt_Opacity;
}
