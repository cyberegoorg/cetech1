#define PointLightSize 2

struct PointLight {
    vec3 position;
    float radius;
    vec4 color;
};

uint get_point_light_count() {
    return floatBitsToUint(load_light_system_header().x);
}

PointLight get_point_light(in uint idx) {
    const uint offset = (idx * PointLightSize);

    PointLight p;
    p.position = get_light_system_buffer_buffer_data(offset + 0 ).xyz;
    p.radius = get_light_system_buffer_buffer_data(offset + 0 ).w;
    p.color = get_light_system_buffer_buffer_data(offset + 1 );
    return p;
}
