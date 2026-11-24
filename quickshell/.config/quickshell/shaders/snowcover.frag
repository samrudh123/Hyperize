// The idle snow cover's picture (WinterCover.qml): left alone, the screen
// frosts over from its edges (a haze with ice needles, thickest in the
// corners) and a drift rises from the bottom until snow fills it. Drawn into
// a texture only when `level` / `frost` step; snowwipe.frag puts it on
// screen minus what the pointer wiped.
// Compile: /usr/lib/qt6/bin/qsb --qt6 -o snowcover.frag.qsb snowcover.frag
#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;
    float level;         // 0..1 drift height (1 = full)
    float frost;         // 0..1 frost reach from the edges
    float seed;
    vec4 snowColor;
    vec4 shadeColor;
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
    for (int i = 0; i < 5; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
    return v;
}
// ice needles pointing in from the nearest edge / corner (see frost.frag)
float needles(vec2 p, float cell, float sd, vec2 from) {
    float a = 0.0;
    vec2 id = floor(p / cell);
    for (int dy = -1; dy <= 1; dy++)
    for (int dx = -1; dx <= 1; dx++) {
        vec2 cid = id + vec2(float(dx), float(dy));
        float h = hash(cid + sd);
        vec2 c = (cid + vec2(hash(cid + sd + 1.3), hash(cid + sd + 2.7))) * cell;
        vec2 rd = c - from;
        float ang = atan(rd.y, rd.x) + (h - 0.5) * 1.7;
        vec2 d = vec2(cos(ang), sin(ang));
        float L = cell * (0.7 + 1.2 * hash(cid + sd + 4.1));
        vec2 pa = p - (c - d * L * 0.5);
        float t = clamp(dot(pa, d), 0.0, L);
        float line = smoothstep(1.1, 0.15, length(pa - d * t)) * (1.0 - 0.6 * t / L);
        vec2 d2 = vec2(cos(ang + 1.05), sin(ang + 1.05));
        vec2 pb = p - (c - d * L * 0.1);
        float t2 = clamp(dot(pb, d2), 0.0, L * 0.35);
        float barb = smoothstep(0.9, 0.1, length(pb - d2 * t2)) * 0.6;
        a = max(a, max(line, barb) * (0.45 + 0.55 * h));
    }
    return a;
}

void main() {
    vec2 uv = qt_TexCoord0;
    vec2 px = uv * itemSize;
    float H = itemSize.y;
    float hb = H - px.y;

    // the drift: a lumpy surface rising from the bottom
    float bump = (fbm(vec2(px.x * 0.0035, seed)) - 0.5) * 150.0
               + (noise(vec2(px.x * 0.02, seed + 3.0)) - 0.5) * 16.0;
    float surf = level * (H + 120.0) + bump * (0.4 + 0.6 * level) - 40.0 * (1.0 - level);
    float drift = smoothstep(surf + 1.2, surf - 1.2, hb) * step(0.001, level);
    float below = surf - hb;

    // frost: from every edge, deeper in the corners
    vec2 dc = min(px, itemSize - px);
    float edge = min(dc.x, dc.y);
    float cd = length(dc);
    float n = fbm(px * 0.006 + seed);
    float reachE = frost * H * (0.10 + 0.12 * n);
    float reachC = frost * H * (0.30 + 0.22 * n);
    float zone = max(smoothstep(reachE, 0.0, edge), smoothstep(reachC, 0.0, cd)) * step(0.001, frost);
    vec2 from = edge == dc.x ? vec2(px.x < itemSize.x * 0.5 ? 0.0 : itemSize.x, px.y)
                             : vec2(px.x, px.y < H * 0.5 ? 0.0 : H);
    if (cd < reachC * 0.8) from = vec2(px.x < itemSize.x * 0.5 ? 0.0 : itemSize.x, px.y < H * 0.5 ? 0.0 : H);
    float grain = noise(px * 0.9 + seed);
    float haze = zone * zone * (0.42 + 0.14 * grain);
    float nd = 0.0;
    if (zone > 0.05)
        nd = needles(px, 22.0, seed, from) * smoothstep(0.1, 0.7, zone)
           + needles(px, 10.0, seed + 9.0, from) * smoothstep(0.3, 0.9, zone) * 0.7;
    float frostA = clamp(haze + nd * 0.7, 0.0, 1.0) * frostColor.a;

    // snow body: soft undulating shade, a bright lit crust right under the
    // surface, sparkles
    float sh = fbm(px * 0.005 + 7.0);
    float lit = exp(-max(below, 0.0) / 10.0);
    vec3 snow = mix(shadeColor.rgb, snowColor.rgb, clamp(0.35 + 0.75 * sh + 0.3 * lit, 0.0, 1.0));
    float sp = hash(floor(px / 2.0) + seed);
    snow += sp > 0.998 ? vec3(0.35) : vec3(0.0);
    float a = drift * 0.97;
    vec3 col = snow;
    if (a < frostA) { col = frostColor.rgb; a = frostA; }
    fragColor = vec4(col * a, a) * qt_Opacity;
}
