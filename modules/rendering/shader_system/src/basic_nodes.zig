const shader_system = @import("shader_system.zig");

pub fn init(api: *const shader_system.ShaderSystemAPI) !void {
    //
    // ADD
    //
    try api.addShaderDefiniton("gpu_add", .{
        .function =
        \\  output.result = a + b;
        ,
        .graph_node = .{
            .name = "gpu_add",
            .display_name = "Add",
            .category = "GPU/Math",

            .inputs = &.{
                .{ .name = "a", .display_name = "A" },
                .{ .name = "b", .display_name = "B" },
            },
            .outputs = &.{
                .{ .name = "result", .display_name = "Result", .type_of = "a" },
            },
        },
    });

    //
    // SUB
    //
    try api.addShaderDefiniton("gpu_sub", .{
        .function =
        \\  output.result = a - b;
        ,
        .graph_node = .{
            .name = "gpu_sub",
            .display_name = "Sub",
            .category = "GPU/Math",

            .inputs = &.{
                .{ .name = "a", .display_name = "A" },
                .{ .name = "b", .display_name = "B" },
            },
            .outputs = &.{
                .{ .name = "result", .display_name = "Result", .type_of = "a" },
            },
        },
    });

    //
    // MUL
    //
    try api.addShaderDefiniton("gpu_mul", .{
        .function =
        \\  output.result = a * b;
        ,
        .graph_node = .{
            .name = "gpu_mul",
            .display_name = "Mul",
            .category = "GPU/Math",

            .inputs = &.{
                .{ .name = "a", .display_name = "A" },
                .{ .name = "b", .display_name = "B" },
            },
            .outputs = &.{
                .{ .name = "result", .display_name = "Result", .type_of = "a" },
            },
        },
    });

    //
    // MUL ADD
    //
    try api.addShaderDefiniton("gpu_mul_add", .{
        .function =
        \\  output.result = a * b + c;
        ,
        .graph_node = .{
            .name = "gpu_mul_add",
            .display_name = "Mul add",
            .category = "GPU/Math",

            .inputs = &.{
                .{ .name = "a", .display_name = "A" },
                .{ .name = "b", .display_name = "B" },
                .{ .name = "c", .display_name = "C" },
            },
            .outputs = &.{
                .{ .name = "result", .display_name = "Result", .type_of = "a" },
            },
        },
    });

    //
    // DIV
    //
    try api.addShaderDefiniton("gpu_div", .{
        .function =
        \\  output.result = a / b;
        ,
        .graph_node = .{
            .name = "gpu_div",
            .display_name = "Div",
            .category = "GPU/Math",

            .inputs = &.{
                .{ .name = "a", .display_name = "A" },
                .{ .name = "b", .display_name = "B" },
            },
            .outputs = &.{
                .{ .name = "result", .display_name = "Result", .type_of = "a" },
            },
        },
    });

    //
    // ABS
    //
    try api.addShaderDefiniton("gpu_abs", .{
        .function =
        \\  output.result = abs(a);
        ,
        .graph_node = .{
            .name = "gpu_abs",
            .display_name = "Abs",
            .category = "GPU/Math",

            .inputs = &.{
                .{ .name = "a", .display_name = "A" },
            },
            .outputs = &.{
                .{ .name = "result", .display_name = "Result", .type_of = "a" },
            },
        },
    });

    //
    // To rad
    //
    try api.addShaderDefiniton("gpu_to_rad", .{
        .function =
        \\  output.result = radians(a);
        ,
        .graph_node = .{
            .name = "gpu_to_rad",
            .display_name = "To RAD",
            .category = "GPU/Math",

            .inputs = &.{
                .{ .name = "a", .display_name = "A" },
            },
            .outputs = &.{
                .{ .name = "result", .display_name = "Result", .type_of = "a" },
            },
        },
    });

    //
    // To deg
    //
    try api.addShaderDefiniton("gpu_to_deg", .{
        .function =
        \\  output.result = degrees(a);
        ,
        .graph_node = .{
            .name = "gpu_to_deg",
            .display_name = "To DEG",
            .category = "GPU/Math",

            .inputs = &.{
                .{ .name = "a", .display_name = "A" },
            },
            .outputs = &.{
                .{ .name = "result", .display_name = "Result", .type_of = "a" },
            },
        },
    });

    //
    // Sin
    //
    try api.addShaderDefiniton("gpu_sin", .{
        .function =
        \\  output.result = sin(a);
        ,
        .graph_node = .{
            .name = "gpu_sin",
            .display_name = "Sin",
            .category = "GPU/Math",

            .inputs = &.{
                .{ .name = "a", .display_name = "A" },
            },
            .outputs = &.{
                .{ .name = "result", .display_name = "Result", .type_of = "a" },
            },
        },
    });

    //
    // Cos
    //
    try api.addShaderDefiniton("gpu_cos", .{
        .function =
        \\  output.result = cos(a);
        ,
        .graph_node = .{
            .name = "gpu_cos",
            .display_name = "Cos",
            .category = "GPU/Math",

            .inputs = &.{
                .{ .name = "a", .display_name = "A" },
            },
            .outputs = &.{
                .{ .name = "result", .display_name = "Result", .type_of = "a" },
            },
        },
    });

    //
    // Mix
    //
    try api.addShaderDefiniton("gpu_mix", .{
        .function =
        \\  output.result = mix(a, b, t);
        ,
        .graph_node = .{
            .name = "gpu_mix",
            .display_name = "Mix",
            .category = "GPU/Math",

            .inputs = &.{
                .{ .name = "a", .display_name = "A" },
                .{ .name = "b", .display_name = "B" },
                .{ .name = "t", .display_name = "T" },
            },
            .outputs = &.{
                .{ .name = "result", .display_name = "Result", .type_of = "a" },
            },
        },
    });
}
