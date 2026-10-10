// Wallpaper transitions (WallpaperTransition.qml). One shader, `mode` picks
// the effect; `progress` runs 0 -> 1 (already eased in QML).
// Compile after editing:
//   /usr/lib/qt6/bin/qsb --qt6 -o transition.frag.qsb transition.frag
#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;
    float mode;
    float aspect;        // width / height
    vec2 origin;         // effect centre, 0..1 (circle / cursor / iris)
};

layout(binding = 1) uniform sampler2D fromTex;
layout(binding = 2) uniform sampler2D toTex;

// modes
const int CIRCLE = 0, CURSOR = 1, IRIS = 2, FADE = 3, WIPE = 4, WAVE = 5,
          SLIDE = 6, ZOOM = 7, DISSOLVE = 8, PIXELATE = 9, DIAMOND = 10;

vec4 sampleZoom(sampler2D t, vec2 uv, vec2 c, float s) {
    // s > 1 zooms in (shows less), s < 1 would sample outside: clamp
    return texture(t, clamp(c + (uv - c) / s, 0.0, 1.0));
}

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float noise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x),
               mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y);
}

// distance from the origin to the farthest corner, aspect-corrected
float maxRadius(vec2 o) {
    vec2 a = vec2(aspect, 1.0);
    float d = 0.0;
    d = max(d, length((vec2(0, 0) - o) * a));
    d = max(d, length((vec2(1, 0) - o) * a));
    d = max(d, length((vec2(0, 1) - o) * a));
    d = max(d, length((vec2(1, 1) - o) * a));
    return d;
}

void main() {
    vec2 uv = qt_TexCoord0;
    float p = clamp(progress, 0.0, 1.0);
    int m = int(mode + 0.5);
    vec2 a = vec2(aspect, 1.0);
    vec4 col;

    if (m == CIRCLE || m == CURSOR) {
        // a circle opens from the origin; inside it the new wallpaper zooms
        // OUT to rest (1.18 -> 1), the old one recedes and dims behind it
        float r = p * (maxRadius(origin) + 0.02);
        float d = length((uv - origin) * a);
        float edge = 0.006;
        float inside = 1.0 - smoothstep(r - edge, r + edge, d);
        vec4 to = sampleZoom(toTex, uv, origin, mix(1.18, 1.0, p));
        vec4 from = sampleZoom(fromTex, uv, origin, mix(1.0, 1.06, p));
        from.rgb *= mix(1.0, 0.55, p);
        // a faint bright rim on the circle's edge
        float rim = (1.0 - smoothstep(0.0, 0.012, abs(d - r))) * (1.0 - p) * 0.35;
        col = mix(from, to, inside);
        col.rgb += rim;
    } else if (m == IRIS) {
        // the old wallpaper closes into a shrinking circle, pushing in as it
        // goes; the new one zooms out into place around it
        float r = (1.0 - p) * (maxRadius(origin) + 0.02);
        float d = length((uv - origin) * a);
        float inside = 1.0 - smoothstep(r - 0.006, r + 0.006, d);
        vec4 from = sampleZoom(fromTex, uv, origin, mix(1.0, 1.15, p));
        vec4 to = sampleZoom(toTex, uv, origin, mix(1.12, 1.0, p));
        to.rgb *= mix(0.6, 1.0, p);
        col = mix(to, from, inside);
    } else if (m == FADE) {
        col = mix(texture(fromTex, uv), texture(toTex, uv), p);
    } else if (m == WIPE) {
        // a soft diagonal edge sweeping left to right
        vec2 dir = normalize(vec2(1.0, 0.35));
        float t = dot(uv * a, dir) / dot(a, abs(dir));
        float w = 0.08;
        float k = smoothstep(t - w, t, p * (1.0 + w));
        col = mix(texture(fromTex, uv), texture(toTex, uv), k);
    } else if (m == WAVE) {
        // a wavy edge rising from the bottom
        float wave = 0.035 * sin(uv.x * 14.0 + p * 9.0) + 0.02 * sin(uv.x * 31.0 - p * 6.0);
        float t = (1.0 - uv.y) + wave;
        float k = smoothstep(t - 0.02, t + 0.02, p * 1.16 - 0.04);
        col = mix(texture(fromTex, uv), texture(toTex, uv), k);
    } else if (m == SLIDE) {
        // the new wallpaper pushes the old one off to the left
        vec2 uf = uv + vec2(p, 0.0);
        vec2 ut = uv - vec2(1.0 - p, 0.0);
        col = uf.x <= 1.0 ? texture(fromTex, uf) : texture(toTex, ut);
        // a thin shadow on the seam
        float seam = abs(uv.x - (1.0 - p));
        col.rgb *= mix(0.7, 1.0, smoothstep(0.0, 0.03, seam));
    } else if (m == ZOOM) {
        // the old one rushes past, the new one zooms out into place
        vec4 from = sampleZoom(fromTex, uv, vec2(0.5), mix(1.0, 1.6, p));
        vec4 to = sampleZoom(toTex, uv, vec2(0.5), mix(1.35, 1.0, p));
        col = mix(from, to, smoothstep(0.25, 0.75, p));
    } else if (m == DISSOLVE) {
        float n = noise(uv * a * 9.0) * 0.65 + noise(uv * a * 40.0) * 0.35;
        float k = smoothstep(n - 0.06, n + 0.06, p * 1.12 - 0.06);
        col = mix(texture(fromTex, uv), texture(toTex, uv), k);
    } else if (m == PIXELATE) {
        // blocks grow to ~53px, swap, and shrink back
        float s = 1.0 - abs(p * 2.0 - 1.0);
        float cells = 1200.0 * pow(36.0 / 1200.0, s);   // geometric: big blocks sooner
        vec2 grid = vec2(cells * aspect, cells) / aspect;
        vec2 q = (floor(uv * grid) + 0.5) / grid;
        vec2 suv = s > 0.02 ? q : uv;
        col = mix(texture(fromTex, suv), texture(toTex, suv), smoothstep(0.4, 0.6, p));
    } else { // DIAMOND
        vec2 d = abs(uv - vec2(0.5)) * a;
        float t = (d.x + d.y) / (0.5 * aspect + 0.5);
        float k = smoothstep(t - 0.04, t + 0.04, p * 1.08);
        col = mix(texture(fromTex, uv), texture(toTex, uv), k);
    }

    fragColor = vec4(col.rgb, 1.0) * qt_Opacity;
}
