#version 440
// Wallpaper transition (see Wallpaper.qml): source1 is the old one, source2
// the new one, progress goes from 0 to 1. Compile with ./build.sh (qsb).
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;
    // Screen width / height (so the hexagons are regular).
    float aspect;
    // Width of the soft edge (antialiasing for the outlines).
    float smoothness;
    // Outline color (the theme's accent).
    vec4 lineColor;
};

layout(binding = 1) uniform sampler2D source1;
layout(binding = 2) uniform sampler2D source2;

// Nix: first the outlines of all the hexagons are drawn over the current
// wallpaper (it's split into a honeycomb); then each hexagon of the old one,
// at a random moment, shrinks toward its center like a tile and darkens, and
// the new one shows in the gaps.

// Rows of hexagons across the screen's height.
const float ROWS = 6.4;
// Share of the animation spent drawing the outlines.
const float OUTLINE = 0.12;
// Outline thickness (0.5 = from the center to the side).
const float LINE = 0.015;
// Share of the remaining time each hexagon takes to shrink (the rest is the
// random offset between them).
const float SHRINK = 0.4;
// How dark a hexagon ends up when it finishes shrinking (0 = black).
const float DARKEST = 0.2;

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
    vec2 scale = vec2(aspect, 1.0) * ROWS;
    vec2 p = qt_TexCoord0 * scale;
    vec4 cell = hexCell(p);
    float d = hexDist(cell.xy);

    // Outlines: they appear in the first part.
    float lineIn = smoothstep(0.0, OUTLINE, progress);
    // Each tile shrinks at its own moment, after the outline.
    float rest = 1.0 - OUTLINE;
    float start = OUTLINE + hash(cell.zw) * rest * (1.0 - SHRINK);
    float local = clamp((progress - start) / (rest * SHRINK), 0.0, 1.0);
    // Size of the old tile: 1 until its turn comes, then down to 0.
    float size = 1.0 - smoothstep(0.0, 1.0, local);
    float edge = 0.5 * size;

    // Inside the tile, the old wallpaper shrunk along with it (sampled farther
    // from the center the smaller it gets).
    vec2 centerUV = (p - cell.xy) / scale;
    vec2 shrunkUV = centerUV + (qt_TexCoord0 - centerUV) / max(size, 0.001);
    vec4 a = texture(source1, shrunkUV);
    // Darkens as it shrinks.
    a.rgb *= mix(1.0, DARKEST, local);
    vec4 b = texture(source2, qt_TexCoord0);

    // 1 inside the tile, 0 outside (the new one shows in the gap).
    float inside = 1.0 - smoothstep(edge - smoothness, edge, d);
    vec4 color = mix(b, a, inside);

    // Outline at the edge of the tile (fades out at the end).
    float line = smoothstep(edge - LINE - smoothness, edge - LINE, d) * inside;
    color = mix(color, vec4(lineColor.rgb, 1.0), line * lineColor.a * lineIn * min(1.0, size * 4.0));

    fragColor = color * qt_Opacity;
}
