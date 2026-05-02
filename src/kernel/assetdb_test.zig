const std = @import("std");
const builtin = @import("builtin");

const apidb_private = @import("apidb.zig");
const task_private = @import("task.zig");
const tempalloc_private = @import("tempalloc.zig");
const cdb_private = @import("cdb.zig");
const cdb_test = @import("cdb_test.zig");
const cdb_types_private = @import("cdb_types.zig");
const log_private = @import("log.zig");
const uuid_private = @import("uuid.zig");
const assetdb_private = @import("assetdb.zig");
const metrics_private = @import("metrics.zig");

const cetech1 = @import("cetech1");
const cdb = cetech1.cdb;
const public = cetech1.assetdb;
const propIdx = cdb.propIdx;
const tempalloc = cetech1.tempalloc;

const FooAsset = public.FooAsset;

pub fn WriteBlobToNull(
    io: std.Io,
    blob: []const u8,
    asset: cdb.ObjId,
    obj_uuid: cetech1.uuid.Uuid,
    prop_hash: cetech1.StrId32,
    root_path: []const u8,
    allocator: std.mem.Allocator,
) anyerror!void {
    _ = io;
    _ = blob;
    _ = asset;
    _ = prop_hash;
    _ = allocator;
    _ = obj_uuid;
    _ = root_path;
}

pub fn ReadBlobFromNull(
    io: std.Io,
    asset: cdb.ObjId,
    obj_uuid: cetech1.uuid.Uuid,
    prop_hash: cetech1.StrId32,
    allocator: std.mem.Allocator,
) anyerror![]u8 {
    _ = io;
    _ = asset;
    _ = obj_uuid;
    _ = prop_hash;
    _ = allocator;
    return &.{};
}

fn testInit() !void {
    try tempalloc_private.init(std.testing.allocator, 256);
    try task_private.init(std.testing.io, std.testing.allocator);
    try apidb_private.init(std.testing.allocator);
    try metrics_private.init(std.testing.allocator);
    try cdb_private.init(std.testing.io, std.testing.allocator);
    try assetdb_private.registerToApi();
    try task_private.start(null);
    try cdb_types_private.registerToApi();
}

fn testDeinit() void {
    cdb_private.deinit();
    apidb_private.deinit();
    task_private.stop();
    task_private.deinit();
    tempalloc_private.deinit();
    metrics_private.deinit();
}

test "asset: Should save asset to json" {
    try testInit();
    defer testDeinit();

    try assetdb_private.init(std.testing.io, std.testing.allocator);
    defer assetdb_private.deinit();

    const db = assetdb_private.getDb();

    const prototype_obj = try assetdb_private.createObjectWithUuid(
        FooAsset.typeIdx(db),
        uuid_private.fromStr("9c49cfdb-0d31-485f-8623-24248b53c30f").?,
    );

    const proto_ref_obj1 = try FooAsset.createObject(db);
    const proto_ref_obj2 = try FooAsset.createObject(db);
    const proto_sub_obj1 = try FooAsset.createObject(db);
    const proto_sub_obj2 = try FooAsset.createObject(db);

    const proto_w = cdb.writeObj(prototype_obj).?;
    const proto_sub_obj1_w = cdb.writeObj(proto_sub_obj1).?;
    const proto_sub_obj2_w = cdb.writeObj(proto_sub_obj2).?;
    try FooAsset.addRefToSet(proto_w, .ReferenceSet, &.{ proto_ref_obj1, proto_ref_obj2 });

    try FooAsset.addSubObjToSet(
        proto_w,
        .SubobjectSet,
        &.{ proto_sub_obj1_w, proto_sub_obj2_w },
    );

    try cdb.writeCommit(proto_sub_obj2_w);
    try cdb.writeCommit(proto_sub_obj1_w);
    try cdb.writeCommit(proto_w);

    const asset_obj = try cdb.createObjectFromPrototype(prototype_obj);
    const asset = public.createAsset("foo", public.getRootFolder(), asset_obj).?;

    const ref_obj1 = try FooAsset.createObject(db);
    const ref_obj2 = try FooAsset.createObject(db);
    const sub_obj1 = try FooAsset.createObject(db);
    const sub_obj2 = try FooAsset.createObject(db);

    const asset_w = cdb.writeObj(asset).?;
    const prototype_obj_w = cdb.writeObj(prototype_obj).?;
    const asset_obj_w = cdb.writeObj(asset_obj).?;
    const sub_obj1_w = cdb.writeObj(sub_obj1).?;
    const sub_obj2_w = cdb.writeObj(sub_obj2).?;

    // Prototype value
    FooAsset.setValue(u64, prototype_obj_w, .U64, 10);
    FooAsset.setValue(i64, prototype_obj_w, .I64, 20);

    try FooAsset.setStr(asset_obj_w, .Str, "foo");
    FooAsset.setValue(bool, asset_obj_w, .Bool, true);
    FooAsset.setValue(u32, asset_obj_w, .U32, 10);
    FooAsset.setValue(i32, asset_obj_w, .I32, 20);
    FooAsset.setValue(f64, asset_obj_w, .F64, 20.1);
    FooAsset.setValue(f32, asset_obj_w, .F32, 30.1);

    try FooAsset.setRef(asset_obj_w, .Reference, ref_obj1);
    try FooAsset.addRefToSet(asset_obj_w, .ReferenceSet, &.{ref_obj2});
    try FooAsset.removeFromRefSet(asset_obj_w, .ReferenceSet, proto_ref_obj1);

    try FooAsset.setSubObj(asset_obj_w, .Subobject, sub_obj1_w);
    const inisiated_subobj1 = try cdb.instantiateSubObjFromSet(asset_obj_w, propIdx(cetech1.cdb_types.BigTypeProps.SubobjectSet), proto_sub_obj1);
    try FooAsset.addSubObjToSet(asset_obj_w, .SubobjectSet, &.{sub_obj2_w});

    const blob = (try FooAsset.createBlob(asset_obj_w, .Blob, "hello blob".len)).?;
    @memcpy(blob, "hello blob");

    try cdb.writeCommit(sub_obj1_w);
    try cdb.writeCommit(sub_obj2_w);
    try cdb.writeCommit(asset_obj_w);
    try cdb.writeCommit(prototype_obj_w);
    try cdb.writeCommit(asset_w);

    var expect_buffer: [2048]u8 = undefined;
    const expected_fmt =
        \\{{
        \\  "__version": "0.1.0",
        \\  "__asset_uuid": "{f}",
        \\  "__type_name": "ct_foo_asset",
        \\  "__uuid": "{f}",
        \\  "__prototype_uuid": "9c49cfdb-0d31-485f-8623-24248b53c30f",
        \\  "bool": true,
        \\  "u32": 10,
        \\  "i32": 20,
        \\  "f32": 30.100000381469727,
        \\  "f64": 20.1,
        \\  "str": "foo",
        \\  "blob": "{x}d667a6af",
        \\  "subobject": {{
        \\    "__type_name": "ct_foo_asset",
        \\    "__uuid": "{f}"
        \\  }},
        \\  "reference": "ct_foo_asset:{f}",
        \\  "subobject_set": [
        \\    {{
        \\      "__type_name": "ct_foo_asset",
        \\      "__uuid": "{f}"
        \\    }}
        \\  ],
        \\  "subobject_set__instantiate": [
        \\    {{
        \\      "__type_name": "ct_foo_asset",
        \\      "__uuid": "{f}",
        \\      "__prototype_uuid": "{f}"
        \\    }}
        \\  ],
        \\  "reference_set": [
        \\    "ct_foo_asset:{f}"
        \\  ],
        \\  "reference_set__removed": [
        \\    "ct_foo_asset:{f}"
        \\  ]
        \\}}
    ;

    var out_buffer: [2048]u8 = @splat(0);
    var fixed_buffer_stream = std.Io.Writer.fixed(&out_buffer);

    try assetdb_private.writeCdbObjJson(
        std.testing.io,
        asset,
        &fixed_buffer_stream,
        asset,
        WriteBlobToNull,
        "",
        std.testing.allocator,
        null,
    );
    try std.testing.expectEqualStrings(
        try std.fmt.bufPrint(
            &expect_buffer,
            expected_fmt,
            .{
                public.getUuid(asset).?,
                public.getUuid(asset_obj).?,
                cetech1.strId32(&public.getUuid(asset_obj).?.bytes).id,
                public.getUuid(sub_obj1).?,
                public.getUuid(ref_obj1).?,
                public.getUuid(sub_obj2).?,
                public.getUuid(inisiated_subobj1).?,
                public.getUuid(proto_sub_obj1).?,
                public.getUuid(ref_obj2).?,
                public.getUuid(proto_ref_obj1).?,
            },
        ),
        std.mem.sliceTo(&out_buffer, 0),
    );

    //std.debug.print("\n {s} \n", .{fixed_buffer_stream.getWritten()});

    cdb.destroyObject(asset);
    cdb.destroyObject(ref_obj1);
    cdb.destroyObject(ref_obj2);
    try cdb.gc(std.testing.allocator, db);
}

test "asset: Should read asset from json reader" {
    try testInit();
    defer testDeinit();

    try assetdb_private.init(std.testing.io, std.testing.allocator);
    defer assetdb_private.deinit();
    const db = assetdb_private.getDb();

    const prototype_obj = try assetdb_private.createObjectWithUuid(FooAsset.typeIdx(db), uuid_private.fromStr("9c49cfdb-0d31-485f-8623-24248b53c30f").?);
    const proto_ref_obj1 = try assetdb_private.createObjectWithUuid(FooAsset.typeIdx(db), uuid_private.fromStr("965a0c48-f166-4f66-a894-9f8d750c7c28").?);
    const proto_ref_obj2 = try assetdb_private.createObjectWithUuid(FooAsset.typeIdx(db), uuid_private.fromStr("8c709979-23ca-4542-90ca-0a9b7a96f3c5").?);
    const proto_sub_obj1 = try assetdb_private.createObjectWithUuid(FooAsset.typeIdx(db), uuid_private.fromStr("16e130f3-f21d-4fa7-8974-b90e607ce640").?);
    const proto_sub_obj2 = try assetdb_private.createObjectWithUuid(FooAsset.typeIdx(db), uuid_private.fromStr("bee0d651-e624-4b78-8500-00cbeeeecf44").?);

    const proto_w = cdb.writeObj(prototype_obj).?;
    const proto_sub_obj1_w = cdb.writeObj(proto_sub_obj1).?;
    const proto_sub_obj2_w = cdb.writeObj(proto_sub_obj2).?;

    try FooAsset.addRefToSet(proto_w, .ReferenceSet, &.{ proto_ref_obj1, proto_ref_obj2 });
    try FooAsset.addSubObjToSet(proto_w, .SubobjectSet, &.{ proto_sub_obj1_w, proto_sub_obj2_w });

    try cdb.writeCommit(proto_sub_obj2_w);
    try cdb.writeCommit(proto_sub_obj1_w);
    try cdb.writeCommit(proto_w);

    const folder1_asset = try public.AssetCdb.createObject(db);
    const folder1 = try public.FolderCdb.createObject(db);
    const folder1_w = public.FolderCdb.write(folder1).?;
    const folder1_asset_w = cdb.writeObj(folder1_asset).?;
    try public.AssetCdb.setSubObj(folder1_asset_w, .Object, folder1_w);
    try cdb.writeCommit(folder1_w);
    try cdb.writeCommit(folder1_asset_w);

    const prototype_obj_w = cdb.writeObj(prototype_obj).?;
    // Prototype value
    cdb.setValue(u64, prototype_obj_w, propIdx(cetech1.cdb_types.BigTypeProps.U64), 10);
    cdb.setValue(i64, prototype_obj_w, propIdx(cetech1.cdb_types.BigTypeProps.I64), 20);
    try cdb.writeCommit(prototype_obj_w);

    const ref_obj1 = try assetdb_private.createObjectWithUuid(FooAsset.typeIdx(db), uuid_private.fromStr("018b5846-c2d5-7921-823a-60d80f9285de").?);
    const ref_obj2 = try assetdb_private.createObjectWithUuid(FooAsset.typeIdx(db), uuid_private.fromStr("018b5846-c2d5-74f2-a050-c9375ad9a1f6").?);

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
        \\  "f32": 30.100000381469727,
        \\  "f64": 20.1,
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

    var fixed_buffer_stream = std.Io.Reader.fixed(input_json);

    const asset = try assetdb_private.readAssetFromReader(
        std.testing.io,
        &fixed_buffer_stream,
        "foo",
        folder1_asset,
        ReadBlobFromNull,
        std.testing.allocator,
    );
    try std.testing.expectEqual(uuid_private.fromStr("018b5846-c2d5-7b88-95f9-a7538a00e76b").?, public.getUuid(asset).?);

    const asset_obj = public.AssetCdb.readSubObj(cdb.readObj(asset).?, .Object);
    try std.testing.expect(asset_obj != null);

    try std.testing.expectEqual(uuid_private.fromStr("018b5846-c2d5-712f-bb12-9d9d15321ecb").?, public.getUuid(asset_obj.?).?);

    var out_buffer: [2048]u8 = @splat(0);
    var fixed_out_buffer_stream = std.Io.Writer.fixed(&out_buffer);
    try assetdb_private.writeCdbObjJson(
        std.testing.io,
        asset,
        &fixed_out_buffer_stream,
        asset,
        WriteBlobToNull,
        "",
        std.testing.allocator,
        null,
    );

    try std.testing.expectEqualStrings(input_json, std.mem.sliceTo(&out_buffer, 0));

    cdb.destroyObject(asset);
    cdb.destroyObject(ref_obj1);
    cdb.destroyObject(ref_obj2);
    cdb.destroyObject(prototype_obj);
    cdb.destroyObject(folder1);
}

test "asset: Should create asset" {
    try testInit();
    defer testDeinit();

    try assetdb_private.init(std.testing.io, std.testing.allocator);
    defer assetdb_private.deinit();

    const asset = public.createAsset("foo", public.getRootFolder(), null);
    try std.testing.expect(asset != null);

    // try db.gc(std.testing.allocator);
    // try cdb_test.expectGCStats(db, 5, 12);
}

test "asset: Should open asset root dir" {
    try testInit();
    defer testDeinit();

    try assetdb_private.init(std.testing.io, std.testing.allocator);
    defer assetdb_private.deinit();

    const db = assetdb_private.getDb();

    const asset_type_hash = try cetech1.cdb_types.addBigType(db, "ct_foo_asset", null);
    _ = asset_type_hash;

    try public.openAssetRootFolder("fixtures/test_asset", std.testing.allocator);

    var root_folder: ?cdb.ObjId = undefined;
    var core_folder: ?cdb.ObjId = undefined;
    var core_subfolder_folder: ?cdb.ObjId = undefined;

    // /
    {
        const foo_obj = public.getObjId(uuid_private.fromStr("018b5846-c2d5-712f-bb12-9d9d15321ecb").?);
        try std.testing.expect(foo_obj != null);

        var foo_obj_asset = cdb.getParent(foo_obj.?);
        try std.testing.expect(!foo_obj_asset.isEmpty());

        const expect_name = "foo";
        try std.testing.expectEqualStrings(
            expect_name,
            public.AssetCdb.readStr(cdb.readObj(foo_obj_asset).?, .Name).?,
        );

        const blob = cdb.readBlob(cdb.readObj(foo_obj.?).?, propIdx(cetech1.cdb_types.BigTypeProps.Blob));
        try std.testing.expectEqualSlices(u8, "hello blob", blob);

        root_folder = public.AssetCdb.readRef(cdb.readObj(foo_obj_asset).?, .Folder);
        try std.testing.expect(root_folder != null);
        try std.testing.expect(null == public.AssetCdb.readStr(cdb.readObj(public.getAssetForObj(root_folder.?).?).?, .Name));

        try std.testing.expectEqual(public.getAssetForObj(root_folder.?).?, public.getRootFolder());
        const set = try cdb.getReferencerSet(std.testing.allocator, root_folder.?);
        defer std.testing.allocator.free(set);
        // TODO: try std.testing.expectEqual(@as(usize, 3), set.len);

        var buff: [128]u8 = undefined;
        const sub_path = try assetdb_private.getFilePathForAsset(&buff, foo_obj_asset);
        try std.testing.expectEqualStrings("foo.ct_foo_asset", sub_path);

        // Check refenced objects
        const expect_name2 = "foo core";
        try std.testing.expectEqualStrings(expect_name2, FooAsset.readStr(
            cdb.readObj(FooAsset.readRef(cdb.readObj(foo_obj.?).?, .Reference).?).?,
            .Str,
        ).?);
    }

    const foo_core_obj = public.getObjId(uuid_private.fromStr("018b5c72-5350-7d06-b5ed-6fed2793fdd4").?);
    // /core
    {
        try std.testing.expect(foo_core_obj != null);

        var foo_core_obj_asset = cdb.getParent(foo_core_obj.?);
        try std.testing.expect(!foo_core_obj_asset.isEmpty());

        const expect_name = "foo_core";
        try std.testing.expectEqualStrings(
            expect_name,
            public.AssetCdb.readStr(cdb.readObj(foo_core_obj_asset).?, .Name).?,
        );

        const blob = cdb.readBlob(cdb.readObj(foo_core_obj.?).?, propIdx(cetech1.cdb_types.BigTypeProps.Blob));
        try std.testing.expectEqualSlices(u8, "hello core blob", blob);

        core_folder = public.AssetCdb.readRef(cdb.readObj(foo_core_obj_asset).?, .Folder);
        try std.testing.expect(core_folder != null);

        const expect_folder_name = "core";
        try std.testing.expectEqualStrings(
            expect_folder_name,
            public.AssetCdb.readStr(cdb.readObj(public.getAssetForObj(core_folder.?).?).?, .Name).?,
        );

        var buff: [128]u8 = undefined;
        const sub_path = try public.getFilePathForAsset(&buff, foo_core_obj_asset);

        if (builtin.os.tag == .windows) {
            try std.testing.expectEqualStrings("core\\foo_core.ct_foo_asset", sub_path);
        } else {
            try std.testing.expectEqualStrings("core/foo_core.ct_foo_asset", sub_path);
        }
    }

    // /core/core_subfolder
    {
        const foo_subcore_obj = public.getObjId(uuid_private.fromStr("018b5c74-06f7-79fd-a6ad-3678552795a1").?);
        try std.testing.expect(foo_subcore_obj != null);

        var foo_subcore_obj_asset = cdb.getParent(foo_subcore_obj.?);
        try std.testing.expect(!foo_subcore_obj_asset.isEmpty());

        const expect_name = "foo_subcore";
        try std.testing.expectEqualStrings(
            expect_name,
            public.AssetCdb.readStr(cdb.readObj(foo_subcore_obj_asset).?, .Name).?,
        );

        const blob = cdb.readBlob(cdb.readObj(foo_subcore_obj.?).?, propIdx(cetech1.cdb_types.BigTypeProps.Blob));
        try std.testing.expectEqualSlices(u8, "hello subcore blob", blob);

        const ref_set = cdb.readRefSet(cdb.readObj(foo_subcore_obj.?).?, propIdx(cetech1.cdb_types.BigTypeProps.ReferenceSet), std.testing.allocator);
        defer std.testing.allocator.free(ref_set.?);
        try std.testing.expect(ref_set != null);
        try std.testing.expectEqualSlices(
            cdb.ObjId,
            &[_]cdb.ObjId{foo_core_obj.?},
            ref_set.?,
        );

        const subobj = public.getObjId(uuid_private.fromStr("018b5c74-06f7-70bb-94e3-10a2a8619d31").?);
        const inisiated_subobj = public.getObjId(uuid_private.fromStr("7d0d10ce-128e-45ab-8c14-c5d486542d4f").?);
        const subobj_set = cdb.readRefSet(cdb.readObj(foo_subcore_obj.?).?, propIdx(cetech1.cdb_types.BigTypeProps.SubobjectSet), std.testing.allocator);
        defer std.testing.allocator.free(subobj_set.?);
        try std.testing.expect(subobj_set != null);
        try std.testing.expectEqualSlices(
            cdb.ObjId,
            &[_]cdb.ObjId{ subobj.?, inisiated_subobj.? },
            subobj_set.?,
        );

        core_subfolder_folder = public.AssetCdb.readRef(cdb.readObj(foo_subcore_obj_asset).?, .Folder);
        try std.testing.expect(core_subfolder_folder != null);

        const expect_folder_name = "core_subfolder";
        try std.testing.expectEqualStrings(
            expect_folder_name,
            public.AssetCdb.readStr(cdb.readObj(public.getAssetForObj(core_subfolder_folder.?).?).?, .Name).?,
        );

        var buff: [128]u8 = undefined;
        const sub_path = try public.getFilePathForAsset(&buff, foo_subcore_obj_asset);

        if (builtin.os.tag == .windows) {
            try std.testing.expectEqualStrings("core\\core_subfolder\\foo_subcore.ct_foo_asset", sub_path);
        } else {
            try std.testing.expectEqualStrings("core/core_subfolder/foo_subcore.ct_foo_asset", sub_path);
        }

        // Check refenced objects
        const expect_name2 = "foo core";
        try std.testing.expectEqualStrings(expect_name2, FooAsset.readStr(
            cdb.readObj(FooAsset.readRef(cdb.readObj(foo_subcore_obj.?).?, .Reference).?).?,
            .Str,
        ).?);
    }
}

test "asset: Should save asset root dir" {
    try testInit();
    defer testDeinit();

    const allocator = try tempalloc.create();
    defer tempalloc.destroy(allocator);

    try assetdb_private.init(std.testing.io, std.testing.allocator);
    defer assetdb_private.deinit();
    const db = assetdb_private.getDb();

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_dir_path = try tmp_dir.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(tmp_dir_path);

    const root_dir = try std.fs.path.join(std.testing.allocator, &.{tmp_dir_path});
    defer std.testing.allocator.free(root_dir);

    const asset_type_hash = try cetech1.cdb_types.addBigType(db, "ct_foo_asset", null);

    try public.openAssetRootFolder(root_dir, allocator);

    const asset_obj = try cdb.createObject(db, asset_type_hash);
    const asset = public.createAsset("foo", public.getRootFolder(), asset_obj).?;

    const asset_obj_w = cdb.writeObj(asset_obj).?;
    const asset_w = cdb.writeObj(asset).?;

    const blob = (try cdb.createBlob(asset_obj_w, propIdx(cetech1.cdb_types.BigTypeProps.Blob), "hello blob".len)).?;
    @memcpy(blob, "hello blob");

    try cdb.writeCommit(asset_w);
    try cdb.writeCommit(asset_obj_w);

    try std.testing.expect(public.isAssetModified(asset));
    try public.saveAllAssets(allocator);
    try std.testing.expect(!public.isAssetModified(asset));

    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "foo.ct_foo_asset.json" });
        defer std.testing.allocator.free(path);

        var f = std.Io.Dir.cwd().openFile(std.testing.io, path, .{});
        try std.testing.expect(f != std.Io.File.OpenError.FileNotFound);
        (try f).close(std.testing.io);
    }

    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "." ++ public.FolderCdb.name ++ ".json" });
        defer std.testing.allocator.free(path);

        var f = std.Io.Dir.cwd().openFile(std.testing.io, path, .{});
        try std.testing.expect(f != std.Io.File.OpenError.FileNotFound);
        (try f).close(std.testing.io);
    }

    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, public.CT_TEMP_FOLDER });
        defer std.testing.allocator.free(path);

        var d = std.Io.Dir.cwd().openDir(std.testing.io, path, .{});
        try std.testing.expect(d != std.Io.Dir.OpenError.FileNotFound);
        (try d).close(std.testing.io);
    }
}

test "asset: Should save modified asset" {
    try testInit();
    defer testDeinit();

    const tmpalloc = try tempalloc.create();
    defer tempalloc.destroy(tmpalloc);

    try assetdb_private.init(std.testing.io, std.testing.allocator);
    defer assetdb_private.deinit();
    const db = assetdb_private.getDb();

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_dir_path = try tmp_dir.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(tmp_dir_path);

    const root_dir = try std.fs.path.join(std.testing.allocator, &.{tmp_dir_path});
    defer std.testing.allocator.free(root_dir);

    const asset_type_hash = try cetech1.cdb_types.addBigType(db, "ct_foo_asset", null);

    try public.openAssetRootFolder(root_dir, tmpalloc);

    const asset_obj = try cdb.createObject(db, asset_type_hash);
    const asset = public.createAsset("foo", public.getRootFolder(), asset_obj).?;

    const asset_obj_w = cdb.writeObj(asset_obj).?;
    const asset_w = cdb.writeObj(asset).?;

    const blob = (try cdb.createBlob(asset_obj_w, propIdx(cetech1.cdb_types.BigTypeProps.Blob), "hello blob".len)).?;
    @memcpy(blob, "hello blob");

    try cdb.writeCommit(asset_w);
    try cdb.writeCommit(asset_obj_w);

    try std.testing.expect(public.isAssetModified(asset));
    try public.saveAllModifiedAssets(tmpalloc);
    try std.testing.expect(!public.isAssetModified(asset));

    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "foo.ct_foo_asset.json" });
        defer std.testing.allocator.free(path);

        var f = std.Io.Dir.cwd().openFile(std.testing.io, path, .{});
        try std.testing.expect(f != std.Io.File.OpenError.FileNotFound);
        (try f).close(std.testing.io);
    }

    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "." ++ public.FolderCdb.name ++ ".json" });
        defer std.testing.allocator.free(path);

        var f = std.Io.Dir.cwd().openFile(std.testing.io, path, .{});
        try std.testing.expect(f != std.Io.File.OpenError.FileNotFound);
        (try f).close(std.testing.io);
    }

    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, public.CT_TEMP_FOLDER });
        defer std.testing.allocator.free(path);

        var d = std.Io.Dir.cwd().openDir(std.testing.io, path, .{});
        try std.testing.expect(d != std.Io.Dir.OpenError.FileNotFound);
        (try d).close(std.testing.io);
    }
}

test "asset: Should rename asset" {
    try testInit();
    defer testDeinit();

    const allocator = try tempalloc.create();
    defer tempalloc.destroy(allocator);

    try assetdb_private.init(std.testing.io, std.testing.allocator);
    defer assetdb_private.deinit();
    const db = assetdb_private.getDb();

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();
    const tmp_dir_path = try tmp_dir.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(tmp_dir_path);

    const root_dir = try std.fs.path.join(std.testing.allocator, &.{tmp_dir_path});
    defer std.testing.allocator.free(root_dir);

    const asset_type_hash = try cetech1.cdb_types.addBigType(db, "ct_foo_asset", null);

    try public.openAssetRootFolder(root_dir, allocator);

    const asset_obj = try cdb.createObject(db, asset_type_hash);
    const asset = public.createAsset("foo", public.getRootFolder(), asset_obj).?;

    const asset_obj_w = cdb.writeObj(asset_obj).?;
    const asset_w = cdb.writeObj(asset).?;

    const blob = (try cdb.createBlob(asset_obj_w, propIdx(cetech1.cdb_types.BigTypeProps.Blob), "hello blob".len)).?;
    @memcpy(blob, "hello blob");

    try cdb.writeCommit(asset_w);
    try cdb.writeCommit(asset_obj_w);

    try std.testing.expect(public.isAssetModified(asset));
    try public.saveAllAssets(allocator);
    try std.testing.expect(!public.isAssetModified(asset));

    // Change name to new name
    {
        const w = cdb.writeObj(asset).?;
        try cetech1.assetdb.AssetCdb.setStr(w, .Name, "bar");
        try cdb.writeCommit(w);
    }

    // Save all assets
    try std.testing.expect(public.isAssetModified(asset));
    try public.saveAllModifiedAssets(allocator);
    try std.testing.expect(!public.isAssetModified(asset));

    // Original asset does not exist
    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "foo.ct_foo_asset.json" });
        defer std.testing.allocator.free(path);

        const f = std.Io.Dir.cwd().openFile(std.testing.io, path, .{});
        try std.testing.expect(f == std.Io.File.OpenError.FileNotFound);
    }

    // Original asset blob dir does not exist
    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "foo.ct_blob" });
        defer std.testing.allocator.free(path);

        const d = std.Io.Dir.cwd().openDir(std.testing.io, path, .{});
        try std.testing.expect(d == std.Io.Dir.OpenError.FileNotFound);
    }

    // Asset with new name exist
    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "bar.ct_foo_asset.json" });
        defer std.testing.allocator.free(path);

        var f = std.Io.Dir.cwd().openFile(std.testing.io, path, .{});
        try std.testing.expect(f != std.Io.File.OpenError.FileNotFound);
        (try f).close(std.testing.io);
    }

    // Asset blob for new named asset exist
    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "bar.ct_blob" });
        defer std.testing.allocator.free(path);

        var d = std.Io.Dir.cwd().openDir(std.testing.io, path, .{});
        try std.testing.expect(d != std.Io.Dir.OpenError.FileNotFound);
        (try d).close(std.testing.io);
    }
}

test "asset: Should move asset" {
    try testInit();
    defer testDeinit();

    const allocator = try tempalloc.create();
    defer tempalloc.destroy(allocator);

    try assetdb_private.init(std.testing.io, std.testing.allocator);
    defer assetdb_private.deinit();
    const db = assetdb_private.getDb();

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_dir_path = try tmp_dir.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(tmp_dir_path);

    const root_dir = try std.fs.path.join(std.testing.allocator, &.{tmp_dir_path});
    defer std.testing.allocator.free(root_dir);

    const asset_type_hash = try cetech1.cdb_types.addBigType(db, "ct_foo_asset", null);

    try public.openAssetRootFolder(root_dir, allocator);

    const asset_obj = try cdb.createObject(db, asset_type_hash);
    const asset = public.createAsset("foo", public.getRootFolder(), asset_obj).?;

    const asset_obj_w = cdb.writeObj(asset_obj).?;
    const asset_w = cdb.writeObj(asset).?;

    const blob = (try cdb.createBlob(asset_obj_w, propIdx(cetech1.cdb_types.BigTypeProps.Blob), "hello blob".len)).?;
    @memcpy(blob, "hello blob");

    try cdb.writeCommit(asset_w);
    try cdb.writeCommit(asset_obj_w);

    const bar_folder = try public.createNewFolder(db, public.getRootFolder(), "bar");

    try std.testing.expect(public.isAssetModified(asset));
    try public.saveAllAssets(allocator);
    try std.testing.expect(!public.isAssetModified(asset));

    // Change folder
    {
        const w = cdb.writeObj(asset).?;
        try cetech1.assetdb.AssetCdb.setRef(w, .Folder, bar_folder);
        try cdb.writeCommit(w);
    }

    // Save all assets
    try std.testing.expect(public.isAssetModified(asset));
    try public.saveAllModifiedAssets(allocator);
    try std.testing.expect(!public.isAssetModified(asset));

    // Original asset does not exist
    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "foo.ct_foo_asset" });
        defer std.testing.allocator.free(path);

        const f = std.Io.Dir.cwd().openFile(std.testing.io, path, .{});
        try std.testing.expect(f == std.Io.File.OpenError.FileNotFound);
    }

    // Original asset blob dir does not exist
    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "foo.ct_blob" });
        defer std.testing.allocator.free(path);

        const d = std.Io.Dir.cwd().openDir(std.testing.io, path, .{});
        try std.testing.expect(d == std.Io.Dir.OpenError.FileNotFound);
    }

    // Asset with new folder exist
    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "bar", "foo.ct_foo_asset.json" });
        defer std.testing.allocator.free(path);

        var f = std.Io.Dir.cwd().openFile(std.testing.io, path, .{});
        try std.testing.expect(f != std.Io.File.OpenError.FileNotFound);
        (try f).close(std.testing.io);
    }

    // Asset blob for new folder exist
    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "bar", "foo.ct_blob" });
        defer std.testing.allocator.free(path);

        var d = std.Io.Dir.cwd().openDir(std.testing.io, path, .{});
        try std.testing.expect(d != std.Io.Dir.OpenError.FileNotFound);
        (try d).close(std.testing.io);
    }
}

test "asset: Should delete asset" {
    try testInit();
    defer testDeinit();

    const allocator = try tempalloc.create();
    defer tempalloc.destroy(allocator);

    try assetdb_private.init(std.testing.io, std.testing.allocator);
    defer assetdb_private.deinit();
    const db = assetdb_private.getDb();

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_dir_path = try tmp_dir.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(tmp_dir_path);

    const root_dir = try std.fs.path.join(std.testing.allocator, &.{tmp_dir_path});
    defer std.testing.allocator.free(root_dir);

    const asset_type_hash = try cetech1.cdb_types.addBigType(db, "ct_foo_asset", null);

    try public.openAssetRootFolder(root_dir, allocator);

    const asset_obj = try cdb.createObject(db, asset_type_hash);
    const asset = public.createAsset("foo", public.getRootFolder(), asset_obj).?;

    const asset_obj_w = cdb.writeObj(asset_obj).?;
    const asset_w = cdb.writeObj(asset).?;

    const blob = (try cdb.createBlob(asset_obj_w, propIdx(cetech1.cdb_types.BigTypeProps.Blob), "hello blob".len)).?;
    @memcpy(blob, "hello blob");

    try cdb.writeCommit(asset_w);
    try cdb.writeCommit(asset_obj_w);

    try std.testing.expect(public.isAssetModified(asset));
    try public.saveAllAssets(allocator);
    try std.testing.expect(!public.isAssetModified(asset));

    try public.deleteAsset(asset);

    // Save all assets
    try std.testing.expect(public.isToDeleted(asset));
    try public.saveAllModifiedAssets(allocator);
    try std.testing.expect(!public.isToDeleted(asset));

    // Original asset does not exist
    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "foo.ct_foo_asset" });
        defer std.testing.allocator.free(path);

        const f = std.Io.Dir.cwd().openFile(std.testing.io, path, .{});
        try std.testing.expect(f == std.Io.File.OpenError.FileNotFound);
    }

    // Original asset blob dir does not exist
    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "foo.ct_blob" });
        defer std.testing.allocator.free(path);

        const d = std.Io.Dir.cwd().openDir(std.testing.io, path, .{});
        try std.testing.expect(d == std.Io.Dir.OpenError.FileNotFound);
    }
}

test "asset: Should revive asset" {
    try testInit();
    defer testDeinit();

    const allocator = try tempalloc.create();
    defer tempalloc.destroy(allocator);

    try assetdb_private.init(std.testing.io, std.testing.allocator);
    defer assetdb_private.deinit();
    const db = assetdb_private.getDb();

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_dir_path = try tmp_dir.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(tmp_dir_path);

    const root_dir = try std.fs.path.join(std.testing.allocator, &.{tmp_dir_path});
    defer std.testing.allocator.free(root_dir);

    const asset_type_hash = try cetech1.cdb_types.addBigType(db, "ct_foo_asset", null);

    try public.openAssetRootFolder(root_dir, allocator);

    const asset_obj = try cdb.createObject(db, asset_type_hash);
    const asset = public.createAsset("foo", public.getRootFolder(), asset_obj).?;

    const asset_obj_w = cdb.writeObj(asset_obj).?;
    const asset_w = cdb.writeObj(asset).?;

    const blob = (try cdb.createBlob(asset_obj_w, propIdx(cetech1.cdb_types.BigTypeProps.Blob), "hello blob".len)).?;
    @memcpy(blob, "hello blob");

    try cdb.writeCommit(asset_w);
    try cdb.writeCommit(asset_obj_w);

    try std.testing.expect(public.isAssetModified(asset));
    try public.saveAllAssets(allocator);
    try std.testing.expect(!public.isAssetModified(asset));

    try public.deleteAsset(asset);
    public.reviveDeleted(asset);

    // Save all assets
    try std.testing.expect(!public.isToDeleted(asset));
    try public.saveAllModifiedAssets(allocator);
    try std.testing.expect(!public.isToDeleted(asset));

    // Original asset does not exist
    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "foo.ct_foo_asset.json" });
        defer std.testing.allocator.free(path);

        var f = std.Io.Dir.cwd().openFile(std.testing.io, path, .{});
        try std.testing.expect(f != std.Io.File.OpenError.FileNotFound);
        (try f).close(std.testing.io);
    }

    // Original asset blob dir does not exist
    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "foo.ct_blob" });
        defer std.testing.allocator.free(path);

        var d = std.Io.Dir.cwd().openDir(std.testing.io, path, .{});
        try std.testing.expect(d != std.Io.Dir.OpenError.FileNotFound);
        (try d).close(std.testing.io);
    }
}

test "asset: Should create asset without asset root" {
    try testInit();
    defer testDeinit();

    const allocator = try tempalloc.create();
    defer tempalloc.destroy(allocator);

    try assetdb_private.init(std.testing.io, std.testing.allocator);
    defer assetdb_private.deinit();
    const db = assetdb_private.getDb();

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_dir_path = try tmp_dir.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(tmp_dir_path);

    const root_dir = try std.fs.path.join(std.testing.allocator, &.{tmp_dir_path});
    defer std.testing.allocator.free(root_dir);

    const asset_type_hash = try cetech1.cdb_types.addBigType(db, "ct_foo_asset", null);

    const asset_obj = try cdb.createObject(db, asset_type_hash);
    const asset = public.createAsset("foo", public.getRootFolder(), asset_obj).?;

    const asset_obj_w = cdb.writeObj(asset_obj).?;
    const asset_w = cdb.writeObj(asset).?;

    const blob = (try cdb.createBlob(asset_obj_w, propIdx(cetech1.cdb_types.BigTypeProps.Blob), "hello blob".len)).?;
    @memcpy(blob, "hello blob");

    try cdb.writeCommit(asset_w);
    try cdb.writeCommit(asset_obj_w);

    try std.testing.expect(public.isAssetModified(asset));
    try public.saveAsAllAssets(allocator, root_dir);
    try std.testing.expect(!public.isAssetModified(asset));

    // Original asset does not exist
    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "foo.ct_foo_asset.json" });
        defer std.testing.allocator.free(path);

        var f = std.Io.Dir.cwd().openFile(std.testing.io, path, .{});
        try std.testing.expect(f != std.Io.File.OpenError.FileNotFound);
        (try f).close(std.testing.io);
    }

    // Original asset blob dir does not exist
    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "foo.ct_blob" });
        defer std.testing.allocator.free(path);

        var d = std.Io.Dir.cwd().openDir(std.testing.io, path, .{});
        try std.testing.expect(d != std.Io.Dir.OpenError.FileNotFound);
        (try d).close(std.testing.io);
    }
}

test "asset: Should create folder without asset root" {
    try testInit();
    defer testDeinit();

    const allocator = try tempalloc.create();
    defer tempalloc.destroy(allocator);

    try assetdb_private.init(std.testing.io, std.testing.allocator);
    defer assetdb_private.deinit();
    const db = assetdb_private.getDb();

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_dir_path = try tmp_dir.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(tmp_dir_path);

    const root_dir = try std.fs.path.join(std.testing.allocator, &.{tmp_dir_path});
    defer std.testing.allocator.free(root_dir);

    const foo_folder = try public.createNewFolder(db, public.getRootFolder(), "foo");
    const foo_folder_asset = public.getAssetForObj(foo_folder).?;

    const asset_type_hash = try cetech1.cdb_types.addBigType(db, "ct_foo_asset", null);

    const asset_obj = try cdb.createObject(db, asset_type_hash);
    const asset = public.createAsset("foo", foo_folder_asset, asset_obj).?;

    const asset_obj_w = cdb.writeObj(asset_obj).?;
    const asset_w = cdb.writeObj(asset).?;

    const blob = (try cdb.createBlob(asset_obj_w, propIdx(cetech1.cdb_types.BigTypeProps.Blob), "hello blob".len)).?;
    @memcpy(blob, "hello blob");

    try cdb.writeCommit(asset_w);
    try cdb.writeCommit(asset_obj_w);

    try std.testing.expect(public.isAssetModified(asset));
    try public.saveAsAllAssets(allocator, root_dir);
    try std.testing.expect(!public.isAssetModified(asset));

    // Original asset does not exist
    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "foo", "foo.ct_foo_asset.json" });
        defer std.testing.allocator.free(path);

        var f = std.Io.Dir.cwd().openFile(std.testing.io, path, .{});
        try std.testing.expect(f != std.Io.File.OpenError.FileNotFound);
        (try f).close(std.testing.io);
    }

    // Original asset blob dir does not exist
    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "foo", "foo.ct_blob" });
        defer std.testing.allocator.free(path);

        var d = std.Io.Dir.cwd().openDir(std.testing.io, path, .{});
        try std.testing.expect(d != std.Io.Dir.OpenError.FileNotFound);
        (try d).close(std.testing.io);
    }
}

test "asset: Should rename folder" {
    try testInit();
    defer testDeinit();

    const allocator = try tempalloc.create();
    defer tempalloc.destroy(allocator);

    try assetdb_private.init(std.testing.io, std.testing.allocator);
    defer assetdb_private.deinit();
    const db = assetdb_private.getDb();

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_dir_path = try tmp_dir.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(tmp_dir_path);

    const root_dir = try std.fs.path.join(std.testing.allocator, &.{tmp_dir_path});
    defer std.testing.allocator.free(root_dir);

    const asset_type_hash = try cetech1.cdb_types.addBigType(db, "ct_foo_asset", null);

    try public.openAssetRootFolder(root_dir, allocator);

    const foo_folder = try public.createNewFolder(db, public.getRootFolder(), "foo");
    const foo_folder_asset = public.getAssetForObj(foo_folder).?;

    const asset_obj = try cdb.createObject(db, asset_type_hash);
    const asset = public.createAsset("foo", foo_folder_asset, asset_obj).?;

    const asset_obj_w = cdb.writeObj(asset_obj).?;
    const asset_w = cdb.writeObj(asset).?;

    const blob = (try cdb.createBlob(asset_obj_w, propIdx(cetech1.cdb_types.BigTypeProps.Blob), "hello blob".len)).?;
    @memcpy(blob, "hello blob");

    try cdb.writeCommit(asset_w);
    try cdb.writeCommit(asset_obj_w);

    try std.testing.expect(public.isAssetModified(asset));
    try public.saveAllAssets(allocator);
    try std.testing.expect(!public.isAssetModified(asset));

    // Change folder
    {
        const w = cdb.writeObj(foo_folder_asset).?;
        try cetech1.assetdb.AssetCdb.setStr(w, .Name, "bar");
        try cdb.writeCommit(w);
    }

    // Save all assets
    try std.testing.expect(public.isAssetModified(foo_folder_asset));
    try public.saveAllModifiedAssets(allocator);
    try std.testing.expect(!public.isAssetModified(foo_folder_asset));

    // Original asset does not exist
    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "foo", "foo.ct_foo_asset.json" });
        defer std.testing.allocator.free(path);

        const f = std.Io.Dir.cwd().openFile(std.testing.io, path, .{});
        try std.testing.expect(f == std.Io.File.OpenError.FileNotFound);
    }

    // Original asset blob dir does not exist
    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "foo", "foo.ct_blob" });
        defer std.testing.allocator.free(path);

        const d = std.Io.Dir.cwd().openDir(std.testing.io, path, .{});
        try std.testing.expect(d == std.Io.Dir.OpenError.FileNotFound);
    }

    // Asset with new folder exist
    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "bar", "foo.ct_foo_asset.json" });
        defer std.testing.allocator.free(path);

        var f = std.Io.Dir.cwd().openFile(std.testing.io, path, .{});
        try std.testing.expect(f != std.Io.File.OpenError.FileNotFound);
        (try f).close(std.testing.io);
    }

    // Asset blob for new folder exist
    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "bar", "foo.ct_blob" });
        defer std.testing.allocator.free(path);

        var d = std.Io.Dir.cwd().openDir(std.testing.io, path, .{});
        try std.testing.expect(d != std.Io.Dir.OpenError.FileNotFound);
        (try d).close(std.testing.io);
    }
}

test "asset: Should move folder" {
    try testInit();
    defer testDeinit();

    const allocator = try tempalloc.create();
    defer tempalloc.destroy(allocator);

    try assetdb_private.init(std.testing.io, std.testing.allocator);
    defer assetdb_private.deinit();
    const db = assetdb_private.getDb();

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_dir_path = try tmp_dir.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(tmp_dir_path);

    const root_dir = try std.fs.path.join(std.testing.allocator, &.{tmp_dir_path});
    defer std.testing.allocator.free(root_dir);

    const asset_type_hash = try cetech1.cdb_types.addBigType(db, "ct_foo_asset", null);

    try public.openAssetRootFolder(root_dir, allocator);

    const foo_folder = try public.createNewFolder(db, public.getRootFolder(), "foo");
    const foo_folder_asset = public.getAssetForObj(foo_folder).?;

    const bar_folder = try public.createNewFolder(db, public.getRootFolder(), "bar");

    const asset_obj = try cdb.createObject(db, asset_type_hash);
    const asset = public.createAsset("foo", foo_folder_asset, asset_obj).?;

    const asset_obj_w = cdb.writeObj(asset_obj).?;
    const asset_w = cdb.writeObj(asset).?;

    const blob = (try cdb.createBlob(asset_obj_w, propIdx(cetech1.cdb_types.BigTypeProps.Blob), "hello blob".len)).?;
    @memcpy(blob, "hello blob");

    try cdb.writeCommit(asset_w);
    try cdb.writeCommit(asset_obj_w);

    try std.testing.expect(public.isAssetModified(asset));
    try public.saveAllAssets(allocator);
    try std.testing.expect(!public.isAssetModified(asset));

    // Change folder
    {
        const w = cdb.writeObj(foo_folder_asset).?;
        try cetech1.assetdb.AssetCdb.setRef(w, .Folder, bar_folder);
        try cdb.writeCommit(w);
    }

    // Save all assets
    try std.testing.expect(public.isAssetModified(foo_folder_asset));
    try public.saveAllModifiedAssets(allocator);
    try std.testing.expect(!public.isAssetModified(foo_folder_asset));

    // Original asset does not exist
    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "foo", "foo.ct_foo_asset" });
        defer std.testing.allocator.free(path);

        const f = std.Io.Dir.cwd().openFile(std.testing.io, path, .{});
        try std.testing.expect(f == std.Io.File.OpenError.FileNotFound);
    }

    // Original asset blob dir does not exist
    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "foo", "foo.ct_blob" });
        defer std.testing.allocator.free(path);

        const d = std.Io.Dir.cwd().openDir(std.testing.io, path, .{});
        try std.testing.expect(d == std.Io.Dir.OpenError.FileNotFound);
    }

    // Asset with new folder exist
    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "bar", "foo", "foo.ct_foo_asset.json" });
        defer std.testing.allocator.free(path);

        var f = std.Io.Dir.cwd().openFile(std.testing.io, path, .{});
        try std.testing.expect(f != std.Io.File.OpenError.FileNotFound);
        (try f).close(std.testing.io);
    }

    // Asset blob for new folder exist
    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "bar", "foo", "foo.ct_blob" });
        defer std.testing.allocator.free(path);

        var d = std.Io.Dir.cwd().openDir(std.testing.io, path, .{});
        try std.testing.expect(d != std.Io.Dir.OpenError.FileNotFound);
        (try d).close(std.testing.io);
    }
}

test "asset: Should delete folder" {
    try testInit();
    defer testDeinit();

    const allocator = try tempalloc.create();
    defer tempalloc.destroy(allocator);

    try assetdb_private.init(std.testing.io, std.testing.allocator);
    defer assetdb_private.deinit();
    const db = assetdb_private.getDb();

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_dir_path = try tmp_dir.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(tmp_dir_path);

    const root_dir = try std.fs.path.join(std.testing.allocator, &.{tmp_dir_path});
    defer std.testing.allocator.free(root_dir);

    const asset_type_hash = try cetech1.cdb_types.addBigType(db, "ct_foo_asset", null);

    try public.openAssetRootFolder(root_dir, allocator);

    const foo_folder = try public.createNewFolder(db, public.getRootFolder(), "foo");
    const foo_folder_asset = public.getAssetForObj(foo_folder).?;

    const asset_obj = try cdb.createObject(db, asset_type_hash);
    const asset = public.createAsset("foo", foo_folder_asset, asset_obj).?;

    const asset_obj_w = cdb.writeObj(asset_obj).?;
    const asset_w = cdb.writeObj(asset).?;

    const blob = (try cdb.createBlob(asset_obj_w, propIdx(cetech1.cdb_types.BigTypeProps.Blob), "hello blob".len)).?;
    @memcpy(blob, "hello blob");

    try cdb.writeCommit(asset_w);
    try cdb.writeCommit(asset_obj_w);

    try std.testing.expect(public.isAssetModified(asset));
    try public.saveAllAssets(allocator);
    try std.testing.expect(!public.isAssetModified(asset));

    // Change folder
    //TODO
    // {
    //     const w = cdb.writeObj(foo_folder_asset).?;
    //     try cetech1.assetdb.Asset.setStr(db, w, .Name, "bar");
    //     try cdb.writeCommit(w);
    // }

    // And delete folder
    try public.deleteFolder(foo_folder_asset);

    // Save all assets
    try std.testing.expect(public.isToDeleted(foo_folder_asset));
    try public.saveAllModifiedAssets(allocator);
    try std.testing.expect(!public.isToDeleted(foo_folder_asset));

    // Original dir does not exist
    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "foo" });
        defer std.testing.allocator.free(path);

        const d = std.Io.Dir.cwd().openDir(std.testing.io, path, .{});
        try std.testing.expect(d == std.Io.Dir.OpenError.FileNotFound);
    }

    // Original asset does not exist
    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "foo", "foo.ct_foo_asset" });
        defer std.testing.allocator.free(path);

        const f = std.Io.Dir.cwd().openFile(std.testing.io, path, .{});
        try std.testing.expect(f == std.Io.File.OpenError.FileNotFound);
    }

    // Original asset blob dir does not exist
    {
        const path = try std.fs.path.join(std.testing.allocator, &.{ root_dir, "foo", "foo.ct_blob" });
        defer std.testing.allocator.free(path);

        const d = std.Io.Dir.cwd().openDir(std.testing.io, path, .{});
        try std.testing.expect(d == std.Io.Dir.OpenError.FileNotFound);
    }
}

test "asset: Should crate new asset from prototype" {
    try testInit();
    defer testDeinit();

    const allocator = try tempalloc.create();
    defer tempalloc.destroy(allocator);

    try assetdb_private.init(std.testing.io, std.testing.allocator);
    defer assetdb_private.deinit();
    const db = assetdb_private.getDb();

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_dir_path = try tmp_dir.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(tmp_dir_path);

    const root_dir = try std.fs.path.join(std.testing.allocator, &.{tmp_dir_path});
    defer std.testing.allocator.free(root_dir);

    const asset_type_hash = try cetech1.cdb_types.addBigType(db, "ct_foo_asset", null);

    try public.openAssetRootFolder(root_dir, allocator);

    const asset_obj = try cdb.createObject(db, asset_type_hash);
    const asset = public.createAsset("foo", public.getRootFolder(), asset_obj).?;

    const asset_obj_w = cdb.writeObj(asset_obj).?;
    const asset_w = cdb.writeObj(asset).?;

    const blob = (try cdb.createBlob(asset_obj_w, propIdx(cetech1.cdb_types.BigTypeProps.Blob), "hello blob".len)).?;
    @memcpy(blob, "hello blob");

    try cdb.writeCommit(asset_w);
    try cdb.writeCommit(asset_obj_w);

    const new_object_asset = try public.createNewAssetFromPrototype(asset);
    const new_object_asset_obj = public.getObjForAsset(new_object_asset).?;
    const new_object_asset_obj_r = FooAsset.read(new_object_asset_obj).?;

    const prototype = cdb.getPrototype(new_object_asset_obj_r);
    try std.testing.expectEqual(asset_obj, prototype);
}

test "asset: Should clone new asset from" {
    try testInit();
    defer testDeinit();

    const allocator = try tempalloc.create();
    defer tempalloc.destroy(allocator);

    try assetdb_private.init(std.testing.io, std.testing.allocator);
    defer assetdb_private.deinit();
    const db = assetdb_private.getDb();

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_dir_path = try tmp_dir.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(tmp_dir_path);

    const root_dir = try std.fs.path.join(std.testing.allocator, &.{tmp_dir_path});
    defer std.testing.allocator.free(root_dir);

    const asset_type_hash = try cetech1.cdb_types.addBigType(db, "ct_foo_asset", null);

    try public.openAssetRootFolder(root_dir, allocator);

    const asset_obj = try cdb.createObject(db, asset_type_hash);
    const asset = public.createAsset("foo", public.getRootFolder(), asset_obj).?;

    const asset_obj_w = cdb.writeObj(asset_obj).?;
    const asset_w = cdb.writeObj(asset).?;

    const blob = (try cdb.createBlob(asset_obj_w, propIdx(cetech1.cdb_types.BigTypeProps.Blob), "hello blob".len)).?;
    @memcpy(blob, "hello blob");

    try cdb.writeCommit(asset_w);
    try cdb.writeCommit(asset_obj_w);

    _ = try public.cloneNewAssetFrom(asset);
}

test "asset: Should get new valid name for asset" {
    try testInit();
    defer testDeinit();

    const allocator = try tempalloc.create();
    defer tempalloc.destroy(allocator);

    try assetdb_private.init(std.testing.io, std.testing.allocator);
    defer assetdb_private.deinit();
    const db = assetdb_private.getDb();

    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_dir_path = try tmp_dir.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(tmp_dir_path);

    const root_dir = try std.fs.path.join(std.testing.allocator, &.{tmp_dir_path});
    defer std.testing.allocator.free(root_dir);

    const asset_type_hash = try cetech1.cdb_types.addBigType(db, "ct_foo_asset", null);

    const foo_folder = try public.createNewFolder(db, public.getRootFolder(), "foo");
    const foo_folder_asset = public.getAssetForObj(foo_folder).?;

    const asset_obj = try cdb.createObject(db, asset_type_hash);
    const asset = public.createAsset("foo", foo_folder_asset, asset_obj).?;

    const asset_obj_w = cdb.writeObj(asset_obj).?;
    const asset_w = cdb.writeObj(asset).?;

    const blob = (try cdb.createBlob(asset_obj_w, propIdx(cetech1.cdb_types.BigTypeProps.Blob), "hello blob".len)).?;
    @memcpy(blob, "hello blob");

    try cdb.writeCommit(asset_w);
    try cdb.writeCommit(asset_obj_w);

    var buff: [256:0]u8 = undefined;
    const name = try public.buffGetValidName(
        std.testing.allocator,
        &buff,
        foo_folder_asset,
        cdb.getTypeIdx(db, cetech1.assetdb.FooAsset.type_hash).?,
        "foo",
    );

    try std.testing.expectEqualStrings("foo2", name);
}
