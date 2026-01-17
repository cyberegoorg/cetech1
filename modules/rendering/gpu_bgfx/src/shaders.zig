// TODO: embed modules in build.
const bgfx_shader = @embedFile("embed/bgfx_shader.sh");
const bgfx_compute = @embedFile("embed/bgfx_compute.sh");
pub const core_shader = bgfx_shader ++ "\n\n" ++ bgfx_compute;
