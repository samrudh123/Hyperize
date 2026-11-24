// Waves riding on top of a (straight) seek line — SeekWaves.qml. The item
// sits right above the line, its bottom edge on the line's top. Over the
// played part only (0 → playhead) three translucent sine layers rise from
// the line and sweep from the start to the playhead and back, with a swell
// riding along; full height wherever the playhead is (short tapers at the
// two ends only).
// Compile after editing:
//   /usr/lib/qt6/bin/qsb --qt6 -o seekwaves.frag.qsb seekwaves.frag
// then RESTART qs: ShaderEffect caches a .qsb by its path, so a hot reload
// keeps drawing the old one.
#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;
    float frac;          // 0..1 played
    float s0;            // sweep positions 0..1 (start → playhead) of the
    float s1;            // three layers, paced in SeekWaves.qml
    float s2;
    float amp;           // 0..1 overall height (0 = flat, nothing drawn)
    float scale;         // wavelength scale (1 = panel size)
    float crest;         // alpha of the front layer's top line
    float lambda1;       // second layer's wavelength (px at scale 1)
    float gap;           // its pattern's offset from the front's (radians)
    float third;         // 0..1 weight of the faint back layer
    float floorH;        // share of the height every layer keeps in its troughs
    vec4 waveColor;      // straight alpha
};

const float TAU = 6.28318530718;

// one layer: height above the line at x. Its pattern is shifted by sw·xs:
// sw goes 0 → 1 → 0 (start → playhead → start), paced by SeekWaves.qml
float layer(float x, float xs, float lambda, float sw, float ph, float env, float hmax) {
    // a short played part gets shorter waves, so it still holds a whole crest
    float k = TAU / min(lambda * scale, max(xs * 0.9, 6.0));
    float shift = xs * sw;
    float u = x - shift;
    float a = 0.5 + 0.5 * sin(k * u + ph);
    float b = 0.5 + 0.5 * sin(0.53 * k * u + 1.7 * ph);
    return hmax * env * (floorH + (1.0 - floorH) * a * (0.6 + 0.4 * b));
}

vec4 over(vec4 top, vec4 under) { return top + under * (1.0 - top.a); }

void main() {
    vec2 p = qt_TexCoord0 * itemSize;
    float W = itemSize.x, H = itemSize.y;
    float xs = frac * W;
    if (amp < 0.002 || p.x > xs + 1.0) { fragColor = vec4(0.0); return; }

    float up = H - p.y;                       // height above the line
    // a short taper at the start (the waves rise almost straight off the
    // line) and a long graceful one into the playhead; full height wherever
    // the playhead is, early in a song too
    float tin = min(xs * 0.12, 6.0 * scale);
    // into the playhead: a long, gentle slope that lands flat on the line
    // (smootherstep: no kink where it meets the line or the full height)
    float tout = max(min(xs * 0.3, 40.0 * scale), 1.0);
    float q = clamp((xs - p.x) / tout, 0.0, 1.0);
    float landing = q * q * q * (q * (q * 6.0 - 15.0) + 10.0);
    float env = smoothstep(0.0, tin, p.x) * landing;
    // a swell riding the front layer's sweep: start → playhead → start
    float pos = xs * s0;
    float sw = max(xs * 0.35, 12.0 * scale);
    float swell = 0.85 + 0.15 * exp(-pow((p.x - pos) / sw, 2.0));
    float hmax = H * amp * swell;

    float h0 = layer(p.x, xs, 52.0, s0, 0.0, env, hmax);          // front
    float h1 = layer(p.x, xs, lambda1, s1, gap, env, hmax * 0.85);
    float h2 = layer(p.x, xs, 80.0, s2, 4.2, env, hmax * 0.7 * third);

    vec3 c = waveColor.rgb;
    float A = waveColor.a;
    // fill: strong, only just see-through (≈48 % for the front layer
    // alone, ≈75 % where all three overlap); antialiased top edges, each
    // with a crest line
    vec4 col = vec4(0.0);
    float hs[3] = float[3](h2, h1, h0);
    float as[3] = float[3](0.28 * third, 0.36, 0.48);
    float cs[3] = float[3](0.50 * third, 0.60, 0.0);   // back crests (front: `crest`)
    for (int i = 0; i < 3; i++) {
        float h = hs[i];
        float cov = clamp(h - up + 0.5, 0.0, 1.0);
        float fade = 1.0 - 0.1 * clamp(up / max(h, 1.0), 0.0, 1.0);
        float a = A * as[i] * cov * fade;
        col = over(vec4(c * a, a), col);
        float la = A * cs[i] * clamp(1.0 - abs(up - h), 0.0, 1.0) * smoothstep(0.3, 1.5, h);
        col = over(vec4(c * la, la), col);
    }
    // a thin bright crest on the front layer
    float d = abs(up - h0);
    float ca = A * crest * clamp(1.0 - d, 0.0, 1.0) * smoothstep(0.3, 1.5, h0);
    col = over(vec4(c * ca, ca), col);

    // hard stop at the playhead (antialiased)
    col *= clamp(xs - p.x + 0.5, 0.0, 1.0);
    fragColor = col * qt_Opacity;
}
