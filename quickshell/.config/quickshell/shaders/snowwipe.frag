// The idle snow cover on screen (WinterCover.qml): its picture
// (snowcover.frag, a texture) minus what the pointer wiped (`wipe`: alpha =
// swept), with a little bank of pushed snow along each swipe's edge.
// Compile: /usr/lib/qt6/bin/qsb --qt6 -o snowwipe.frag.qsb snowwipe.frag
#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 bankColor;
};
layout(binding = 1) uniform sampler2D src;
layout(binding = 2) uniform sampler2D wipe;

void main() {
    vec4 c = texture(src, qt_TexCoord0);            // premultiplied
    float m = texture(wipe, qt_TexCoord0).a;
    float keep = 1.0 - smoothstep(0.3, 0.75, m);
    float bank = smoothstep(0.06, 0.32, m) * smoothstep(0.72, 0.38, m) * c.a;
    vec4 o = c * keep;
    o = mix(o, vec4(bankColor.rgb, 1.0) * 0.8, bank * 0.45);
    fragColor = o * qt_Opacity;
}
