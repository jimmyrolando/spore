#version 440
// Wallpaper transition (see Wallpaper.qml): source1 is the old one, source2
// the new one, progress goes from 0 to 1. Compile with ./build.sh (qsb).
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;
    // Screen width / height (so the colonies are round).
    float aspect;
    // Width of the soft edge, on the same scale as the screen (0..1).
    float smoothness;
    // Glow of the growth front (the theme's accent).
    vec4 lineColor;
};

layout(binding = 1) uniform sampler2D source1;
layout(binding = 2) uniform sampler2D source2;

// Spore: the new wallpaper spreads like a fungus colony. Hundreds of spores
// land on the screen (one per cell of a grid, at a random spot inside it) at
// random moments: few at first and more and more. Each one appears as a
// small spore (of varying size) and grows from the moment it lands as a
// colony with an irregular edge (noise, not a perfect circle), revealing the
// new wallpaper.
//
// At any moment all colonies grow at the same speed, and that speed rises
// over time (progress ^ ACCEL): a colony's size is what it grew since it
// landed, so the first ones are the biggest and they merge little by little,
// faster and faster, until they cover everything near the end. Before, they
// all reached full size together: almost nothing in the first half and then
// everything was covered at once (it looked like a jump).
//
// An accent glow marks the front while it grows, and a dot marks a spore as
// it lands.

// Rows of cells across the screen's height (one spore per cell).
const float ROWS = 13.0;
// Spores land between 0 and LAND and take SEED to reach their spore size
// (between SEEDR and SEEDR + SEEDV cells of radius).
const float LAND = 0.85;
const float SEED = 0.06;
const float SEEDR = 0.1;
const float SEEDV = 0.14;
// Speed curve (progress ^ ACCEL): almost nothing at first and faster and
// faster.
const float ACCEL = 1.8;
// How much a colony that lands at the start grows over the whole transition,
// in cells, and how much the speed varies from one colony to another (+-).
// With these values everything is covered by about 97 % of the time; the
// remaining gaps fade out at the end (see outside).
const float GROW = 1.6;
const float VARY = 0.15;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

vec2 hash2(vec2 p) {
    return vec2(hash(p), hash(p + vec2(37.1, 17.3)));
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// Noise at three scales: edges with big lobes and fine detail.
float fbm(vec2 p) {
    return 0.55 * noise(p) + 0.3 * noise(p * 2.03 + 7.1) + 0.15 * noise(p * 4.1 + 3.3);
}

void main() {
    vec4 a = texture(source1, qt_TexCoord0);
    vec4 b = texture(source2, qt_TexCoord0);
    if (progress >= 0.999) {
        fragColor = b * qt_Opacity;
        return;
    }

    vec2 p = qt_TexCoord0 * vec2(aspect, 1.0) * ROWS;
    vec2 cell = floor(p);
    // A single noise field for all the colonies: the edges are continuous.
    float wobble = fbm(p * 1.7) - 0.5;
    // Width of the soft edge, in cells.
    float w = smoothness * ROWS;
    // What a colony has grown: GROW * its speed * (this, minus the same value at
    // the moment it landed).
    float now = pow(progress, ACCEL);

    // Signed distance to the edge of the nearest colony (< 0 = inside), whether
    // that colony has landed (for its glow), and the dot of the landing ones.
    float field = 1e3;
    float growing = 0.0;
    float landing = 0.0;

    // A colony reaches about two cells: look two cells to each side.
    for (int j = -2; j <= 2; j++) {
        for (int i = -2; i <= 2; i++) {
            vec2 id = cell + vec2(float(i), float(j));
            vec2 spore = id + 0.15 + 0.7 * hash2(id);
            // Seeding: when it lands (sqrt: few early and more and more) and how big the
            // spore gets.
            float land = sqrt(hash(id + 11.7)) * LAND;
            float seedR = SEEDR + SEEDV * hash(id + 5.3);
            float seed = clamp((progress - land) / SEED, 0.0, 1.0);
            // Colony: the spore plus what it grew since it landed, without pausing.
            float speed = 1.0 + VARY * (2.0 * hash(id + 23.9) - 1.0);
            float r = seedR * seed + GROW * speed * max(now - pow(land, ACCEL), 0.0);
            float dist = length(p - spore);
            // + w * (1 - seed): it doesn't exist until it lands (otherwise every future
            // spore showed a faint dot of the new wallpaper from the first frame) and
            // when it lands it appears gradually.
            float f = dist + wobble * 0.9 * min(r, 1.0) - r + w * (1.0 - seed);
            if (f < field) {
                field = f;
                growing = seed;
            }
            // A landing spore: a dot for an instant before it settles.
            float fall = clamp((progress - (land - 0.04)) / 0.04, 0.0, 1.0) * (1.0 - seed);
            landing = max(landing, fall * (1.0 - smoothstep(0.05, 0.09, dist)));
        }
    }

    // 0 inside a colony (the new one), 1 outside (the old one). The last gaps
    // fade into the new one instead of closing all at once at the end.
    float outside = smoothstep(-w, w, field) * (1.0 - smoothstep(0.96, 0.999, progress));
    vec4 color = mix(b, a, outside);
    // Glow of the front, just outside the edge; it fades out completely at the
    // end.
    float glow = exp(-max(field, 0.0) / (w * 4.0)) * step(-w, field) * growing
        * (1.0 - smoothstep(0.85, 1.0, progress));
    color = mix(color, vec4(lineColor.rgb, 1.0), glow * lineColor.a * 0.6);
    // The dot of a landing spore, only over the old wallpaper (not visible
    // inside a colony).
    color = mix(color, vec4(lineColor.rgb, 1.0), landing * outside * lineColor.a);
    fragColor = color * qt_Opacity;
}
