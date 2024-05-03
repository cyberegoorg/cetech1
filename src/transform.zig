const std = @import("std");

const apidb = @import("apidb.zig");
const ecs_private = @import("ecs.zig");

const cetech1 = @import("cetech1");
const public = cetech1.transform;
const ecs = cetech1.ecs;
const zm = cetech1.math;

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
            .{ .id = ecs.id(public.WorldTransform), .inout = .In, .oper = .Optional, .src = .{ .flags = ecs.Parent | ecs.Cascade } },
            .{ .id = ecs.id(public.Position), .inout = .In },
            .{ .id = ecs.id(public.Rotation), .inout = .In, .oper = .Optional },
            .{ .id = ecs.id(public.Scale), .inout = .In, .oper = .Optional },
        },
    },
    struct {
        pub fn iterate(iter: *ecs.IterO) !void {
            const it = ecs_private.api.toIter(iter);

            while (it.nextTable()) {
                if (!it.changed()) {
                    it.skip();
                    continue;
                }

                it.populate();

                const world_transform = it.field(public.WorldTransform, 1).?;
                const parent_world_transform = it.field(public.WorldTransform, 2);

                const positions = it.field(public.Position, 3).?;
                const rotations = it.field(public.Rotation, 4);
                const scales = it.field(public.Scale, 5);
                const count = it.count();

                if (parent_world_transform) |p| {
                    if (it.isSelf(3)) {
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
                    if (it.isSelf(3)) {
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
                    if (it.isSelf(4)) {
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
            const it = ecs_private.api.toIter(iter);

            const world = it.getWorld();
            const ents = it.entities();
            for (0..it.count()) |i| {
                _ = world.setId(public.WorldTransform, ents[i], &public.WorldTransform{});
            }
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
}
