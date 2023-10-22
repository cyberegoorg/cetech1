const std = @import("std");
const cetech1 = @import("cetech1");

pub const c = @cImport({
    @cInclude("cetech1/modules/editor/editor.h");
});

pub const Icons = struct {
    pub const Open = cetech1.editorui.Icons.FA_FOLDER_OPEN;
    pub const OpenProject = cetech1.editorui.Icons.FA_FOLDER_OPEN;

    pub const OpenTab = cetech1.editorui.Icons.FA_WINDOW_MAXIMIZE;
    pub const CloseTab = cetech1.editorui.Icons.FA_RECTANGLE_XMARK;

    pub const Save = cetech1.editorui.Icons.FA_FLOPPY_DISK;
    pub const SaveAll = cetech1.editorui.Icons.FA_FLOPPY_DISK;

    pub const Add = cetech1.editorui.Icons.FA_PLUS;
    pub const Remove = cetech1.editorui.Icons.FA_MINUS;
    pub const Close = cetech1.editorui.Icons.FA_XMARK;

    pub const CopyToClipboard = cetech1.editorui.Icons.FA_CLIPBOARD;

    pub const Nothing = cetech1.editorui.Icons.FA_FACE_SMILE_WINK;
    pub const Deleted = cetech1.editorui.Icons.FA_TRASH;
    pub const Quit = cetech1.editorui.Icons.FA_DOOR_OPEN;

    pub const Debug = cetech1.editorui.Icons.FA_BUG;
};

pub const CdbTreeViewArgs = extern struct {
    expand_object: bool,
};

pub const cdbPropertiesViewArgs = extern struct {};

pub const hidePropertyAspect = c.ct_editorui_ui_property_aspect{};

pub const EditorAPI = struct {
    selectObj: *const fn (db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId) void,

    // Tabs
    openTabWithPinnedObj: *const fn (db: *cetech1.cdb.CdbDb, tab_type_hash: cetech1.strid.StrId32, obj: cetech1.cdb.ObjId) void,

    // UI elements
    uiAssetInput: *const fn (allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId, read_only: bool) anyerror!void,
    uiPropLabel: *const fn (name: [:0]const u8, color: ?[4]f32) void,
    uiPropInput: *const fn (db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId, prop_idx: u32) anyerror!void,
    uiPropInputBegin: *const fn (db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId, prop_idx: u32) anyerror!void,
    uiPropInputEnd: *const fn () void,

    // Property utils
    formatedPropNameToBuff: *const fn (buf: []u8, prop_name: [:0]const u8) anyerror![]u8,
    getPropertyColor: *const fn (db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId, prop_idx: u32) ?[4]f32,

    // Property view
    cdbPropertiesView: *const fn (allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId, args: cdbPropertiesViewArgs) anyerror!void,
    cdbPropertiesObj: *const fn (allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId, args: cdbPropertiesViewArgs) anyerror!void,

    // Tree view
    cdbTreeView: *const fn (allocator: std.mem.Allocator, db: *cetech1.cdb.CdbDb, obj: cetech1.cdb.ObjId, selected_obj: cetech1.cdb.ObjId, args: CdbTreeViewArgs) anyerror!?cetech1.cdb.ObjId,
    cdbTreeNode: *const fn (label: [:0]const u8, default_open: bool, no_push: bool, selected: bool) bool,
    cdbTreePop: *const fn () void,
};
