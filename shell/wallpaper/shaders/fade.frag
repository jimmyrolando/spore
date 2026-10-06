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

// Fundido.
void main() {
    vec4 a = texture(source1, qt_TexCoord0);
    vec4 b = texture(source2, qt_TexCoord0);
    fragColor = mix(a, b, progress) * qt_Opacity;
}
