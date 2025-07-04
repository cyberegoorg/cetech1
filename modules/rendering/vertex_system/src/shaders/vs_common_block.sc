#define read_idx(mat, idx) mat[idx / 4][idx % 4]

void init_vertex_loader(inout ct_vertex_loader_ctx ctx, in ct_input input, in uint instance_id) {
    ctx = (ct_vertex_loader_ctx)(0);

    ctx.instance_id = instance_id;
    ctx.active_channels = uint(load_vertex_system_data().x);
    ctx.num_vertices = uint(load_vertex_system_data().y);
    ctx.num_sets = uint(load_vertex_system_data().z);

    ctx.offset = vertex_system_offsets;
    ctx.stride = vertex_system_strides;
    ctx.buffer_idx = vertex_system_buffer_idx;

    // ctx.position = input.a_position;
}

float vertex_system_load_float(in uint channel_idx, in uint offset) {
    switch (channel_idx) {
        case 0: return load_vertex_system_channel0_buffer(offset);
        case 1: return load_vertex_system_channel1_buffer(offset);
        default: return 0;
    }
}

vec2 vertex_system_load_vec2(in uint channel_idx, in uint offset) {
    switch (channel_idx) {
        case 0: return vec2(load_vertex_system_channel0_buffer(offset), load_vertex_system_channel0_buffer(offset + 1));
        case 1: return vec2(load_vertex_system_channel1_buffer(offset), load_vertex_system_channel1_buffer(offset + 1));
        default: return vec2_splat(0);
    }
}

vec3 vertex_system_load_vec3(in uint channel_idx, in uint offset) {
    switch (channel_idx) {
        case 0: return vec3(load_vertex_system_channel0_buffer(offset), load_vertex_system_channel0_buffer(offset + 1), load_vertex_system_channel0_buffer(offset + 2));
        case 1: return vec3(load_vertex_system_channel1_buffer(offset), load_vertex_system_channel1_buffer(offset + 1), load_vertex_system_channel1_buffer(offset + 2));
        default: return vec3_splat(0);
    }
}

vec4 vertex_system_load_vec4(in uint channel_idx, in uint offset) {
    switch (channel_idx) {
        case 0: return vec4(load_vertex_system_channel0_buffer(offset), load_vertex_system_channel0_buffer(offset + 1), load_vertex_system_channel0_buffer(offset + 2), load_vertex_system_channel0_buffer(offset + 3));
        case 1: return vec4(load_vertex_system_channel1_buffer(offset), load_vertex_system_channel1_buffer(offset + 1), load_vertex_system_channel1_buffer(offset + 2), load_vertex_system_channel1_buffer(offset + 3));
        default: return vec4_splat(0);
    }
}

bool vertex_system_has_channel(in ct_vertex_loader_ctx ctx, in uint channel_id) {
    return ctx.active_channels & (1 << channel_id);
}

vec4 load_vertex_position(in ct_vertex_loader_ctx ctx, in uint vertex_id, in uint set) {
    uint offset = (set * ctx.num_vertices + vertex_id) * floatBitsToUint(read_idx(ctx.stride, CT_VERTEX_SEMANTIC_POSITION)) + floatBitsToUint(read_idx(ctx.offset, CT_VERTEX_SEMANTIC_POSITION));
    uint buffer_idx = floatBitsToUint(ctx.buffer_idx[CT_VERTEX_SEMANTIC_POSITION]);
    return vertex_system_has_channel(ctx, CT_VERTEX_SEMANTIC_POSITION) ? vec4(vertex_system_load_vec3(buffer_idx, offset), 1) : vec4(0, 0, 0, 1);
}

vec4 load_vertex_color(in ct_vertex_loader_ctx ctx, in uint vertex_id, in uint set) {
    uint offset = (set * ctx.num_vertices + vertex_id) * floatBitsToUint(read_idx(ctx.stride, CT_VERTEX_SEMANTIC_COLOR)) + floatBitsToUint(read_idx(ctx.offset, CT_VERTEX_SEMANTIC_COLOR));
    uint buffer_idx = floatBitsToUint(ctx.buffer_idx[CT_VERTEX_SEMANTIC_COLOR]);
    return vertex_system_has_channel(ctx, CT_VERTEX_SEMANTIC_COLOR) ? vertex_system_load_vec4(buffer_idx, offset) : vec4(1, 0, 0, 1);
}