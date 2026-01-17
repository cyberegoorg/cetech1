#define read_by_idx(a, idx) a[idx / 4][idx % 4]
#define get_channel_data(channel_idx, offset) ((channel_idx == 0 ? get_vertex_system_channel0_buffer_data(offset): get_vertex_system_channel1_buffer_data(offset)))

void init_vertex_loader(out ct_vertex_loader_ctx ctx, in ct_input input) {
    ctx = (ct_vertex_loader_ctx)(0);

    ctx.active_channels = floatBitsToUint(load_vertex_system_header().x);
    ctx.num_vertices = floatBitsToUint(load_vertex_system_header().y);
    ctx.num_sets = floatBitsToUint(load_vertex_system_header().z);

    load_vertex_system_offsets(ctx.offset);
    load_vertex_system_strides(ctx.stride);
    load_vertex_system_buffer_idx(ctx.buffer_idx);

    // ctx.position = input.a_position;
}

float vertex_system_load_float(in uint channel_idx, in uint offset) {
    return get_channel_data(channel_idx, offset + 0);
}

vec2 vertex_system_load_vec2(in uint channel_idx, in uint offset) {
    return vec2(get_channel_data(channel_idx, offset + 0), get_channel_data(channel_idx, offset + 1));
}

vec3 vertex_system_load_vec3(in uint channel_idx, in uint offset) {
    return vec3(get_channel_data(channel_idx, offset + 0), get_channel_data(channel_idx, offset + 1), get_channel_data(channel_idx, offset + 2));
}

vec4 vertex_system_load_vec4(in uint channel_idx, in uint offset) {
    return vec4(get_channel_data(channel_idx, offset + 0), get_channel_data(channel_idx, offset + 1), get_channel_data(channel_idx, offset + 2), get_channel_data(channel_idx, offset + 3));
}

bool vertex_system_has_channel(in ct_vertex_loader_ctx ctx, in uint channel_id) {
    return ctx.active_channels & (1 << channel_id);
}

vec4 load_vertex_position(in ct_vertex_loader_ctx ctx, in uint vertex_id, in uint set) {
    const uint offset = (set * ctx.num_vertices + vertex_id) * floatBitsToUint(read_by_idx(ctx.stride, CT_VERTEX_SEMANTIC_POSITION)) + floatBitsToUint(read_by_idx(ctx.offset, CT_VERTEX_SEMANTIC_POSITION));
    const uint buffer_idx = floatBitsToUint(read_by_idx(ctx.buffer_idx, CT_VERTEX_SEMANTIC_POSITION));
    return vertex_system_has_channel(ctx, CT_VERTEX_SEMANTIC_POSITION) ? vec4(vertex_system_load_vec3(buffer_idx, offset), 1) : vec4(0, 0, 0, 1);
}

vec3 load_vertex_normal0(in ct_vertex_loader_ctx ctx, in uint vertex_id, in uint set) {
    const uint offset = (set * ctx.num_vertices + vertex_id) * floatBitsToUint(read_by_idx(ctx.stride, CT_VERTEX_SEMANTIC_NORMAL0)) + floatBitsToUint(read_by_idx(ctx.offset, CT_VERTEX_SEMANTIC_NORMAL0));
    const uint buffer_idx = floatBitsToUint(read_by_idx(ctx.buffer_idx, CT_VERTEX_SEMANTIC_NORMAL0));
    return vertex_system_has_channel(ctx, CT_VERTEX_SEMANTIC_NORMAL0) ? vertex_system_load_vec3(buffer_idx, offset) : vec3(0, 1, 0);
}

vec4 load_vertex_color0(in ct_vertex_loader_ctx ctx, in uint vertex_id, in uint set) {
    const uint offset = (set * ctx.num_vertices + vertex_id) * floatBitsToUint(read_by_idx(ctx.stride, CT_VERTEX_SEMANTIC_COLOR0)) + floatBitsToUint(read_by_idx(ctx.offset, CT_VERTEX_SEMANTIC_COLOR0));
    const uint buffer_idx = floatBitsToUint(read_by_idx(ctx.buffer_idx, CT_VERTEX_SEMANTIC_COLOR0));
    return vertex_system_has_channel(ctx, CT_VERTEX_SEMANTIC_COLOR0) ? vertex_system_load_vec4(buffer_idx, offset) : vec4(1, 0, 0, 1);
}
