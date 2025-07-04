

#define PointLightSize 2

struct PointLight {
    vec4 position;
    vec4 color;
};

uint get_point_light_count() {
    return floatBitsToUint(load_light_system_header().y);
}

PointLight get_point_light(in uint idx) {
    const uint offset = floatBitsToUint(load_light_system_header().x);

    PointLight p;
    
    p.position = get_light_system_buffer_buffer_data(offset + (idx*PointLightSize) + 0 );
    p.color = get_light_system_buffer_buffer_data(offset + (idx*PointLightSize) + 1 );
    
    return p;
}

