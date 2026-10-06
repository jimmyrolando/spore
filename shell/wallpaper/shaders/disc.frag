#version 440
// Wallpaper transition (see Wallpaper.qml): source1 is the old one, source2
// the new one, progress goes from 0 to 1. Compile with ./build.sh (qsb).
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;
    // Screen width / height (so the circle is round).
    float aspect;
    // Width of the soft edge, on the same scale as progress.
    float smoothness;
};

layout(binding = 1) uniform sampler2D source1;
layout(binding = 2) uniform sampler2D source2;

// A circle growing from the center with a soft edge.
void main() {
    vec4 a = texture(source1, qt_TexCoord0);
    vec4 b = texture(source2, qt_TexCoord0);
    vec2 p = (qt_TexCoord0 - 0.5) * vec2(aspect, 1.0);
    // Distance to the farthest corner: at progress = 1 it covers everything.
    float farthest = length(vec2(aspect, 1.0) * 0.5);
    float radius = progress * (farthest + smoothness);
    float m = smoothstep(radius - smoothness, radius, length(p));
    fragColor = mix(b, a, m) * qt_Opacity;
}
