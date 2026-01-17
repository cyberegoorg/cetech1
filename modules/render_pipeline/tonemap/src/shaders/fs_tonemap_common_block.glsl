#define TONEMAP_TYPE_ACESS 0
#define TONEMAP_TYPE_UNCHARTED 1
#define TONEMAP_TYPE_LUMINANCE_DEBUG 2


struct ct_tonemap_params {
    uint tonemap_type;
    bool bloom_enabled;
};

ct_tonemap_params load_tonemap_params() {
    ct_tonemap_params params = (ct_tonemap_params)0;
    
    params.tonemap_type = floatBitsToUint(load_params().x);
    params.bloom_enabled = bool(floatBitsToUint(load_params().y));

    return params;
}

// Uncharted 2 filmic operator
// John Hable
// https://www.gdcvault.com/play/1012351/Uncharted-2-HDR
// https://www.slideshare.net/ozlael/hable-john-uncharted2-hdr-lighting
vec3 hable_map(vec3 color) {
    // values used are directly from the presentation
    // comments have the values taken from the website above
    const float A = 0.22; // shoulder strength // 0.15
    const float B = 0.30; // linear strength // 0.50
    const float C = 0.10; // linear angle
    const float D = 0.20; // toe strength
    const float E = 0.01; // toe numerator // 0.02
    const float F = 0.30; // toe denominator
    return ((color * (A * color + C * B) + D * E) / (color * (A * color + B) + D * F)) - E / F;
}

// From: https://google.github.io/filament/Filament.md.html
const ARRAY_BEGIN(vec3, debugColors, 16)
    vec3(0.0, 0.0, 0.0),         // black
    vec3(0.0, 0.0, 0.1647),      // darkest blue
    vec3(0.0, 0.0, 0.3647),      // darker blue
    vec3(0.0, 0.0, 0.6647),      // dark blue
    vec3(0.0, 0.0, 0.9647),      // blue
    vec3(0.0, 0.9255, 0.9255),   // cyan
    vec3(0.0, 0.5647, 0.0),      // dark green
    vec3(0.0, 0.7843, 0.0),      // green
    vec3(1.0, 1.0, 0.0),         // yellow
    vec3(0.90588, 0.75294, 0.0), // yellow-orange
    vec3(1.0, 0.5647, 0.0),      // orange
    vec3(1.0, 0.0, 0.0),         // bright red
    vec3(0.8392, 0.0, 0.0),      // red
    vec3(1.0, 0.0, 1.0),         // magenta
    vec3(0.6, 0.3333, 0.7882),   // purple
    vec3(1.0, 1.0, 1.0)          // white
ARRAY_END();

vec3 tonemap_display_range(in vec3 x) {
    // The 5th color in the array (cyan) represents middle gray (18%)
    // Every stop above or below middle gray causes a color shift
    float v = log2(luma(x) / 0.18);
    v = clamp(v + 5.0, 0.0, 15.0);
    int index = int(floor(v));
    return mix(debugColors[index], debugColors[min(15, index + 1)], fract(v));
}
