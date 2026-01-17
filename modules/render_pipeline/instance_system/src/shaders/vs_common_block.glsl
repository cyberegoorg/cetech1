mat4 load_model_transform(in ct_input input, in uint instance_id) {
    const float offset = floatBitsToUint(load_instance_system_header().x) + (4 * instance_id);
    return mtxFromCols(
        get_instance_system_mtx_buffer_data(offset + 0),
        get_instance_system_mtx_buffer_data(offset + 1),
        get_instance_system_mtx_buffer_data(offset + 2),
        get_instance_system_mtx_buffer_data(offset + 3)
    );
}
