#define PointLightSize 2
#define SpotLightSize 3
#define DirectionLightSize 3

#define PI     (3.14159265359)
#define INV_PI (0.31830988618)

// Taken directly from GLTF 2.0 specs
const vec3 dielectric_specular = vec3(0.04, 0.04, 0.04);
const vec3 black = vec3(0.0, 0.0, 0.0);

struct ct_point_light {
    vec3 position;
    float radius;
    vec3 power;
};

struct ct_spot_light {
    ct_point_light pl;
    vec3 direction;
    float angle_scale;
    float angle_offset;
};

struct ct_direction_light {
    ct_point_light pl;
    vec3 direction;
};

struct ct_pbr_mat_coef {
    vec3 diffuse; // this becomes black for higher metalness
    vec3 F0; // Fresnel reflectance at normal incidence
    float a; // remapped roughness (^2)
};

struct ct_pbr_material {
    vec4 albedo;
    vec3 normal;
    vec3 emissive;
    float metallic;
    float roughness;
    float occlusion;
};

uint get_point_light_count() {
    return floatBitsToUint(load_light_system_header().x);
}

uint get_spot_light_count() {
    return floatBitsToUint(load_light_system_header().y);
}

uint get_direction_light_count() {
    return floatBitsToUint(load_light_system_header().z);
}

ct_point_light get_point_light(in uint idx) {
    const uint offset = (idx * PointLightSize);

    ct_point_light p;

    p.position = get_light_system_buffer_buffer_data(offset + 0).xyz;
    p.radius = get_light_system_buffer_buffer_data(offset + 0).w;
    p.power = get_light_system_buffer_buffer_data(offset + 1).xyz;

    return p;
}

ct_spot_light get_spot_light(in uint idx) {
    const uint offset = (get_point_light_count() * PointLightSize) + (idx * SpotLightSize);

    ct_spot_light p;

    p.pl.position = get_light_system_buffer_buffer_data(offset + 0).xyz;
    p.pl.radius = get_light_system_buffer_buffer_data(offset + 0).w;
    p.pl.power = get_light_system_buffer_buffer_data(offset + 1).xyz;

    p.angle_scale = get_light_system_buffer_buffer_data(offset + 1).w;
    p.angle_offset = get_light_system_buffer_buffer_data(offset + 2).w;

    p.direction = get_light_system_buffer_buffer_data(offset + 2).xyz;

    return p;
}

ct_direction_light get_directional_light(in uint idx) {
    const uint offset = (get_point_light_count() * PointLightSize) + (get_spot_light_count() * SpotLightSize) + (idx * DirectionLightSize);

    ct_direction_light p;

    p.pl.position = get_light_system_buffer_buffer_data(offset + 0).xyz;
    p.pl.radius = get_light_system_buffer_buffer_data(offset + 0).w;
    p.pl.power = get_light_system_buffer_buffer_data(offset + 1).xyz;

    p.direction = get_light_system_buffer_buffer_data(offset + 2).xyz;

    return p;
}

// frosbite
float smooth_distance_attenuation(float squared_distance, float inv_sqr_att_radius) {
    float factor = squared_distance * inv_sqr_att_radius;
    float smooth_factor = saturate(1.0 - factor * factor);
    return smooth_factor * smooth_factor;
}

// frosbite
float get_distance_attenuation(in vec3 unL, float inv_sqr_att_radius) {
    float sqr_distance = dot(unL, unL);

    float attenuation = 1.0 / (max(sqr_distance, 0.01 * 0.01));
    attenuation *= smooth_distance_attenuation(sqr_distance, inv_sqr_att_radius);

    return attenuation;
}

// frosbite
float get_angle_attenuation(in vec3 L, in vec3 light_direction, float light_angle_scale, float light_angle_offset) {
    float cd = dot(light_direction, L);
    float attenuation = saturate(cd * light_angle_scale + light_angle_offset);
    attenuation *= attenuation;
    return attenuation;
}

// Schlick approximation to Fresnel equation
vec3 f_schlick(float VoH, vec3 F0) {
    float f = pow(1.0 - VoH, 5.0);
    return f + F0 * (1.0 - f);
}

// Bruce Walter et al. 2007. Microfacet Models for Refraction through Rough Surfaces.
// equivalent to Trowbridge-Reitz
float d_ggx(float NoH, float a) {
    a = NoH * a;
    float k = a / (1.0 - NoH * NoH + a * a);
    return k * k * INV_PI;
}

// Heitz 2014. Understanding the Masking-Shadowing Function in Microfacet-Based BRDFs.
// http://jcgt.org/published/0003/02/03/paper.pdf
// based on height-correlated Smith-GGX
float v_smith_ggx_correlated(float NoV, float NoL, float a) {
    float a2 = a * a;
    float GGXV = NoL * sqrt(NoV * NoV * (1.0 - a2) + a2);
    float GGXL = NoV * sqrt(NoL * NoL * (1.0 - a2) + a2);
    return 0.5 / (GGXV + GGXL);
}

// Version without height-correlation
float v_smith_ggx(float NoV, float NoL, float a) {
    float a2 = a * a;
    float GGXV = NoV + sqrt(NoV * NoV * (1.0 - a2) + a2);
    float GGXL = NoL + sqrt(NoL * NoL * (1.0 - a2) + a2);
    return 1.0 / (GGXV * GGXL);
}

// Lambertian diffuse BRDF
// uniform color
float fd_lambert() {
    // normalize to conserve energy
    // cos integrates to pi over the hemisphere
    // incoming light is multiplied by cos and BRDF
    return INV_PI;
}

// https://github.com/KhronosGroup/glTF/tree/master/specification/2.0#appendix-b-brdf-implementation
vec3 brdf(in vec3 v, in vec3 l, in vec3 n, in float NoV, in float NoL, in ct_pbr_mat_coef mat_coef) {
    // V is the normalized vector from the shading location to the eye
    // L is the normalized vector from the shading location to the light
    // N is the surface normal in the same space as the above values
    // H is the half vector, where H = normalize(L+V)

    vec3 h = normalize(l + v);
    float NoH = saturate(dot(n, h));
    float VoH = saturate(dot(v, h));

    // specular BRDF
    float D = d_ggx(NoH, mat_coef.a);
    vec3 F = f_schlick(VoH, mat_coef.F0);
    float V = v_smith_ggx_correlated(NoV, NoL, mat_coef.a);
    vec3 Fr = F * (V * D);

    // diffuse BRDF
    vec3 Fd = mat_coef.diffuse * fd_lambert();

    return Fr + (1.0 - F) * Fd;
}

// Tokuyoshi et al. 2019. Improved Geometric Specular Antialiasing.
// http://www.jp.square-enix.com/tech/library/pdf/ImprovedGeometricSpecularAA.pdf
float specular_anti_aliasing(vec3 N, float a) {
    // normal-based isotropic filtering

    const float SIGMA2 = 0.25; // squared std dev of pixel filter kernel (in pixels)
    const float KAPPA = 0.18; // clamping threshold

    vec3 dndu = dFdx(N);
    vec3 dndv = dFdy(N);
    float variance = SIGMA2 * (dot(dndu, dndu) + dot(dndv, dndv));
    float kernelRoughness2 = min(2.0 * variance, KAPPA);
    return saturate(a + kernelRoughness2);
}

ct_pbr_mat_coef pbr_calc_mat_params(in ct_pbr_material mat, in vec3 N) {
    ct_pbr_mat_coef coef;
    coef.diffuse = mix(mat.albedo.rgb * (vec3_splat(1.0) - dielectric_specular), black, mat.metallic);
    coef.F0 = mix(dielectric_specular, mat.albedo.rgb, mat.metallic);

    coef.a = mat.roughness * mat.roughness;
    coef.a = max(coef.a, 0.01);
    coef.a = specular_anti_aliasing(N, coef.a);

    return coef;
}

vec3 calc_point_light(ct_point_light light, in float dist, in vec3 L, in vec3 unL, in vec3 V, in vec3 N, in float NoV, in ct_pbr_mat_coef mat_coef) {
    const float attenuation = dist == 0 ? 1.0 : get_distance_attenuation(unL, 1 / (light.radius * light.radius));
    if (attenuation <= 0.0) return vec3_splat(0);

    const float NoL = saturate(dot(N, L));
    return brdf(V, L, N, NoV, NoL, mat_coef) * NoL * light.power * attenuation;
}

vec3 pbr_calc_out_radiance(in vec3 V, in vec3 N, in vec3 wp, in ct_pbr_material mat) {
    const uint point_light_count = get_point_light_count();
    const uint spot_light_count = get_spot_light_count();
    const uint directional_light_count = get_direction_light_count();

    const ct_pbr_mat_coef mat_coef = pbr_calc_mat_params(mat, N);
    const float NoV = abs(dot(N, V)) + 1e-5;

    vec3 out_rad = vec3_splat(0);

    //
    // POINT LIGHT
    //
    for (int i = 0; i < point_light_count; i++) {
        const ct_point_light light = get_point_light(i);
        const vec3 unL = light.position - wp;
        const vec3 L = normalize(unL);
        const float dist = distance(light.position, wp);
        out_rad += calc_point_light(light, dist, L, unL, V, N, NoV, mat_coef);
    }

    //
    // SPOT LIGHT
    //
    for (int i = 0; i < spot_light_count; i++) {
        const ct_spot_light light = get_spot_light(i);

        const vec3 unL = light.pl.position - wp;
        const vec3 L = normalize(unL);
        const float dist = distance(light.pl.position, wp);

        const vec3 point_rad = calc_point_light(light.pl, dist, L, unL, V, N, NoV, mat_coef);
        if (!any(point_rad)) continue;

        const float spot_attenuation = get_angle_attenuation(-L, light.direction, light.angle_scale, light.angle_offset);

        out_rad += point_rad * spot_attenuation;
    }

    //
    // DIRECTIONAL LIGHT
    //
    for (int i = 0; i < directional_light_count; i++) {
        const ct_direction_light light = get_directional_light(i);

        const vec3 unL = -light.direction;
        const vec3 L = normalize(unL);
        const vec3 point_rad = calc_point_light(light.pl, 0, L, unL, V, N, NoV, mat_coef);
        out_rad += point_rad;
    }

    // Ambient
    out_rad += 0.0 * mat_coef.diffuse * mat.occlusion;

    // Emisive
    out_rad += mat.emissive;

    return out_rad;
}
