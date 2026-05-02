const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");

const cdb = cetech1.cdb;
const ecs = cetech1.ecs;
const gpu = cetech1.gpu;
const task = cetech1.task;
const coreui = cetech1.coreui;
const apidb = cetech1.apidb;
const tempalloc = cetech1.tempalloc;
const assetdb = cetech1.assetdb;

const public = cetech1.luauvm;

const zlua = @import("zlua");

const module_name = .luauvm;

// Need for logging from std.
pub const std_options: std.Options = .{
    .logFn = cetech1.log.zigLogFnGen(),
};
// Log for module
const log = std.log.scoped(module_name);

// Basic cetech "import".
var _allocator: Allocator = undefined;

// Global state that can surive hot-reload
const G = struct {};
var _g: *G = undefined;

var _luau_asset_io_i = assetdb.AssetIOI.implement(struct {
    pub fn canImport(filename: []const u8, _: []const u8) bool {
        const extension = std.fs.path.extension(filename);
        return std.ascii.eqlIgnoreCase(extension, ".luau");
    }

    pub fn importAsset(
        io: std.Io,
        db: cdb.DbId,
        prereq: cetech1.task.TaskID,
        dir: std.Io.Dir,
        folder: cdb.ObjId,
        filename: []const u8,
        reimport_to: ?cdb.ObjId,
    ) !cetech1.task.TaskID {
        const Task = struct {
            io: std.Io,
            db: cdb.DbId,
            dir: std.Io.Dir,
            folder: cdb.ObjId,
            filename: []const u8,
            reimport_to: ?cdb.ObjId,
            pub fn exec(self: *@This()) !void {
                const allocator = tempalloc.create() catch undefined;
                defer tempalloc.destroy(allocator);

                const full_path = self.dir.realPathFileAlloc(self.io, self.filename, allocator) catch undefined;
                defer allocator.free(full_path);

                log.debug("Importing luau asset {s}", .{full_path});

                var asset_file = self.dir.openFile(self.io, self.filename, .{ .mode = .read_only }) catch |err| {
                    log.err("Could not import luau {}", .{err});
                    return;
                };

                defer asset_file.close(self.io);
                // defer self.dir.close(self.io);

                var buffer: [1024]u8 = undefined;
                var rb = asset_file.reader(self.io, &buffer);
                const asset_reader = &rb.interface;

                const asset_obj = if (self.reimport_to) |to| assetdb.getObjForAsset(to).? else try public.LuauScriptCdb.createObject(self.db);

                const content = try asset_reader.readAlloc(allocator, try asset_file.length(self.io));
                defer allocator.free(content);

                const bytecode = try zlua.compile(allocator, content, .{});
                defer allocator.free(bytecode);

                {
                    const w = public.LuauScriptCdb.write(asset_obj).?;
                    const blob = (try public.LuauScriptCdb.createBlob(w, .Bytecode, bytecode.len)).?;
                    @memcpy(blob, bytecode);
                    try public.LuauScriptCdb.commit(w);
                }

                const asset_name = std.fs.path.stem(std.fs.path.stem(self.filename));
                const asset = self.reimport_to orelse assetdb.createImportedAsset(asset_name, self.folder, asset_obj, self.filename).?;
                try assetdb.saveAsset(allocator, asset);

                // Save current version to assedb.
                // _assetroot_fs.markObjSaved(self.io, asset, cdb.getVersion(asset));
            }
        };

        return try task.schedule(
            prereq,
            Task{
                .io = io,
                .db = db,
                .dir = dir,
                .folder = folder,
                .filename = filename,
                .reimport_to = reimport_to,
            },
            .{},
        );
    }
});

var _luau_script_type_idx: cdb.TypeIdx = undefined;

const logic_c = ecs.ComponentI.implement(
    public.LuauScriptComponent,
    .{
        .display_name = "Luau script",
        .cdb_type_hash = public.LuauScriptComponentCdb.type_hash,
        .category = "Scripting",
    },
    struct {
        pub fn fromCdb(
            allocator: std.mem.Allocator,
            obj: cdb.ObjId,
            data: []u8,
        ) anyerror!void {
            _ = allocator;

            const r = cdb.readObj(obj) orelse return;

            const position = std.mem.bytesAsValue(public.LuauScriptComponent, data);
            position.* = public.LuauScriptComponent{
                .script = public.LuauScriptComponentCdb.readRef(r, .Script) orelse .{},
            };
        }
    },
);

pub const LuauScriptComponentInstance = extern struct {
    instance: ?*zlua.Lua = null,
};

const logic_instance_c = ecs.ComponentI.implement(
    LuauScriptComponentInstance,
    .{
        .display_name = "Luau logic instance ",
    },
    struct {
        pub fn onDestroy(components: []LuauScriptComponentInstance) !void {
            for (components) |c| {
                if (c.instance) |inst| {
                    inst.deinit();
                }
            }
        }

        pub fn onMove(dsts: []LuauScriptComponentInstance, srcs: []LuauScriptComponentInstance) !void {
            for (dsts, srcs) |*dst, *src| {
                dst.* = src.*;

                // Prevent double delete
                src.instance = null;
            }
        }

        pub fn onRemove(manager: ?*anyopaque, iter: *ecs.Iter) !void {
            _ = manager;
            _ = iter;

            const alloc = try tempalloc.create();
            defer tempalloc.destroy(alloc);
        }
    },
);

const init_logic_system_i = ecs.SystemI.implement(
    .{
        .name = "luau_script_component.init",
        .multi_threaded = true,
        .phase = ecs.OnLoad,
        .query = &.{
            .{ .id = ecs.id(LuauScriptComponentInstance), .inout = .Out, .oper = .Not },
            .{ .id = ecs.id(public.LuauScriptComponent), .inout = .In },
        },
    },
    struct {
        pub fn iterate(world: *ecs.World, it: *ecs.Iter, dt: f32) !void {
            _ = dt;

            const alloc = try tempalloc.create();
            defer tempalloc.destroy(alloc);

            const ents = it.entities();

            const render_components = it.field(public.LuauScriptComponent, 1).?;

            for (0..it.count()) |idx| {
                const c = render_components[idx];
                if (c.script.isEmpty()) continue;

                const scipt_r = public.LuauScriptCdb.read(c.script).?;
                const bytecode = public.LuauScriptCdb.readBlob(scipt_r, .Bytecode);

                const lua_state = try zlua.Lua.init(_allocator);

                lua_state.openLibs();

                // TODO: chunkname
                try lua_state.loadBytecode("", bytecode);
                try lua_state.protectedCall(.{});

                _ = world.setComponent(LuauScriptComponentInstance, ents[idx], &.{ .instance = lua_state });
            }
        }
    },
);

const tick_logic_system_i = ecs.SystemI.implement(
    .{
        .name = "luau_component.tick",
        .multi_threaded = true,
        .phase = ecs.OnUpdate,
        .simulation = true,
        .query = &.{
            .{ .id = ecs.id(LuauScriptComponentInstance), .inout = .In },
            .{ .id = ecs.id(public.LuauScriptComponent), .inout = .In },
        },
    },
    struct {
        pub fn iterate(world: *ecs.World, it: *ecs.Iter, dt: f32) !void {
            _ = world;
            _ = dt;

            const alloc = try tempalloc.create();
            defer tempalloc.destroy(alloc);

            const ents = it.entities();
            for (ents, 0..) |ent, idx| {
                // _ = ent;
                const ent_s: zlua.Number = @floatFromInt(ent);
                const inst = it.field(LuauScriptComponentInstance, 0).?;
                _ = try inst[idx].instance.?.autoCall(?void, "tick", .{ent_s});
            }
        }
    },
);

// Register all cdb stuff in this method
var create_cdb_types_i = cdb.CreateTypesI.implement(struct {
    pub fn createTypes(db: cdb.DbId) !void {
        _luau_script_type_idx = try cdb.addType(
            db,
            public.LuauScriptCdb.name,
            &[_]cdb.PropDef{
                .{
                    .prop_idx = public.LuauScriptCdb.propIdx(.Bytecode),
                    .name = "bytecode",
                    .type = .BLOB,
                },
            },
        );

        {
            _ = try cdb.addType(
                db,
                public.LuauScriptComponentCdb.name,
                &[_]cdb.PropDef{
                    .{
                        .prop_idx = public.LuauScriptComponentCdb.propIdx(.Script),
                        .name = "script",
                        .type = cdb.PropType.REFERENCE,
                        .type_hash = public.LuauScriptCdb.type_hash,
                    },
                },
            );
        }
    }
});

// Create types, register api, interfaces etc...
pub fn load_module_zig(io: std.Io, allocator: Allocator, load: bool, reload: bool) anyerror!bool {
    _ = reload;
    _ = io;

    // basic
    _allocator = allocator;

    // impl interface
    try apidb.implOrRemove(module_name, cdb.CreateTypesI, &create_cdb_types_i, load);
    try apidb.implOrRemove(module_name, assetdb.AssetIOI, &_luau_asset_io_i, load);

    // Components
    try apidb.implOrRemove(module_name, ecs.ComponentI, &logic_c, load);
    try apidb.implOrRemove(module_name, ecs.ComponentI, &logic_instance_c, load);

    // Systems
    try apidb.implOrRemove(module_name, ecs.SystemI, &init_logic_system_i, load);
    try apidb.implOrRemove(module_name, ecs.SystemI, &tick_logic_system_i, load);

    // create global variable that can survive reload
    _g = try apidb.setGlobalVar(G, module_name, "_g", .{});

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_luauvm(io: *const std.Io, apidb_: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, io, apidb_, allocator, load, reload);
}
