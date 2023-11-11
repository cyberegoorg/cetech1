const std = @import("std");
const builtin = @import("builtin");

const apidb = @import("apidb.zig");
const task = @import("task.zig");
const tempalloc = @import("tempalloc.zig");
const cdb = @import("cdb.zig");
const cdb_test = @import("cdb_test.zig");
const cdb_types = @import("cdb_types.zig");
const log = @import("log.zig");
const uuid = @import("uuid.zig");
const private = @import("assetdb.zig");

const public = @import("../assetdb.zig");
const cetech1 = @import("../cetech1.zig");
const propIdx = cetech1.cdb.propIdx;

const FooAsset = public.FooAsset;

pub fn WriteBlobToNull(
    blob: []const u8,
    asset: cetech1.cdb.ObjId,
    obj_uuid: cetech1.uuid.Uuid,
    prop_hash: cetech1.strid.StrId32,
    root_path: []const u8,
    tmp_allocator: std.mem.Allocator,
) anyerror!void {
    _ = blob;
    _ = asset;
    _ = prop_hash;
    _ = tmp_allocator;
    _ = obj_uuid;
    _ = root_path;
}

pub fn ReadBlobFromNull(
    asset: cetech1.cdb.ObjId,
    obj_uuid: cetech1.uuid.Uuid,
    prop_hash: cetech1.strid.StrId32,
    tmp_allocator: std.mem.Allocator,
) anyerror![]u8 {
    _ = asset;
    _ = obj_uuid;
    _ = prop_hash;
    _ = tmp_allocator;
    return &.{};
}

fn testInit() !void {
    try tempalloc.init(std.testing.allocator, 256);
    try task.init(std.testing.allocator);
    try apidb.init(std.testing.allocator);
    try cdb.init(std.testing.allocator);
    try private.registerToApi();
    try task.start();
    try cdb_types.registerToApi();
}

fn testDeinit() void {
    cdb.deinit();
    apidb.deinit();
    task.deinit();
    tempalloc.deinit();
}

test "asset: Should save asset to json" {
    try testInit();
    defer testDeinit();

    var db = try cdb.api.createDb("Test");
    defer cdb.api.destroyDb(db);

    try private.init(std.testing.allocator, &db);
    defer private.deinit();

    const prototype_obj = try private.createObjectWithUuid(FooAsset.type_hash, uuid.fromStr("9c49cfdb-0d31-485f-8623-24248b53c30f").?);
    const proto_ref_obj1 = try FooAsset.createObject(&db);
    const proto_ref_obj2 = try FooAsset.createObject(&db);
    const proto_sub_obj1 = try FooAsset.createObject(&db);
    const proto_sub_obj2 = try FooAsset.createObject(&db);

    const proto_w = db.writeObj(prototype_obj).?;
    const proto_sub_obj1_w = db.writeObj(proto_sub_obj1).?;
    const proto_sub_obj2_w = db.writeObj(proto_sub_obj2).?;
    try FooAsset.addRefToSet(&db, proto_w, .REFERENCE_SET, &.{ proto_ref_obj1, proto_ref_obj2 });

    try FooAsset.addSubObjToSet(
        &db,
        proto_w,
        .SUBOBJECT_SET,
        &.{ proto_sub_obj1_w, proto_sub_obj2_w },
    );

    db.writeCommit(proto_sub_obj2_w);
    db.writeCommit(proto_sub_obj1_w);
    db.writeCommit(proto_w);

    const asset_obj = try db.createObjectFromPrototype(prototype_obj);
    const asset = private.api.createAsset("foo", private.api.getRootFolder(), asset_obj).?;

    const ref_obj1 = try FooAsset.createObject(&db);
    const ref_obj2 = try FooAsset.createObject(&db);
    const sub_obj1 = try FooAsset.createObject(&db);
    const sub_obj2 = try FooAsset.createObject(&db);

    const asset_w = db.writeObj(asset).?;
    const prototype_obj_w = db.writeObj(prototype_obj).?;
    const asset_obj_w = db.writeObj(asset_obj).?;
    const sub_obj1_w = db.writeObj(sub_obj1).?;
    const sub_obj2_w = db.writeObj(sub_obj2).?;

    // Prototype value
    FooAsset.setValue(&db, u64, prototype_obj_w, .U64, 10);
    FooAsset.setValue(&db, i64, prototype_obj_w, .I64, 20);

    try FooAsset.setStr(&db, asset_obj_w, .STR, "foo");
    FooAsset.setValue(&db, bool, asset_obj_w, .BOOL, true);
    FooAsset.setValue(&db, u32, asset_obj_w, .U32, 10);
    FooAsset.setValue(&db, i32, asset_obj_w, .I32, 20);
    FooAsset.setValue(&db, f64, asset_obj_w, .F64, 20.0);
    FooAsset.setValue(&db, f32, asset_obj_w, .F32, 30.0);

    try FooAsset.setRef(&db, asset_obj_w, .REFERENCE, ref_obj1);
    try FooAsset.addRefToSet(&db, asset_obj_w, .REFERENCE_SET, &.{ref_obj2});
    try FooAsset.removeFromRefSet(&db, asset_obj_w, .REFERENCE_SET, proto_ref_obj1);

    try FooAsset.setSubObj(&db, asset_obj_w, .SUBOBJECT, sub_obj1_w);
    const inisiated_subobj1 = try db.instantiateSubObjFromSet(asset_obj_w, propIdx(cetech1.cdb_types.BigTypeProps.SUBOBJECT_SET), proto_sub_obj1);
    try FooAsset.addSubObjToSet(&db, asset_obj_w, .SUBOBJECT_SET, &.{sub_obj2_w});

    const blob = (try FooAsset.createBlob(&db, asset_obj_w, .BLOB, "hello blob".len)).?;
    @memcpy(blob, "hello blob");

    db.writeCommit(sub_obj1_w);
    db.writeCommit(sub_obj2_w);
    db.writeCommit(asset_obj_w);
    db.writeCommit(prototype_obj_w);
    db.writeCommit(asset_w);

    var expect_buffer: [2048]u8 = undefined;
    const expected_fmt =
        \\{{
        \\  "__version": "0.1.0",
        \\  "__asset_uuid": "{s}",
        \\  "__type_name": "ct_foo_asset",
        \\  "__uuid": "{s}",
        \\  "__prototype_uuid": "9c49cfdb-0d31-485f-8623-24248b53c30f",
        \\  "BOOL": true,
        \\  "U32": 10,
        \\  "I32": 20,
        \\  "F32": 3.0e+01,
        \\  "F64": 2.0e+01,
        \\  "STR": "foo",
        \\  "BLOB": "{x}3f1f6a11",
        \\  "SUBOBJECT": {{
        \\    "__type_name": "ct_foo_asset",
        \\    "__uuid": "{s}"
        \\  }},
        \\  "REFERENCE": "ct_foo_asset:{s}",
        \\  "SUBOBJECT_SET": [
        \\    {{
        \\      "__type_name": "ct_foo_asset",
        \\      "__uuid": "{s}"
        \\    }}
        \\  ],
        \\  "SUBOBJECT_SET__instantiate": [
        \\    {{
        \\      "__type_name": "ct_foo_asset",
        \\      "__uuid": "{s}",
        \\      "__prototype_uuid": "{s}"
        \\    }}
        \\  ],
        \\  "REFERENCE_SET": [
        \\    "ct_foo_asset:{s}"
        \\  ],
        \\  "REFERENCE_SET__removed": [
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
        .{},
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
                cetech1.strid.strId32(&private.api.getUuid(asset_obj).?.bytes).id,
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

    db.destroyObject(asset);
    db.destroyObject(ref_obj1);
    db.destroyObject(ref_obj2);
    try db.gc(std.testing.allocator);
}

test "asset: Should read asset from json reader" {
    try testInit();
    defer testDeinit();

    var db = try cdb.api.createDb("Test");
    defer cdb.api.destroyDb(db);

    try private.init(std.testing.allocator, &db);
    defer private.deinit();

    const prototype_obj = try private.createObjectWithUuid(FooAsset.type_hash, uuid.fromStr("9c49cfdb-0d31-485f-8623-24248b53c30f").?);
    const proto_ref_obj1 = try private.createObjectWithUuid(FooAsset.type_hash, uuid.fromStr("965a0c48-f166-4f66-a894-9f8d750c7c28").?);
    const proto_ref_obj2 = try private.createObjectWithUuid(FooAsset.type_hash, uuid.fromStr("8c709979-23ca-4542-90ca-0a9b7a96f3c5").?);
    const proto_sub_obj1 = try private.createObjectWithUuid(FooAsset.type_hash, uuid.fromStr("16e130f3-f21d-4fa7-8974-b90e607ce640").?);
    const proto_sub_obj2 = try private.createObjectWithUuid(FooAsset.type_hash, uuid.fromStr("bee0d651-e624-4b78-8500-00cbeeeecf44").?);

    const proto_w = db.writeObj(prototype_obj).?;
    const proto_sub_obj1_w = db.writeObj(proto_sub_obj1).?;
    const proto_sub_obj2_w = db.writeObj(proto_sub_obj2).?;

    try FooAsset.addRefToSet(&db, proto_w, .REFERENCE_SET, &.{ proto_ref_obj1, proto_ref_obj2 });
    try FooAsset.addSubObjToSet(&db, proto_w, .SUBOBJECT_SET, &.{ proto_sub_obj1_w, proto_sub_obj2_w });

    db.writeCommit(proto_sub_obj2_w);
    db.writeCommit(proto_sub_obj1_w);
    db.writeCommit(proto_w);

    const folder1 = try public.FolderType.createObject(&db);
    const folder2 = try public.FolderType.createObject(&db);

    const prototype_obj_w = db.writeObj(prototype_obj).?;
    // Prototype value
    db.setValue(u64, prototype_obj_w, propIdx(cetech1.cdb_types.BigTypeProps.U64), 10);
    db.setValue(i64, prototype_obj_w, propIdx(cetech1.cdb_types.BigTypeProps.I64), 20);
    db.writeCommit(prototype_obj_w);

    const ref_obj1 = try private.createObjectWithUuid(FooAsset.type_hash, uuid.fromStr("018b5846-c2d5-7921-823a-60d80f9285de").?);
    const ref_obj2 = try private.createObjectWithUuid(FooAsset.type_hash, uuid.fromStr("018b5846-c2d5-74f2-a050-c9375ad9a1f6").?);

    const input_json =
        \\{
        \\  "__version": "0.1.0",
        \\  "__asset_uuid": "018b5846-c2d5-7b88-95f9-a7538a00e76b",
        \\  "__type_name": "ct_foo_asset",
        \\  "__uuid": "018b5846-c2d5-712f-bb12-9d9d15321ecb",
        \\  "__prototype_uuid": "9c49cfdb-0d31-485f-8623-24248b53c30f",
        \\  "BOOL": true,
        \\  "U32": 10,
        \\  "I32": 20,
        \\  "F32": 3.0e+01,
        \\  "F64": 2.0e+01,
        \\  "STR": "foo",
        \\  "SUBOBJECT": {
        \\    "__type_name": "ct_foo_asset",
        \\    "__uuid": "018b5846-c2d5-7c82-82b4-525348222242"
        \\  },
        \\  "REFERENCE": "ct_foo_asset:018b5846-c2d5-7921-823a-60d80f9285de",
        \\  "SUBOBJECT_SET": [
        \\    {
        \\      "__type_name": "ct_foo_asset",
        \\      "__uuid": "018b5846-c2d5-7584-9183-a95f78095230"
        \\    }
        \\  ],
        \\  "SUBOBJECT_SET__instantiate": [
        \\    {
        \\      "__type_name": "ct_foo_asset",
        \\      "__uuid": "0277c070-b7a4-4ae1-947f-f85c67ec15a6",
        \\      "__prototype_uuid": "16e130f3-f21d-4fa7-8974-b90e607ce640"
        \\    }
        \\  ],
        \\  "REFERENCE_SET": [
        \\    "ct_foo_asset:018b5846-c2d5-74f2-a050-c9375ad9a1f6"
        \\  ],
        \\  "REFERENCE_SET__removed": [
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
        folder1,
        ReadBlobFromNull,
        std.testing.allocator,
    );
    try std.testing.expectEqual(uuid.fromStr("018b5846-c2d5-7b88-95f9-a7538a00e76b").?, private.api.getUuid(asset).?);

    const asset_obj = public.AssetType.readSubObj(&db, db.readObj(asset).?, .Object);
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
        folder2,
        WriteBlobToNull,
        "",
        std.testing.allocator,
    );

    try std.testing.expectEqualStrings(input_json, fixed_out_buffer_stream.getWritten());

    db.destroyObject(asset);
    db.destroyObject(ref_obj1);
    db.destroyObject(ref_obj2);
    db.destroyObject(prototype_obj);
    db.destroyObject(folder1);
    db.destroyObject(folder2);
}

test "asset: Should create asset" {
    try testInit();
    defer testDeinit();

    var db = try cdb.api.createDb("Test");
    defer cdb.api.destroyDb(db);

    try private.init(std.testing.allocator, &db);

    const asset = private.api.createAsset("foo", private.api.getRootFolder(), null);
    try std.testing.expect(asset != null);

    private.deinit();
    try db.gc(std.testing.allocator);
    try cdb_test.expectGCStats(db, 4, 9);
}

test "asset: Should open asset dir" {
    try testInit();
    defer testDeinit();

    // log.api.err(
    //     MODULE_NAME,
    //     "ddddd {x}{x}",
    //     .{ cetech1.strid.strId32(&(try uuid.fromStr("018b5846-c2d5-712f-bb12-9d9d15321ecb")).bytes).id, cetech1.strid.strId32("BLOB").id },
    // );

    // log.api.err(
    //     MODULE_NAME,
    //     "ddddd {x}{x}",
    //     .{ cetech1.strid.strId32(&(try uuid.fromStr("018b5c74-06f7-79fd-a6ad-3678552795a1")).bytes).id, cetech1.strid.strId32("BLOB").id },
    // );

    // log.api.err(
    //     MODULE_NAME,
    //     "ddddd {x}{x}",
    //     .{ cetech1.strid.strId32(&(try uuid.fromStr("018b5c72-5350-7d06-b5ed-6fed2793fdd4")).bytes).id, cetech1.strid.strId32("BLOB").id },
    // );

    var db = try cdb.api.createDb("Test");
    defer cdb.api.destroyDb(db);

    const asset_type_hash = try cetech1.cdb_types.addBigType(&db, "ct_foo_asset");
    _ = asset_type_hash;

    try private.init(std.testing.allocator, &db);
    defer private.deinit();

    for (0..1) |_| {
        try private.api.openAssetRootFolder("tests/test_asset", std.testing.allocator);

        var root_folder: ?cetech1.cdb.ObjId = undefined;
        var core_folder: ?cetech1.cdb.ObjId = undefined;
        var core_subfolder_folder: ?cetech1.cdb.ObjId = undefined;

        // /
        {
            const foo_obj = private.api.getObjId(uuid.fromStr("018b5846-c2d5-712f-bb12-9d9d15321ecb").?);
            try std.testing.expect(foo_obj != null);

            var foo_obj_asset = db.getParent(db.readObj(foo_obj.?).?);
            try std.testing.expect(!foo_obj_asset.isEmpty());

            const expect_name = "foo";
            try std.testing.expectEqualStrings(
                expect_name,
                public.AssetType.readStr(&db, db.readObj(foo_obj_asset).?, .Name).?,
            );

            const blob = db.readBlob(db.readObj(foo_obj.?).?, propIdx(cetech1.cdb_types.BigTypeProps.BLOB));
            try std.testing.expectEqualSlices(u8, "hello blob", blob);

            root_folder = public.AssetType.readRef(&db, db.readObj(foo_obj_asset).?, .Folder);
            try std.testing.expect(root_folder != null);
            try std.testing.expect(null == public.FolderType.readStr(&db, db.readObj(root_folder.?).?, .Name));

            try std.testing.expectEqual(root_folder, private.api.getRootFolder());
            const set = try db.getReferencerSet(root_folder.?, std.testing.allocator);
            defer std.testing.allocator.free(set);
            // TODO: try std.testing.expectEqual(@as(usize, 3), set.len);

            const sub_path = try private.getFilePathForAsset(foo_obj_asset, std.testing.allocator);
            defer std.testing.allocator.free(sub_path);
            try std.testing.expectEqualStrings("foo.ct_foo_asset", sub_path);

            // Check refenced objects
            const expect_name2 = "foo core";
            try std.testing.expectEqualStrings(expect_name2, FooAsset.readStr(
                &db,
                db.readObj(FooAsset.readRef(&db, db.readObj(foo_obj.?).?, .REFERENCE).?).?,
                .STR,
            ).?);
        }

        const foo_core_obj = private.api.getObjId(uuid.fromStr("018b5c72-5350-7d06-b5ed-6fed2793fdd4").?);
        // /core
        {
            try std.testing.expect(foo_core_obj != null);

            var foo_core_obj_asset = db.getParent(db.readObj(foo_core_obj.?).?);
            try std.testing.expect(!foo_core_obj_asset.isEmpty());

            const expect_name = "foo_core";
            try std.testing.expectEqualStrings(
                expect_name,
                public.AssetType.readStr(&db, db.readObj(foo_core_obj_asset).?, .Name).?,
            );

            const blob = db.readBlob(db.readObj(foo_core_obj.?).?, propIdx(cetech1.cdb_types.BigTypeProps.BLOB));
            try std.testing.expectEqualSlices(u8, "hello core blob", blob);

            core_folder = public.AssetType.readRef(&db, db.readObj(foo_core_obj_asset).?, .Folder);
            try std.testing.expect(core_folder != null);

            const expect_folder_name = "core";
            try std.testing.expectEqualStrings(
                expect_folder_name,
                public.FolderType.readStr(&db, db.readObj(core_folder.?).?, .Name).?,
            );

            const sub_path = try private.getFilePathForAsset(foo_core_obj_asset, std.testing.allocator);
            defer std.testing.allocator.free(sub_path);

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

            var foo_subcore_obj_asset = db.getParent(db.readObj(foo_subcore_obj.?).?);
            try std.testing.expect(!foo_subcore_obj_asset.isEmpty());

            const expect_name = "foo_subcore";
            try std.testing.expectEqualStrings(
                expect_name,
                public.AssetType.readStr(&db, db.readObj(foo_subcore_obj_asset).?, .Name).?,
            );

            const blob = db.readBlob(db.readObj(foo_subcore_obj.?).?, propIdx(cetech1.cdb_types.BigTypeProps.BLOB));
            try std.testing.expectEqualSlices(u8, "hello subcore blob", blob);

            const ref_set = db.readRefSet(db.readObj(foo_subcore_obj.?).?, propIdx(cetech1.cdb_types.BigTypeProps.REFERENCE_SET), std.testing.allocator);
            defer std.testing.allocator.free(ref_set.?);
            try std.testing.expect(ref_set != null);
            try std.testing.expectEqualSlices(
                cetech1.cdb.ObjId,
                &[_]cetech1.cdb.ObjId{foo_core_obj.?},
                ref_set.?,
            );

            const subobj = private.api.getObjId(uuid.fromStr("018b5c74-06f7-70bb-94e3-10a2a8619d31").?);
            const inisiated_subobj = private.api.getObjId(uuid.fromStr("7d0d10ce-128e-45ab-8c14-c5d486542d4f").?);
            const subobj_set = db.readRefSet(db.readObj(foo_subcore_obj.?).?, propIdx(cetech1.cdb_types.BigTypeProps.SUBOBJECT_SET), std.testing.allocator);
            defer std.testing.allocator.free(subobj_set.?);
            try std.testing.expect(subobj_set != null);
            try std.testing.expectEqualSlices(
                cetech1.cdb.ObjId,
                &[_]cetech1.cdb.ObjId{ subobj.?, inisiated_subobj.? },
                subobj_set.?,
            );

            core_subfolder_folder = public.AssetType.readRef(&db, db.readObj(foo_subcore_obj_asset).?, .Folder);
            try std.testing.expect(core_subfolder_folder != null);

            const expect_folder_name = "core_subfolder";
            try std.testing.expectEqualStrings(
                expect_folder_name,
                public.FolderType.readStr(&db, db.readObj(core_subfolder_folder.?).?, .Name).?,
            );

            const sub_path = try private.getFilePathForAsset(foo_subcore_obj_asset, std.testing.allocator);
            defer std.testing.allocator.free(sub_path);

            if (builtin.os.tag == .windows) {
                try std.testing.expectEqualStrings("core\\core_subfolder\\foo_subcore.ct_foo_asset", sub_path);
            } else {
                try std.testing.expectEqualStrings("core/core_subfolder/foo_subcore.ct_foo_asset", sub_path);
            }

            // Check refenced objects
            const expect_name2 = "foo core";
            try std.testing.expectEqualStrings(expect_name2, FooAsset.readStr(
                &db,
                db.readObj(FooAsset.readRef(&db, db.readObj(foo_subcore_obj.?).?, .REFERENCE).?).?,
                .STR,
            ).?);
        }
    }
}

test "asset: Should save asset dir" {
    try testInit();
    defer testDeinit();

    var tmpalloc = try tempalloc.api.createTempArena();
    defer tempalloc.api.destroyTempArena(tmpalloc);

    var db = try cdb.api.createDb("Test");
    defer cdb.api.destroyDb(db);

    const root_dir = "tests/tmp/test_asset_save";
    try std.fs.cwd().deleteTree(root_dir);
    try std.fs.cwd().makePath(root_dir);

    const asset_type_hash = try cetech1.cdb_types.addBigType(&db, "ct_foo_asset");

    try private.init(std.testing.allocator, &db);
    defer private.deinit();

    try private.api.openAssetRootFolder(root_dir, tmpalloc.allocator());

    const asset_obj = try db.createObject(asset_type_hash);
    const asset = private.api.createAsset("foo", private.api.getRootFolder(), asset_obj).?;

    const asset_obj_w = db.writeObj(asset_obj).?;
    const asset_w = db.writeObj(asset).?;

    const blob = (try db.createBlob(asset_obj_w, propIdx(cetech1.cdb_types.BigTypeProps.BLOB), "hello blob".len)).?;
    @memcpy(blob, "hello blob");

    db.writeCommit(asset_w);
    db.writeCommit(asset_obj_w);

    try std.testing.expect(private.api.isAssetModified(asset));
    try private.api.saveAllAssets(tmpalloc.allocator());
    try std.testing.expect(!private.api.isAssetModified(asset));

    var f = std.fs.cwd().openFile(root_dir ++ "/foo.ct_foo_asset", .{});
    try std.testing.expect(f != std.fs.File.OpenError.FileNotFound);
    (try f).close();

    f = std.fs.cwd().openFile(root_dir ++ "/." ++ public.FolderType.name, .{});
    try std.testing.expect(f != std.fs.File.OpenError.FileNotFound);
    (try f).close();

    var d = std.fs.cwd().openDir(root_dir ++ "/" ++ private.CT_TEMP_FOLDER, .{});
    try std.testing.expect(d != std.fs.Dir.OpenError.FileNotFound);
    (try d).close();
}

test "asset: Should save modified asset" {
    try testInit();
    defer testDeinit();

    var tmpalloc = try tempalloc.api.createTempArena();
    defer tempalloc.api.destroyTempArena(tmpalloc);

    var db = try cdb.api.createDb("Test");
    defer cdb.api.destroyDb(db);

    const root_dir = "tests/tmp/test_asset_save_modified";
    try std.fs.cwd().deleteTree(root_dir);
    try std.fs.cwd().makePath(root_dir);

    const asset_type_hash = try cetech1.cdb_types.addBigType(&db, "ct_foo_asset");

    try private.init(std.testing.allocator, &db);
    defer private.deinit();

    try private.api.openAssetRootFolder(root_dir, tmpalloc.allocator());

    const asset_obj = try db.createObject(asset_type_hash);
    const asset = private.api.createAsset("foo", private.api.getRootFolder(), asset_obj).?;

    const asset_obj_w = db.writeObj(asset_obj).?;
    const asset_w = db.writeObj(asset).?;

    const blob = (try db.createBlob(asset_obj_w, propIdx(cetech1.cdb_types.BigTypeProps.BLOB), "hello blob".len)).?;
    @memcpy(blob, "hello blob");

    db.writeCommit(asset_w);
    db.writeCommit(asset_obj_w);

    try std.testing.expect(private.api.isAssetModified(asset));
    try private.api.saveAllModifiedAssets(tmpalloc.allocator());
    try std.testing.expect(!private.api.isAssetModified(asset));

    var f = std.fs.cwd().openFile(root_dir ++ "/foo.ct_foo_asset", .{});
    try std.testing.expect(f != std.fs.File.OpenError.FileNotFound);
    (try f).close();

    f = std.fs.cwd().openFile(root_dir ++ "/." ++ public.FolderType.name, .{});
    try std.testing.expect(f != std.fs.File.OpenError.FileNotFound);
    (try f).close();

    var d = std.fs.cwd().openDir(root_dir ++ "/" ++ private.CT_TEMP_FOLDER, .{});
    try std.testing.expect(d != std.fs.Dir.OpenError.FileNotFound);
    (try d).close();
}
