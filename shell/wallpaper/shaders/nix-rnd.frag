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

// Random Nix: the screen is split into a grid of hexagons and each one, at a
// random moment (fixed per cell), fills with the new wallpaper growing from
// its center.

// Rows of hexagons across the screen's height.
const float ROWS = 12.0;
// Share of the animation each hexagon takes (the rest is the offset).
const float CELL = 0.3;

const vec2 S = vec2(1.0, 1.7320508);

// Relative center (xy) and id (zw) of the hexagon (pointy top) containing p.
vec4 hexCell(vec2 p) {
    vec4 c = floor(vec4(p, p - vec2(0.5, 1.0)) / S.xyxy) + 0.5;
    vec4 h = vec4(p - c.xy * S, p - (c.zw + 0.5) * S);
    return dot(h.xy, h.xy) < dot(h.zw, h.zw) ? vec4(h.xy, c.xy) : vec4(h.zw, c.zw + 0.5);
}

// 0 at the center, 0.5 at the sides.
float hexDist(vec2 p) {
    p = abs(p);
    return max(dot(p, S * 0.5), p.x);
}

float hash(vec2 id) {
    return fract(sin(dot(id, vec2(127.1, 311.7))) * 43758.5453);
}

void main() {
    vec4 a = texture(source1, qt_TexCoord0);
    vec4 b = texture(source2, qt_TexCoord0);
    vec4 cell = hexCell(qt_TexCoord0 * vec2(aspect, 1.0) * ROWS);
    float start = hash(cell.zw) * (1.0 - CELL);
    float local = clamp((progress - start) / CELL, 0.0, 1.0);
    // Radius growing from 0 to a bit more than the hexagon (no seams).
    float radius = local * (0.5 + smoothness);
    float m = smoothstep(radius - smoothness, radius, hexDist(cell.xy));
    fragColor = mix(b, a, m) * qt_Opacity;
}
