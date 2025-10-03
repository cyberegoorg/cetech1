const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");

const cdb = cetech1.cdb;
const ecs = cetech1.ecs;

const gpu = cetech1.gpu;
const coreui = cetech1.coreui;
const assetdb = cetech1.assetdb;
const zm = cetech1.math.zmath;

const editor = @import("editor");
const editor_inspector = @import("editor_inspector");

const public = @import("visibility_flags.zig");

const module_name = .visibility_flags;

// Need for logging from std.
pub const std_options: std.Options = .{
    .logFn = cetech1.log.zigLogFnGen(&_log),
};
// Log for module
const log = std.log.scoped(module_name);

// Basic cetech "import".
var _allocator: Allocator = undefined;
var _apidb: *const cetech1.apidb.ApiDbAPI = undefined;
var _log: *const cetech1.log.LogAPI = undefined;
var _cdb: *const cdb.CdbAPI = undefined;
var _kernel: *const cetech1.kernel.KernelApi = undefined;
var _tmpalloc: *const cetech1.tempalloc.TempAllocApi = undefined;
var _profiler: *const cetech1.profiler.ProfilerAPI = undefined;
var _task: *const cetech1.task.TaskAPI = undefined;
var _coreui: *const coreui.CoreUIApi = undefined;

const NameToIdx = cetech1.AutoArrayHashMap(cetech1.StrId32, u32);
const IdxToName = cetech1.AutoArrayHashMap(u32, cetech1.StrId32);
const UuidToIdx = cetech1.AutoArrayHashMap(u32, u32);
const UuidToIface = cetech1.AutoArrayHashMap(u32, *const public.VisibilityFlagI);

// Global state that can surive hot-reload
const G = struct {
    flags_i_version: cetech1.apidb.InterfaceVersion = 0,

    name_to_idx: NameToIdx = .{},
    idx_to_name: IdxToName = .{},
    uuid_to_idx: UuidToIdx = .{},
    uuid_to_iface: UuidToIface = .{},

    default_flags: public.VisibilityFlags = .initEmpty(),

    component_value_menu_aspect: *editor.UiSetMenusAspect = undefined,
    tag_prop_aspect: *editor_inspector.UiEmbedPropertyAspect = undefined,

    visibility_flags_properties_aspect: *editor_inspector.UiEmbedPropertiesAspect = undefined,
};
var _g: *G = undefined;

pub const api = public.VisibilityFlagsApi{
    .fromName = fromName,
    .toName = toName,
    .createFlags = createFlags,
    .createFlagsFromUuids = createFlagsFromUuids,
};

fn fromName(name: cetech1.StrId32) ?public.VisibilityFlags {
    var result: public.VisibilityFlags = .initEmpty();
    const idx = _g.name_to_idx.get(name) orelse return null;
    result.set(idx);
    return result;
}
fn toName(visibility_flag: public.VisibilityFlags) ?cetech1.StrId32 {
    return _g.idx_to_name.get(@truncate(visibility_flag.findFirstSet() orelse return null));
}

fn createFlags(names: []const cetech1.StrId32) ?public.VisibilityFlags {
    var result = _g.default_flags;

    for (names) |value| {
        result.set(_g.name_to_idx.get(value) orelse return null);
    }

    return result;
}

fn createFlagsFromUuids(names: []const u32) ?public.VisibilityFlags {
    var result = public.VisibilityFlags.initEmpty();

    for (names) |value| {
        result.set(_g.uuid_to_idx.get(value) orelse return null);
    }

    return result;
}

var kernel_task = cetech1.kernel.KernelTaskI.implement(
    "VisibilityFlags",
    &[_]cetech1.StrId64{},
    struct {
        pub fn init() !void {
            try _g.name_to_idx.ensureTotalCapacity(_allocator, public.MAX_FLAGS);
            try _g.idx_to_name.ensureTotalCapacity(_allocator, public.MAX_FLAGS);
            try _g.uuid_to_idx.ensureTotalCapacity(_allocator, public.MAX_FLAGS);
            try _g.uuid_to_iface.ensureTotalCapacity(_allocator, public.MAX_FLAGS);
        }

        pub fn shutdown() !void {
            _g.name_to_idx.deinit(_allocator);
            _g.idx_to_name.deinit(_allocator);
            _g.uuid_to_idx.deinit(_allocator);
            _g.uuid_to_iface.deinit(_allocator);
        }
    },
);

var update_task = cetech1.kernel.KernelTaskUpdateI.implment(
    cetech1.kernel.OnLoad,
    "VisibilityFlags",
    &[_]cetech1.StrId64{},
    null,
    struct {
        pub fn update(kernel_tick: u64, dt: f32) !void {
            _ = kernel_tick;
            _ = dt;

            const alloc = try _tmpalloc.create();
            defer _tmpalloc.destroy(alloc);

            const flags_i_version = _apidb.getInterafcesVersion(public.VisibilityFlagI);
            if (flags_i_version != _g.flags_i_version) {
                log.debug("Supported visibility flags:", .{});

                _g.default_flags = .initEmpty();

                const impls = try _apidb.getImpl(alloc, public.VisibilityFlagI);
                defer alloc.free(impls);
                for (impls, 0..) |iface, idx| {
                    log.debug("\t - {s} - {d}", .{ iface.name, iface.uuid });

                    _g.name_to_idx.putAssumeCapacity(iface.hash, @truncate(idx));
                    _g.idx_to_name.putAssumeCapacity(@truncate(idx), iface.hash);
                    _g.uuid_to_idx.putAssumeCapacity(@truncate(iface.uuid), @truncate(idx));
                    _g.uuid_to_iface.putAssumeCapacity(@truncate(iface.uuid), iface);

                    if (iface.default) {
                        _g.default_flags.set(idx);
                    }
                }
                _g.flags_i_version = flags_i_version;
            }
        }
    },
);

// Aspects
const flags_menu_aspect = editor.UiSetMenusAspect.implement(struct {
    pub fn addMenu(
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
        prop_idx: u32,
        filter: ?[:0]const u8,
    ) !void {
        _ = prop_idx; // autofix
        _ = filter;

        const db = _cdb.getDbFromObjid(obj);
        const flags_r = public.VisibilityFlagsCdb.read(_cdb, obj).?;

        var active_flags_set = cetech1.ArraySet(u32).init();
        defer active_flags_set.deinit(allocator);

        if (try public.VisibilityFlagsCdb.readSubObjSet(_cdb, flags_r, .flags, allocator)) |flags| {
            defer allocator.free(flags);

            for (flags) |flag_obj| {
                const flag_r = public.VisibilityFlagCdb.read(_cdb, flag_obj).?;
                const uuid = public.VisibilityFlagCdb.readValue(u32, _cdb, flag_r, .uuid);
                _ = try active_flags_set.add(allocator, uuid);
            }
        }

        const impls = try _apidb.getImpl(allocator, public.VisibilityFlagI);
        defer allocator.free(impls);

        for (impls) |iface| {
            if (iface.hash.isEmpty()) continue;
            if (active_flags_set.contains(iface.uuid)) continue;

            if (_coreui.menuItem(_allocator, iface.name, .{}, null)) {
                const flag_obj = try public.VisibilityFlagCdb.createObject(_cdb, db);
                const flag_w = public.VisibilityFlagCdb.write(_cdb, flag_obj).?;
                const flags_w = public.VisibilityFlagsCdb.write(_cdb, obj).?;

                public.VisibilityFlagCdb.setValue(u32, _cdb, flag_w, .uuid, iface.uuid);

                try public.VisibilityFlagsCdb.addSubObjToSet(_cdb, flags_w, .flags, &.{flag_w});

                try public.VisibilityFlagCdb.commit(_cdb, flag_w);
                try public.VisibilityFlagsCdb.commit(_cdb, flags_w);
            }
        }
    }
});

// Tag property  aspect
var tag_prop_aspect = editor_inspector.UiEmbedPropertyAspect.implement(struct {
    pub fn ui(
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
        prop_idx: u32,
        args: editor_inspector.cdbPropertiesViewArgs,
    ) !void {
        _ = args.filter;
        const obj_r = _cdb.readObj(obj) orelse return;
        //const db = _cdb.getDbFromObjid(obj);

        // if (args.in_table) {
        _coreui.tableNextColumn();
        // }

        if (_coreui.button(coreui.Icons.Add ++ "###AddVisibilityFlag", .{})) {
            _coreui.openPopup("ui_visibility_flags_add_popup", .{});
        }

        if (try _cdb.readSubObjSet(obj_r, prop_idx, allocator)) |tags| {
            for (tags) |flag_obj| {
                const flag_r = public.VisibilityFlagCdb.read(_cdb, flag_obj).?;
                const uuid = public.VisibilityFlagCdb.readValue(u32, _cdb, flag_r, .uuid);

                const iface = _g.uuid_to_iface.get(uuid).?;

                if (true) {
                    const style = _coreui.getStyle();
                    const pos_a = _coreui.getItemRectMax()[0];
                    const text_size = _coreui.calcTextSize(iface.name, .{})[0] + 2 * style.frame_padding[0];

                    if (pos_a + text_size + style.item_spacing[0] < _coreui.getWindowPos()[0] + _coreui.getContentRegionAvail()[0]) {
                        _coreui.sameLine(.{});
                    }
                }

                if (_coreui.button(iface.name, .{})) {
                    const obj_w = _cdb.writeObj(obj).?;
                    const flag_w = public.VisibilityFlagCdb.write(_cdb, flag_obj).?;
                    try public.VisibilityFlagsCdb.removeFromSubObjSet(_cdb, obj_w, .flags, flag_w);
                    try _cdb.writeCommit(obj_w);
                }
            }
        }

        if (_coreui.beginPopup("ui_visibility_flags_add_popup", .{})) {
            defer _coreui.endPopup();

            try flags_menu_aspect.add_menu(allocator, obj, 0, null);
        }
    }
});

var color4f_properties_aspec = editor_inspector.UiEmbedPropertiesAspect.implement(struct {
    pub fn ui(
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
        args: editor_inspector.cdbPropertiesViewArgs,
    ) !void {
        // _ = allocator;
        _ = args;

        _coreui.pushObjUUID(obj);
        defer _coreui.popId();

        const obj_r = public.VisibilityFlagsCdb.read(_cdb, obj) orelse return;

        if (_coreui.button(coreui.Icons.Add ++ "###AddVisibilityFlag", .{})) {
            _coreui.openPopup("ui_visibility_flags_add_popup", .{});
        }

        if (try public.VisibilityFlagsCdb.readSubObjSet(_cdb, obj_r, .flags, allocator)) |tags| {
            for (tags) |flag_obj| {
                const flag_r = public.VisibilityFlagCdb.read(_cdb, flag_obj).?;
                const uuid = public.VisibilityFlagCdb.readValue(u32, _cdb, flag_r, .uuid);

                const iface = _g.uuid_to_iface.get(uuid).?;

                if (true) {
                    const style = _coreui.getStyle();
                    const pos_a = _coreui.getItemRectMax()[0];
                    const text_size = _coreui.calcTextSize(iface.name, .{})[0] + 2 * style.frame_padding[0];

                    if (pos_a + text_size + style.item_spacing[0] < _coreui.getWindowPos()[0] + _coreui.getContentRegionAvail()[0]) {
                        _coreui.sameLine(.{});
                    }
                }

                if (_coreui.button(iface.name, .{})) {
                    const obj_w = _cdb.writeObj(obj).?;
                    const flag_w = public.VisibilityFlagCdb.write(_cdb, flag_obj).?;
                    try public.VisibilityFlagsCdb.removeFromSubObjSet(_cdb, obj_w, .flags, flag_w);
                    try _cdb.writeCommit(obj_w);
                }
            }
        }

        if (_coreui.beginPopup("ui_visibility_flags_add_popup", .{})) {
            defer _coreui.endPopup();

            try flags_menu_aspect.add_menu(allocator, obj, 0, null);
        }
    }
});

// Register all cdb stuff in this method
var create_cdb_types_i = cdb.CreateTypesI.implement(struct {
    pub fn createTypes(db: cdb.DbId) !void {
        // VisibilityFlagCdb

        const visibility_flag_type_idx = try _cdb.addType(
            db,
            public.VisibilityFlagCdb.name,
            &[_]cdb.PropDef{
                .{
                    .prop_idx = public.VisibilityFlagCdb.propIdx(.uuid),
                    .name = "uuid",
                    .type = cdb.PropType.U32,
                },
            },
        );
        _ = visibility_flag_type_idx; // autofix

        const visibility_flags_type_idx = try _cdb.addType(
            db,
            public.VisibilityFlagsCdb.name,
            &[_]cdb.PropDef{
                .{
                    .prop_idx = public.VisibilityFlagsCdb.propIdx(.flags),
                    .name = "flags",
                    .type = cdb.PropType.SUBOBJECT_SET,
                    .type_hash = public.VisibilityFlagCdb.type_hash,
                },
            },
        );
        // _ = visibility_flags_type_idx;

        const default_flags = try _cdb.createObject(db, visibility_flags_type_idx);
        const default_flags_w = _cdb.writeObj(default_flags).?;
        const impls = try _apidb.getImpl(_allocator, public.VisibilityFlagI);
        defer _allocator.free(impls);
        for (impls, 0..) |iface, idx| {
            _ = idx;
            if (iface.default) {
                const flag_obj = try public.VisibilityFlagCdb.createObject(_cdb, db);
                const flag_w = public.VisibilityFlagCdb.write(_cdb, flag_obj).?;
                public.VisibilityFlagCdb.setValue(u32, _cdb, flag_w, .uuid, iface.uuid);
                try public.VisibilityFlagsCdb.addSubObjToSet(_cdb, default_flags_w, .flags, &.{flag_w});
                try public.VisibilityFlagCdb.commit(_cdb, flag_w);
            }
        }
        try _cdb.writeCommit(default_flags_w);
        _cdb.setDefaultObject(default_flags);
    }
});

const post_create_types_i = cdb.PostCreateTypesI.implement(struct {
    pub fn postCreateTypes(db: cdb.DbId) !void {
        try public.VisibilityFlagsCdb.addPropertyAspect(
            editor.UiSetMenusAspect,
            _cdb,
            db,
            .flags,
            _g.component_value_menu_aspect,
        );

        try public.VisibilityFlagsCdb.addPropertyAspect(
            editor_inspector.UiEmbedPropertyAspect,
            _cdb,
            db,
            .flags,
            _g.tag_prop_aspect,
        );

        try public.VisibilityFlagsCdb.addAspect(
            editor_inspector.UiEmbedPropertiesAspect,
            _cdb,
            db,
            _g.visibility_flags_properties_aspect,
        );
    }
});

// Create types, register api, interfaces etc...
pub fn load_module_zig(apidb: *const cetech1.apidb.ApiDbAPI, allocator: Allocator, log_api: *const cetech1.log.LogAPI, load: bool, reload: bool) anyerror!bool {
    _ = reload; // autofix
    // basic
    _allocator = allocator;
    _log = log_api;
    _apidb = apidb;
    _cdb = apidb.getZigApi(module_name, cdb.CdbAPI).?;
    _kernel = apidb.getZigApi(module_name, cetech1.kernel.KernelApi).?;
    _tmpalloc = apidb.getZigApi(module_name, cetech1.tempalloc.TempAllocApi).?;
    _profiler = apidb.getZigApi(module_name, cetech1.profiler.ProfilerAPI).?;
    _task = apidb.getZigApi(module_name, cetech1.task.TaskAPI).?;
    _coreui = apidb.getZigApi(module_name, coreui.CoreUIApi).?;

    try apidb.setOrRemoveZigApi(module_name, public.VisibilityFlagsApi, &api, load);

    // impl interface
    try apidb.implOrRemove(module_name, cetech1.kernel.KernelTaskI, &kernel_task, load);
    try apidb.implOrRemove(module_name, cetech1.kernel.KernelTaskUpdateI, &update_task, load);
    try apidb.implOrRemove(module_name, cdb.CreateTypesI, &create_cdb_types_i, load);
    try apidb.implOrRemove(module_name, cdb.PostCreateTypesI, &post_create_types_i, load);

    // create global variable that can survive reload
    _g = try apidb.setGlobalVar(G, module_name, "_g", .{});

    _g.component_value_menu_aspect = try apidb.setGlobalVarValue(editor.UiSetMenusAspect, module_name, "ct_visibility_flags_menu_aspect", flags_menu_aspect);
    _g.tag_prop_aspect = try apidb.setGlobalVarValue(editor_inspector.UiEmbedPropertyAspect, module_name, "ct_visibility_flags_embed_propery_aspect", tag_prop_aspect);
    _g.visibility_flags_properties_aspect = try apidb.setGlobalVarValue(editor_inspector.UiEmbedPropertiesAspect, module_name, "ct_visibility_flags_embed_properties_aspect", color4f_properties_aspec);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_visibility_flags(apidb: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb, allocator, load, reload);
}
