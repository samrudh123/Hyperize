// One slanted card of the workspace picker (WorkspacePicker.qml): the
// parallelogram the wallpaper picker draws with cairo — drop shadow, picture
// clipped to the slant and dimmed with distance, outline — in one pass, with
// antialiased edges. The item is the card's bounding box plus `margin` on
// every side (room for the outline and the shadow below it).
// Compile after editing:
//   /usr/lib/qt6/bin/qsb --qt6 -o card.frag.qsb card.frag
#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 itemSize;       // the whole item, margins included
    float margin;
    float cardW;         // width of the card without its slant
    float cardH;
    float slant;
    float imgW;          // width of the preview texture (centred on the card)
    float dim;           // 0..1 towards dimColor
    float lineW;         // outline width
    float shadowA;       // shadow opacity
    float hasTex;        // 0 = no preview yet, fill with dimColor instead
    vec4 strokeColor;
    vec4 dimColor;
    vec4 emptyColor;
};

layout(binding = 1) uniform sampler2D src;

// signed distance to the card's edge, positive inside
float sdf(vec2 p) {
    float k = cardH / sqrt(cardH * cardH + slant * slant);
    float edge = slant * (1.0 - p.y / cardH);          // left edge's x at this y
    float l = (p.x - edge) * k;
    float r = (edge + cardW - p.x) * k;
    return min(min(l, r), min(p.y, cardH - p.y));
}

void main() {
    vec2 p = qt_TexCoord0 * itemSize - vec2(margin);
    float d = sdf(p);

    float fill = clamp(d + 0.5, 0.0, 1.0);
    float stroke = clamp(lineW * 0.5 - abs(d) + 0.5, 0.0, 1.0);
    float shadow = smoothstep(-7.0, 5.0, sdf(p - vec2(0.0, 10.0))) * shadowA;

    vec2 uv = vec2((p.x - (cardW + slant) * 0.5 + imgW * 0.5) / imgW, p.y / cardH);
    vec4 pic = hasTex > 0.5 ? texture(src, clamp(uv, 0.0, 1.0)) : emptyColor;
    pic.rgb = mix(pic.rgb, dimColor.rgb * pic.a, dim);

    vec4 col = vec4(0.0, 0.0, 0.0, shadow);
    col = pic * fill + col * (1.0 - fill);
    vec4 sc = vec4(strokeColor.rgb * strokeColor.a, strokeColor.a) * stroke;
    col = sc + col * (1.0 - sc.a);
    fragColor = col * qt_Opacity;
}
