const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");
const public = @import("editor.zig");
const Icons = cetech1.editorui.Icons;

const MODULE_NAME = "editor";

const PROP_HEADER_BG_COLOR = .{ 0.2, 0.2, 0.2, 0.65 };
const PROTOTYPE_PROPERTY_COLOR = .{ 0.5, 0.5, 0.5, 1.0 };
const PROTOTYPE_PROPERTY_OVERIDED_COLOR = .{ 0.0, 0.8, 1.0, 1.0 };
const INSIATED_COLOR = .{ 1.0, 0.6, 0.0, 1.0 };
const REMOVED_COLOR = .{ 0.7, 0.0, 0.0, 1.0 };

var _allocator: Allocator = undefined;
var _apidb: *cetech1.apidb.ApiDbAPI = undefined;
var _log: *cetech1.log.LogAPI = undefined;
var _cdb: *cetech1.cdb.CdbAPI = undefined;
var _kernel: *cetech1.kernel.KernelApi = undefined;
var _editorui: *cetech1.editorui.EditorUIApi = undefined;
var _assetdb: *cetech1.assetdb.AssetDBAPI = undefined;
var _tempalloc: *cetech1.tempalloc.TempAllocApi = undefined;

const TabsSelectedObject = std.AutoArrayHashMap(*public.c.struct_ct_editorui_tab_i, cetech1.cdb.ObjId);
const TabsMap = std.AutoArrayHashMap(*anyopaque, *public.c.struct_ct_editorui_tab_i);
const TabsIdPool = cetech1.mem.IdPool(u32);
const TabsIds = std.AutoArrayHashMap(cetech1.strid.StrId32, TabsIdPool);

// Global state
const G = struct {
    main_db: cetech1.cdb.CdbDb = undefined,
    show_demos: bool = false,
    tabs: TabsMap = undefined,
    tabids: TabsIds = undefined,
    tab2selectedobj: TabsSelectedObject = undefined,
    last_selected_obj: cetech1.cdb.ObjId = undefined,
    last_focused_tab: ?*public.c.struct_ct_editorui_tab_i = null,
};
var _g: *G = undefined;

var api = public.EditorAPI{
    .selectObj = selectObj,
    .openTabWithPinnedObj = openTabWithPinnedObj,
    .cdbTreeView = cdbTreeView,
    .cdbTreeNode = cdbTreeNode,
    .cdbTreePop = cdbTreePop,
    .cdbPropertiesView = cdbPropertiesView,
    .cdbPropertiesObj = cdbPropertiesObj,
    .uiAssetInput = uiAssetInput,
    .uiPropLabel = uiPropLabel,
    .uiPropInput = uiInputForProperty,
    .formatedPropNameToBuff = formatedPropNameToBuff,
    .getPropertyColor = getPropertyColor,
    .uiPropInputBegin = uiPropInputBegin,
    .uiPropInputEnd = uiPropInputEnd,
};

fn getPropertyColor(db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId, prop_idx: u32) ?[4]f32 {
    const prototype_obj = db.getPrototype(db.readObj(obj).?);
    const has_prototype = !prototype_obj.isEmpty();

    var color: ?[4]f32 = null;
    if (has_prototype) {
        color = PROTOTYPE_PROPERTY_COLOR;
        if (db.isPropertyOverrided(db.readObj(obj).?, prop_idx)) {
            color = PROTOTYPE_PROPERTY_OVERIDED_COLOR;
        }
    }
    return color;
}

fn uiInputProtoBtns(db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId, prop_idx: u32) !void {
    const proto_obj = db.getPrototype(db.readObj(obj).?);
    if (proto_obj.isEmpty()) return;

    const types = db.getTypePropDef(obj.type_hash).?;
    const prop_def = types[prop_idx];

    const is_overided = db.isPropertyOverrided(db.readObj(obj).?, prop_idx);

    if (prop_def.type == .BLOB) return;

    if (_editorui.beginPopup("property_protoypes_menu", .{})) {
        if (_editorui.menuItem(Icons.FA_ARROW_ROTATE_LEFT ++ "  " ++ "Reset to prototype value", .{ .enabled = is_overided })) {
            var w = db.writeObj(obj).?;
            defer db.writeCommit(w);
            db.resetPropertyOveride(w, prop_idx);
        }

        if (_editorui.menuItem(Icons.FA_ARROW_UP ++ "  " ++ "Propagate to prototype", .{ .enabled = is_overided })) {
            // Set value from parent. This is probably not need.
            {
                var w = db.writeObj(proto_obj).?;
                defer db.writeCommit(w);
                var r = db.readObj(obj).?;

                switch (prop_def.type) {
                    .BOOL => {
                        const value = db.readValue(bool, r, prop_idx);
                        db.setValue(bool, w, prop_idx, value);
                    },
                    .F32 => {
                        const value = db.readValue(f32, r, prop_idx);
                        db.setValue(f32, w, prop_idx, value);
                    },
                    .F64 => {
                        const value = db.readValue(f64, r, prop_idx);
                        db.setValue(f64, w, prop_idx, value);
                    },
                    .I32 => {
                        const value = db.readValue(i32, r, prop_idx);
                        db.setValue(i32, w, prop_idx, value);
                    },
                    .U32 => {
                        const value = db.readValue(u32, r, prop_idx);
                        db.setValue(u32, w, prop_idx, value);
                    },
                    .I64 => {
                        const value = db.readValue(i64, r, prop_idx);
                        db.setValue(i64, w, prop_idx, value);
                    },
                    .U64 => {
                        const value = db.readValue(u64, r, prop_idx);
                        db.setValue(u64, w, prop_idx, value);
                    },
                    .STR => {
                        if (db.readStr(r, prop_idx)) |str| {
                            try db.setStr(w, prop_idx, str);
                        }
                    },
                    .BLOB => {},
                    else => {},
                }
                db.resetPropertyOveride(w, prop_idx);
            }

            // reset value overide
            {
                var w = db.writeObj(obj).?;
                defer db.writeCommit(w);
                db.resetPropertyOveride(w, prop_idx);
            }
        }

        _editorui.endPopup();
    }

    if (_editorui.button(Icons.FA_ARROWS_TURN_TO_DOTS, .{})) {
        _editorui.openPopup("property_protoypes_menu", .{});
    }

    _editorui.sameLine(.{});
}

fn uiPropInputBegin(db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId, prop_idx: u32) !void {
    _editorui.tableNextColumn();

    var reader = db.readObj(obj).?;

    _editorui.pushPtrId(reader);
    _editorui.pushIntId(prop_idx);

    try uiInputProtoBtns(db, obj, prop_idx);

    _editorui.setNextItemWidth(-std.math.floatMin(f32));
}

fn uiPropInputEnd() void {
    _editorui.popId();
    _editorui.popId();
}

fn uiInputForProperty(db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId, prop_idx: u32) !void {
    var buf: [128:0]u8 = undefined;
    @memset(&buf, 0);

    var reader = db.readObj(obj).?;

    try uiPropInputBegin(db, obj, prop_idx);
    defer uiPropInputEnd();

    var prop_defs = db.getTypePropDef(obj.type_hash).?;
    var prop_def = prop_defs[prop_idx];

    switch (prop_def.type) {
        .BOOL => {
            var value = db.readValue(bool, reader, prop_idx);
            if (_editorui.checkbox("", .{
                .v = &value,
            })) {
                var w = db.writeObj(obj).?;
                defer db.writeCommit(w);
                db.setValue(bool, w, prop_idx, value);
            }
        },
        .F32 => {
            var value = db.readValue(f32, reader, prop_idx);
            if (_editorui.inputFloat("", .{
                .v = &value,
                .flags = .{
                    .enter_returns_true = true,
                },
            })) {
                var w = db.writeObj(obj).?;
                defer db.writeCommit(w);
                db.setValue(f32, w, prop_idx, value);
            }
        },
        .F64 => {
            var value = db.readValue(f64, reader, prop_idx);
            if (_editorui.inputDouble("", .{
                .v = &value,
                .flags = .{
                    .enter_returns_true = true,
                },
            })) {
                var w = db.writeObj(obj).?;
                defer db.writeCommit(w);
                db.setValue(f64, w, prop_idx, value);
            }
        },
        .I32 => {
            var value = db.readValue(i32, reader, prop_idx);
            if (_editorui.inputI32("", .{
                .v = &value,
                .flags = .{
                    .enter_returns_true = true,
                },
            })) {
                var w = db.writeObj(obj).?;
                defer db.writeCommit(w);
                db.setValue(i32, w, prop_idx, value);
            }
        },
        .U32 => {
            var value = db.readValue(u32, reader, prop_idx);
            if (_editorui.inputU32("", .{
                .v = &value,
                .flags = .{
                    .enter_returns_true = true,
                },
            })) {
                var w = db.writeObj(obj).?;
                defer db.writeCommit(w);
                db.setValue(u32, w, prop_idx, value);
            }
        },
        .I64 => {
            var value = db.readValue(i64, reader, prop_idx);
            if (_editorui.inputI64("", .{
                .v = &value,
                .flags = .{
                    .enter_returns_true = true,
                },
            })) {
                var w = db.writeObj(obj).?;
                defer db.writeCommit(w);
                db.setValue(i64, w, prop_idx, value);
            }
        },
        .U64 => {
            var value = db.readValue(u64, reader, prop_idx);
            if (_editorui.inputU64("", .{
                .v = &value,
                .flags = .{
                    .enter_returns_true = true,
                },
            })) {
                var w = db.writeObj(obj).?;
                defer db.writeCommit(w);
                db.setValue(u64, w, prop_idx, value);
            }
        },
        .STR => {
            var name = db.readStr(reader, prop_idx);
            if (name) |str| {
                _ = try std.fmt.bufPrintZ(&buf, "{s}", .{str});
            }
            if (_editorui.inputText("", .{
                .buf = &buf,
                .flags = .{
                    .enter_returns_true = true,
                },
            })) {
                var w = db.writeObj(obj).?;
                defer db.writeCommit(w);
                var new_name_buf: [128:0]u8 = undefined;
                var new_name = try std.fmt.bufPrintZ(&new_name_buf, "{s}", .{std.mem.sliceTo(&buf, 0)});
                try db.setStr(w, prop_idx, new_name);
            }
        },
        .BLOB => {
            _editorui.textUnformatted("---");
        },
        else => {
            _editorui.textUnformatted("- !!INVALID TYPE!! -");
            _log.err(MODULE_NAME, "Invalid property type for uiInputForProperty {}", .{prop_def.type});
        },
    }
}

fn uiPropLabel(name: [:0]const u8, color: ?[4]f32) void {
    _editorui.tableNextColumn();
    _editorui.alignTextToFramePadding();

    if (color) |c| {
        _editorui.textUnformattedColored(c, name);
    } else {
        _editorui.textUnformatted(name);
    }
}

fn formatedPropNameToBuff(buf: []u8, prop_name: [:0]const u8) ![]u8 {
    var split = std.mem.split(u8, prop_name, "_");
    const first = split.first();

    var buff_stream = std.io.fixedBufferStream(buf);
    var writer = buff_stream.writer();

    var tmp_buf: [128]u8 = undefined;

    var it: ?[]const u8 = first;
    while (it) |word| : (it = split.next()) {
        var word_formated = try std.fmt.bufPrint(&tmp_buf, "{s}", .{word});

        if (word.ptr == first.ptr) {
            word_formated[0] = std.ascii.toUpper(word_formated[0]);
        }

        _ = try writer.write(word_formated);
        _ = try writer.write(" ");
    }

    var writen = buff_stream.getWritten();
    return writen[0 .. writen.len - 1];
}
fn uiAssetInput(allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId, read_only: bool) !void {
    if (_assetdb.getAssetForObj(obj)) |proto_asset| {
        var buff: [128:0]u8 = undefined;
        var path = try _assetdb.getFilePathForAsset(proto_asset, allocator);
        defer allocator.free(path);

        var asset_name = try std.fmt.bufPrintZ(&buff, "{s}", .{path});

        var reader = db.readObj(obj).?;
        _editorui.pushPtrId(reader);
        defer _editorui.popId();

        _editorui.tableNextColumn();

        if (_editorui.beginPopup("ui_asset_context_menu", .{})) {
            if (_editorui.menuItem("Select asset", .{ .enabled = true })) {
                selectObj(db, proto_asset);
            }

            _editorui.endPopup();
        }

        if (_editorui.button(Icons.FA_ELLIPSIS, .{})) {
            _editorui.openPopup("ui_asset_context_menu", .{});
        }
        _editorui.sameLine(.{});
        _editorui.setNextItemWidth(-std.math.floatMin(f32));
        _ = _editorui.inputText("", .{
            .buf = asset_name,
            .flags = .{
                .read_only = read_only,
                .auto_select_all = true,
            },
        });
    }
}
fn cdbPropertiesView(allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId, args: public.cdbPropertiesViewArgs) !void {
    if (_editorui.beginTable("Properties", .{
        .column = 2,
        .flags = .{
            .resizable = true,
            .no_saved_settings = true,
            .borders = cetech1.editorui.TableBorderFlags.all,
        },
    })) {
        _editorui.tableSetupColumn("Name", .{});
        _editorui.tableSetupColumn("Value", .{});
        _editorui.tableHeadersRow();

        try cdbPropertiesObj(allocator, db, obj, args);

        _editorui.endTable();
    }
}

fn cdbPropertiesObj(allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId, args: public.cdbPropertiesViewArgs) !void {
    // Find properties asspect for obj type.
    var ui_aspect = db.getAspect(public.c.ct_editorui_ui_properties_aspect, obj.type_hash);
    if (ui_aspect) |aspect| {
        aspect.ui_properties.?(@constCast(@ptrCast(&allocator)), @ptrCast(db.db), obj.toC(public.c.ct_cdb_objid_t));
        return;
    }

    const prototype_obj = db.getPrototype(db.readObj(obj).?);
    const has_prototype = !prototype_obj.isEmpty();

    var prop_defs = db.getTypePropDef(obj.type_hash).?;

    var buff: [128:0]u8 = undefined;
    var prop_name_buff: [128:0]u8 = undefined;

    // Show prototype ui
    if (has_prototype) {
        api.uiPropLabel("Prototype", null);
        try api.uiAssetInput(allocator, db, prototype_obj, true);
    }

    for (prop_defs, 0..) |prop_def, idx| {
        const prop_idx: u32 = @truncate(idx);

        const prop_name = try api.formatedPropNameToBuff(&prop_name_buff, prop_def.name);
        const prop_color = api.getPropertyColor(db, obj, prop_idx);

        var ui_prop_aspect = db.getPropertyAspect(public.c.ct_editorui_ui_property_aspect, obj.type_hash, prop_idx);

        // If exist aspect and is empty hide property.
        if (ui_prop_aspect) |aspect| {
            if (aspect.ui_property == null) continue;
        }

        switch (prop_def.type) {
            .SUBOBJECT, .REFERENCE => {
                var subobj: cetech1.cdb.ObjId = undefined;

                if (prop_def.type == .REFERENCE) {
                    subobj = db.readRef(db.readObj(obj).?, prop_idx) orelse continue;
                } else {
                    subobj = db.readSubObj(db.readObj(obj).?, prop_idx) orelse continue;
                }

                var label = try std.fmt.bufPrintZ(&buff, "{s}{s}", .{ prop_name, if (prop_def.type == .REFERENCE) " " ++ Icons.FA_LINK else "" });
                _editorui.tableNextColumn();

                if (prop_color) |c| {
                    _editorui.pushStyleColor4f(.{ .idx = .text, .c = c });
                }

                var open = _editorui.treeNode(label);

                if (prop_color != null) {
                    _editorui.popStyleColor(.{});
                }

                _editorui.tableNextColumn();

                _editorui.tableSetBgColor(.{
                    .color = _editorui.colorConvertFloat4ToU32(PROP_HEADER_BG_COLOR),
                    .target = .row_bg0,
                });

                if (open) {
                    try cdbPropertiesObj(allocator, db, subobj, args);
                    _editorui.treePop();
                }
            },
            .SUBOBJECT_SET, .REFERENCE_SET => {
                var prop_label = try std.fmt.bufPrintZ(&buff, "{s}{s}", .{ prop_name, if (prop_def.type == .REFERENCE_SET) " " ++ Icons.FA_LINK else "" });

                _editorui.tableNextColumn();
                var open = _editorui.treeNode(prop_label);
                _editorui.tableNextColumn();

                _editorui.tableSetBgColor(.{
                    .color = _editorui.colorConvertFloat4ToU32(PROP_HEADER_BG_COLOR),
                    .target = .row_bg0,
                });

                if (open) {
                    var set: ?[]const cetech1.cdb.ObjId = undefined;
                    if (prop_def.type == .REFERENCE_SET) {
                        set = db.readRefSet(db.readObj(obj).?, prop_idx, allocator);
                    } else {
                        set = try db.readSubObjSet(db.readObj(obj).?, prop_idx, allocator);
                    }

                    if (set) |s| {
                        defer allocator.free(set.?);

                        for (s, 0..) |subobj, set_idx| {
                            var label = try std.fmt.bufPrintZ(&buff, "{d}", .{set_idx});
                            _editorui.tableNextColumn();
                            var open_inset = _editorui.treeNode(label);
                            _editorui.tableNextColumn();
                            if (open_inset) {
                                try cdbPropertiesObj(allocator, db, subobj, args);
                                _editorui.treePop();
                            }
                        }
                    }
                    _editorui.treePop();
                }
            },

            else => {
                var label = try std.fmt.bufPrintZ(&buff, "{s}", .{prop_name});
                api.uiPropLabel(label, prop_color);

                if (ui_prop_aspect) |aspect| {
                    if (aspect.ui_property) |ui| {
                        ui(@constCast(@ptrCast(&allocator)), @ptrCast(db.db), obj.toC(public.c.ct_cdb_objid_t), prop_idx);
                    }
                } else {
                    try api.uiPropInput(db, obj, prop_idx);
                }
            },
        }
    }
}

fn cdbTreeNode(label: [:0]const u8, default_open: bool, no_push: bool, selected: bool) bool {
    return _editorui.treeNodeFlags(label, .{ .open_on_arrow = true, .default_open = default_open, .no_tree_push_on_open = no_push, .selected = selected });
}

fn cdbTreePop() void {
    return _editorui.treePop();
}

fn openTabWithPinnedObj(db: *cetech1.cdb.CdbDb, tab_type_hash: cetech1.strid.StrId32, obj: cetech1.cdb.ObjId) void {
    if (createNewTab(tab_type_hash)) |tab| {
        tabSelectObj(db, obj, tab);
        tab.pinned_obj = true;
    }
}

fn tabSelectObj(db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId, tab: *public.c.struct_ct_editorui_tab_i) void {
    _g.tab2selectedobj.put(tab, obj) catch undefined;
    if (tab.vt.*.obj_selected) |obj_selected| {
        obj_selected(tab.inst, @ptrCast(db.db), .{ .id = obj.id, .type_hash = .{ .id = obj.type_hash.id } });
    }
}

fn selectObj(db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId) void {
    for (_g.tabs.values()) |tab| {
        if (tab.pinned_obj) continue;
        tabSelectObj(db, obj, tab);
    }

    _g.last_selected_obj = obj;
}

fn alocateTabId(tab_hash: cetech1.strid.StrId32) !u32 {
    var get_or_put = try _g.tabids.getOrPut(tab_hash);
    if (!get_or_put.found_existing) {
        var pool = TabsIdPool.init(_allocator);
        get_or_put.value_ptr.* = pool;
    }

    return get_or_put.value_ptr.create(null);
}

fn dealocateTabId(tab_hash: cetech1.strid.StrId32, tabid: u32) !void {
    var pool = _g.tabids.getPtr(tab_hash).?;
    try pool.destroy(tabid);
}

fn createNewTab(tab_hash: cetech1.strid.StrId32) ?*public.c.ct_editorui_tab_i {
    var it = _apidb.getFirstImpl(public.c.ct_editorui_tab_type_i);
    while (it) |node| : (it = node.next) {
        var iface = cetech1.apidb.ApiDbAPI.toInterface(public.c.ct_editorui_tab_type_i, node);
        if (iface.tab_hash.id != tab_hash.id) continue;

        var tab_inst = iface.*.create.?(@ptrCast(_g.main_db.db));
        _g.tabs.put(tab_inst.*.inst.?, tab_inst) catch undefined;
        tab_inst.*.tabid = alocateTabId(.{ .id = tab_inst.*.vt.*.tab_hash.id }) catch undefined;
        return tab_inst;
    }
    return null;
}

fn destroyTab(tab: *public.c.ct_editorui_tab_i) void {
    if (tab.vt.*.destroy) |tab_destroy| {
        std.debug.assert(_g.tabs.swapRemove(tab.inst));
        dealocateTabId(.{ .id = tab.vt.*.tab_hash.id }, tab.tabid) catch undefined;
        tab_destroy(tab);
    }
    if (_g.last_focused_tab == tab) {
        _g.last_focused_tab = null;
    }
}

const modal_quit = "Quit?";
var show_quit_modal = false;
fn quitSaveModal() !void {
    if (show_quit_modal) {
        _editorui.openPopup(modal_quit, .{});
    }

    if (_editorui.beginPopupModal(
        modal_quit,
        .{ .flags = .{
            .always_auto_resize = true,
            .no_saved_settings = true,
        } },
    )) {
        _editorui.textUnformatted("Project have unsaved changes.\nWhat do you do?");

        if (_editorui.button(public.Icons.SaveAll ++ " " ++ public.Icons.Quit ++ " " ++ "Save and Quit", .{})) {
            _editorui.closeCurrentPopup();

            var tmp_arena = _tempalloc.createTempArena() catch undefined;
            defer _tempalloc.destroyTempArena(tmp_arena);

            try _assetdb.saveAllModifiedAssets(tmp_arena.allocator());
            _kernel.quit();
            show_quit_modal = false;
        }

        _editorui.sameLine(.{});
        if (_editorui.button(public.Icons.Quit ++ " " ++ "Quit", .{})) {
            _editorui.closeCurrentPopup();
            _kernel.quit();
            show_quit_modal = false;
        }

        _editorui.sameLine(.{});
        if (_editorui.button(public.Icons.Nothing ++ "" ++ "Nothing", .{})) {
            _editorui.closeCurrentPopup();
            show_quit_modal = false;
        }

        _editorui.endPopup();
    }
}

fn tryQuit() void {
    if (_assetdb.isProjectModified()) {
        show_quit_modal = true;
    } else {
        _kernel.quit();
    }
}

fn doMainMenu(alocator: std.mem.Allocator) !void {
    _editorui.beginMainMenuBar();

    if (_editorui.beginMenu("Editor", true)) {
        defer _editorui.endMenu();

        if (_editorui.menuItem(public.Icons.OpenProject ++ "  " ++ "Open project", .{})) {
            var buf: [256:0]u8 = undefined;
            var str = try std.fs.cwd().realpath(".", &buf);
            buf[str.len] = 0;

            if (try _editorui.openFileDialog(cetech1.assetdb.ProjectType.name, @ptrCast(&buf))) |path| {
                defer _editorui.freePath(path);
                var dir = std.fs.path.dirname(path).?;
                selectObj(&_g.main_db, cetech1.cdb.OBJID_ZERO);
                try _assetdb.openAssetRootFolder(dir, _allocator);
            }
        }

        if (_editorui.menuItem(public.Icons.SaveAll ++ "  " ++ "Save all", .{ .enabled = _assetdb.isProjectModified() })) {
            try _assetdb.saveAllModifiedAssets(alocator);
        }

        _editorui.separator();

        if (_editorui.menuItem(public.Icons.Quit ++ "  " ++ "Quit", .{})) tryQuit();
    }

    try doTabMainMenu(alocator);

    if (_editorui.beginMenu("Window", true)) {
        _editorui.endMenu();
    }

    if (_editorui.beginMenu(public.Icons.Debug, true)) {
        if (_editorui.menuItem(public.Icons.SaveAll ++ "  " ++ "Force save all", .{ .enabled = _assetdb.isProjectOpened() })) {
            try _assetdb.saveAllAssets(alocator);
        }

        _editorui.separator();
        _ = _editorui.menuItemPtr("Show EditorUI demos", .{ .selected = &_g.show_demos });

        _editorui.separatorText("Kernel tick rate");

        var rate = _kernel.getKernelTickRate();
        if (_editorui.inputU32("###kernel_tick_rate", .{ .v = &rate, .flags = .{ .enter_returns_true = true } })) {
            _kernel.setKernelTickRate(rate);
        }

        _editorui.endMenu();
    }

    _editorui.endMainMenuBar();
}

fn doTabMainMenu(alocator: std.mem.Allocator) !void {
    if (_editorui.beginMenu("Tabs", true)) {
        if (_editorui.beginMenu(public.Icons.OpenTab ++ "  " ++ "Create", true)) {
            // Create tabs
            var it = _apidb.getFirstImpl(public.c.ct_editorui_tab_type_i);
            while (it) |node| : (it = node.next) {
                var iface = cetech1.apidb.ApiDbAPI.toInterface(public.c.ct_editorui_tab_type_i, node);
                var menu_name = if (iface.menu_name) |menu_name_fce| menu_name_fce() else continue;

                var tab_type_menu_name = cetech1.fromCstrZ(menu_name);
                if (_editorui.menuItem(tab_type_menu_name, .{})) {
                    var tab_inst = createNewTab(.{ .id = iface.tab_hash.id });
                    _ = tab_inst;
                }
            }
            _editorui.endMenu();
        }

        if (_editorui.beginMenu(public.Icons.CloseTab ++ "  " ++ "Close", _g.tabs.count() != 0)) {
            var tabs = std.ArrayList(*public.c.struct_ct_editorui_tab_i).init(alocator);
            defer tabs.deinit();
            try tabs.appendSlice(_g.tabs.values());

            for (tabs.items) |tab| {
                var buf: [128]u8 = undefined;
                var tab_title_full = try std.fmt.bufPrintZ(&buf, "{s} {d}", .{ cetech1.fromCstrZ(tab.vt.*.menu_name.?()), tab.tabid });
                if (_editorui.menuItem(tab_title_full, .{})) {
                    destroyTab(tab);
                }
            }
            _editorui.endMenu();
        }

        _editorui.endMenu();
    }
}

fn doTabs(tmp_allocator: std.mem.Allocator) !void {
    var tabs = std.ArrayList(*public.c.struct_ct_editorui_tab_i).init(tmp_allocator);
    defer tabs.deinit();
    try tabs.appendSlice(_g.tabs.values());

    for (tabs.items) |tab| {
        var tab_open = true;

        var tab_title = tab.vt.*.title.?(tab.inst.?);

        var tab_selected_object = _g.tab2selectedobj.get(tab);
        var asset_name_buf: [128]u8 = undefined;
        var asset_name: ?[]u8 = null;

        if (tab.vt.*.show_sel_obj_in_title) {
            if (tab_selected_object) |selected_obj| {
                if (_assetdb.getAssetForObj(selected_obj)) |asset| {
                    const type_name = _g.main_db.getTypeName(asset.type_hash).?;
                    const asset_name_str = cetech1.assetdb.AssetType.readStr(&_g.main_db, _g.main_db.readObj(asset).?, .Name).?;
                    asset_name = try std.fmt.bufPrint(&asset_name_buf, "- {s}.{s}", .{ asset_name_str, type_name });
                }
            }
        }

        // {s}###{} => ### use last part as id and survive label change. ## use lable+id
        var buf: [128]u8 = undefined;
        var tab_title_full = try std.fmt.bufPrintZ(
            &buf,
            "{s} {d} " ++ "{s}" ++ "###{s}_{d}",
            .{
                cetech1.fromCstrZ(tab_title),
                tab.tabid,
                if (asset_name) |n| n else "",
                tab.vt.*.tab_name.?,
                tab.tabid,
            },
        );

        const tab_flags = cetech1.editorui.WindowFlags{
            .menu_bar = true, //tab.vt.*.menu != null,
            //.no_saved_settings = true,
        };
        if (_editorui.begin(tab_title_full, .{ .popen = &tab_open, .flags = tab_flags })) {
            if (_editorui.isWindowFocused(cetech1.editorui.FocusedFlags.root_and_child_windows)) {
                if (_g.last_focused_tab != tab) {
                    _g.last_focused_tab = tab;
                    if (tab.vt.*.focused) |focused| {
                        focused(tab.inst);
                    }
                }
            }

            // Draw menu if needed.
            if (tab.vt.*.menu) |tab_menu| {
                _editorui.beginMenuBar();

                // If needed show pin object button
                if (tab.vt.*.show_pin_object) {
                    var new_pinned = tab.pinned_obj;
                    if (_editorui.menuItemPtr(if (tab.pinned_obj) Icons.FA_LOCK else Icons.FA_LOCK_OPEN ++ "", .{ .selected = &new_pinned })) {
                        tab.pinned_obj = new_pinned;
                        tabSelectObj(@ptrCast(&_g.main_db.db), _g.last_selected_obj, tab);
                    }
                }

                tab_menu(tab.inst);
                _editorui.endMenuBar();
            }

            // Draw content if needed.
            if (tab.vt.*.ui) |tab_ui| {
                tab_ui(tab.inst);
            }
        }
        _editorui.end();

        if (!tab_open) {
            destroyTab(tab);
        }
    }
}

fn editorui_ui(callocator: ?*const cetech1.c.ct_allocator_t) callconv(.C) void {
    var allocator = cetech1.modules.allocFromCApi(callocator.?);
    doMainMenu(allocator) catch undefined;
    quitSaveModal() catch undefined;
    doTabs(allocator) catch undefined;

    if (_g.show_demos) _editorui.showDemoWindow();
}

var editorui_ui_i = cetech1.c.ct_editorui_ui_i{ .ui = editorui_ui };

fn cdbTreeView(allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId, selected_obj: cetech1.cdb.ObjId, args: public.CdbTreeViewArgs) !?cetech1.cdb.ObjId {
    // if exist aspect use it
    var ui_aspect = db.getAspect(public.c.ct_editorui_ui_tree_aspect, obj.type_hash);
    if (ui_aspect) |aspect| {
        var new_selected = aspect.ui_tree.?(@constCast(@ptrCast(&allocator)), @ptrCast(db.db), obj.toC(public.c.ct_cdb_objid_t), selected_obj.toC(public.c.ct_cdb_objid_t), args.expand_object);
        if (new_selected.id != 0) {
            return cetech1.cdb.ObjId.fromC(public.c.ct_cdb_objid_t, new_selected);
        }
        return null;
    }

    var reader = db.readObj(obj).?;
    _editorui.pushPtrId(reader);
    defer _editorui.popId();

    // Do generic tree walk
    var prop_defs = db.getTypePropDef(obj.type_hash).?;

    var buff: [128:0]u8 = undefined;
    var prop_name_buff: [128:0]u8 = undefined;
    var new_selected: ?cetech1.cdb.ObjId = null;
    for (prop_defs, 0..) |prop_def, idx| {
        const prop_idx: u32 = @truncate(idx);
        const prop_name = try api.formatedPropNameToBuff(&prop_name_buff, prop_def.name);

        _editorui.pushIntId(prop_idx);
        defer _editorui.popId();

        switch (prop_def.type) {
            .SUBOBJECT, .REFERENCE => {
                var subobj: cetech1.cdb.ObjId = undefined;

                if (prop_def.type == .REFERENCE) {
                    subobj = db.readRef(db.readObj(obj).?, prop_idx) orelse continue;
                } else {
                    subobj = db.readSubObj(db.readObj(obj).?, prop_idx) orelse continue;
                }

                var label = try std.fmt.bufPrintZ(
                    &buff,
                    "{s}{s}",
                    .{ prop_name, if (prop_def.type == .REFERENCE) " " ++ Icons.FA_LINK else "" },
                );

                const color = api.getPropertyColor(db, obj, prop_idx);
                if (color) |c| {
                    _editorui.pushStyleColor4f(.{ .idx = .text, .c = c });
                }

                var open = api.cdbTreeNode(label, false, false, selected_obj.eq(subobj));

                if (color != null) {
                    _editorui.popStyleColor(.{});
                }

                if (_editorui.isItemActivated()) {
                    new_selected = subobj;
                }

                if (open) {
                    if (try cdbTreeView(allocator, db, subobj, selected_obj, args)) |s| {
                        new_selected = s;
                    }
                    api.cdbTreePop();
                }
            },
            .SUBOBJECT_SET, .REFERENCE_SET => {
                var prop_label = try std.fmt.bufPrintZ(
                    &buff,
                    "{s}{s}",
                    .{ prop_name, if (prop_def.type == .REFERENCE_SET) " " ++ Icons.FA_LINK else "" },
                );
                var open = api.cdbTreeNode(prop_label, false, false, false);

                if (open) {
                    // added
                    var set: ?[]const cetech1.cdb.ObjId = undefined;
                    if (prop_def.type == .REFERENCE_SET) {
                        set = db.readRefSet(db.readObj(obj).?, prop_idx, allocator);
                    } else {
                        set = try db.readSubObjSet(db.readObj(obj).?, prop_idx, allocator);
                    }

                    var inisiated_prototypes = std.AutoHashMap(cetech1.cdb.ObjId, void).init(allocator);
                    defer inisiated_prototypes.deinit();

                    if (set) |s| {
                        defer allocator.free(set.?);

                        for (s, 0..) |subobj, set_idx| {
                            _editorui.pushIntId(@truncate(set_idx));
                            defer _editorui.popId();

                            var label = try std.fmt.bufPrintZ(&buff, "{d}", .{set_idx});

                            const is_inisiated = db.isIinisiated(db.readObj(obj).?, prop_idx, db.readObj(subobj).?);

                            if (is_inisiated) {
                                _editorui.pushStyleColor4f(.{ .idx = .text, .c = INSIATED_COLOR });
                                try inisiated_prototypes.put(db.getPrototype(db.readObj(subobj).?), {});
                            }

                            var open_inset = api.cdbTreeNode(label, false, false, selected_obj.eq(subobj));

                            if (is_inisiated) {
                                _editorui.popStyleColor(.{});
                            }

                            if (_editorui.isItemActivated()) {
                                new_selected = subobj;
                            }
                            if (open_inset) {
                                if (try cdbTreeView(allocator, db, subobj, selected_obj, args)) |sel| {
                                    new_selected = sel;
                                }

                                api.cdbTreePop();
                            }
                        }
                    }

                    // removed
                    if (prop_def.type == .REFERENCE_SET) {
                        set = db.readRefSetRemoved(db.readObj(obj).?, prop_idx, allocator);
                    } else {
                        set = db.readSubObjSetRemoved(db.readObj(obj).?, prop_idx, allocator);
                    }

                    if (set) |s| {
                        defer allocator.free(set.?);

                        for (s, 0..) |subobj, set_idx| {
                            _editorui.pushIntId(@truncate(set_idx));
                            defer _editorui.popId();
                            if (inisiated_prototypes.contains(subobj)) continue;

                            var label: ?[:0]u8 = null;
                            if (_assetdb.getUuid(subobj)) |uuid| {
                                label = try std.fmt.bufPrintZ(&buff, public.Icons.Deleted ++ " " ++ "{s}###{}", .{ uuid, uuid });
                            } else {
                                label = try std.fmt.bufPrintZ(&buff, public.Icons.Deleted ++ " " ++ "{d}:{d}###{d}{d}", .{ subobj.id, subobj.type_hash.id, subobj.id, subobj.type_hash.id });
                            }

                            _editorui.pushStyleColor4f(.{ .idx = .text, .c = REMOVED_COLOR });
                            defer _editorui.popStyleColor(.{});

                            if (_editorui.treeNodeFlags(label.?, .{ .leaf = true, .selected = selected_obj.eq(subobj) })) {
                                if (_editorui.isItemActivated()) {
                                    new_selected = subobj;
                                }
                                _editorui.treePop();
                            }
                        }
                    }

                    api.cdbTreePop();
                }
            },

            else => {},
        }
    }

    return new_selected;
}

fn init(main_db: ?*cetech1.c.ct_cdb_db_t) !void {
    _g.main_db = cetech1.cdb.CdbDb.fromDbT(main_db.?, _cdb);
    _g.tabs = TabsMap.init(_allocator);
    _g.tabids = TabsIds.init(_allocator);
    _g.tab2selectedobj = TabsSelectedObject.init(_allocator);

    // Create tab that has create_on_init == true. Primary for basic toolchain
    var it = _apidb.getFirstImpl(public.c.ct_editorui_tab_type_i);
    while (it) |node| : (it = node.next) {
        var iface = cetech1.apidb.ApiDbAPI.toInterface(public.c.ct_editorui_tab_type_i, node);
        if (iface.create_on_init) {
            _ = createNewTab(.{ .id = iface.tab_hash.id });
        }
    }
}

fn shutdown() !void {
    _g.tabs.deinit();
    _g.tabids.deinit();
    _g.tab2selectedobj.deinit();
}

var editor_kernel_task = cetech1.kernel.KernelTaskInterface(
    "EditorUI",
    &[_]cetech1.strid.StrId64{},
    init,
    shutdown,
);

fn kernelQuitHandler() bool {
    tryQuit();
    return true;
}

// Create types, register api, interfaces etc...
pub fn load_module_zig(apidb: *cetech1.apidb.ApiDbAPI, allocator: Allocator, log: *cetech1.log.LogAPI, load: bool, reload: bool) anyerror!bool {
    _ = reload;
    // basic
    _allocator = allocator;
    _log = log;
    _apidb = apidb;
    _cdb = apidb.getZigApi(cetech1.cdb.CdbAPI).?;
    _editorui = apidb.getZigApi(cetech1.editorui.EditorUIApi).?;
    _kernel = apidb.getZigApi(cetech1.kernel.KernelApi).?;
    _assetdb = apidb.getZigApi(cetech1.assetdb.AssetDBAPI).?;
    _tempalloc = apidb.getZigApi(cetech1.tempalloc.TempAllocApi).?;

    // create global variable that can survive reload
    _g = try apidb.globalVar(G, MODULE_NAME, "_g", .{});

    try apidb.setOrRemoveZigApi(public.EditorAPI, &api, load);

    try apidb.implOrRemove(cetech1.c.ct_kernel_task_i, &editor_kernel_task, load);
    try apidb.implOrRemove(cetech1.c.ct_editorui_ui_i, &editorui_ui_i, load);

    _kernel.setCanQuit(kernelQuitHandler);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_editor(__apidb: ?*const cetech1.c.ct_apidb_api_t, __allocator: ?*const cetech1.c.ct_allocator_t, __load: u8, __reload: u8) callconv(.C) u8 {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, __apidb, __allocator, __load, __reload);
}
