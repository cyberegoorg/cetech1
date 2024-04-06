const std = @import("std");

const GfxApi = @import("gfx.zig").GfxApi;
const GpuViewport = @import("gpu.zig").GpuViewport;
const GfxDDApi = @import("gfxdd.zig").GfxDDApi;

pub const Pass = struct {
    setup: *const fn (pass: *Pass, builder: GraphBuilder) anyerror!void,
    render: *const fn (builder: GraphBuilder, gfx_api: *const GfxApi, viewport: GpuViewport) anyerror!void,

    pub fn implement(comptime T: type) Pass {
        if (!std.meta.hasFn(T, "setup")) @compileError("implement me");
        if (!std.meta.hasFn(T, "render")) @compileError("implement me");

        const p = Pass{
            .setup = &T.setup,
            .render = &T.render,
        };

        return p;
    }
};

pub const Module = struct {
    pub fn addPassToModule(self: Module, pass: Pass) !void {
        self.vtable.addPassToModule(self.ptr, pass);
    }
    pub fn addModuleToModule(self: Module, module: Module) !void {
        self.vtable.addModuleToModule(self.ptr, module);
    }

    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        addPassToModule: *const fn (self: *anyopaque, pass: Pass) anyerror!void,
        addModuleToModule: *const fn (self: *anyopaque, module: Module) anyerror!void,

        pub fn implement(comptime T: type) VTable {
            if (!std.meta.hasFn(T, "addPassToModule")) @compileError("implement me");
            if (!std.meta.hasFn(T, "addModuleToModule")) @compileError("implement me");

            return VTable{
                .addPassToModule = &T.addPassToModule,
                .addModuleToModule = &T.addModuleToModule,
            };
        }
    };
};

pub const GraphBuilder = struct {
    pub fn addPass(builder: GraphBuilder, pass: *Pass) !void {
        return builder.vtable.addPass(builder.ptr, pass);
    }
    pub fn render(builder: GraphBuilder, gfx_api: *const GfxApi, viewport: GpuViewport) !void {
        return builder.vtable.render(builder.ptr, gfx_api, viewport);
    }

    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        addPass: *const fn (builder: *anyopaque, pass: *Pass) anyerror!void,
        render: *const fn (builder: *anyopaque, gfx_api: *const GfxApi, viewport: GpuViewport) anyerror!void,

        pub fn implement(comptime T: type) VTable {
            if (!std.meta.hasFn(T, "builderAddPass")) @compileError("implement me");
            if (!std.meta.hasFn(T, "builderRender")) @compileError("implement me");

            return VTable{
                .builderAddPass = &T.builderAddPass,
                .builderRender = &T.builderRender,
            };
        }
    };
};

pub const RenderGraph = struct {
    pub fn addPass(self: RenderGraph, pass: Pass) !void {
        return self.vtable.addPass(self.ptr, pass);
    }
    pub fn addModule(self: RenderGraph, module: Module) !void {
        self.vtable.addModule(self.ptr, module);
    }
    pub fn createModule(self: RenderGraph) !Module {
        return self.vtable.createModule(self.ptr);
    }
    pub fn createBuilder(self: RenderGraph) !GraphBuilder {
        return self.vtable.createBuilder(self.ptr);
    }
    pub fn destroyBuilder(self: RenderGraph, builder: GraphBuilder) void {
        self.vtable.destroyBuilder(self.ptr, builder);
    }
    pub fn setupBuilder(self: RenderGraph, builder: GraphBuilder) !void {
        return self.vtable.setupBuilder(self.ptr, builder);
    }

    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        addPass: *const fn (self: *anyopaque, pass: Pass) anyerror!void,
        addModule: *const fn (self: *anyopaque, module: Module) anyerror!void,
        createModule: *const fn (self: *anyopaque) anyerror!Module,
        createBuilder: *const fn (self: *anyopaque) anyerror!GraphBuilder,
        destroyBuilder: *const fn (self: *anyopaque, builder: GraphBuilder) void,
        setupBuilder: *const fn (self: *anyopaque, builder: GraphBuilder) anyerror!void,

        pub fn implement(comptime T: type) VTable {
            if (!std.meta.hasFn(T, "addPass")) @compileError("implement me");
            if (!std.meta.hasFn(T, "addModule")) @compileError("implement me");
            if (!std.meta.hasFn(T, "createModule")) @compileError("implement me");
            if (!std.meta.hasFn(T, "createBuilder")) @compileError("implement me");
            if (!std.meta.hasFn(T, "destroyBuilder")) @compileError("implement me");
            if (!std.meta.hasFn(T, "setupBuilder")) @compileError("implement me");

            return VTable{
                .addPass = &T.addPass,
                .addModule = &T.addModule,
                .createModule = &T.createModule,
                .createBuilder = &T.createBuilder,
                .destroyBuilder = &T.destroyBuilder,
                .setupBuilder = &T.setupBuilder,
            };
        }
    };
};

pub const GfxRGApi = struct {
    create: *const fn () anyerror!RenderGraph,
    destroy: *const fn (rg: RenderGraph) void,
};
