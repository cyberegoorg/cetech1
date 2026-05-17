/// AssetDB main API
/// Asset is CDB object associated with name, folder and is load/save from fs, net etc.
/// Asset act like wraper for real asset object that is store inside "asset" property.
const std = @import("std");
const cdb = @import("cdb.zig");
const cdb_types = @import("cdb_types.zig");
const task = @import("task.zig");
const cetech1 = @import("../cetech1.zig");
const uuid = @import("uuid.zig");
const host = @import("host.zig");
const apidb = cetech1.apidb;
const log = std.log.scoped(.assetdb);

// Type for root of all assets
pub const AssetRootCdb = cdb.CdbTypeDecl(
    "ct_asset_root",
    enum(u32) {
        Assets = 0,
    },
    struct {},
);

/// CDB type for asset wraper
pub const AssetCdb = cdb.CdbTypeDecl(
    "ct_asset",
    enum(u32) {
        Name = 0,
        Description,
        Folder,
        Tags,
        Object,
    },
    struct {},
);

/// CDB type for folder
pub const FolderCdb = cdb.CdbTypeDecl(
    "ct_folder",
    enum(u32) {
        Color,
    },
    struct {},
);

/// CDB type for asset/folder tags
pub const TagCdb = cdb.CdbTypeDecl(
    "ct_tag",
    enum(u32) {
        Name = 0,
        Color,
    },
    struct {},
);

/// CDB type for tags filter or similiar stuff
pub const TagsCdb = cdb.CdbTypeDecl(
    "ct_tags",
    enum(u32) {
        Tags = 0,
    },
    struct {},
);

/// CDB type for project
pub const ProjectCdb = cdb.CdbTypeDecl(
    "ct_project",
    enum(u32) {
        Name = 0,
        Organization,
    },
    struct {},
);

pub const AssetRootOpenedI = extern struct {
    pub const c_name = "ct_assetroot_opened_i";
    pub const name_hash = cetech1.strId64(@This().c_name);

    opened: ?*const fn () anyerror!void,

    pub inline fn implement(comptime T: type) @This() {
        return @This(){
            .opened = T.opened,
        };
    }
};

pub const CT_TEMP_FOLDER = ".ct_temp";

/// Asset In/Out interface
/// Use this if you need define your non-cdb assets importer or exporter
pub const AssetIOI = struct {
    const Self = @This();
    pub const c_name = "ct_assetdb_asset_io_i";
    pub const name_hash = cetech1.strId64(@This().c_name);

    /// Can import asset that has this extension?
    can_import: ?*const fn (filename: []const u8, extension: []const u8) bool,

    /// Can reimport asset?
    can_reimport: ?*const fn (db: cdb.DbId, asset: cdb.ObjId) bool, //TODO

    /// Can export asset with this extension?
    can_export: ?*const fn (db: cdb.DbId, asset: cdb.ObjId, filename: []const u8, extension: []const u8) bool,

    ///Crete import asset task.
    import_asset: ?*const fn (
        io: std.Io,
        db: cdb.DbId,
        prereq: task.TaskID,
        dir: std.Io.Dir,
        folder: cdb.ObjId,
        filename: []const u8,
        reimport_to: ?cdb.ObjId,
    ) anyerror!task.TaskID,

    /// Crete export asset task.
    export_asset: ?*const fn (
        io: std.Io,
        db: cdb.DbId,
        root_path: []const u8,
        sub_path: []const u8,
        asset: cdb.ObjId,
    ) anyerror!task.TaskID,

    /// For implement this interface use this fce and construct your type as anonym struct as param;
    pub inline fn implement(comptime T: type) AssetIOI {
        const hasExport = std.meta.hasFn(T, "exportAsset");
        const hasImport = std.meta.hasFn(T, "importAsset");
        const hasCanImport = std.meta.hasFn(T, "canImport");
        const hasCanReimport = std.meta.hasFn(T, "canReimport");
        const hasCanExport = std.meta.hasFn(T, "canExport");

        if (!hasExport and !hasImport) {
            @compileError("AssetIOI must have least one of importAsset, exportAsset");
        }

        return AssetIOI{
            .can_import = if (hasCanImport) T.canImport else null,
            .can_reimport = if (hasCanReimport) T.canReimport else null,
            .can_export = if (hasCanExport) T.canExport else null,
            .import_asset = if (hasImport) T.importAsset else null,
            .export_asset = if (hasExport) T.exportAsset else null,
        };
    }
};

pub const FilteredAsset = struct {
    score: f64,
    obj: cdb.ObjId,

    pub fn lessThan(context: void, a: FilteredAsset, b: FilteredAsset) bool {
        _ = context;
        return a.score < b.score;
    }
};

pub const FilteredAssets = []FilteredAsset;

pub const AssetRootI = struct {
    const Self = @This();

    pub fn addImportedAsset(self: Self, io: std.Io, asset_uuid: uuid.Uuid, imported_from: []const u8) !void {
        return self.vtable.addImportedAsset(self.inst, io, asset_uuid, imported_from);
    }
    pub fn isModified(self: Self) bool {
        return self.vtable.isModified(self.inst);
    }
    pub fn isObjModified(self: Self, asset: cdb.ObjId) bool {
        return self.vtable.isObjModified(self.inst, asset);
    }
    pub fn deleteAsset(self: Self, asset: cdb.ObjId) anyerror!void {
        return self.vtable.deleteAsset(self.inst, asset);
    }
    pub fn deleteFolder(self: Self, folder: cdb.ObjId) anyerror!void {
        return self.vtable.deleteFolder(self.inst, folder);
    }
    pub fn isToDeleted(self: Self, asset_or_folder: cdb.ObjId) bool {
        return self.vtable.isToDeleted(self.inst, asset_or_folder);
    }
    pub fn reviveDeleted(self: Self, asset_or_folder: cdb.ObjId) void {
        self.vtable.reviveDeleted(self.inst, asset_or_folder);
    }
    pub fn getAssetUuid(self: Self, io: std.Io, path: []const u8) ?uuid.Uuid {
        return self.vtable.getAssetUuid(self.inst, io, path);
    }
    pub fn saveAll(self: Self, io: std.Io, allocator: std.mem.Allocator) !void {
        return self.vtable.saveAll(self.inst, io, allocator);
    }
    pub fn saveAllModifiedAssets(self: Self, io: std.Io, allocator: std.mem.Allocator) !void {
        return self.vtable.saveAllModifiedAssets(self.inst, io, allocator);
    }
    pub fn saveAsAllAssets(self: Self, io: std.Io, allocator: std.mem.Allocator, path: []const u8) !void {
        return self.vtable.saveAsAllAssets(self.inst, io, allocator, path);
    }
    pub fn markObjSaved(self: Self, io: std.Io, objdi: cdb.ObjId, version: u64) void {
        self.vtable.markObjSaved(self.inst, io, objdi, version);
    }
    pub fn isProjectOpened(self: Self) bool {
        return self.vtable.isProjectOpened(self.inst);
    }
    pub fn getTmpPath(self: Self, io: std.Io, path_buf: []u8) !?[]u8 {
        return self.vtable.getTmpPath(self.inst, io, path_buf);
    }
    pub fn getRootFolder(self: Self) cdb.ObjId {
        return self.vtable.getRootFolder(self.inst);
    }
    pub fn addAssetToRoot(self: Self, io: std.Io, asset: cdb.ObjId) !void {
        return self.vtable.addAssetToRoot(self.inst, io, asset);
    }
    pub fn openAssetRootFolder(self: Self, io: std.Io, asset_root_path: []const u8, allocator: std.mem.Allocator) !void {
        return self.vtable.openAssetRootFolder(self.inst, io, asset_root_path, allocator);
    }
    pub fn saveAsset(self: Self, io: std.Io, allocator: std.mem.Allocator, root_path: []const u8, asset: cdb.ObjId) !cetech1.task.TaskID {
        return self.vtable.saveAsset(self.inst, io, allocator, root_path, asset);
    }
    pub fn saveFolderObj(self: Self, io: std.Io, allocator: std.mem.Allocator, folder_asset: cdb.ObjId, root_path: []const u8) !void {
        return self.vtable.saveFolderObj(self.inst, io, allocator, folder_asset, root_path);
    }
    pub fn getAssetRootPath(self: Self) ?[]const u8 {
        return self.vtable.getAssetRootPath(self.inst);
    }
    pub fn getAssetRootObj(self: Self) cdb.ObjId {
        return self.vtable.getAssetRootObj(self.inst);
    }
    pub fn createImportedAsset(self: *Self, asset_name: []const u8, asset_folder: cdb.ObjId, asset_obj: cdb.ObjId, imported_from: []const u8) ?cdb.ObjId {
        return self.vtable.createImportedAsset(self.inst, asset_name, asset_folder, asset_obj, imported_from);
    }

    inst: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        addImportedAsset: *const fn (self: *anyopaque, io: std.Io, asset_uuid: uuid.Uuid, imported_from: []const u8) anyerror!void,
        createImportedAsset: *const fn (self: *anyopaque, asset_name: []const u8, asset_folder: cdb.ObjId, asset_obj: cdb.ObjId, imported_from: []const u8) ?cdb.ObjId,
        isModified: *const fn (self: *anyopaque) bool,
        isObjModified: *const fn (self: *anyopaque, asset: cdb.ObjId) bool,
        deleteAsset: *const fn (self: *anyopaque, asset: cdb.ObjId) anyerror!void,
        deleteFolder: *const fn (self: *anyopaque, folder: cdb.ObjId) anyerror!void,
        isToDeleted: *const fn (self: *anyopaque, asset_or_folder: cdb.ObjId) bool,
        reviveDeleted: *const fn (self: *anyopaque, asset_or_folder: cdb.ObjId) void,
        getAssetUuid: *const fn (self: *anyopaque, io: std.Io, path: []const u8) ?uuid.Uuid,
        saveAll: *const fn (self: *anyopaque, io: std.Io, allocator: std.mem.Allocator) anyerror!void,
        saveAllModifiedAssets: *const fn (self: *anyopaque, io: std.Io, allocator: std.mem.Allocator) anyerror!void,
        saveAsAllAssets: *const fn (self: *anyopaque, io: std.Io, allocator: std.mem.Allocator, path: []const u8) anyerror!void,
        markObjSaved: *const fn (self: *anyopaque, io: std.Io, objdi: cdb.ObjId, version: u64) void,
        isProjectOpened: *const fn (self: *anyopaque) bool,
        getTmpPath: *const fn (self: *anyopaque, io: std.Io, path_buf: []u8) anyerror!?[]u8,
        getRootFolder: *const fn (self: *anyopaque) cdb.ObjId,
        addAssetToRoot: *const fn (self: *anyopaque, io: std.Io, asset: cdb.ObjId) anyerror!void,
        openAssetRootFolder: *const fn (self: *anyopaque, io: std.Io, asset_root_path: []const u8, allocator: std.mem.Allocator) anyerror!void,
        saveAsset: *const fn (self: *anyopaque, io: std.Io, allocator: std.mem.Allocator, root_path: []const u8, asset: cdb.ObjId) anyerror!cetech1.task.TaskID,
        saveFolderObj: *const fn (self: *anyopaque, io: std.Io, allocator: std.mem.Allocator, folder_asset: cdb.ObjId, root_path: []const u8) anyerror!void,
        getAssetRootPath: *const fn (self: *anyopaque) ?[]const u8,
        getAssetRootObj: *const fn (self: *anyopaque) cdb.ObjId,

        pub fn implement(comptime T: type) @This() {
            return @This(){
                .addImportedAsset = @ptrCast(&T.addImportedAsset),
                .isModified = @ptrCast(&T.isModified),
                .isObjModified = @ptrCast(&T.isObjModified),
                .deleteAsset = @ptrCast(&T.deleteAsset),
                .deleteFolder = @ptrCast(&T.deleteFolder),
                .isToDeleted = @ptrCast(&T.isToDeleted),
                .reviveDeleted = @ptrCast(&T.reviveDeleted),
                .getAssetUuid = @ptrCast(&T.getAssetUuid),
                .saveAll = @ptrCast(&T.saveAll),
                .saveAllModifiedAssets = @ptrCast(&T.saveAllModifiedAssets),
                .saveAsAllAssets = @ptrCast(&T.saveAsAllAssets),
                .markObjSaved = @ptrCast(&T.markObjSaved),
                .isProjectOpened = @ptrCast(&T.isProjectOpened),
                .getTmpPath = @ptrCast(&T.getTmpPath),
                .getRootFolder = @ptrCast(&T.getRootFolder),
                .addAssetToRoot = @ptrCast(&T.addAssetToRoot),
                .openAssetRootFolder = @ptrCast(&T.openAssetRootFolder),
                .saveAsset = @ptrCast(&T.saveAsset),
                .saveFolderObj = @ptrCast(&T.saveFolderObj),
                .getAssetRootPath = @ptrCast(&T.getAssetRootPath),
                .getAssetRootObj = @ptrCast(&T.getAssetRootObj),
                .createImportedAsset = @ptrCast(&T.createImportedAsset),
            };
        }
    };
};

pub const AssetRootProviderI = struct {
    pub const c_name = "ct_assetroot_provider_i";
    pub const name_hash = cetech1.strId64(@This().c_name);

    create: *const fn () anyerror!AssetRootI,
    destroy: *const fn (root: AssetRootI) void,

    pub fn implement(comptime T: type) @This() {
        return @This(){
            .create = T.create,
            .destroy = T.destroy,
        };
    }
};

/// Create new asset with name, folder and probably asset object.
pub inline fn createAsset(asset_name: []const u8, asset_folder: cdb.ObjId, asset_obj: ?cdb.ObjId) ?cdb.ObjId {
    return api.createAsset(asset_name, asset_folder, asset_obj);
}

/// Create new asset with name, folder and probably asset object.
pub inline fn createImportedAsset(asset_name: []const u8, asset_folder: cdb.ObjId, asset_obj: cdb.ObjId, imported_from: []const u8) ?cdb.ObjId {
    return api.createImportedAsset(asset_name, asset_folder, asset_obj, imported_from);
}

/// Open asset root folder, crete basic struct if not exist and load assets.
pub inline fn openAssetRootFolder(asset_root_path: []const u8, allocator: std.mem.Allocator) !void {
    try api.openAssetRootFolder(asset_root_path, allocator);
}

/// Get root folder object.
pub inline fn getRootFolder() cdb.ObjId {
    return api.getRootFolder();
}

/// Get path to tmp directory within asset root dir
pub inline fn getTmpPath(path_buff: []u8) !?[]u8 {
    return try api.getTmpPath(path_buff);
}

/// Is asset modified?
pub inline fn isAssetModified(asset: cdb.ObjId) bool {
    return api.isAssetModified(asset);
}

/// Is any asset in project modified?
pub inline fn isProjectModified() bool {
    return api.isProjectModified();
}

/// Force save all assets.
pub inline fn saveAllAssets(allocator: std.mem.Allocator) !void {
    return api.saveAllAssets(allocator);
}

/// Save only modified assets.
pub inline fn saveAllModifiedAssets(allocator: std.mem.Allocator) !void {
    return api.saveAllModifiedAssets(allocator);
}

/// Save asset.
pub inline fn saveAsset(allocator: std.mem.Allocator, asset: cdb.ObjId) !void {
    return api.saveAsset(allocator, asset);
}

pub fn isAssetNameValid(allocator: std.mem.Allocator, folder: cdb.ObjId, type_idx: cdb.TypeIdx, base_name: [:0]const u8) !bool {
    return api.isAssetNameValid(allocator, folder, type_idx, base_name);
}
pub fn getAssetForObj(obj: cdb.ObjId) ?cdb.ObjId {
    return api.getAssetForObj(obj);
}
pub fn getObjForAsset(obj: cdb.ObjId) ?cdb.ObjId {
    return api.getObjForAsset(obj);
}
pub fn isAssetFolder(obj: cdb.ObjId) bool {
    return api.isAssetFolder(obj);
}
pub fn isObjAssetObj(obj: cdb.ObjId) bool {
    return api.isObjAssetObj(obj);
}
pub fn getAssetRootObj() cdb.ObjId {
    return api.getAssetRootObj();
}
pub fn getDb() cdb.DbId {
    return api.getDb();
}
pub fn getFilePathForAsset(buff: []u8, asset: cdb.ObjId) ![]u8 {
    return api.getFilePathForAsset(buff, asset);
}

pub fn getPathForAsset(buff: []u8, asset: cdb.ObjId, extension: []const u8) ![]u8 {
    return api.getPathForAsset(buff, asset, extension);
}

pub fn getAssetByPath(path: []const u8) ?cdb.ObjId {
    return api.getAssetByPath(path);
}

pub fn getPathForFolder(buff: []u8, asset: cdb.ObjId) ![]u8 {
    return api.getPathForFolder(buff, asset);
}
pub fn createNewFolder(db: cdb.DbId, parent_folder: cdb.ObjId, name: [:0]const u8) !cdb.ObjId {
    return api.createNewFolder(db, parent_folder, name);
}
pub fn saveAsAllAssets(allocator: std.mem.Allocator, path: []const u8) !void {
    return api.saveAsAllAssets(allocator, path);
}
pub fn deleteAsset(asset: cdb.ObjId) !void {
    return api.deleteAsset(asset);
}
pub fn deleteFolder(folder: cdb.ObjId) !void {
    return api.deleteFolder(folder);
}
pub fn isToDeleted(asset_or_folder: cdb.ObjId) bool {
    return api.isToDeleted(asset_or_folder);
}
pub fn reviveDeleted(asset_or_folder: cdb.ObjId) void {
    return api.reviveDeleted(asset_or_folder);
}
pub fn isProjectOpened() bool {
    return api.isProjectOpened();
}
pub fn createNewAssetFromPrototype(asset: cdb.ObjId) !cdb.ObjId {
    return api.createNewAssetFromPrototype(asset);
}
pub fn cloneNewAssetFrom(asset: cdb.ObjId) !cdb.ObjId {
    return api.cloneNewAssetFrom(asset);
}
pub fn openInOs(allocator: std.mem.Allocator, open_type: host.OpenInType, asset: cdb.ObjId) !void {
    return api.openInOs(allocator, open_type, asset);
}
pub fn isRootFolder(asset: cdb.ObjId) bool {
    return api.isRootFolder(asset);
}
pub fn isAssetObjTypeOf(asset: cdb.ObjId, type_idx: cdb.TypeIdx) bool {
    return api.isAssetObjTypeOf(asset, type_idx);
}
pub fn buffGetValidName(allocator: std.mem.Allocator, buf: [:0]u8, folder: cdb.ObjId, type_idx: cdb.TypeIdx, base_name: [:0]const u8) ![:0]const u8 {
    return api.buffGetValidName(allocator, buf, folder, type_idx, base_name);
}
pub fn getAssetRootPath() ?[]const u8 {
    return api.getAssetRootPath();
}
pub fn filerAsset(allocator: std.mem.Allocator, filter: [:0]const u8, tags_filter: cdb.ObjId) !FilteredAssets {
    return api.filerAsset(allocator, filter, tags_filter);
}
pub fn findFirstAssetIOForImport(filename: []const u8, extension: []const u8) ?*const AssetIOI {
    return api.findFirstAssetIOForImport(filename, extension);
}
pub fn findFirstAssetIOForExport(db: cdb.DbId, asset: cdb.ObjId, filename: []const u8, extension: []const u8) ?*const AssetIOI {
    return api.findFirstAssetIOForExport(db, asset, filename, extension);
}

pub fn setAssetNameAndFolder(asset_w: *cdb.Obj, name: []const u8, description: ?[]const u8, asset_folder: cdb.ObjId) !void {
    return api.setAssetNameAndFolder(asset_w, name, description, asset_folder);
}

pub const AssetDBAPI = struct {
    findFirstAssetIOForImport: *const fn (filename: []const u8, extension: []const u8) ?*const AssetIOI,
    findFirstAssetIOForExport: *const fn (db: cdb.DbId, asset: cdb.ObjId, filename: []const u8, extension: []const u8) ?*const AssetIOI,
    isAssetNameValid: *const fn (allocator: std.mem.Allocator, folder: cdb.ObjId, type_idx: cdb.TypeIdx, base_name: [:0]const u8) anyerror!bool,
    getAssetForObj: *const fn (obj: cdb.ObjId) ?cdb.ObjId,
    getObjForAsset: *const fn (obj: cdb.ObjId) ?cdb.ObjId,
    isAssetFolder: *const fn (obj: cdb.ObjId) bool,
    isObjAssetObj: *const fn (obj: cdb.ObjId) bool,
    getAssetRootObj: *const fn () cdb.ObjId,
    getDb: *const fn () cdb.DbId,
    getFilePathForAsset: *const fn (buff: []u8, asset: cdb.ObjId) anyerror![]u8,
    getPathForAsset: *const fn (buff: []u8, asset: cdb.ObjId, extension: ?[]const u8) anyerror![]u8,
    getAssetByPath: *const fn (path: []const u8) ?cdb.ObjId,
    getPathForFolder: *const fn (buff: []u8, asset: cdb.ObjId) anyerror![]u8,
    createNewFolder: *const fn (db: cdb.DbId, parent_folder: cdb.ObjId, name: [:0]const u8) anyerror!cdb.ObjId,
    saveAsAllAssets: *const fn (allocator: std.mem.Allocator, path: []const u8) anyerror!void,
    deleteAsset: *const fn (asset: cdb.ObjId) anyerror!void,
    deleteFolder: *const fn (folder: cdb.ObjId) anyerror!void,
    isToDeleted: *const fn (asset_or_folder: cdb.ObjId) bool,
    reviveDeleted: *const fn (asset_or_folder: cdb.ObjId) void,
    isProjectOpened: *const fn () bool,
    createNewAssetFromPrototype: *const fn (asset: cdb.ObjId) anyerror!cdb.ObjId,
    cloneNewAssetFrom: *const fn (asset: cdb.ObjId) anyerror!cdb.ObjId,
    openInOs: *const fn (allocator: std.mem.Allocator, open_type: host.OpenInType, asset: cdb.ObjId) anyerror!void,
    isRootFolder: *const fn (asset: cdb.ObjId) bool,
    isAssetObjTypeOf: *const fn (asset: cdb.ObjId, type_idx: cdb.TypeIdx) bool,
    buffGetValidName: *const fn (allocator: std.mem.Allocator, buf: [:0]u8, folder: cdb.ObjId, type_idx: cdb.TypeIdx, base_name: [:0]const u8) anyerror![:0]const u8,
    getAssetRootPath: *const fn () ?[]const u8,
    filerAsset: *const fn (allocator: std.mem.Allocator, filter: [:0]const u8, tags_filter: cdb.ObjId) anyerror!FilteredAssets,

    createAsset: *const fn (asset_name: []const u8, asset_folder: cdb.ObjId, asset_obj: ?cdb.ObjId) ?cdb.ObjId,
    createImportedAsset: *const fn (asset_name: []const u8, asset_folder: cdb.ObjId, asset_obj: cdb.ObjId, imported_from: []const u8) ?cdb.ObjId,
    openAssetRootFolder: *const fn (asset_root_path: []const u8, allocator: std.mem.Allocator) anyerror!void,
    getRootFolder: *const fn () cdb.ObjId,

    isAssetModified: *const fn (asset: cdb.ObjId) bool,
    isProjectModified: *const fn () bool,
    saveAllAssets: *const fn (allocator: std.mem.Allocator) anyerror!void,
    saveAllModifiedAssets: *const fn (allocator: std.mem.Allocator) anyerror!void,
    saveAsset: *const fn (allocator: std.mem.Allocator, asset: cdb.ObjId) anyerror!void,
    getTmpPath: *const fn ([]u8) anyerror!?[]u8,

    setAssetNameAndFolder: *const fn (asset_w: *cdb.Obj, name: []const u8, description: ?[]const u8, asset_folder: cdb.ObjId) anyerror!void,
};

pub var api: *const AssetDBAPI = undefined;

pub fn loadAPI(comptime module: @EnumLiteral()) !void {
    api = apidb.getZigApi(module, AssetDBAPI).?;
}

// For testing.
pub const FooAsset = cdb_types.BigTypeDecl("ct_foo_asset");
pub const BarAsset = cdb_types.BigTypeDecl("ct_bar_asset");
pub const BazAsset = cdb_types.BigTypeDecl("ct_baz_asset");
