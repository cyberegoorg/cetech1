const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");

const cdb = cetech1.cdb;
const ecs = cetech1.ecs;

const zm = cetech1.math.zmath;
const gpu = cetech1.gpu;
const dag = cetech1.dag;
const coreui = cetech1.coreui;

const public = @import("render_viewport.zig");

const transform = @import("transform");
const render_graph = @import("render_graph");
const camera = @import("camera");
const visibility_flags = @import("visibility_flags");

const FrustumList = cetech1.ArrayList(cetech1.math.FrustumPlanes);
const VisibilityBitFieldList = cetech1.ArrayList(public.VisibilityBitField);
const VisibilityAtomicFieldList = cetech1.ArrayList(std.atomic.Value(u32));
const EntitiesIdxList = cetech1.ArrayList(usize);

pub const MatList = cetech1.ArrayList(transform.WorldTransform);
pub const CullableBufferList = cetech1.ArrayList(*anyopaque);
pub const CullingSphereVolumeList = cetech1.ArrayList(public.SphereBoudingVolume);
pub const CullingBoxVolumeList = cetech1.ArrayList(public.BoxBoudingVolume);

pub const MatSliceList = cetech1.ArrayList([]transform.WorldTransform);
pub const DataSliceList = cetech1.ArrayList([]u8);

// Log for module
const log = std.log.scoped(.culling);

pub const ViewersList = cetech1.ArrayList(Viewer);
pub const Viewer = struct {
    mtx: [16]f32,
    proj: [16]f32,
    camera: camera.Camera,
    visibility_mask: visibility_flags.VisibilityFlags,
};

pub const CullingRequest = struct {
    allocator: std.mem.Allocator,

    mtx: MatList = .{},
    data: CullableBufferList = .{},
    sphere_volumes: CullingSphereVolumeList = .{},
    box_volumes: CullingBoxVolumeList = .{},

    data_size: usize,

    pub fn init(allocator: std.mem.Allocator, data_size: usize, cullable_count: usize) !CullingRequest {
        var cr = CullingRequest{
            .allocator = allocator,
            .data_size = data_size,
        };

        try cr.mtx.ensureTotalCapacityPrecise(cr.allocator, cullable_count);

        try cr.data.ensureTotalCapacityPrecise(cr.allocator, cullable_count);
        try cr.data.resize(cr.allocator, cullable_count);

        try cr.sphere_volumes.ensureTotalCapacityPrecise(cr.allocator, cullable_count);
        try cr.sphere_volumes.resize(cr.allocator, cullable_count);

        return cr;
    }

    pub fn clear(self: *CullingRequest, cullable_count: usize) !void {
        self.mtx.clearRetainingCapacity();
        self.data.clearRetainingCapacity();
        self.sphere_volumes.clearRetainingCapacity();
        self.box_volumes.clearRetainingCapacity();

        try self.mtx.ensureTotalCapacityPrecise(self.allocator, cullable_count);

        try self.data.ensureTotalCapacityPrecise(self.allocator, cullable_count);
        try self.data.resize(self.allocator, cullable_count);

        try self.sphere_volumes.ensureTotalCapacityPrecise(self.allocator, cullable_count);
        try self.sphere_volumes.resize(self.allocator, cullable_count);
    }

    pub fn deinit(self: *CullingRequest) void {
        self.mtx.deinit(self.allocator);
        self.data.deinit(self.allocator);
        self.sphere_volumes.deinit(self.allocator);
        self.box_volumes.deinit(self.allocator);
    }
};

pub const CullingResult = struct {
    allocator: std.mem.Allocator,

    visibility: VisibilityAtomicFieldList = .{},

    sphere_entites_idx: EntitiesIdxList = .{},
    box_entites_idx: EntitiesIdxList = .{},
    compact_visibility: VisibilityAtomicFieldList = .{},

    visible_cnt: std.atomic.Value(usize),

    pub fn init(allocator: std.mem.Allocator) CullingResult {
        return CullingResult{
            .allocator = allocator,
            .visible_cnt = std.atomic.Value(usize).init(0),
        };
    }

    pub fn clear(self: *CullingResult) void {
        self.visible_cnt = std.atomic.Value(usize).init(0);
        self.visibility.clearRetainingCapacity();
        self.sphere_entites_idx.clearRetainingCapacity();
        self.box_entites_idx.clearRetainingCapacity();
        self.compact_visibility.clearRetainingCapacity();
    }

    pub fn deinit(self: *CullingResult) void {
        self.visibility.deinit(self.allocator);
        self.sphere_entites_idx.deinit(self.allocator);
        self.box_entites_idx.deinit(self.allocator);
        self.compact_visibility.deinit(self.allocator);
    }

    pub fn setVisibility(self: *CullingResult, idx: usize, viewer_idx: usize, visible: bool) void {
        if (visible) {
            _ = self.visibility.items[idx].bitSet(@truncate(viewer_idx), .monotonic);
        } else {
            @panic("WTF");
        }
    }

    pub fn visibleCount(self: *CullingResult) usize {
        return self.visible_cnt.raw;
    }

    pub fn prepareBoxCompaction(self: *CullingResult, count: usize) !void {
        try self.box_entites_idx.ensureTotalCapacityPrecise(self.allocator, count);
        try self.box_entites_idx.resize(self.allocator, count);
        try self.compact_visibility.ensureTotalCapacityPrecise(self.allocator, count);
        try self.compact_visibility.resize(self.allocator, count);

        @memset(self.compact_visibility.items, public.VisibilityBitField.initEmpty());
    }

    pub fn compaction(self: *CullingResult, count: usize, out_entites_idx: []usize, in_entites_idx: ?[]const usize) usize {
        var renderable_cnt: usize = 0;
        for (0..count) |cullable_idx| {
            if (self.visibility.items[cullable_idx].raw == 0) continue;

            self.compact_visibility.items[renderable_cnt] = self.visibility.items[cullable_idx];
            out_entites_idx[renderable_cnt] = if (in_entites_idx) |idxs| idxs[cullable_idx] else cullable_idx;

            renderable_cnt += 1;
        }

        return renderable_cnt;
    }

    pub fn compactionSpheres(self: *CullingResult, count: usize) !usize {
        try self.sphere_entites_idx.ensureTotalCapacityPrecise(self.allocator, self.visible_cnt.raw);
        try self.sphere_entites_idx.resize(self.allocator, self.visible_cnt.raw);

        try self.compact_visibility.ensureTotalCapacityPrecise(self.allocator, self.visible_cnt.raw);
        try self.compact_visibility.resize(self.allocator, self.visible_cnt.raw);
        @memset(self.compact_visibility.items, std.atomic.Value(u32).init(0));

        return self.compaction(
            count,
            self.sphere_entites_idx.items,
            null,
        );
    }

    pub fn compactionBox(self: *CullingResult, count: usize) !usize {
        try self.box_entites_idx.ensureTotalCapacityPrecise(self.allocator, self.visible_cnt.raw);
        try self.box_entites_idx.resize(self.allocator, self.visible_cnt.raw);

        try self.compact_visibility.ensureTotalCapacityPrecise(self.allocator, self.visible_cnt.raw);
        try self.compact_visibility.resize(self.allocator, self.visible_cnt.raw);
        @memset(self.compact_visibility.items, std.atomic.Value(u32).init(0));

        return self.compaction(
            count,
            self.box_entites_idx.items,
            self.sphere_entites_idx.items,
        );
    }
};

// TODO : Faster (Culling in clip space? simd?)
const CullingSphereTask = struct {
    count: usize,
    visibility_offset: usize,
    volumes: []const public.SphereBoudingVolume,
    frustums: []const cetech1.math.FrustumPlanes,
    viewers: []const Viewer,
    result: *CullingResult,
    viewer_idx: usize,
    profiler: *const cetech1.profiler.ProfilerAPI,

    pub fn exec(self: *@This()) !void {
        var zone = self.profiler.ZoneN(@src(), "CullingSphereTask");
        defer zone.End();

        for (self.volumes, 0..) |sphere, i| {
            if (sphere.visibility_mask.intersectWith(self.viewers[self.viewer_idx].visibility_mask).mask == 0) continue;

            if (sphere.skip_culling or cetech1.math.frustumPlanesVsSphereNaive(self.frustums[self.viewer_idx], sphere.center, sphere.radius)) {
                self.result.setVisibility(self.visibility_offset + i, self.viewer_idx, true);
                _ = self.result.visible_cnt.fetchAdd(1, .monotonic);
            }
        }
    }
};

// TODO : Faster (Culling in clip space? simd?)
const CullingBoxTask = struct {
    count: usize,
    visibility_offset: usize,
    volumes: []const public.BoxBoudingVolume,
    frustums: []const cetech1.math.FrustumPlanes,
    viewers: []const Viewer,
    result: *CullingResult,
    profiler: *const cetech1.profiler.ProfilerAPI,
    viewer_idx: usize,

    pub fn exec(self: *@This()) !void {
        var zone = self.profiler.ZoneN(@src(), "CullingBoxTask");
        defer zone.End();

        for (self.volumes, 0..) |box, i| {
            if (box.visibility_mask.intersectWith(self.viewers[self.viewer_idx].visibility_mask).mask == 0) continue;

            if (box.skip_culling or cetech1.math.frustumPlanesVsOBBNaive(self.frustums[self.viewer_idx], box.t.mtx, box.min, box.max)) {
                self.result.setVisibility(self.visibility_offset + i, self.viewer_idx, true);
                _ = self.result.visible_cnt.fetchAdd(1, .monotonic);
            }
        }
    }
};

pub const CullingSystem = struct {
    const Self = @This();

    const RequestPool = cetech1.heap.PoolWithLock(CullingRequest);
    const RequestMap = cetech1.AutoArrayHashMap(cetech1.StrId32, *CullingRequest);

    const ResultPool = cetech1.heap.PoolWithLock(CullingResult);
    const ResultMap = cetech1.AutoArrayHashMap(cetech1.StrId32, *CullingResult);

    allocator: std.mem.Allocator,

    crq_pool: RequestPool,
    request_map: RequestMap = .{},

    cr_pool: ResultPool,
    result_map: ResultMap = .{},

    tasks: cetech1.task.TaskIdList = .{},

    draw_culling_sphere_debug: bool = false,
    draw_culling_box_debug: bool = false,

    profiler: *const cetech1.profiler.ProfilerAPI,
    task: *const cetech1.task.TaskAPI,

    pub fn init(
        allocator: std.mem.Allocator,
        profiler: *const cetech1.profiler.ProfilerAPI,
        task: *const cetech1.task.TaskAPI,
    ) Self {
        return .{
            .allocator = allocator,
            .crq_pool = RequestPool.init(allocator),
            .cr_pool = ResultPool.init(allocator),
            .profiler = profiler,
            .task = task,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.request_map.values()) |value| {
            value.deinit();
        }

        for (self.result_map.values()) |value| {
            value.deinit();
        }

        self.request_map.deinit(self.allocator);
        self.crq_pool.deinit();

        self.result_map.deinit(self.allocator);
        self.cr_pool.deinit();

        self.tasks.deinit(self.allocator);
    }

    pub fn getNewRequest(self: *Self, cullable_type: cetech1.StrId32, cullable_count: usize, cullable_size: usize) !*CullingRequest {
        if (self.request_map.get(cullable_type)) |rq| {
            try rq.clear(cullable_count);

            if (self.result_map.get(cullable_type)) |rs| {
                rs.clear();
            }

            return rq;
        }

        const rq = try self.crq_pool.create();
        rq.* = try CullingRequest.init(self.allocator, cullable_size, cullable_count);
        try self.request_map.put(self.allocator, cullable_type, rq);

        const rs = try self.cr_pool.create();
        rs.* = CullingResult.init(self.allocator);
        try self.result_map.put(self.allocator, cullable_type, rs);

        return rq;
    }

    pub fn getResult(self: *Self, rq_type: cetech1.StrId32) ?*CullingResult {
        return self.result_map.get(rq_type);
    }

    pub fn getRequest(self: *Self, rq_type: cetech1.StrId32) ?*CullingRequest {
        return self.request_map.get(rq_type);
    }

    pub fn doCullingSpheres(self: *Self, allocator: std.mem.Allocator, viewers: []const Viewer, freze_mtx: ?zm.Mat) !usize {
        var cull_zone = self.profiler.ZoneN(@src(), "Culling system - doCullingSpheres");
        defer cull_zone.End();

        var frustums = try FrustumList.initCapacity(allocator, viewers.len);
        defer frustums.deinit(allocator);

        for (viewers) |v| {
            const mtx = zm.mul(zm.matFromArr(if (freze_mtx) |mtx| zm.matToArr(mtx) else v.mtx), zm.matFromArr(v.proj));
            frustums.appendAssumeCapacity(cetech1.math.buildFrustumPlanes(zm.matToArr(mtx)));
        }

        self.tasks.clearRetainingCapacity();

        //
        // Sphere phase
        //
        {
            var zone = self.profiler.ZoneN(@src(), "Culling system - Sphere culling");
            defer zone.End();

            for (self.request_map.keys(), self.request_map.values()) |k, request| {
                const result = self.getResult(k) orelse continue; // TODO: warning

                const items_count = request.sphere_volumes.items.len;

                try result.visibility.ensureTotalCapacityPrecise(result.allocator, items_count);
                try result.visibility.resize(result.allocator, items_count);
                @memset(result.visibility.items, std.atomic.Value(u32).init(0));

                if (items_count == 0) continue;

                const ARGS = struct {
                    rq: *CullingRequest,
                    result: *CullingResult,
                    frustums: []const cetech1.math.FrustumPlanes,
                    viewers: []const Viewer,
                    viewer_idx: usize,
                };
                for (0..viewers.len) |viewer_idx| {
                    if (try cetech1.task.batchWorkloadTask(
                        .{
                            .allocator = allocator,
                            .task_api = self.task,
                            .profiler_api = self.profiler,
                            .count = items_count,
                        },
                        ARGS{
                            .rq = request,
                            .result = result,
                            .frustums = frustums.items,
                            .viewers = viewers,
                            .viewer_idx = viewer_idx,
                        },
                        struct {
                            pub fn createTask(create_args: ARGS, batch_id: usize, args: cetech1.task.BatchWorkloadArgs, count: usize) CullingSphereTask {
                                const rq = create_args.rq;

                                return CullingSphereTask{
                                    .count = count,
                                    .visibility_offset = batch_id * args.batch_size * create_args.frustums.len,
                                    .frustums = create_args.frustums,
                                    .viewers = create_args.viewers,
                                    .result = create_args.result,
                                    .volumes = rq.sphere_volumes.items[batch_id * args.batch_size .. (batch_id * args.batch_size) + count],
                                    .profiler = args.profiler_api,
                                    .viewer_idx = create_args.viewer_idx,
                                };
                            }
                        },
                    )) |t| {
                        try self.tasks.append(self.allocator, t);
                    }
                }
            }

            if (self.tasks.items.len != 0) {
                self.task.waitMany(self.tasks.items);
            }
        }

        // Filter sphere results
        {
            var zone = self.profiler.ZoneN(@src(), "Culling system - Filter sphere culling results");
            defer zone.End();

            var cnt: usize = 0;
            for (self.request_map.keys(), self.request_map.values()) |k, rq| {
                const result = self.getResult(k) orelse continue; // TODO: warning
                cnt += try result.compactionSpheres(rq.sphere_volumes.items.len);
            }
            return cnt;
        }
    }

    pub fn doCullingBox(self: *Self, allocator: std.mem.Allocator, viewers: []const Viewer, freze_mtx: ?zm.Mat) !void {
        var cull_zone = self.profiler.ZoneN(@src(), "Culling system - doCullingBox");
        defer cull_zone.End();

        var frustums = try FrustumList.initCapacity(allocator, viewers.len);
        defer frustums.deinit(allocator);

        for (viewers) |v| {
            const mtx = zm.mul(zm.matFromArr(if (freze_mtx) |mtx| zm.matToArr(mtx) else v.mtx), zm.matFromArr(v.proj));
            frustums.appendAssumeCapacity(cetech1.math.buildFrustumPlanes(zm.matToArr(mtx)));
        }

        self.tasks.clearRetainingCapacity();

        //
        // Box phase
        //
        {
            var zone = self.profiler.ZoneN(@src(), "Culling system - Box culling");
            defer zone.End();

            for (self.request_map.keys(), self.request_map.values()) |k, value| {
                const result = self.getResult(k) orelse continue; // TODO: warning

                const items_count = value.box_volumes.items.len;

                result.visible_cnt = std.atomic.Value(usize).init(0);

                try result.visibility.ensureTotalCapacityPrecise(result.allocator, items_count);
                try result.visibility.resize(result.allocator, items_count);
                @memset(result.visibility.items, std.atomic.Value(u32).init(0));

                if (items_count == 0) continue;

                for (0..viewers.len) |viewer_idx| {
                    const ARGS = struct {
                        rq: *CullingRequest,
                        result: *CullingResult,
                        frustums: []const cetech1.math.FrustumPlanes,
                        viewers: []const Viewer,
                        viewer_idx: usize,
                    };

                    if (try cetech1.task.batchWorkloadTask(
                        .{
                            .allocator = allocator,
                            .task_api = self.task,
                            .profiler_api = self.profiler,
                            .count = items_count,
                        },
                        ARGS{
                            .rq = value,
                            .result = result,
                            .frustums = frustums.items,
                            .viewers = viewers,
                            .viewer_idx = viewer_idx,
                        },
                        struct {
                            pub fn createTask(create_args: ARGS, batch_id: usize, args: cetech1.task.BatchWorkloadArgs, count: usize) CullingBoxTask {
                                const rq = create_args.rq;

                                return CullingBoxTask{
                                    .count = count,
                                    .visibility_offset = batch_id * args.batch_size * create_args.frustums.len,
                                    .frustums = create_args.frustums,
                                    .viewers = create_args.viewers,
                                    .result = create_args.result,
                                    .volumes = rq.box_volumes.items[batch_id * args.batch_size .. (batch_id * args.batch_size) + count],
                                    .profiler = args.profiler_api,
                                    .viewer_idx = create_args.viewer_idx,
                                };
                            }
                        },
                    )) |t| {
                        try self.tasks.append(self.allocator, t);
                    }
                }
            }

            if (self.tasks.items.len != 0) {
                self.task.waitMany(self.tasks.items);
            }
        }

        // Filter box results
        {
            var zone = self.profiler.ZoneN(@src(), "Culling system - Filter box culling results");
            defer zone.End();

            var cnt: usize = 0;
            for (self.request_map.keys(), self.request_map.values()) |k, rq| {
                const result = self.getResult(k) orelse continue; // TODO: warning
                cnt += try result.compactionBox(rq.box_volumes.items.len);
            }
        }
    }

    pub fn debugdrawBoundingSpheres(self: *Self, dd: gpu.DDEncoder) !void {
        var zone = self.profiler.ZoneN(@src(), "Culling system - Debug draw");
        defer zone.End();

        dd.setWireframe(true);
        defer dd.setWireframe(false);

        for (self.request_map.keys(), self.request_map.values()) |k, rq| {
            const result = self.getResult(k) orelse continue; // TODO: warning

            for (result.sphere_entites_idx.items) |ent_idx| {
                const sphere = rq.sphere_volumes.items[ent_idx];

                dd.drawCircleAxis(.X, sphere.center, sphere.radius, 0);
                dd.drawCircleAxis(.Y, sphere.center, sphere.radius, 0);
                dd.drawCircleAxis(.Z, sphere.center, sphere.radius, 0);

                // dd.drawSphere(sphere.center, sphere.radius);
            }
        }
    }

    pub fn debugdrawBoundingBoxes(self: *Self, dd: gpu.DDEncoder) !void {
        var zone = self.profiler.ZoneN(@src(), "Culling system - Debug draw");
        defer zone.End();

        dd.setWireframe(true);
        defer dd.setWireframe(false);

        for (self.request_map.keys(), self.request_map.values()) |k, rq| {
            _ = k;

            for (rq.box_volumes.items) |box| {
                dd.pushTransform(&box.t.mtx);
                defer dd.popTransform();
                dd.drawAABB(box.min, box.max);
            }
        }
    }
};
