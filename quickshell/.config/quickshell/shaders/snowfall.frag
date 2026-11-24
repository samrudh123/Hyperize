// Falling snow — WinterOverlay.qml (the winter theme). Procedural: the screen
// is cut into cells per depth layer, a cell holds at most one flake (a hash
// says whether, where, how big), and the layers slide down at their own
// speed (parallax), sideways with the wind (drift) and each flake sways.
// Near the pointer the flakes part around it (Festivitas-style): each pixel
// looks the flake up at the position the push would have moved it from,
// inside `hole` there is none.
// Compile after editing:
//   /usr/lib/qt6/bin/qsb --qt6 -o snowfall.frag.qsb snowfall.frag
// then RESTART qs (a .qsb is cached by its path; a hot reload keeps the old).
#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;
    float t;             // seconds (wrapped)
    float drift;         // wind, integrated: px a speed-60 flake has moved sideways
    float density;       // 1 = normal
    vec2 cursor;         // pointer in item px (far away = none)
    float push;          // 0..1 how hard flakes part around it
    vec4 flakeColor;     // straight alpha
    vec4 rimColor;       // flake outline (light mode: darker, so it shows on white)
};

// "hash without sine" (Dave Hoskins): no visible grid at screen-size coords
float hash(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// one layer: returns (body, rim) alpha
vec2 layer(vec2 p, float cell, float speed, float size, float prob, float sway,
           float seed, float pushK, float star) {
    // part around the pointer: find where this pixel's flake came from
    vec2 d = p - cursor;
    float r = length(d);
    float R = 120.0;
    float A = 70.0 * push * pushK;
    if (A > 0.0) {
        float s = r - A * exp(-(r * r) / (R * R));
        if (s < 0.0) return vec2(0.0);
        p = cursor + (r > 0.001 ? d / r : vec2(0.0)) * s;
    }
    vec2 q = p;
    q.y -= t * speed;
    q.x -= drift * speed / 60.0;
    vec2 id = floor(q / cell);
    vec2 f = fract(q / cell);
    float h = hash(id + seed);
    if (h > prob * density) return vec2(0.0);
    vec2 c = vec2(0.25 + 0.5 * hash(id + seed + 1.7), 0.25 + 0.5 * hash(id + seed + 3.1));
    c.x += sin(t * (0.5 + h * 0.9) + h * 40.0) * sway;
    float rad = size * (0.6 + 0.8 * hash(id + seed + 5.3)) / cell;
    vec2 v = (f - c) * cell;              // px from the flake's centre
    float dist = length(v) / cell;
    if (star > 0.0 && hash(id + seed + 7.7) < star) {
        // a six-armed crystal, slowly turning
        float ang = atan(v.y, v.x) + t * (0.3 + h) ;
        float arms = abs(cos(3.0 * ang));
        float lenPx = length(v);
        float armW = 0.9 + 0.5 * (1.0 - lenPx / (rad * cell));
        float onArm = smoothstep(armW + 0.8, armW - 0.2, lenPx * sqrt(max(0.0, 1.0 - arms * arms)));
        float inR = smoothstep(rad * cell, rad * cell - 1.2, lenPx);
        float core = smoothstep(1.6, 0.6, lenPx);
        float a = max(onArm * inR, core);
        return vec2(a, 0.0);
    }
    float body = smoothstep(rad, rad * 0.25, dist);
    float rim = smoothstep(rad * 1.55, rad, dist) - body;
    return vec2(body, max(rim, 0.0));
}

void main() {
    vec2 p = qt_TexCoord0 * itemSize;
    vec2 a = vec2(0.0);
    vec2 l;
    l = layer(p, 30.0, 22.0, 1.1, 0.30, 0.15, 11.0, 0.35, 0.0); a += l * 0.50;
    l = layer(p, 46.0, 34.0, 1.6, 0.30, 0.18, 23.0, 0.60, 0.0); a += l * 0.70;
    l = layer(p, 72.0, 52.0, 2.3, 0.26, 0.18, 37.0, 0.85, 0.0); a += l * 0.88;
    l = layer(p, 130.0, 78.0, 3.4, 0.17, 0.16, 53.0, 1.00, 0.0); a += l * 0.62;
    l = layer(p, 210.0, 64.0, 7.0, 0.10, 0.12, 71.0, 1.00, 1.0); a += l * 0.85;
    float body = clamp(a.x, 0.0, 1.0);
    float rim = clamp(a.y, 0.0, 1.0) * rimColor.a;
    vec3 col = flakeColor.rgb * body + rimColor.rgb * rim;
    float alpha = clamp(body * flakeColor.a + rim, 0.0, 1.0);
    fragColor = vec4(col * flakeColor.a, alpha) * qt_Opacity;
}
