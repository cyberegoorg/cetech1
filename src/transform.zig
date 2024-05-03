const std = @import("std");

const apidb = @import("apidb.zig");
const ecs_private = @import("ecs.zig");
const graphvm_private = @import("graphvm.zig");

const cetech1 = @import("cetech1");
const public = cetech1.transform;
const ecs = cetech1.ecs;
const zm = cetech1.math;
const graphvm = cetech1.graphvm;

const module_name = .transform;
const log = std.log.scoped(module_name);

const position_c = ecs.ComponentI.implement(public.Position, struct {});
const rotation_c = ecs.ComponentI.implement(public.Rotation, struct {});
const scale_c = ecs.ComponentI.implement(public.Scale, struct {});
const world_tranform_c = cetech1.ecs.ComponentI.implement(public.WorldTransform, struct {});

const transform_system_i = ecs.SystemI.implement(
    .{
        .name = "transform system",
        .multi_threaded = false,
        .instanced = true,
        .phase = ecs.OnValidate,
        .query = &.{
            .{ .id = ecs.id(public.WorldTransform), .inout = .Out },
            .{ .id = ecs.id(public.WorldTransform), .inout = .In, .oper = .Optional, .src = .{ .id = ecs.Up | ecs.Cascade } },
            .{ .id = ecs.id(public.Position), .inout = .In },
            .{ .id = ecs.id(public.Rotation), .inout = .In, .oper = .Optional },
            .{ .id = ecs.id(public.Scale), .inout = .In, .oper = .Optional },
        },
    },
    struct {
        pub fn iterate(iter: *ecs.IterO) !void {
            var it = ecs_private.api.toIter(iter);

            while (it.next()) {
                if (!it.changed()) {
                    it.skip();
                    continue;
                }

                const world_transform = it.field(public.WorldTransform, 0).?;
                const parent_world_transform = it.field(public.WorldTransform, 1);

                const positions = it.field(public.Position, 2).?;
                const rotations = it.field(public.Rotation, 3);
                const scales = it.field(public.Scale, 4);
                const count = it.count();

                if (parent_world_transform) |p| {
                    if (it.isSelf(2)) {
                        for (0..count) |i| {
                            const model_mat = zm.translation(positions[i].x, positions[i].y, positions[i].z);
                            world_transform[i].mtx = zm.mul(p[0].mtx, model_mat);
                        }
                    } else {
                        for (0..count) |i| {
                            const model_mat = zm.translation(positions[0].x, positions[0].y, positions[0].z);
                            world_transform[i].mtx = zm.mul(p[0].mtx, model_mat);
                        }
                    }
                } else {
                    if (it.isSelf(2)) {
                        for (0..count) |i| {
                            const model_mat = zm.translation(positions[i].x, positions[i].y, positions[i].z);
                            world_transform[i].mtx = model_mat;
                        }
                    } else {
                        for (0..count) |i| {
                            const model_mat = zm.translation(positions[0].x, positions[0].y, positions[0].z);
                            world_transform[i].mtx = model_mat;
                        }
                    }
                }

                if (rotations) |r| {
                    if (it.isSelf(3)) {
                        for (0..count) |i| {
                            const mat = zm.quatToMat(r[i].q);
                            world_transform[i].mtx = zm.mul(mat, world_transform[i].mtx);
                        }
                    } else {
                        for (0..count) |i| {
                            const mat = zm.quatToMat(r[0].q);
                            world_transform[i].mtx = zm.mul(mat, world_transform[i].mtx);
                        }
                    }
                }

                if (scales) |s| {
                    for (0..count) |i| {
                        const mat = zm.scaling(s[i].x, s[i].y, s[i].z);
                        world_transform[i].mtx = zm.mul(mat, world_transform[i].mtx);
                    }
                }
            }
        }
    },
);

const spawn_transform_world_system_i = ecs.SystemI.implement(
    .{
        .name = "spawn world transform system",
        .multi_threaded = true,
        .phase = ecs.PostLoad,
        .query = &.{
            .{ .id = ecs.id(public.WorldTransform), .inout = .Out, .oper = .Not },
            .{ .id = ecs.id(public.Rotation), .inout = .In, .oper = .Or },
            .{ .id = ecs.id(public.Scale), .inout = .In, .oper = .Or },
            .{ .id = ecs.id(public.Position), .inout = .In },
        },
    },
    struct {
        pub fn update(iter: *ecs.IterO) !void {
            var it = ecs_private.api.toIter(iter);

            const world = it.getWorld();
            const ents = it.entities();
            for (0..it.count()) |i| {
                _ = world.setId(public.WorldTransform, ents[i], &public.WorldTransform{});
            }
        }
    },
);

const set_position_node_i = graphvm.GraphNodeI.implement(
    .{
        .name = "Set position",
        .type_name = "transform_set_position",
        .category = "Transform",
        .sidefect = true,
    },
    null,
    struct {
        pub fn getInputPins(allocator: std.mem.Allocator, db: cetech1.cdb.Db, graph_obj: cetech1.cdb.ObjId, node_obj: cetech1.cdb.ObjId) ![]const graphvm.NodePin {
            _ = node_obj; // autofix
            _ = graph_obj; // autofix
            _ = db; // autofix
            return allocator.dupe(graphvm.NodePin, &.{
                graphvm.NodePin.init("Flow", graphvm.NodePin.pinHash("flow", false), graphvm.PinTypes.Flow),
                graphvm.NodePin.init("Entity", graphvm.NodePin.pinHash("entity", false), ecs.PinTypes.Entity),
                graphvm.NodePin.init("Position", graphvm.NodePin.pinHash("position", false), graphvm.PinTypes.VEC3F),
            });
        }

        pub fn getOutputPins(allocator: std.mem.Allocator, db: cetech1.cdb.Db, graph_obj: cetech1.cdb.ObjId, node_obj: cetech1.cdb.ObjId) ![]const graphvm.NodePin {
            _ = node_obj; // autofix
            _ = db; // autofix
            _ = graph_obj; // autofix
            return allocator.dupe(graphvm.NodePin, &.{});
        }

        pub fn execute(args: graphvm.ExecuteArgs, in_pins: graphvm.InPins, out_pins: graphvm.OutPins) !void {
            _ = out_pins; // autofix

            _, const ent = in_pins.read(ecs.EntityId, 1) orelse return;
            _, const position = in_pins.read([3]f32, 2) orelse return;

            const w = graphvm_private.api.getContext(anyopaque, args.instance, ecs.ECS_WORLD_CONTEXT) orelse return;

            const world = ecs_private.api.toWorld(w);
            _ = world.setId(
                public.Position,
                ent,
                &public.Position{
                    .x = position[0],
                    .y = position[1],
                    .z = position[2],
                },
            );
        }
    },
);

pub fn regsitreAll() !void {
    _ = @alignOf(public.WorldTransform);
    _ = @alignOf(public.Position);
    _ = @alignOf(public.Rotation);
    _ = @alignOf(public.Scale);

    try apidb.api.implInterface(module_name, ecs.ComponentI, &world_tranform_c);
    try apidb.api.implInterface(module_name, ecs.ComponentI, &position_c);
    try apidb.api.implInterface(module_name, ecs.ComponentI, &rotation_c);
    try apidb.api.implInterface(module_name, ecs.ComponentI, &scale_c);

    try apidb.api.implInterface(module_name, ecs.SystemI, &transform_system_i);
    try apidb.api.implInterface(module_name, ecs.SystemI, &spawn_transform_world_system_i);

    try apidb.api.implInterface(module_name, graphvm.GraphNodeI, &set_position_node_i);
}
