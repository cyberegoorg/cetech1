const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");

const cdb = cetech1.cdb;
const ecs = cetech1.ecs;

const gpu = cetech1.gpu;
const coreui = cetech1.coreui;
const assetdb = cetech1.assetdb;

const editor = @import("editor");
const editor_inspector = @import("editor_inspector");

const public = @import("visibility_flags.zig");

const module_name = .visibility_flags;

// Need for logging from std.
pub const std_options: std.Options = .{
    .logFn = cetech1.log.zigLogFnGen(),
};
// Log for module
const log = std.log.scoped(module_name);

// Basic cetech "import".
var _allocator: Allocator = undefined;
const apidb = cetech1.apidb;

const tempalloc = cetech1.tempalloc;
const profiler = cetech1.profiler;
const task = cetech1.task;

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

    visibility_flags_menu_aspect: *editor.UiSetMenusAspect = undefined,
    visibility_flags_prop_aspect: *editor_inspector.UiInspectorPropertyValueAspect = undefined,
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

            const alloc = try tempalloc.create();
            defer tempalloc.destroy(alloc);

            const flags_i_version = apidb.getInterafcesVersion(public.VisibilityFlagI);
            if (flags_i_version != _g.flags_i_version) {
                log.debug("Supported visibility flags:", .{});

                _g.default_flags = .initEmpty();

                const impls = try apidb.getImpl(alloc, public.VisibilityFlagI);
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
const visibility_flags_menu_aspect = editor.UiSetMenusAspect.implement(struct {
    pub fn addMenu(
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
        prop_idx: u32,
        filter: ?[:0]const u8,
    ) !void {
        _ = prop_idx;
        _ = filter;

        const db = cdb.getDbFromObjid(obj);
        const flags_r = public.VisibilityFlagsCdb.read(obj).?;

        var active_flags_set = cetech1.ArraySet(u32).init();
        defer active_flags_set.deinit(allocator);

        if (try public.VisibilityFlagsCdb.readSubObjSet(flags_r, .Flags, allocator)) |flags| {
            defer allocator.free(flags);

            for (flags) |flag_obj| {
                const flag_r = public.VisibilityFlagCdb.read(flag_obj).?;
                const uuid = public.VisibilityFlagCdb.readValue(u32, flag_r, .UUID);
                _ = try active_flags_set.add(allocator, uuid);
            }
        }

        const impls = try apidb.getImpl(allocator, public.VisibilityFlagI);
        defer allocator.free(impls);

        for (impls) |iface| {
            if (iface.hash.isEmpty()) continue;
            if (active_flags_set.contains(iface.uuid)) continue;

            if (coreui.menuItem(_allocator, iface.name, .{}, null)) {
                const flag_obj = try public.VisibilityFlagCdb.createObject(db);
                const flag_w = public.VisibilityFlagCdb.write(flag_obj).?;
                const flags_w = public.VisibilityFlagsCdb.write(obj).?;

                public.VisibilityFlagCdb.setValue(u32, flag_w, .UUID, iface.uuid);

                try public.VisibilityFlagsCdb.addSubObjToSet(flags_w, .Flags, &.{flag_w});

                try public.VisibilityFlagCdb.commit(flag_w);
                try public.VisibilityFlagsCdb.commit(flags_w);
            }
        }
    }
});

var visibility_flags_prop_aspect = editor_inspector.UiInspectorPropertyValueAspect.implement(struct {
    pub fn ui(
        allocator: std.mem.Allocator,
        obj: cdb.ObjId,
        prop_idx: u32,
        args: editor_inspector.InspectorViewArgs,
    ) !void {
        _ = args.filter;
        const obj_r = cdb.readObj(obj) orelse return;
        //const db = cdb.getDbFromObjid(obj);

        if (coreui.button(coreui.Icons.Add ++ "###AddVisibilityFlag", .{})) {
            coreui.openPopup("ui_visibility_flags_add_popup", .{});
        }

        if (try cdb.readSubObjSet(obj_r, prop_idx, allocator)) |tags| {
            for (tags) |flag_obj| {
                const flag_r = public.VisibilityFlagCdb.read(flag_obj).?;
                const uuid = public.VisibilityFlagCdb.readValue(u32, flag_r, .UUID);

                const iface = _g.uuid_to_iface.get(uuid).?;

                if (true) {
                    const style = coreui.getStyle();
                    const pos_a = coreui.getItemRectMax().x;
                    const text_size = coreui.calcTextSize(iface.name, .{}).x + 2 * style.frame_padding.x;

                    if (pos_a + text_size + style.item_spacing.x < coreui.getWindowPos().x + coreui.getContentRegionAvail().x) {
                        coreui.sameLine(.{});
                    }
                }

                if (coreui.button(iface.name, .{})) {
                    const obj_w = cdb.writeObj(obj).?;
                    const flag_w = public.VisibilityFlagCdb.write(flag_obj).?;
                    try public.VisibilityFlagsCdb.removeFromSubObjSet(obj_w, .Flags, flag_w);
                    try cdb.writeCommit(obj_w);
                }
            }
        }

        if (coreui.beginPopup("ui_visibility_flags_add_popup", .{})) {
            defer coreui.endPopup();

            try visibility_flags_menu_aspect.add_menu(allocator, obj, 0, null);
        }
    }
});

// Register all cdb stuff in this method
var create_cdb_types_i = cdb.CreateTypesI.implement(struct {
    pub fn createTypes(db: cdb.DbId) !void {
        // VisibilityFlagCdb

        const visibility_flag_type_idx = try cdb.addType(
            db,
            public.VisibilityFlagCdb.name,
            &[_]cdb.PropDef{
                .{
                    .prop_idx = public.VisibilityFlagCdb.propIdx(.UUID),
                    .name = "uuid",
                    .type = cdb.PropType.U32,
                },
            },
        );
        _ = visibility_flag_type_idx;

        const visibility_flags_type_idx = try cdb.addType(
            db,
            public.VisibilityFlagsCdb.name,
            &[_]cdb.PropDef{
                .{
                    .prop_idx = public.VisibilityFlagsCdb.propIdx(.Flags),
                    .name = "flags",
                    .type = cdb.PropType.SUBOBJECT_SET,
                    .type_hash = public.VisibilityFlagCdb.type_hash,
                },
            },
        );
        // _ = visibility_flags_type_idx;

        const default_flags = try cdb.createObject(db, visibility_flags_type_idx);
        const default_flags_w = cdb.writeObj(default_flags).?;
        const impls = try apidb.getImpl(_allocator, public.VisibilityFlagI);
        defer _allocator.free(impls);
        for (impls, 0..) |iface, idx| {
            _ = idx;
            if (iface.default) {
                const flag_obj = try public.VisibilityFlagCdb.createObject(db);
                const flag_w = public.VisibilityFlagCdb.write(flag_obj).?;
                public.VisibilityFlagCdb.setValue(u32, flag_w, .UUID, iface.uuid);
                try public.VisibilityFlagsCdb.addSubObjToSet(default_flags_w, .Flags, &.{flag_w});
                try public.VisibilityFlagCdb.commit(flag_w);
            }
        }
        try cdb.writeCommit(default_flags_w);
        cdb.setDefaultObject(default_flags);
    }
});

const post_create_types_i = cdb.PostCreateTypesI.implement(struct {
    pub fn postCreateTypes(db: cdb.DbId) !void {
        try public.VisibilityFlagsCdb.addPropertyAspect(
            editor.UiSetMenusAspect,

            db,
            .Flags,
            _g.visibility_flags_menu_aspect,
        );

        try public.VisibilityFlagsCdb.addPropertyAspect(
            editor_inspector.UiInspectorPropertyValueAspect,

            db,
            .Flags,
            _g.visibility_flags_prop_aspect,
        );
    }
});

// Create types, register api, interfaces etc...
pub fn load_module_zig(allocator: Allocator, load: bool, reload: bool) anyerror!bool {
    _ = reload;
    // basic
    _allocator = allocator;
    public.api = &api;

    try cdb.loadAPI(module_name);
    // try kernel.loadAPI(module_name);
    try tempalloc.loadAPI(module_name);
    try profiler.loadAPI(module_name);
    try task.loadAPI(module_name);
    try coreui.loadAPI(module_name);

    try apidb.setOrRemoveZigApi(module_name, public.VisibilityFlagsApi, &api, load);

    // impl interface
    try apidb.implOrRemove(module_name, cetech1.kernel.KernelTaskI, &kernel_task, load);
    try apidb.implOrRemove(module_name, cetech1.kernel.KernelTaskUpdateI, &update_task, load);
    try apidb.implOrRemove(module_name, cdb.CreateTypesI, &create_cdb_types_i, load);
    try apidb.implOrRemove(module_name, cdb.PostCreateTypesI, &post_create_types_i, load);

    // create global variable that can survive reload
    _g = try apidb.setGlobalVar(G, module_name, "_g", .{});

    _g.visibility_flags_menu_aspect = try apidb.setGlobalVarValue(editor.UiSetMenusAspect, module_name, "ct_visibility_flags_menu_aspect", visibility_flags_menu_aspect);
    _g.visibility_flags_prop_aspect = try apidb.setGlobalVarValue(editor_inspector.UiInspectorPropertyValueAspect, module_name, "ct_visibility_flags_embed_propery_aspect", visibility_flags_prop_aspect);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_visibility_flags(apidb_: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, apidb_, allocator, load, reload);
}
