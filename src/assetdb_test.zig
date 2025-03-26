const std = @import("std");
const builtin = @import("builtin");

const apidb = @import("apidb.zig");
const task = @import("task.zig");
const tempalloc = @import("tempalloc.zig");
const cdb_private = @import("cdb.zig");
const cdb_test = @import("cdb_test.zig");
const cdb_types = @import("cdb_types.zig");
const log = @import("log.zig");
const uuid = @import("uuid.zig");
const private = @import("assetdb.zig");
const metrics = @import("metrics.zig");

const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;
const public = cetech1.assetdb;
const propIdx = cdb.propIdx;

var _cdb = &cdb_private.api;

const FooAsset = public.FooAsset;

pub fn WriteBlobToNull(
    blob: []const u8,
    asset: cdb.ObjId,
    obj_uuid: cetech1.uuid.Uuid,
    prop_hash: cetech1.StrId32,
    root_path: []const u8,
    allocator: std.mem.Allocator,
) anyerror!void {
    _ = blob;
    _ = asset;
    _ = prop_hash;
    _ = allocator;
    _ = obj_uuid;
    _ = root_path;
}

pub fn ReadBlobFromNull(
    asset: cdb.ObjId,
    obj_uuid: cetech1.uuid.Uuid,
    prop_hash: cetech1.StrId32,
    allocator: std.mem.Allocator,
) anyerror![]u8 {
    _ = asset;
    _ = obj_uuid;
    _ = prop_hash;
    _ = allocator;
    return &.{};
}

fn testInit() !void {
    try tempalloc.init(std.testing.allocator, 256);
    try task.init(std.testing.allocator);
    try apidb.init(std.testing.allocator);
    try metrics.init(std.testing.allocator);
    try cdb_private.init(std.testing.allocator);
    try private.registerToApi();
    try task.start();
    try cdb_types.registerToApi();
}

fn testDeinit() void {
    cdb_private.deinit();
    apidb.deinit();
    task.stop();
    task.deinit();
    tempalloc.deinit();
    metrics.deinit();
}

test "asset: Should save asset to json" {
    try testInit();
    defer testDeinit();

    try private.init(std.testing.allocator);
    defer private.deinit();

    const db = private.getDb();

    const prototype_obj = try private.createObjectWithUuid(
        FooAsset.typeIdx(_cdb, db),
        uuid.fromStr("9c49cfdb-0d31-485f-8623-24248b53c30f").?,
    );

    const proto_ref_obj1 = try FooAsset.createObject(_cdb, db);
    const proto_ref_obj2 = try FooAsset.createObject(_cdb, db);
    const proto_sub_obj1 = try FooAsset.createObject(_cdb, db);
    const proto_sub_obj2 = try FooAsset.createObject(_cdb, db);

    const proto_w = _cdb.writeObj(prototype_obj).?;
    const proto_sub_obj1_w = _cdb.writeObj(proto_sub_obj1).?;
    const proto_sub_obj2_w = _cdb.writeObj(proto_sub_obj2).?;
    try FooAsset.addRefToSet(_cdb, proto_w, .ReferenceSet, &.{ proto_ref_obj1, proto_ref_obj2 });

    try FooAsset.addSubObjToSet(
        _cdb,
        proto_w,
        .SubobjectSet,
        &.{ proto_sub_obj1_w, proto_sub_obj2_w },
    );

    try _cdb.writeCommit(proto_sub_obj2_w);
    try _cdb.writeCommit(proto_sub_obj1_w);
    try _cdb.writeCommit(proto_w);

    const asset_obj = try _cdb.createObjectFromPrototype(prototype_obj);
    const asset = private.api.createAsset("foo", private.api.getRootFolder(), asset_obj).?;

    const ref_obj1 = try FooAsset.createObject(_cdb, db);
    const ref_obj2 = try FooAsset.createObject(_cdb, db);
    const sub_obj1 = try FooAsset.createObject(_cdb, db);
    const sub_obj2 = try FooAsset.createObject(_cdb, db);

    const asset_w = _cdb.writeObj(asset).?;
    const prototype_obj_w = _cdb.writeObj(prototype_obj).?;
    const asset_obj_w = _cdb.writeObj(asset_obj).?;
    const sub_obj1_w = _cdb.writeObj(sub_obj1).?;
    const sub_obj2_w = _cdb.writeObj(sub_obj2).?;

    // Prototype value
    FooAsset.setValue(u64, _cdb, prototype_obj_w, .U64, 10);
    FooAsset.setValue(i64, _cdb, prototype_obj_w, .I64, 20);

    try FooAsset.setStr(_cdb, asset_obj_w, .Str, "foo");
    FooAsset.setValue(bool, _cdb, asset_obj_w, .Bool, true);
    FooAsset.setValue(u32, _cdb, asset_obj_w, .U32, 10);
    FooAsset.setValue(i32, _cdb, asset_obj_w, .I32, 20);
    FooAsset.setValue(f64, _cdb, asset_obj_w, .F64, 20.0);
    FooAsset.setValue(f32, _cdb, asset_obj_w, .F32, 30.0);

    try FooAsset.setRef(_cdb, asset_obj_w, .Reference, ref_obj1);
    try FooAsset.addRefToSet(_cdb, asset_obj_w, .ReferenceSet, &.{ref_obj2});
    try FooAsset.removeFromRefSet(_cdb, asset_obj_w, .ReferenceSet, proto_ref_obj1);

    try FooAsset.setSubObj(_cdb, asset_obj_w, .Subobject, sub_obj1_w);
    const inisiated_subobj1 = try _cdb.instantiateSubObjFromSet(asset_obj_w, propIdx(cetech1.cdb_types.BigTypeProps.SubobjectSet), proto_sub_obj1);
    try FooAsset.addSubObjToSet(_cdb, asset_obj_w, .SubobjectSet, &.{sub_obj2_w});

    const blob = (try FooAsset.createBlob(_cdb, asset_obj_w, .Blob, "hello blob".len)).?;
    @memcpy(blob, "hello blob");

    try _cdb.writeCommit(sub_obj1_w);
    try _cdb.writeCommit(sub_obj2_w);
    try _cdb.writeCommit(asset_obj_w);
    try _cdb.writeCommit(prototype_obj_w);
    try _cdb.writeCommit(asset_w);

    var expect_buffer: [2048]u8 = undefined;
    const expected_fmt =
        \\{{
        \\  "__version": "0.1.0",
        \\  "__asset_uuid": "{s}",
        \\  "__type_name": "ct_foo_asset",
        \\  "__uuid": "{s}",
        \\  "__prototype_uuid": "9c49cfdb-0d31-485f-8623-24248b53c30f",
        \\  "bool": true,
        \\  "u32": 10,
        \\  "i32": 20,
        \\  "f32": 3e1,
        \\  "f64": 2e1,
        \\  "str": "foo",
        \\  "blob": "{x}d667a6af",
        \\  "subobject": {{
        \\    "__type_name": "ct_foo_asset",
        \\    "__uuid": "{s}"
        \\  }},
        \\  "reference": "ct_foo_asset:{s}",
        \\  "subobject_set": [
        \\    {{
        \\      "__type_name": "ct_foo_asset",
        \\      "__uuid": "{s}"
        \\    }}
        \\  ],
        \\  "subobject_set__instantiate": [
        \\    {{
        \\      "__type_name": "ct_foo_asset",
        \\      "__uuid": "{s}",
        \\      "__prototype_uuid": "{s}"
        \\    }}
        \\  ],
        \\  "reference_set": [
        \\    "ct_foo_asset:{s}"
        \\  ],
        \\  "reference_set__removed": [
        \\    "ct_foo_asset:{s}"
        \\  ]
        \\}}
    ;

    var out_buffer: [2048]u8 = undefined;
    var fixed_buffer_stream = std.io.fixedBufferStream(&out_buffer);
    const out_stream = fixed_buffer_stream.writer();

    try private.writeCdbObjJson(
        @TypeOf(out_stream),
        asset,
        out_stream,
        asset,
        WriteBlobToNull,
        "",
        std.testing.allocator,
    );
    try std.testing.expectEqualStrings(
        try std.fmt.bufPrint(
            &expect_buffer,
            expected_fmt,
            .{
                private.api.getUuid(asset).?,
                private.api.getUuid(asset_obj).?,
                cetech1.strId32(&private.api.getUuid(asset_obj).?.bytes).id,
                private.api.getUuid(sub_obj1).?,
                private.api.getUuid(ref_obj1).?,
                private.api.getUuid(sub_obj2).?,
                private.api.getUuid(inisiated_subobj1).?,
                private.api.getUuid(proto_sub_obj1).?,
                private.api.getUuid(ref_obj2).?,
                private.api.getUuid(proto_ref_obj1).?,
            },
        ),
        fixed_buffer_stream.getWritten(),
    );

    //std.debug.print("\n {s} \n", .{fixed_buffer_stream.getWritten()});

    _cdb.destroyObject(asset);
    _cdb.destroyObject(ref_obj1);
    _cdb.destroyObject(ref_obj2);
    try _cdb.gc(std.testing.allocator, db);
}

test "asset: Should read asset from json reader" {
    try testInit();
    defer testDeinit();

    try private.init(std.testing.allocator);
    defer private.deinit();
    const db = private.getDb();

    const prototype_obj = try private.createObjectWithUuid(FooAsset.typeIdx(_cdb, db), uuid.fromStr("9c49cfdb-0d31-485f-8623-24248b53c30f").?);
    const proto_ref_obj1 = try private.createObjectWithUuid(FooAsset.typeIdx(_cdb, db), uuid.fromStr("965a0c48-f166-4f66-a894-9f8d750c7c28").?);
    const proto_ref_obj2 = try private.createObjectWithUuid(FooAsset.typeIdx(_cdb, db), uuid.fromStr("8c709979-23ca-4542-90ca-0a9b7a96f3c5").?);
    const proto_sub_obj1 = try private.createObjectWithUuid(FooAsset.typeIdx(_cdb, db), uuid.fromStr("16e130f3-f21d-4fa7-8974-b90e607ce640").?);
    const proto_sub_obj2 = try private.createObjectWithUuid(FooAsset.typeIdx(_cdb, db), uuid.fromStr("bee0d651-e624-4b78-8500-00cbeeeecf44").?);

    const proto_w = _cdb.writeObj(prototype_obj).?;
    const proto_sub_obj1_w = _cdb.writeObj(proto_sub_obj1).?;
    const proto_sub_obj2_w = _cdb.writeObj(proto_sub_obj2).?;

    try FooAsset.addRefToSet(_cdb, proto_w, .ReferenceSet, &.{ proto_ref_obj1, proto_ref_obj2 });
    try FooAsset.addSubObjToSet(_cdb, proto_w, .SubobjectSet, &.{ proto_sub_obj1_w, proto_sub_obj2_w });

    try _cdb.writeCommit(proto_sub_obj2_w);
    try _cdb.writeCommit(proto_sub_obj1_w);
    try _cdb.writeCommit(proto_w);

    const folder1_asset = try public.Asset.createObject(_cdb, db);
    const folder1 = try public.Folder.createObject(_cdb, db);
    const folder1_w = public.Folder.write(_cdb, folder1).?;
    const folder1_asset_w = _cdb.writeObj(folder1_asset).?;
    try public.Asset.setSubObj(_cdb, folder1_asset_w, .Object, folder1_w);
    try _cdb.writeCommit(folder1_w);
    try _cdb.writeCommit(folder1_asset_w);

    const prototype_obj_w = _cdb.writeObj(prototype_obj).?;
    // Prototype value
    _cdb.setValue(u64, prototype_obj_w, propIdx(cetech1.cdb_types.BigTypeProps.U64), 10);
    _cdb.setValue(i64, prototype_obj_w, propIdx(cetech1.cdb_types.BigTypeProps.I64), 20);
    try _cdb.writeCommit(prototype_obj_w);

    const ref_obj1 = try private.createObjectWithUuid(FooAsset.typeIdx(_cdb, db), uuid.fromStr("018b5846-c2d5-7921-823a-60d80f9285de").?);
    const ref_obj2 = try private.createObjectWithUuid(FooAsset.typeIdx(_cdb, db), uuid.fromStr("018b5846-c2d5-74f2-a050-c9375ad9a1f6").?);

    const input_json =
        \\{
        \\  "__version": "0.1.0",
        \\  "__asset_uuid": "018b5846-c2d5-7b88-95f9-a7538a00e76b",
        \\  "__type_name": "ct_foo_asset",
        \\  "__uuid": "018b5846-c2d5-712f-bb12-9d9d15321ecb",
        \\  "__prototype_uuid": "9c49cfdb-0d31-485f-8623-24248b53c30f",
        \\  "bool": true,
        \\  "u32": 10,
        \\  "i32": 20,
        \\  "f32": 3e1,
        \\  "f64": 2e1,
        \\  "str": "foo",
        \\  "subobject": {
        \\    "__type_name": "ct_foo_asset",
        \\    "__uuid": "018b5846-c2d5-7c82-82b4-525348222242"
        \\  },
        \\  "reference": "ct_foo_asset:018b5846-c2d5-7921-823a-60d80f9285de",
        \\  "subobject_set": [
        \\    {
        \\      "__type_name": "ct_foo_asset",
        \\      "__uuid": "018b5846-c2d5-7584-9183-a95f78095230"
        \\    }
        \\  ],
        \\  "subobject_set__instantiate": [
        \\    {
        \\      "__type_name": "ct_foo_asset",
        \\      "__uuid": "0277c070-b7a4-4ae1-947f-f85c67ec15a6",
        \\      "__prototype_uuid": "16e130f3-f21d-4fa7-8974-b90e607ce640"
        \\    }
        \\  ],
        \\  "reference_set": [
        \\    "ct_foo_asset:018b5846-c2d5-74f2-a050-c9375ad9a1f6"
        \\  ],
        \\  "reference_set__removed": [
        \\    "ct_foo_asset:965a0c48-f166-4f66-a894-9f8d750c7c28"
        \\  ]
        \\}
    ;

    var fixed_buffer_stream = std.io.fixedBufferStream(input_json);
    const in_stream = fixed_buffer_stream.reader();

    const asset = try private.readAssetFromReader(
        @TypeOf(in_stream),
        in_stream,
        "foo",
        folder1_asset,
        ReadBlobFromNull,
        std.testing.allocator,
    );
    try std.testing.expectEqual(uuid.fromStr("018b5846-c2d5-7b88-95f9-a7538a00e76b").?, private.api.getUuid(asset).?);

    const asset_obj = public.Asset.readSubObj(_cdb, _cdb.readObj(asset).?, .Object);
    try std.testing.expect(asset_obj != null);

    try std.testing.expectEqual(uuid.fromStr("018b5846-c2d5-712f-bb12-9d9d15321ecb").?, private.api.getUuid(asset_obj.?).?);

    var out_buffer: [2048]u8 = undefined;
    var fixed_out_buffer_stream = std.io.fixedBufferStream(&out_buffer);
    const out_stream = fixed_out_buffer_stream.writer();
    try private.writeCdbObjJson(
        @TypeOf(out_stream),
        asset,
        out_stream,
        asset,
        WriteBlobToNull,
        "",
        std.testing.allocator,
    );

    try std.testing.expectEqualStrings(input_json, fixed_out_buffer_stream.getWritten());

    _cdb.destroyObject(asset);
    _cdb.destroyObject(ref_obj1);
    _cdb.destroyObject(ref_obj2);
    _cdb.destroyObject(prototype_obj);
    _cdb.destroyObject(folder1);
}

test "asset: Should create asset" {
    try testInit();
    defer testDeinit();

    try private.init(std.testing.allocator);
    defer private.deinit();

    const asset = private.api.createAsset("foo", private.api.getRootFolder(), null);
    try std.testing.expect(asset != null);

    // try db.gc(std.testing.allocator);
    // try cdb_test.expectGCStats(db, 5, 12);
}

test "asset: Should open asset root dir" {
    try testInit();
    defer testDeinit();

    try private.init(std.testing.allocator);
    defer private.deinit();

    const db = private.getDb();

    const asset_type_hash = try cetech1.cdb_types.addBigType(_cdb, db, "ct_foo_asset", null);
    _ = asset_type_hash;

    try private.api.openAssetRootFolder("fixtures/test_asset", std.testing.allocator);

    var root_folder: ?cdb.ObjId = undefined;
    var core_folder: ?cdb.ObjId = undefined;
    var core_subfolder_folder: ?cdb.ObjId = undefined;

    // /
    {
        const foo_obj = private.api.getObjId(uuid.fromStr("018b5846-c2d5-712f-bb12-9d9d15321ecb").?);
        try std.testing.expect(foo_obj != null);

        var foo_obj_asset = _cdb.getParent(foo_obj.?);
        try std.testing.expect(!foo_obj_asset.isEmpty());

        const expect_name = "foo";
        try std.testing.expectEqualStrings(
            expect_name,
            public.Asset.readStr(_cdb, _cdb.readObj(foo_obj_asset).?, .Name).?,
        );

        const blob = _cdb.readBlob(_cdb.readObj(foo_obj.?).?, propIdx(cetech1.cdb_types.BigTypeProps.Blob));
        try std.testing.expectEqualSlices(u8, "hello blob", blob);

        root_folder = public.Asset.readRef(_cdb, _cdb.readObj(foo_obj_asset).?, .Folder);
        try std.testing.expect(root_folder != null);
        try std.testing.expect(null == public.Asset.readStr(_cdb, _cdb.readObj(private.api.getAssetForObj(root_folder.?).?).?, .Name));

        try std.testing.expectEqual(private.api.getAssetForObj(root_folder.?).?, private.api.getRootFolder());
        const set = try _cdb.getReferencerSet(std.testing.allocator, root_folder.?);
        defer std.testing.allocator.free(set);
        // TODO: try std.testing.expectEqual(@as(usize, 3), set.len);

        var buff: [128]u8 = undefined;
        const sub_path = try private.getFilePathForAsset(&buff, foo_obj_asset);
        try std.testing.expectEqualStrings("foo.ct_foo_asset", sub_path);

        // Check refenced objects
        const expect_name2 = "foo core";
        try std.testing.expectEqualStrings(expect_name2, FooAsset.readStr(
            _cdb,
            _cdb.readObj(FooAsset.readRef(_cdb, _cdb.readObj(foo_obj.?).?, .Reference).?).?,
            .Str,
        ).?);
    }

    const foo_core_obj = private.api.getObjId(uuid.fromStr("018b5c72-5350-7d06-b5ed-6fed2793fdd4").?);
    // /core
    {
        try std.testing.expect(foo_core_obj != null);

        var foo_core_obj_asset = _cdb.getParent(foo_core_obj.?);
        try std.testing.expect(!foo_core_obj_asset.isEmpty());

        const expect_name = "foo_core";
        try std.testing.expectEqualStrings(
            expect_name,
            public.Asset.readStr(_cdb, _cdb.readObj(foo_core_obj_asset).?, .Name).?,
        );

        const blob = _cdb.readBlob(_cdb.readObj(foo_core_obj.?).?, propIdx(cetech1.cdb_types.BigTypeProps.Blob));
        try std.testing.expectEqualSlices(u8, "hello core blob", blob);

        core_folder = public.Asset.readRef(_cdb, _cdb.readObj(foo_core_obj_asset).?, .Folder);
        try std.testing.expect(core_folder != null);

        const expect_folder_name = "core";
        try std.testing.expectEqualStrings(
            expect_folder_name,
            public.Asset.readStr(_cdb, _cdb.readObj(private.api.getAssetForObj(core_folder.?).?).?, .Name).?,
        );

        var buff: [128]u8 = undefined;
        const sub_path = try private.api.getFilePathForAsset(&buff, foo_core_obj_asset);

        if (builtin.os.tag == .windows) {
            try std.testing.expectEqualStrings("core\\foo_core.ct_foo_asset", sub_path);
        } else {
            try std.testing.expectEqualStrings("core/foo_core.ct_foo_asset", sub_path);
        }
    }

    // /core/core_subfolder
    {
        const foo_subcore_obj = private.api.getObjId(uuid.fromStr("018b5c74-06f7-79fd-a6ad-3678552795a1").?);
        try std.testing.expect(foo_subcore_obj != null);

        var foo_subcore_obj_asset = _cdb.getParent(foo_subcore_obj.?);
        try std.testing.expect(!foo_subcore_obj_asset.isEmpty());

        const expect_name = "foo_subcore";
        try std.testing.expectEqualStrings(
            expect_name,
            public.Asset.readStr(_cdb, _cdb.readObj(foo_subcore_obj_asset).?, .Name).?,
        );

        const blob = _cdb.readBlob(_cdb.readObj(foo_subcore_obj.?).?, propIdx(cetech1.cdb_types.BigTypeProps.Blob));
        try std.testing.expectEqualSlices(u8, "hello subcore blob", blob);

        const ref_set = _cdb.readRefSet(_cdb.readObj(foo_subcore_obj.?).?, propIdx(cetech1.cdb_types.BigTypeProps.ReferenceSet), std.testing.allocator);
        defer std.testing.allocator.free(ref_set.?);
        try std.testing.expect(ref_set != null);
        try std.testing.expectEqualSlices(
            cdb.ObjId,
            &[_]cdb.ObjId{foo_core_obj.?},
            ref_set.?,
        );

        const subobj = private.api.getObjId(uuid.fromStr("018b5c74-06f7-70bb-94e3-10a2a8619d31").?);
        const inisiated_subobj = private.api.getObjId(uuid.fromStr("7d0d10ce-128e-45ab-8c14-c5d486542d4f").?);
        const subobj_set = _cdb.readRefSet(_cdb.readObj(foo_subcore_obj.?).?, propIdx(cetech1.cdb_types.BigTypeProps.SubobjectSet), std.testing.allocator);
        defer std.testing.allocator.free(subobj_set.?);
        try std.testing.expect(subobj_set != null);
        try std.testing.expectEqualSlices(
            cdb.ObjId,
            &[_]cdb.ObjId{ subobj.?, inisiated_subobj.? },
            subobj_set.?,
        );

        core_subfolder_folder = public.Asset.readRef(_cdb, _cdb.readObj(foo_subcore_obj_asset).?, .Folder);
        try std.testing.expect(core_subfolder_folder != null);

        const expect_folder_name = "core_subfolder";
        try std.testing.expectEqualStrings(
            expect_folder_name,
            public.Asset.readStr(_cdb, _cdb.readObj(private.api.getAssetForObj(core_subfolder_folder.?).?).?, .Name).?,
        );

        var buff: [128]u8 = undefined;
        const sub_path = try private.api.getFilePathForAsset(&buff, foo_subcore_obj_asset);

        if (builtin.os.tag == .windows) {
            try std.testing.expectEqualStrings("core\\core_subfolder\\foo_subcore.ct_foo_asset", sub_path);
        } else {
            try std.testing.expectEqualStrings("core/core_subfolder/foo_subcore.ct_foo_asset", sub_path);
        }

        // Check refenced objects
        const expect_name2 = "foo core";
        try std.testing.expectEqualStrings(expect_name2, FooAsset.readStr(
            _cdb,
            _cdb.readObj(FooAsset.readRef(_cdb, _cdb.readObj(foo_subcore_obj.?).?, .Reference).?).?,
            .Str,
        ).?);
    }
}

test "asset: Should save asset root dir" {
    try testInit();
    defer testDeinit();

    const allocator = try tempalloc.api.create();
    defer tempalloc.api.destroy(allocator);

    try private.init(std.testing.allocator);
    defer private.deinit();
    const db = private.getDb();

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_dir_path = try tmp_dir.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_dir_path);

    const root_dir = try std.fs.path.join(std.testing.allocator, &.{tmp_dir_path});
    defer std.testing.allocator.free(root_dir);

    const asset_type_hash = try cetech1.cdb_types.addBigType(_cdb, db, "ct_foo_asset", null);

    try private.api.openAssetRootFolder(root_dir, allocator);

    const asset_obj = try _cdb.createObject(db, asset_type_hash);
    const asset = private.api.createAsset("foo", private.api.getRootFolder(), asset_obj).?;

    const asset_obj_w = _cdb.writeObj(asset_obj).?;
    const asset_w = _cdb.writeObj(asset).?;

    const blob = (try _cdb.createBlob(asset_obj_w, propIdx(cetech1.cdb_types.BigTypeProps.Blob), "hello blob".len)).?;
    @memcpy(blob, "hello blob");

    try _cdb.writeCommit(asset_w);
    try _cdb.writeCommit(asset_obj_w);

    try std.testing.expect(private.api.isAssetModified(asset));
    try private.api.saveAllAssets(allocator);
    try std.testing.expect(!private.api.isAssetModified(asset));

    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "foo.ct_foo_asset.json" });
        defer std.testing.allocator.free(path);

        var f = std.fs.cwd().openFile(path, .{});
        try std.testing.expect(f != std.fs.File.OpenError.FileNotFound);
        (try f).close();
    }

    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "." ++ public.Folder.name ++ ".json" });
        defer std.testing.allocator.free(path);

        var f = std.fs.cwd().openFile(path, .{});
        try std.testing.expect(f != std.fs.File.OpenError.FileNotFound);
        (try f).close();
    }

    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, public.CT_TEMP_FOLDER });
        defer std.testing.allocator.free(path);

        var d = std.fs.cwd().openDir(path, .{});
        try std.testing.expect(d != std.fs.Dir.OpenError.FileNotFound);
        (try d).close();
    }
}

test "asset: Should save modified asset" {
    try testInit();
    defer testDeinit();

    const tmpalloc = try tempalloc.api.create();
    defer tempalloc.api.destroy(tmpalloc);

    try private.init(std.testing.allocator);
    defer private.deinit();
    const db = private.getDb();

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_dir_path = try tmp_dir.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_dir_path);

    const root_dir = try std.fs.path.join(std.testing.allocator, &.{tmp_dir_path});
    defer std.testing.allocator.free(root_dir);

    const asset_type_hash = try cetech1.cdb_types.addBigType(_cdb, db, "ct_foo_asset", null);

    try private.api.openAssetRootFolder(root_dir, tmpalloc);

    const asset_obj = try _cdb.createObject(db, asset_type_hash);
    const asset = private.api.createAsset("foo", private.api.getRootFolder(), asset_obj).?;

    const asset_obj_w = _cdb.writeObj(asset_obj).?;
    const asset_w = _cdb.writeObj(asset).?;

    const blob = (try _cdb.createBlob(asset_obj_w, propIdx(cetech1.cdb_types.BigTypeProps.Blob), "hello blob".len)).?;
    @memcpy(blob, "hello blob");

    try _cdb.writeCommit(asset_w);
    try _cdb.writeCommit(asset_obj_w);

    try std.testing.expect(private.api.isAssetModified(asset));
    try private.api.saveAllModifiedAssets(tmpalloc);
    try std.testing.expect(!private.api.isAssetModified(asset));

    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "foo.ct_foo_asset.json" });
        defer std.testing.allocator.free(path);

        var f = std.fs.cwd().openFile(path, .{});
        try std.testing.expect(f != std.fs.File.OpenError.FileNotFound);
        (try f).close();
    }

    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "." ++ public.Folder.name ++ ".json" });
        defer std.testing.allocator.free(path);

        var f = std.fs.cwd().openFile(path, .{});
        try std.testing.expect(f != std.fs.File.OpenError.FileNotFound);
        (try f).close();
    }

    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, public.CT_TEMP_FOLDER });
        defer std.testing.allocator.free(path);

        var d = std.fs.cwd().openDir(path, .{});
        try std.testing.expect(d != std.fs.Dir.OpenError.FileNotFound);
        (try d).close();
    }
}

test "asset: Should rename asset" {
    try testInit();
    defer testDeinit();

    const allocator = try tempalloc.api.create();
    defer tempalloc.api.destroy(allocator);

    try private.init(std.testing.allocator);
    defer private.deinit();
    const db = private.getDb();

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_dir_path = try tmp_dir.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_dir_path);

    const root_dir = try std.fs.path.join(std.testing.allocator, &.{tmp_dir_path});
    defer std.testing.allocator.free(root_dir);

    const asset_type_hash = try cetech1.cdb_types.addBigType(_cdb, db, "ct_foo_asset", null);

    try private.api.openAssetRootFolder(root_dir, allocator);

    const asset_obj = try _cdb.createObject(db, asset_type_hash);
    const asset = private.api.createAsset("foo", private.api.getRootFolder(), asset_obj).?;

    const asset_obj_w = _cdb.writeObj(asset_obj).?;
    const asset_w = _cdb.writeObj(asset).?;

    const blob = (try _cdb.createBlob(asset_obj_w, propIdx(cetech1.cdb_types.BigTypeProps.Blob), "hello blob".len)).?;
    @memcpy(blob, "hello blob");

    try _cdb.writeCommit(asset_w);
    try _cdb.writeCommit(asset_obj_w);

    try std.testing.expect(private.api.isAssetModified(asset));
    try private.api.saveAllAssets(allocator);
    try std.testing.expect(!private.api.isAssetModified(asset));

    // Change name to new name
    {
        const w = _cdb.writeObj(asset).?;
        try cetech1.assetdb.Asset.setStr(_cdb, w, .Name, "bar");
        try _cdb.writeCommit(w);
    }

    // Save all assets
    try std.testing.expect(private.api.isAssetModified(asset));
    try private.api.saveAllModifiedAssets(allocator);
    try std.testing.expect(!private.api.isAssetModified(asset));

    // Original asset does not exist
    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "foo.ct_foo_asset.json" });
        defer std.testing.allocator.free(path);

        const f = std.fs.cwd().openFile(path, .{});
        try std.testing.expect(f == std.fs.File.OpenError.FileNotFound);
    }

    // Original asset blob dir does not exist
    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "foo.ct_blob" });
        defer std.testing.allocator.free(path);

        const d = std.fs.cwd().openDir(path, .{});
        try std.testing.expect(d == std.fs.Dir.OpenError.FileNotFound);
    }

    // Asset with new name exist
    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "bar.ct_foo_asset.json" });
        defer std.testing.allocator.free(path);

        var f = std.fs.cwd().openFile(path, .{});
        try std.testing.expect(f != std.fs.File.OpenError.FileNotFound);
        (try f).close();
    }

    // Asset blob for new named asset exist
    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "bar.ct_blob" });
        defer std.testing.allocator.free(path);

        var d = std.fs.cwd().openDir(path, .{});
        try std.testing.expect(d != std.fs.Dir.OpenError.FileNotFound);
        (try d).close();
    }
}

test "asset: Should move asset" {
    try testInit();
    defer testDeinit();

    const allocator = try tempalloc.api.create();
    defer tempalloc.api.destroy(allocator);

    try private.init(std.testing.allocator);
    defer private.deinit();
    const db = private.getDb();

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_dir_path = try tmp_dir.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_dir_path);

    const root_dir = try std.fs.path.join(std.testing.allocator, &.{tmp_dir_path});
    defer std.testing.allocator.free(root_dir);

    const asset_type_hash = try cetech1.cdb_types.addBigType(_cdb, db, "ct_foo_asset", null);

    try private.api.openAssetRootFolder(root_dir, allocator);

    const asset_obj = try _cdb.createObject(db, asset_type_hash);
    const asset = private.api.createAsset("foo", private.api.getRootFolder(), asset_obj).?;

    const asset_obj_w = _cdb.writeObj(asset_obj).?;
    const asset_w = _cdb.writeObj(asset).?;

    const blob = (try _cdb.createBlob(asset_obj_w, propIdx(cetech1.cdb_types.BigTypeProps.Blob), "hello blob".len)).?;
    @memcpy(blob, "hello blob");

    try _cdb.writeCommit(asset_w);
    try _cdb.writeCommit(asset_obj_w);

    const bar_folder = try private.api.createNewFolder(db, private.api.getRootFolder(), "bar");

    try std.testing.expect(private.api.isAssetModified(asset));
    try private.api.saveAllAssets(allocator);
    try std.testing.expect(!private.api.isAssetModified(asset));

    // Change folder
    {
        const w = _cdb.writeObj(asset).?;
        try cetech1.assetdb.Asset.setRef(_cdb, w, .Folder, bar_folder);
        try _cdb.writeCommit(w);
    }

    // Save all assets
    try std.testing.expect(private.api.isAssetModified(asset));
    try private.api.saveAllModifiedAssets(allocator);
    try std.testing.expect(!private.api.isAssetModified(asset));

    // Original asset does not exist
    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "foo.ct_foo_asset" });
        defer std.testing.allocator.free(path);

        const f = std.fs.cwd().openFile(path, .{});
        try std.testing.expect(f == std.fs.File.OpenError.FileNotFound);
    }

    // Original asset blob dir does not exist
    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "foo.ct_blob" });
        defer std.testing.allocator.free(path);

        const d = std.fs.cwd().openDir(path, .{});
        try std.testing.expect(d == std.fs.Dir.OpenError.FileNotFound);
    }

    // Asset with new folder exist
    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "bar", "foo.ct_foo_asset.json" });
        defer std.testing.allocator.free(path);

        var f = std.fs.cwd().openFile(path, .{});
        try std.testing.expect(f != std.fs.File.OpenError.FileNotFound);
        (try f).close();
    }

    // Asset blob for new folder exist
    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "bar", "foo.ct_blob" });
        defer std.testing.allocator.free(path);

        var d = std.fs.cwd().openDir(path, .{});
        try std.testing.expect(d != std.fs.Dir.OpenError.FileNotFound);
        (try d).close();
    }
}

test "asset: Should delete asset" {
    try testInit();
    defer testDeinit();

    const allocator = try tempalloc.api.create();
    defer tempalloc.api.destroy(allocator);

    try private.init(std.testing.allocator);
    defer private.deinit();
    const db = private.getDb();

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_dir_path = try tmp_dir.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_dir_path);

    const root_dir = try std.fs.path.join(std.testing.allocator, &.{tmp_dir_path});
    defer std.testing.allocator.free(root_dir);

    const asset_type_hash = try cetech1.cdb_types.addBigType(_cdb, db, "ct_foo_asset", null);

    try private.api.openAssetRootFolder(root_dir, allocator);

    const asset_obj = try _cdb.createObject(db, asset_type_hash);
    const asset = private.api.createAsset("foo", private.api.getRootFolder(), asset_obj).?;

    const asset_obj_w = _cdb.writeObj(asset_obj).?;
    const asset_w = _cdb.writeObj(asset).?;

    const blob = (try _cdb.createBlob(asset_obj_w, propIdx(cetech1.cdb_types.BigTypeProps.Blob), "hello blob".len)).?;
    @memcpy(blob, "hello blob");

    try _cdb.writeCommit(asset_w);
    try _cdb.writeCommit(asset_obj_w);

    try std.testing.expect(private.api.isAssetModified(asset));
    try private.api.saveAllAssets(allocator);
    try std.testing.expect(!private.api.isAssetModified(asset));

    try private.api.deleteAsset(asset);

    // Save all assets
    try std.testing.expect(private.api.isToDeleted(asset));
    try private.api.saveAllModifiedAssets(allocator);
    try std.testing.expect(!private.api.isToDeleted(asset));

    // Original asset does not exist
    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "foo.ct_foo_asset" });
        defer std.testing.allocator.free(path);

        const f = std.fs.cwd().openFile(path, .{});
        try std.testing.expect(f == std.fs.File.OpenError.FileNotFound);
    }

    // Original asset blob dir does not exist
    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "foo.ct_blob" });
        defer std.testing.allocator.free(path);

        const d = std.fs.cwd().openDir(path, .{});
        try std.testing.expect(d == std.fs.Dir.OpenError.FileNotFound);
    }
}

test "asset: Should revive asset" {
    try testInit();
    defer testDeinit();

    const allocator = try tempalloc.api.create();
    defer tempalloc.api.destroy(allocator);

    try private.init(std.testing.allocator);
    defer private.deinit();
    const db = private.getDb();

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_dir_path = try tmp_dir.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_dir_path);

    const root_dir = try std.fs.path.join(std.testing.allocator, &.{tmp_dir_path});
    defer std.testing.allocator.free(root_dir);

    const asset_type_hash = try cetech1.cdb_types.addBigType(_cdb, db, "ct_foo_asset", null);

    try private.api.openAssetRootFolder(root_dir, allocator);

    const asset_obj = try _cdb.createObject(db, asset_type_hash);
    const asset = private.api.createAsset("foo", private.api.getRootFolder(), asset_obj).?;

    const asset_obj_w = _cdb.writeObj(asset_obj).?;
    const asset_w = _cdb.writeObj(asset).?;

    const blob = (try _cdb.createBlob(asset_obj_w, propIdx(cetech1.cdb_types.BigTypeProps.Blob), "hello blob".len)).?;
    @memcpy(blob, "hello blob");

    try _cdb.writeCommit(asset_w);
    try _cdb.writeCommit(asset_obj_w);

    try std.testing.expect(private.api.isAssetModified(asset));
    try private.api.saveAllAssets(allocator);
    try std.testing.expect(!private.api.isAssetModified(asset));

    try private.api.deleteAsset(asset);
    private.api.reviveDeleted(asset);

    // Save all assets
    try std.testing.expect(!private.api.isToDeleted(asset));
    try private.api.saveAllModifiedAssets(allocator);
    try std.testing.expect(!private.api.isToDeleted(asset));

    // Original asset does not exist
    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "foo.ct_foo_asset.json" });
        defer std.testing.allocator.free(path);

        var f = std.fs.cwd().openFile(path, .{});
        try std.testing.expect(f != std.fs.File.OpenError.FileNotFound);
        (try f).close();
    }

    // Original asset blob dir does not exist
    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "foo.ct_blob" });
        defer std.testing.allocator.free(path);

        var d = std.fs.cwd().openDir(path, .{});
        try std.testing.expect(d != std.fs.Dir.OpenError.FileNotFound);
        (try d).close();
    }
}

test "asset: Should create asset without asset root" {
    try testInit();
    defer testDeinit();

    const allocator = try tempalloc.api.create();
    defer tempalloc.api.destroy(allocator);

    try private.init(std.testing.allocator);
    defer private.deinit();
    const db = private.getDb();

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_dir_path = try tmp_dir.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_dir_path);

    const root_dir = try std.fs.path.join(std.testing.allocator, &.{tmp_dir_path});
    defer std.testing.allocator.free(root_dir);

    const asset_type_hash = try cetech1.cdb_types.addBigType(_cdb, db, "ct_foo_asset", null);

    const asset_obj = try _cdb.createObject(db, asset_type_hash);
    const asset = private.api.createAsset("foo", private.api.getRootFolder(), asset_obj).?;

    const asset_obj_w = _cdb.writeObj(asset_obj).?;
    const asset_w = _cdb.writeObj(asset).?;

    const blob = (try _cdb.createBlob(asset_obj_w, propIdx(cetech1.cdb_types.BigTypeProps.Blob), "hello blob".len)).?;
    @memcpy(blob, "hello blob");

    try _cdb.writeCommit(asset_w);
    try _cdb.writeCommit(asset_obj_w);

    try std.testing.expect(private.api.isAssetModified(asset));
    try private.api.saveAsAllAssets(allocator, root_dir);
    try std.testing.expect(!private.api.isAssetModified(asset));

    // Original asset does not exist
    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "foo.ct_foo_asset.json" });
        defer std.testing.allocator.free(path);

        var f = std.fs.cwd().openFile(path, .{});
        try std.testing.expect(f != std.fs.File.OpenError.FileNotFound);
        (try f).close();
    }

    // Original asset blob dir does not exist
    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "foo.ct_blob" });
        defer std.testing.allocator.free(path);

        var d = std.fs.cwd().openDir(path, .{});
        try std.testing.expect(d != std.fs.Dir.OpenError.FileNotFound);
        (try d).close();
    }
}

test "asset: Should create folder without asset root" {
    try testInit();
    defer testDeinit();

    const allocator = try tempalloc.api.create();
    defer tempalloc.api.destroy(allocator);

    try private.init(std.testing.allocator);
    defer private.deinit();
    const db = private.getDb();

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_dir_path = try tmp_dir.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_dir_path);

    const root_dir = try std.fs.path.join(std.testing.allocator, &.{tmp_dir_path});
    defer std.testing.allocator.free(root_dir);

    const foo_folder = try private.api.createNewFolder(db, private.api.getRootFolder(), "foo");
    const foo_folder_asset = private.api.getAssetForObj(foo_folder).?;

    const asset_type_hash = try cetech1.cdb_types.addBigType(_cdb, db, "ct_foo_asset", null);

    const asset_obj = try _cdb.createObject(db, asset_type_hash);
    const asset = private.api.createAsset("foo", foo_folder_asset, asset_obj).?;

    const asset_obj_w = _cdb.writeObj(asset_obj).?;
    const asset_w = _cdb.writeObj(asset).?;

    const blob = (try _cdb.createBlob(asset_obj_w, propIdx(cetech1.cdb_types.BigTypeProps.Blob), "hello blob".len)).?;
    @memcpy(blob, "hello blob");

    try _cdb.writeCommit(asset_w);
    try _cdb.writeCommit(asset_obj_w);

    try std.testing.expect(private.api.isAssetModified(asset));
    try private.api.saveAsAllAssets(allocator, root_dir);
    try std.testing.expect(!private.api.isAssetModified(asset));

    // Original asset does not exist
    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "foo", "foo.ct_foo_asset.json" });
        defer std.testing.allocator.free(path);

        var f = std.fs.cwd().openFile(path, .{});
        try std.testing.expect(f != std.fs.File.OpenError.FileNotFound);
        (try f).close();
    }

    // Original asset blob dir does not exist
    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "foo", "foo.ct_blob" });
        defer std.testing.allocator.free(path);

        var d = std.fs.cwd().openDir(path, .{});
        try std.testing.expect(d != std.fs.Dir.OpenError.FileNotFound);
        (try d).close();
    }
}

test "asset: Should rename folder" {
    try testInit();
    defer testDeinit();

    const allocator = try tempalloc.api.create();
    defer tempalloc.api.destroy(allocator);

    try private.init(std.testing.allocator);
    defer private.deinit();
    const db = private.getDb();

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_dir_path = try tmp_dir.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_dir_path);

    const root_dir = try std.fs.path.join(std.testing.allocator, &.{tmp_dir_path});
    defer std.testing.allocator.free(root_dir);

    const asset_type_hash = try cetech1.cdb_types.addBigType(_cdb, db, "ct_foo_asset", null);

    try private.api.openAssetRootFolder(root_dir, allocator);

    const foo_folder = try private.api.createNewFolder(db, private.api.getRootFolder(), "foo");
    const foo_folder_asset = private.api.getAssetForObj(foo_folder).?;

    const asset_obj = try _cdb.createObject(db, asset_type_hash);
    const asset = private.api.createAsset("foo", foo_folder_asset, asset_obj).?;

    const asset_obj_w = _cdb.writeObj(asset_obj).?;
    const asset_w = _cdb.writeObj(asset).?;

    const blob = (try _cdb.createBlob(asset_obj_w, propIdx(cetech1.cdb_types.BigTypeProps.Blob), "hello blob".len)).?;
    @memcpy(blob, "hello blob");

    try _cdb.writeCommit(asset_w);
    try _cdb.writeCommit(asset_obj_w);

    try std.testing.expect(private.api.isAssetModified(asset));
    try private.api.saveAllAssets(allocator);
    try std.testing.expect(!private.api.isAssetModified(asset));

    // Change folder
    {
        const w = _cdb.writeObj(foo_folder_asset).?;
        try cetech1.assetdb.Asset.setStr(_cdb, w, .Name, "bar");
        try _cdb.writeCommit(w);
    }

    // Save all assets
    try std.testing.expect(private.api.isAssetModified(foo_folder_asset));
    try private.api.saveAllModifiedAssets(allocator);
    try std.testing.expect(!private.api.isAssetModified(foo_folder_asset));

    // Original asset does not exist
    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "foo", "foo.ct_foo_asset.json" });
        defer std.testing.allocator.free(path);

        const f = std.fs.cwd().openFile(path, .{});
        try std.testing.expect(f == std.fs.File.OpenError.FileNotFound);
    }

    // Original asset blob dir does not exist
    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "foo", "foo.ct_blob" });
        defer std.testing.allocator.free(path);

        const d = std.fs.cwd().openDir(path, .{});
        try std.testing.expect(d == std.fs.Dir.OpenError.FileNotFound);
    }

    // Asset with new folder exist
    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "bar", "foo.ct_foo_asset.json" });
        defer std.testing.allocator.free(path);

        var f = std.fs.cwd().openFile(path, .{});
        try std.testing.expect(f != std.fs.File.OpenError.FileNotFound);
        (try f).close();
    }

    // Asset blob for new folder exist
    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "bar", "foo.ct_blob" });
        defer std.testing.allocator.free(path);

        var d = std.fs.cwd().openDir(path, .{});
        try std.testing.expect(d != std.fs.Dir.OpenError.FileNotFound);
        (try d).close();
    }
}

test "asset: Should move folder" {
    try testInit();
    defer testDeinit();

    const allocator = try tempalloc.api.create();
    defer tempalloc.api.destroy(allocator);

    try private.init(std.testing.allocator);
    defer private.deinit();
    const db = private.getDb();

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_dir_path = try tmp_dir.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_dir_path);

    const root_dir = try std.fs.path.join(std.testing.allocator, &.{tmp_dir_path});
    defer std.testing.allocator.free(root_dir);

    const asset_type_hash = try cetech1.cdb_types.addBigType(_cdb, db, "ct_foo_asset", null);

    try private.api.openAssetRootFolder(root_dir, allocator);

    const foo_folder = try private.api.createNewFolder(db, private.api.getRootFolder(), "foo");
    const foo_folder_asset = private.api.getAssetForObj(foo_folder).?;

    const bar_folder = try private.api.createNewFolder(db, private.api.getRootFolder(), "bar");

    const asset_obj = try _cdb.createObject(db, asset_type_hash);
    const asset = private.api.createAsset("foo", foo_folder_asset, asset_obj).?;

    const asset_obj_w = _cdb.writeObj(asset_obj).?;
    const asset_w = _cdb.writeObj(asset).?;

    const blob = (try _cdb.createBlob(asset_obj_w, propIdx(cetech1.cdb_types.BigTypeProps.Blob), "hello blob".len)).?;
    @memcpy(blob, "hello blob");

    try _cdb.writeCommit(asset_w);
    try _cdb.writeCommit(asset_obj_w);

    try std.testing.expect(private.api.isAssetModified(asset));
    try private.api.saveAllAssets(allocator);
    try std.testing.expect(!private.api.isAssetModified(asset));

    // Change folder
    {
        const w = _cdb.writeObj(foo_folder_asset).?;
        try cetech1.assetdb.Asset.setRef(_cdb, w, .Folder, bar_folder);
        try _cdb.writeCommit(w);
    }

    // Save all assets
    try std.testing.expect(private.api.isAssetModified(foo_folder_asset));
    try private.api.saveAllModifiedAssets(allocator);
    try std.testing.expect(!private.api.isAssetModified(foo_folder_asset));

    // Original asset does not exist
    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "foo", "foo.ct_foo_asset" });
        defer std.testing.allocator.free(path);

        const f = std.fs.cwd().openFile(path, .{});
        try std.testing.expect(f == std.fs.File.OpenError.FileNotFound);
    }

    // Original asset blob dir does not exist
    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "foo", "foo.ct_blob" });
        defer std.testing.allocator.free(path);

        const d = std.fs.cwd().openDir(path, .{});
        try std.testing.expect(d == std.fs.Dir.OpenError.FileNotFound);
    }

    // Asset with new folder exist
    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "bar", "foo", "foo.ct_foo_asset.json" });
        defer std.testing.allocator.free(path);

        var f = std.fs.cwd().openFile(path, .{});
        try std.testing.expect(f != std.fs.File.OpenError.FileNotFound);
        (try f).close();
    }

    // Asset blob for new folder exist
    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "bar", "foo", "foo.ct_blob" });
        defer std.testing.allocator.free(path);

        var d = std.fs.cwd().openDir(path, .{});
        try std.testing.expect(d != std.fs.Dir.OpenError.FileNotFound);
        (try d).close();
    }
}

test "asset: Should delete folder" {
    try testInit();
    defer testDeinit();

    const allocator = try tempalloc.api.create();
    defer tempalloc.api.destroy(allocator);

    try private.init(std.testing.allocator);
    defer private.deinit();
    const db = private.getDb();

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_dir_path = try tmp_dir.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_dir_path);

    const root_dir = try std.fs.path.join(std.testing.allocator, &.{tmp_dir_path});
    defer std.testing.allocator.free(root_dir);

    const asset_type_hash = try cetech1.cdb_types.addBigType(_cdb, db, "ct_foo_asset", null);

    try private.api.openAssetRootFolder(root_dir, allocator);

    const foo_folder = try private.api.createNewFolder(db, private.api.getRootFolder(), "foo");
    const foo_folder_asset = private.api.getAssetForObj(foo_folder).?;

    const asset_obj = try _cdb.createObject(db, asset_type_hash);
    const asset = private.api.createAsset("foo", foo_folder_asset, asset_obj).?;

    const asset_obj_w = _cdb.writeObj(asset_obj).?;
    const asset_w = _cdb.writeObj(asset).?;

    const blob = (try _cdb.createBlob(asset_obj_w, propIdx(cetech1.cdb_types.BigTypeProps.Blob), "hello blob".len)).?;
    @memcpy(blob, "hello blob");

    try _cdb.writeCommit(asset_w);
    try _cdb.writeCommit(asset_obj_w);

    try std.testing.expect(private.api.isAssetModified(asset));
    try private.api.saveAllAssets(allocator);
    try std.testing.expect(!private.api.isAssetModified(asset));

    // Change folder
    //TODO
    // {
    //     const w = _cdb.writeObj(foo_folder_asset).?;
    //     try cetech1.assetdb.Asset.setStr(db, w, .Name, "bar");
    //     try _cdb.writeCommit(w);
    // }

    // And delete folder
    try private.api.deleteFolder(foo_folder_asset);

    // Save all assets
    try std.testing.expect(private.api.isToDeleted(foo_folder_asset));
    try private.api.saveAllModifiedAssets(allocator);
    try std.testing.expect(!private.api.isToDeleted(foo_folder_asset));

    // Original dir does not exist
    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "foo" });
        defer std.testing.allocator.free(path);

        const d = std.fs.cwd().openDir(path, .{});
        try std.testing.expect(d == std.fs.Dir.OpenError.FileNotFound);
    }

    // Original asset does not exist
    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "foo", "foo.ct_foo_asset" });
        defer std.testing.allocator.free(path);

        const f = std.fs.cwd().openFile(path, .{});
        try std.testing.expect(f == std.fs.File.OpenError.FileNotFound);
    }

    // Original asset blob dir does not exist
    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "foo", "foo.ct_blob" });
        defer std.testing.allocator.free(path);

        const d = std.fs.cwd().openDir(path, .{});
        try std.testing.expect(d == std.fs.Dir.OpenError.FileNotFound);
    }
}

test "asset: Should crate new asset from prototype" {
    try testInit();
    defer testDeinit();

    const allocator = try tempalloc.api.create();
    defer tempalloc.api.destroy(allocator);

    try private.init(std.testing.allocator);
    defer private.deinit();
    const db = private.getDb();

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_dir_path = try tmp_dir.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_dir_path);

    const root_dir = try std.fs.path.join(std.testing.allocator, &.{tmp_dir_path});
    defer std.testing.allocator.free(root_dir);

    const asset_type_hash = try cetech1.cdb_types.addBigType(_cdb, db, "ct_foo_asset", null);

    try private.api.openAssetRootFolder(root_dir, allocator);

    const asset_obj = try _cdb.createObject(db, asset_type_hash);
    const asset = private.api.createAsset("foo", private.api.getRootFolder(), asset_obj).?;

    const asset_obj_w = _cdb.writeObj(asset_obj).?;
    const asset_w = _cdb.writeObj(asset).?;

    const blob = (try _cdb.createBlob(asset_obj_w, propIdx(cetech1.cdb_types.BigTypeProps.Blob), "hello blob".len)).?;
    @memcpy(blob, "hello blob");

    try _cdb.writeCommit(asset_w);
    try _cdb.writeCommit(asset_obj_w);

    const new_object_asset = try private.api.createNewAssetFromPrototype(asset);
    const new_object_asset_obj = private.api.getObjForAsset(new_object_asset).?;
    const new_object_asset_obj_r = FooAsset.read(_cdb, new_object_asset_obj).?;

    const prototype = _cdb.getPrototype(new_object_asset_obj_r);
    try std.testing.expectEqual(asset_obj, prototype);
}

test "asset: Should clone new asset from" {
    try testInit();
    defer testDeinit();

    const allocator = try tempalloc.api.create();
    defer tempalloc.api.destroy(allocator);

    try private.init(std.testing.allocator);
    defer private.deinit();
    const db = private.getDb();

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_dir_path = try tmp_dir.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_dir_path);

    const root_dir = try std.fs.path.join(std.testing.allocator, &.{tmp_dir_path});
    defer std.testing.allocator.free(root_dir);

    const asset_type_hash = try cetech1.cdb_types.addBigType(_cdb, db, "ct_foo_asset", null);

    try private.api.openAssetRootFolder(root_dir, allocator);

    const asset_obj = try _cdb.createObject(db, asset_type_hash);
    const asset = private.api.createAsset("foo", private.api.getRootFolder(), asset_obj).?;

    const asset_obj_w = _cdb.writeObj(asset_obj).?;
    const asset_w = _cdb.writeObj(asset).?;

    const blob = (try _cdb.createBlob(asset_obj_w, propIdx(cetech1.cdb_types.BigTypeProps.Blob), "hello blob".len)).?;
    @memcpy(blob, "hello blob");

    try _cdb.writeCommit(asset_w);
    try _cdb.writeCommit(asset_obj_w);

    _ = try private.api.cloneNewAssetFrom(asset);
}

test "asset: Should get new valid name for asset" {
    try testInit();
    defer testDeinit();

    const allocator = try tempalloc.api.create();
    defer tempalloc.api.destroy(allocator);

    try private.init(std.testing.allocator);
    defer private.deinit();
    const db = private.getDb();

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_dir_path = try tmp_dir.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_dir_path);

    const root_dir = try std.fs.path.join(std.testing.allocator, &.{tmp_dir_path});
    defer std.testing.allocator.free(root_dir);

    const asset_type_hash = try cetech1.cdb_types.addBigType(_cdb, db, "ct_foo_asset", null);

    const foo_folder = try private.api.createNewFolder(db, private.api.getRootFolder(), "foo");
    const foo_folder_asset = private.api.getAssetForObj(foo_folder).?;

    const asset_obj = try _cdb.createObject(db, asset_type_hash);
    const asset = private.api.createAsset("foo", foo_folder_asset, asset_obj).?;

    const asset_obj_w = _cdb.writeObj(asset_obj).?;
    const asset_w = _cdb.writeObj(asset).?;

    const blob = (try _cdb.createBlob(asset_obj_w, propIdx(cetech1.cdb_types.BigTypeProps.Blob), "hello blob".len)).?;
    @memcpy(blob, "hello blob");

    try _cdb.writeCommit(asset_w);
    try _cdb.writeCommit(asset_obj_w);

    var buff: [256:0]u8 = undefined;
    const name = try private.api.buffGetValidName(
        std.testing.allocator,
        &buff,
        foo_folder_asset,
        _cdb.getTypeIdx(db, cetech1.assetdb.FooAsset.type_hash).?,
        "foo",
    );

    try std.testing.expectEqualStrings("foo2", name);
}
