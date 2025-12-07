const builtin = @import("builtin");
const std = @import("std");

const cetech1 = @import("cetech1");
const public = cetech1.cdb;
const cdb_private = @import("cdb.zig");

const StrId32 = cetech1.StrId32;
const strId32 = cetech1.strId32;

const cdb = cetech1.cdb;

const log = @import("log.zig");
const apidb = @import("apidb.zig");
const profiler = @import("profiler.zig");
const task = @import("task.zig");
const uuid = @import("uuid.zig");
const metrics = @import("metrics.zig");

var _cdb = &cdb_private.api;

pub fn testInit() !void {
    try task.init(std.testing.allocator);
    try apidb.init(std.testing.allocator);
    try metrics.init(std.testing.allocator);
    try cdb_private.init(std.testing.allocator);
    try task.start(null);
}

pub fn testDeinit() void {
    cdb_private.deinit();
    apidb.deinit();
    task.stop();
    task.deinit();
    metrics.deinit();
}

pub fn expectGCStats(db: cdb.DbId, alocated_objids: u32, free_object: u32) !void {
    const true_db = cdb_private.toDbFromDbT(db);
    try std.testing.expectEqual(alocated_objids, true_db.objids_alocated);
    try std.testing.expectEqual(@as(u32, free_object), true_db.free_objects);
}

test "cdb: Should create cdb DB" {
    try testInit();
    defer testDeinit();

    const db = try cdb_private.api.createDb("Test");
    defer cdb_private.api.destroyDb(db);
}

test "cdb: Should register type" {
    try testInit();
    defer testDeinit();

    const db = try cdb_private.api.createDb("Test");
    defer cdb_private.api.destroyDb(db);

    const type_hash = try _cdb.addType(
        db,
        "foo",
        &.{},
    );

    try std.testing.expectEqual(_cdb.getTypeIdx(db, strId32("foo")).?, type_hash);

    const props = _cdb.getTypePropDef(db, type_hash);
    try std.testing.expect(props != null);

    const expected_num: u32 = 0;
    _ = expected_num;
    try std.testing.expectEqual(@as(usize, 0), props.?.len);
}

test "cdb: Should register create types handler " {
    try testInit();
    defer testDeinit();

    var create_cdb_types_i = public.CreateTypesI.implement(struct {
        pub fn createTypes(db: cdb.DbId) !void {
            const type_hash = _cdb.addType(
                db,
                "foo",
                &.{
                    .{ .prop_idx = 0, .name = "prop1", .type = public.PropType.F32 },
                    .{ .prop_idx = 1, .name = "prop2", .type = public.PropType.F64 },
                },
            ) catch unreachable;
            _ = type_hash;
        }
    });

    try apidb.api.implOrRemove(.foo, public.CreateTypesI, &create_cdb_types_i, true);

    const db = try cdb_private.api.createDb("Test");
    defer cdb_private.api.destroyDb(db);

    const type_hash = strId32("foo");

    const props = _cdb.getTypePropDef(db, _cdb.getTypeIdx(db, type_hash).?);
    try std.testing.expect(props != null);
    try std.testing.expectEqual(@as(usize, 2), props.?.len);
}

test "cdb: Should register aspect" {
    try testInit();
    defer testDeinit();

    const FooAspect = struct {
        pub const c_name = "foo_aspect";
        pub const name_hash = cetech1.strId32(c_name);

        const Self = @This();
        barFn: *const fn (db_: public.DbId) void,

        pub fn barImpl(db_: public.DbId) void {
            _ = db_;
        }

        pub fn bar(self: *Self, db_: public.DbId) void {
            return self.barFn(db_);
        }
    };

    var foo_aspect = FooAspect{ .barFn = &FooAspect.barImpl };

    var create_cdb_types_i = public.CreateTypesI.implement(struct {
        pub fn createTypes(db: cdb.DbId) !void {
            const type_hash = _cdb.addType(
                db,
                "foo",
                &.{
                    .{ .prop_idx = 0, .name = "prop1", .type = public.PropType.F32 },
                    .{ .prop_idx = 1, .name = "prop2", .type = public.PropType.F32 },
                },
            ) catch unreachable;
            _ = type_hash;
        }
    });

    try apidb.api.implOrRemove(.foo, public.CreateTypesI, &create_cdb_types_i, true);

    const db = try cdb_private.api.createDb("Test");
    defer cdb_private.api.destroyDb(db);

    const type_hash = strId32("foo");
    const type_idx = _cdb.getTypeIdx(db, type_hash).?;

    var aspect = _cdb.getAspect(FooAspect, db, _cdb.getTypeIdx(db, type_hash).?);
    try std.testing.expect(aspect == null);

    try _cdb.addAspect(FooAspect, db, type_idx, &foo_aspect);

    aspect = _cdb.getAspect(FooAspect, db, type_idx);
    try std.testing.expect(aspect != null);
    try std.testing.expectEqual(&foo_aspect, aspect.?);

    aspect.?.bar(db);
}

test "cdb: Should register property aspect" {
    try testInit();
    defer testDeinit();

    const FooAspect = struct {
        pub const c_name = "foo_aspect";
        pub const name_hash = cetech1.strId32(c_name);

        const Self = @This();
        barFn: *const fn (db_: public.DbId) void,

        pub fn barImpl(db_: public.DbId) void {
            _ = db_; // autofix

        }

        pub fn bar(self: *Self, db_: public.DbId) void {
            return self.barFn(db_);
        }
    };

    var foo_aspect = FooAspect{ .barFn = &FooAspect.barImpl };

    var create_cdb_types_i = public.CreateTypesI.implement(struct {
        pub fn createTypes(db: cdb.DbId) !void {
            const type_hash = _cdb.addType(
                db,
                "foo",
                &.{
                    .{ .prop_idx = 0, .name = "prop1", .type = public.PropType.F32 },
                    .{ .prop_idx = 1, .name = "prop2", .type = public.PropType.F32 },
                },
            ) catch unreachable;
            _ = type_hash;
        }
    });
    try apidb.api.implOrRemove(.foo, public.CreateTypesI, &create_cdb_types_i, true);

    const db = try cdb_private.api.createDb("Test");
    defer cdb_private.api.destroyDb(db);

    const type_hash = strId32("foo");
    const type_idx = _cdb.getTypeIdx(db, type_hash).?;

    var aspect = _cdb.getPropertyAspect(FooAspect, db, type_idx, 0);
    try std.testing.expect(aspect == null);
    aspect = _cdb.getPropertyAspect(FooAspect, db, type_idx, 1);
    try std.testing.expect(aspect == null);

    try _cdb.addPropertyAspect(FooAspect, db, type_idx, 1, &foo_aspect);

    aspect = _cdb.getPropertyAspect(FooAspect, db, type_idx, 0);
    try std.testing.expect(aspect == null);

    aspect = _cdb.getPropertyAspect(FooAspect, db, type_idx, 1);
    try std.testing.expect(aspect != null);
    try std.testing.expectEqual(&foo_aspect, aspect.?);

    aspect.?.bar(db);
}

test "cdb: Should create object from type" {
    try testInit();
    defer testDeinit();

    const db = try cdb_private.api.createDb("Test");
    defer cdb_private.api.destroyDb(db);

    const type_hash = try _cdb.addType(
        db,
        "foo",
        &.{},
    );

    const obj1 = try _cdb.createObject(db, type_hash);
    const obj2 = try _cdb.createObject(db, type_hash);

    try std.testing.expect(_cdb.isAlive(obj1));
    try std.testing.expect(_cdb.isAlive(obj2));

    try std.testing.expectEqual(type_hash.idx, obj1.type_idx.idx);
    try std.testing.expectEqual(type_hash.idx, obj2.type_idx.idx);
    try std.testing.expect(obj1.id != obj2.id);

    _cdb.destroyObject(obj1);
    _cdb.destroyObject(obj2);

    try _cdb.gc(std.testing.allocator, db);
    try expectGCStats(db, 2, 2);

    try std.testing.expect(!_cdb.isAlive(obj1));
    try std.testing.expect(!_cdb.isAlive(obj2));
}

// test "cdb: Should create object from type with uuid" {
//     try testInit();
//     defer testDeinit();

//     const db = try cdb.api.createDb("Test");
//     defer cdb.api.destroyDb(db);

//     const type_hash = try _cdb.addType(db,
//         "foo",
//         &.{},
//     );

//     var uuid1 = uuid.api.newUUID7();
//     var obj1 = try db.createObjectWithUuid(type_hash, uuid1);
//     var obj1_uuid = db.getObjUuid(obj1);
//     try std.testing.expectEqualSlices(u8, &uuid1.bytes, &obj1_uuid.bytes);

//     _cdb.destroyObject(obj1);

//     try _cdb.gc(std.testing.allocator, db);
//     try expectGCStats(db, 1, 1);
// }

// test "cdb: Should find objid by uuid" {
//     try testInit();
//     defer testDeinit();

//     const db = try cdb.api.createDb("Test");
//     defer cdb.api.destroyDb(db);

//     const type_hash = try _cdb.addType(db,
//         "foo",
//         &.{},
//     );

//     var uuid1 = uuid.api.newUUID7();
//     var obj1 = try db.createObjectWithUuid(type_hash, uuid1);

//     var obj2 = try _cdb.createObject(db, type_hash);
//     var uuid2 = db.getObjUuid(obj2);

//     try std.testing.expectEqual(obj1, db.getObjIdFromUuid(uuid1).?);
//     try std.testing.expectEqual(obj2, db.getObjIdFromUuid(uuid2).?);

//     _cdb.destroyObject(obj1);
//     _cdb.destroyObject(obj2);

//     try _cdb.gc(std.testing.allocator, db);
//     try expectGCStats(db, 2, 2);
// }

test "cdb: Should create object from default obj" {
    try testInit();
    defer testDeinit();

    const db = try cdb_private.api.createDb("Test");
    defer cdb_private.api.destroyDb(db);

    const type_hash = try _cdb.addType(
        db,
        "foo",
        &.{
            .{ .prop_idx = 0, .name = "prop1", .type = public.PropType.U64 },
        },
    );

    const obj1 = try _cdb.createObject(db, type_hash);

    {
        const w = _cdb.writeObj(obj1).?;
        _cdb.setValue(u64, w, 0, 20);
        try _cdb.writeCommit(w);
    }

    _cdb.setDefaultObject(obj1);

    const obj2 = try _cdb.createObject(db, type_hash);
    try std.testing.expectEqual(@as(u64, 20), _cdb.readValue(u64, _cdb.readObj(obj2).?, 0));

    _cdb.destroyObject(obj1);
    _cdb.destroyObject(obj2);

    try _cdb.gc(std.testing.allocator, db);
    try expectGCStats(db, 2, 3);
}

test "cdb: Should clone object" {
    try testInit();
    defer testDeinit();

    const db = try cdb_private.api.createDb("Test");
    defer cdb_private.api.destroyDb(db);

    const type_hash = try _cdb.addType(
        db,
        "foo",
        &.{
            .{ .prop_idx = 0, .name = "prop1", .type = public.PropType.U64 },
            .{ .prop_idx = 1, .name = "prop2", .type = public.PropType.SUBOBJECT },
            .{ .prop_idx = 2, .name = "prop3", .type = public.PropType.SUBOBJECT_SET },
            .{ .prop_idx = 3, .name = "prop4", .type = public.PropType.REFERENCE_SET },
        },
    );

    const obj1 = try _cdb.createObject(db, type_hash);
    const sub_obj1 = try _cdb.createObject(db, type_hash);
    const sub_obj2 = try _cdb.createObject(db, type_hash);
    const sub_obj3 = try _cdb.createObject(db, type_hash);
    const ref_obj1 = try _cdb.createObject(db, type_hash);
    const ref_obj2 = try _cdb.createObject(db, type_hash);

    {
        const w = _cdb.writeObj(obj1).?;
        const subobj1_w = _cdb.writeObj(sub_obj1).?;
        const subobj2_w = _cdb.writeObj(sub_obj2).?;
        const subobj3_w = _cdb.writeObj(sub_obj3).?;

        _cdb.setValue(u64, w, 0, 10);
        try _cdb.setSubObj(w, 1, subobj1_w);

        try _cdb.addSubObjToSet(w, 2, &.{ subobj2_w, subobj3_w });
        try _cdb.addRefToSet(w, 3, &.{ ref_obj1, ref_obj2 });

        try _cdb.writeCommit(w);
        try _cdb.writeCommit(subobj1_w);
        try _cdb.writeCommit(subobj2_w);
        try _cdb.writeCommit(subobj3_w);
    }

    const obj2 = try _cdb.cloneObject(obj1);

    try std.testing.expectEqual(type_hash.idx, obj1.type_idx.idx);
    try std.testing.expectEqual(obj1.type_idx.idx, obj2.type_idx.idx);
    try std.testing.expect(obj1.id != obj2.id);

    try std.testing.expectEqual(@as(u64, 10), _cdb.readValue(u64, _cdb.readObj(obj2).?, 0));

    const subobj_obj2 = _cdb.readSubObj(_cdb.readObj(obj2).?, 1).?;
    try std.testing.expect(subobj_obj2.id != sub_obj1.id);

    {
        const w = _cdb.writeObj(obj2).?;
        _cdb.setValue(u64, w, 0, 20);
        try _cdb.writeCommit(w);
    }

    try std.testing.expectEqual(@as(u64, 10), _cdb.readValue(u64, _cdb.readObj(obj1).?, 0));
    try std.testing.expectEqual(@as(u64, 20), _cdb.readValue(u64, _cdb.readObj(obj2).?, 0));

    // subobject set
    const set = try _cdb.readSubObjSet(_cdb.readObj(obj2).?, 2, std.testing.allocator);
    try std.testing.expect(set != null);
    //try std.testing.expect(set.?.len == 2);
    for (set.?) |subobj| {
        try std.testing.expect(subobj.id != sub_obj2.id);
        try std.testing.expect(subobj.id != sub_obj3.id);
    }
    std.testing.allocator.free(set.?);

    // ref set
    const ref_set = _cdb.readRefSet(_cdb.readObj(obj2).?, 3, std.testing.allocator);
    try std.testing.expect(ref_set != null);
    try std.testing.expectEqualSlices(
        public.ObjId,
        &[_]public.ObjId{ ref_obj1, ref_obj2 },
        ref_set.?,
    );
    std.testing.allocator.free(ref_set.?);

    _cdb.destroyObject(obj1);
    _cdb.destroyObject(obj2);
    _cdb.destroyObject(ref_obj1);
    _cdb.destroyObject(ref_obj2);

    try _cdb.gc(std.testing.allocator, db);
    try expectGCStats(db, 10, 15);
}

test "cdb: Should create retarget write" {
    try testInit();
    defer testDeinit();

    const db = try cdb_private.api.createDb("Test");
    defer cdb_private.api.destroyDb(db);

    const type_hash = try _cdb.addType(
        db,
        "foo",
        &.{
            .{ .prop_idx = 0, .name = "prop1", .type = public.PropType.U64 },
        },
    );

    const obj1 = try _cdb.createObject(db, type_hash);
    const obj2 = try _cdb.createObject(db, type_hash);

    var obj1_w = _cdb.writeObj(obj1).?;
    _cdb.setValue(u64, obj1_w, 0, 11);
    try _cdb.writeCommit(obj1_w);

    const obj2_w = _cdb.writeObj(obj2).?;
    _cdb.setValue(u64, obj2_w, 0, 22);
    try _cdb.writeCommit(obj2_w);

    obj1_w = _cdb.writeObj(obj1).?;
    _cdb.setValue(u64, obj1_w, 0, 42);
    try _cdb.retargetWrite(obj1_w, obj2);
    try _cdb.writeCommit(obj1_w);

    const value = _cdb.readValue(u64, _cdb.readObj(obj2).?, 0);

    try std.testing.expectEqual(@as(u64, 42), value);

    _cdb.destroyObject(obj1);
    _cdb.destroyObject(obj2);

    try _cdb.gc(std.testing.allocator, db);
    try expectGCStats(db, 2, 5);
}

fn testNumericValues(
    comptime T: type,
    db: cdb.DbId,
    type_hash: cdb.TypeIdx,
) !void {
    const obj1 = try _cdb.createObject(db, type_hash);

    var obj_reader = _cdb.readObj(obj1);
    try std.testing.expect(obj_reader != null);

    var value = _cdb.readValue(T, obj_reader.?, 0);
    try std.testing.expectEqual(@as(T, 0), value);

    value = _cdb.readValue(T, obj_reader.?, 1);
    try std.testing.expectEqual(@as(T, 0), value);

    {
        const writer = _cdb.writeObj(obj1).?;
        _cdb.setValue(T, writer, 0, 1);
        try _cdb.writeCommit(writer);
    }

    obj_reader = _cdb.readObj(obj1);
    try std.testing.expect(obj_reader != null);

    value = _cdb.readValue(T, obj_reader.?, 0);
    try std.testing.expectEqual(@as(T, 1), value);

    value = _cdb.readValue(T, obj_reader.?, 1);
    try std.testing.expectEqual(@as(T, 0), value);

    {
        const writer = _cdb.writeObj(obj1).?;
        _cdb.setValue(T, writer, 1, 2);
        try _cdb.writeCommit(writer);
    }

    obj_reader = _cdb.readObj(obj1);
    try std.testing.expect(obj_reader != null);

    value = _cdb.readValue(T, obj_reader.?, 0);
    try std.testing.expectEqual(@as(T, 1), value);

    value = _cdb.readValue(T, obj_reader.?, 1);
    try std.testing.expectEqual(@as(T, 2), value);

    _cdb.destroyObject(obj1);

    try _cdb.gc(std.testing.allocator, db);
    try expectGCStats(db, 1, 3);
}

test "cdb: Should read/write U64 property " {
    try testInit();
    defer testDeinit();

    const db = try cdb_private.api.createDb("Test");
    defer cdb_private.api.destroyDb(db);

    const type_hash = try _cdb.addType(
        db,
        "foo",
        &.{
            .{ .prop_idx = 0, .name = "prop1", .type = public.PropType.U64 },
            .{ .prop_idx = 1, .name = "prop2", .type = public.PropType.U64 },
        },
    );

    try testNumericValues(u64, db, type_hash);
}

test "cdb: Should read/write I64 property " {
    try testInit();
    defer testDeinit();

    const db = try cdb_private.api.createDb("Test");
    defer cdb_private.api.destroyDb(db);

    const type_hash = try _cdb.addType(
        db,
        "foo",
        &.{
            .{ .prop_idx = 0, .name = "prop1", .type = public.PropType.I64 },
            .{ .prop_idx = 1, .name = "prop2", .type = public.PropType.I64 },
        },
    );

    try testNumericValues(i64, db, type_hash);
}

test "cdb: Should read/write F64 property " {
    try testInit();
    defer testDeinit();

    const db = try cdb_private.api.createDb("Test");
    defer cdb_private.api.destroyDb(db);

    const type_hash = try _cdb.addType(
        db,
        "foo",
        &.{
            .{ .prop_idx = 0, .name = "prop1", .type = public.PropType.F64 },
            .{ .prop_idx = 1, .name = "prop2", .type = public.PropType.F64 },
        },
    );

    try testNumericValues(f64, db, type_hash);
}

test "cdb: Should read/write U32 property " {
    try testInit();
    defer testDeinit();

    const db = try cdb_private.api.createDb("Test");
    defer cdb_private.api.destroyDb(db);

    const type_hash = try _cdb.addType(
        db,
        "foo",
        &.{
            .{ .prop_idx = 0, .name = "prop1", .type = public.PropType.U32 },
            .{ .prop_idx = 1, .name = "prop2", .type = public.PropType.U32 },
        },
    );

    try testNumericValues(u32, db, type_hash);
}
test "cdb: Should read/write I32 property " {
    try testInit();
    defer testDeinit();

    const db = try cdb_private.api.createDb("Test");
    defer cdb_private.api.destroyDb(db);

    const type_hash = try _cdb.addType(
        db,
        "foo",
        &.{
            .{ .prop_idx = 0, .name = "prop1", .type = public.PropType.I32 },
            .{ .prop_idx = 1, .name = "prop2", .type = public.PropType.I32 },
        },
    );

    try testNumericValues(i32, db, type_hash);
}

test "cdb: Should read/write F32 property " {
    try testInit();
    defer testDeinit();

    const db = try cdb_private.api.createDb("Test");
    defer cdb_private.api.destroyDb(db);

    const type_hash = try _cdb.addType(
        db,
        "foo",
        &.{
            .{ .prop_idx = 0, .name = "prop1", .type = public.PropType.F32 },
            .{ .prop_idx = 1, .name = "prop2", .type = public.PropType.F32 },
        },
    );

    try testNumericValues(f32, db, type_hash);
}

test "cdb: Should read/write string property " {
    try testInit();
    defer testDeinit();

    const db = try cdb_private.api.createDb("Test");
    defer cdb_private.api.destroyDb(db);

    const type_hash = try _cdb.addType(
        db,
        "foo",
        &.{
            .{ .prop_idx = 0, .name = "prop1", .type = public.PropType.STR },
            .{ .prop_idx = 1, .name = "prop2", .type = public.PropType.STR },
        },
    );

    const obj1 = try _cdb.createObject(db, type_hash);

    var obj_reader = _cdb.readObj(obj1);
    try std.testing.expect(obj_reader != null);

    var value = _cdb.readStr(obj_reader.?, 0);

    {
        const writer = _cdb.writeObj(obj1).?;
        const str = "FOO";
        try _cdb.setStr(writer, 0, str);
        try _cdb.writeCommit(writer);
    }

    obj_reader = _cdb.readObj(obj1);
    try std.testing.expect(obj_reader != null);

    value = _cdb.readStr(obj_reader.?, 0);
    try std.testing.expect(value != null);
    try std.testing.expectEqualSlices(u8, "FOO", value.?);

    _cdb.destroyObject(obj1);

    try _cdb.gc(std.testing.allocator, db);
    try expectGCStats(db, 1, 2);
}

test "cdb: Should read/write bool property " {
    try testInit();
    defer testDeinit();

    const db = try cdb_private.api.createDb("Test");
    defer cdb_private.api.destroyDb(db);

    const type_hash = try _cdb.addType(
        db,
        "foo",
        &.{
            .{ .prop_idx = 0, .name = "prop1", .type = public.PropType.BOOL },
            .{ .prop_idx = 1, .name = "prop2", .type = public.PropType.BOOL },
        },
    );

    const obj1 = try _cdb.createObject(db, type_hash);

    var obj_reader = _cdb.readObj(obj1);
    try std.testing.expect(obj_reader != null);

    var value = _cdb.readValue(bool, obj_reader.?, 0);
    try std.testing.expect(!value);

    {
        const writer = _cdb.writeObj(obj1).?;
        _cdb.setValue(bool, writer, 0, true);
        try _cdb.writeCommit(writer);
    }

    obj_reader = _cdb.readObj(obj1);
    try std.testing.expect(obj_reader != null);

    value = _cdb.readValue(bool, obj_reader.?, 0);
    try std.testing.expect(value);

    _cdb.destroyObject(obj1);

    try _cdb.gc(std.testing.allocator, db);
    try expectGCStats(db, 1, 2);
}

test "cdb: Should get object version" {
    try testInit();
    defer testDeinit();

    const db = try cdb_private.api.createDb("Test");
    defer cdb_private.api.destroyDb(db);

    const type_hash = try _cdb.addType(
        db,
        "foo",
        &.{
            .{ .prop_idx = 0, .name = "prop1", .type = public.PropType.BOOL },
            .{ .prop_idx = 1, .name = "prop2", .type = public.PropType.BOOL },
        },
    );

    const obj1 = try _cdb.createObject(db, type_hash);
    const init_version = _cdb.getVersion(obj1);

    try std.testing.expectEqual(init_version, _cdb.getVersion(obj1));

    {
        const writer = _cdb.writeObj(obj1).?;
        _cdb.setValue(bool, writer, 0, true);
        try _cdb.writeCommit(writer);
    }

    try std.testing.expect(init_version != _cdb.getVersion(obj1));

    _cdb.destroyObject(obj1);
    try _cdb.gc(std.testing.allocator, db);
    try expectGCStats(db, 1, 2);
}

test "cdb: Should read/write subobject property " {
    try testInit();
    defer testDeinit();

    const db = try cdb_private.api.createDb("Test");
    defer cdb_private.api.destroyDb(db);

    const type_hash = try _cdb.addType(
        db,
        "foo",
        &.{
            .{ .prop_idx = 0, .name = "prop1", .type = public.PropType.SUBOBJECT },
        },
    );

    const type_hash2 = try _cdb.addType(
        db,
        "foo2",
        &.{
            .{ .prop_idx = 0, .name = "prop1", .type = public.PropType.F64 },
        },
    );

    const obj1 = try _cdb.createObject(db, type_hash);
    defer _cdb.destroyObject(obj1);

    const sub_obj1 = try _cdb.createObject(db, type_hash2);
    defer _cdb.destroyObject(sub_obj1);

    var obj_reader = _cdb.readObj(obj1);
    try std.testing.expect(obj_reader != null);

    {
        const writer = _cdb.writeObj(obj1).?;

        const sub_writer = _cdb.writeObj(sub_obj1).?;

        try _cdb.setSubObj(writer, 0, sub_writer);

        try _cdb.writeCommit(sub_writer);
        try _cdb.writeCommit(writer);
    }

    obj_reader = _cdb.readObj(obj1);
    try std.testing.expect(obj_reader != null);

    const value = _cdb.readSubObj(obj_reader.?, 0);
    try std.testing.expect(value != null);
    try std.testing.expectEqual(sub_obj1, value.?);

    // Test if destroy parent destroy of subobjects
    _cdb.destroyObject(obj1);

    try _cdb.gc(std.testing.allocator, db);
    try expectGCStats(db, 2, 4);

    obj_reader = _cdb.readObj(obj1);
    try std.testing.expectEqual(@as(?*public.Obj, null), obj_reader);

    obj_reader = _cdb.readObj(sub_obj1);
    try std.testing.expectEqual(@as(?*public.Obj, null), obj_reader);
}

test "cdb: Should delete subobject" {
    try testInit();
    defer testDeinit();

    const db = try cdb_private.api.createDb("Test");
    defer cdb_private.api.destroyDb(db);

    const type_hash = try _cdb.addType(
        db,
        "foo",
        &.{
            .{ .prop_idx = 0, .name = "prop1", .type = public.PropType.SUBOBJECT },
        },
    );

    const type_hash2 = try _cdb.addType(
        db,
        "foo2",
        &.{
            .{ .prop_idx = 0, .name = "prop1", .type = public.PropType.SUBOBJECT },
        },
    );

    const obj1 = try _cdb.createObject(db, type_hash);

    const sub_obj1 = try _cdb.createObject(db, type_hash2);

    {
        const writer = _cdb.writeObj(obj1).?;

        const sub_writer = _cdb.writeObj(sub_obj1).?;

        try _cdb.setSubObj(writer, 0, sub_writer);

        try _cdb.writeCommit(sub_writer);
        try _cdb.writeCommit(writer);
    }

    // Test if destroy subobjects set parent property to 0
    _cdb.destroyObject(sub_obj1);

    try _cdb.gc(std.testing.allocator, db);
    try expectGCStats(db, 2, 3);

    const obj_reader = _cdb.readObj(obj1).?;
    const sub_obj1_read = _cdb.readSubObj(obj_reader, 0);
    try std.testing.expectEqual(@as(?public.ObjId, null), sub_obj1_read);

    _cdb.destroyObject(obj1);
    try _cdb.gc(std.testing.allocator, db);
    try expectGCStats(db, 2, 1);
}

test "cdb: Should read/write subobj set property " {
    try testInit();
    defer testDeinit();

    const db = try cdb_private.api.createDb("Test");
    defer cdb_private.api.destroyDb(db);

    const type_hash = try _cdb.addType(
        db,
        "foo",
        &.{
            .{ .prop_idx = 0, .name = "prop1", .type = public.PropType.SUBOBJECT_SET },
        },
    );

    const obj1 = try _cdb.createObject(db, type_hash);
    const sub_obj1 = try _cdb.createObject(db, type_hash);
    const sub_obj2 = try _cdb.createObject(db, type_hash);

    var obj_reader = _cdb.readObj(obj1);
    try std.testing.expect(obj_reader != null);

    {
        const writer = _cdb.writeObj(obj1).?;
        const sub_obj1_writer = _cdb.writeObj(sub_obj1).?;
        const sub_obj2_writer = _cdb.writeObj(sub_obj2).?;

        try _cdb.addSubObjToSet(writer, 0, &[_]*public.Obj{ sub_obj1_writer, sub_obj2_writer });

        try _cdb.writeCommit(sub_obj2_writer);
        try _cdb.writeCommit(sub_obj1_writer);
        try _cdb.writeCommit(writer);
    }

    obj_reader = _cdb.readObj(obj1);
    try std.testing.expect(obj_reader != null);

    var set = try _cdb.readSubObjSet(obj_reader.?, 0, std.testing.allocator);

    try std.testing.expect(set != null);
    try std.testing.expectEqualSlices(
        public.ObjId,
        &[_]public.ObjId{ sub_obj1, sub_obj2 },
        set.?,
    );

    std.testing.allocator.free(set.?);

    // Remove object
    {
        const writer = _cdb.writeObj(obj1).?;
        const sub_obj1_writer = _cdb.writeObj(sub_obj1).?;

        try _cdb.removeFromSubObjSet(writer, 0, sub_obj1_writer);

        try _cdb.writeCommit(sub_obj1_writer);
        try _cdb.writeCommit(writer);
    }

    obj_reader = _cdb.readObj(obj1);
    try std.testing.expect(obj_reader != null);

    set = try _cdb.readSubObjSet(obj_reader.?, 0, std.testing.allocator);

    try std.testing.expect(set != null);
    try std.testing.expectEqualSlices(
        public.ObjId,
        &[_]public.ObjId{sub_obj2},
        set.?,
    );

    std.testing.allocator.free(set.?);

    _cdb.destroyObject(sub_obj1);
    _cdb.destroyObject(sub_obj2);

    // object is removed from parent after gc
    try _cdb.gc(std.testing.allocator, db);
    try expectGCStats(db, 3, 7);

    obj_reader = _cdb.readObj(obj1);
    set = try _cdb.readSubObjSet(obj_reader.?, 0, std.testing.allocator);
    try std.testing.expect(set != null);
    try std.testing.expectEqualSlices(
        public.ObjId,
        &[_]public.ObjId{},
        set.?,
    );

    std.testing.allocator.free(set.?);

    _cdb.destroyObject(obj1);
    try _cdb.gc(std.testing.allocator, db);
    try expectGCStats(db, 3, 1);
}

test "cdb: Should read/write reference property" {
    try testInit();
    defer testDeinit();

    const db = try cdb_private.api.createDb("Test");
    defer cdb_private.api.destroyDb(db);

    const type_hash = try _cdb.addType(
        db,
        "foo",
        &.{
            .{ .prop_idx = 0, .name = "prop1", .type = public.PropType.REFERENCE },
        },
    );

    const obj1 = try _cdb.createObject(db, type_hash);

    const ref_obj1 = try _cdb.createObject(db, type_hash);

    var obj_reader = _cdb.readObj(obj1);
    try std.testing.expect(obj_reader != null);

    {
        const writer = _cdb.writeObj(obj1).?;
        try _cdb.setRef(writer, 0, ref_obj1);
        try _cdb.writeCommit(writer);
    }

    obj_reader = _cdb.readObj(obj1);
    try std.testing.expect(obj_reader != null);

    const value = _cdb.readRef(obj_reader.?, 0);
    try std.testing.expect(value != null);
    try std.testing.expectEqual(ref_obj1, value.?);

    // Ref has obj1 as referencer
    var referencer_set = try _cdb.getReferencerSet(std.testing.allocator, ref_obj1);
    try std.testing.expectEqualSlices(
        public.ObjId,
        &[_]public.ObjId{obj1},
        referencer_set,
    );
    std.testing.allocator.free(referencer_set);

    // Delete object does not delete reference.
    _cdb.destroyObject(obj1);
    try _cdb.gc(std.testing.allocator, db);

    obj_reader = _cdb.readObj(obj1);
    try std.testing.expectEqual(@as(?*public.Obj, null), obj_reader);

    obj_reader = _cdb.readObj(ref_obj1);
    try std.testing.expect(obj_reader != null);

    // Ref has empty referencers
    referencer_set = try _cdb.getReferencerSet(std.testing.allocator, ref_obj1);
    try std.testing.expectEqualSlices(
        public.ObjId,
        &[_]public.ObjId{},
        referencer_set,
    );
    std.testing.allocator.free(referencer_set);

    // if refcounter work good we can delete object. if not shit hapends and you have bad day.
    _cdb.destroyObject(ref_obj1);
    try _cdb.gc(std.testing.allocator, db);
    try expectGCStats(db, 2, 1);

    obj_reader = _cdb.readObj(ref_obj1);
    try std.testing.expect(obj_reader == null);

    try _cdb.gc(std.testing.allocator, db);
    try expectGCStats(db, 2, 0);
}

test "cdb: Should read/write reference set property " {
    try testInit();
    defer testDeinit();

    const db = try cdb_private.api.createDb("Test");
    defer cdb_private.api.destroyDb(db);

    const type_hash = try _cdb.addType(
        db,
        "foo",
        &.{
            .{ .prop_idx = 0, .name = "prop1", .type = public.PropType.REFERENCE_SET },
        },
    );

    const obj1 = try _cdb.createObject(db, type_hash);
    const ref_obj1 = try _cdb.createObject(db, type_hash);
    const ref_obj2 = try _cdb.createObject(db, type_hash);

    var obj_reader = _cdb.readObj(obj1);
    try std.testing.expect(obj_reader != null);

    {
        const writer = _cdb.writeObj(obj1).?;
        try _cdb.addRefToSet(writer, 0, &[_]public.ObjId{ ref_obj1, ref_obj2 });

        // try add same items
        try _cdb.addRefToSet(writer, 0, &[_]public.ObjId{ ref_obj1, ref_obj2 });
        try _cdb.writeCommit(writer);
    }

    obj_reader = _cdb.readObj(obj1);
    try std.testing.expect(obj_reader != null);

    var set = _cdb.readRefSet(obj_reader.?, 0, std.testing.allocator);
    try std.testing.expect(set != null);
    try std.testing.expectEqualSlices(
        public.ObjId,
        &[_]public.ObjId{ ref_obj1, ref_obj2 },
        set.?,
    );
    std.testing.allocator.free(set.?);

    // Ref1 has obj1 as referencer
    var referencer_set = try _cdb.getReferencerSet(std.testing.allocator, ref_obj1);
    try std.testing.expectEqualSlices(
        public.ObjId,
        &[_]public.ObjId{obj1},
        referencer_set,
    );
    std.testing.allocator.free(referencer_set);
    // Ref2 has obj1 as referencer
    referencer_set = try _cdb.getReferencerSet(std.testing.allocator, ref_obj2);
    try std.testing.expectEqualSlices(
        public.ObjId,
        &[_]public.ObjId{obj1},
        referencer_set,
    );
    std.testing.allocator.free(referencer_set);

    const writer = _cdb.writeObj(obj1).?;
    try _cdb.removeFromRefSet(writer, 0, ref_obj1);
    try _cdb.writeCommit(writer);

    obj_reader = _cdb.readObj(obj1);
    try std.testing.expect(obj_reader != null);

    set = _cdb.readRefSet(obj_reader.?, 0, std.testing.allocator);
    try std.testing.expect(set != null);
    try std.testing.expectEqualSlices(
        public.ObjId,
        &[_]public.ObjId{ref_obj2},
        set.?,
    );
    std.testing.allocator.free(set.?);

    // Ref1 has empty referencer
    referencer_set = try _cdb.getReferencerSet(std.testing.allocator, ref_obj1);
    try std.testing.expectEqualSlices(
        public.ObjId,
        &[_]public.ObjId{},
        referencer_set,
    );
    std.testing.allocator.free(referencer_set);
    // Ref2 has obj1 as referencer
    referencer_set = try _cdb.getReferencerSet(std.testing.allocator, ref_obj2);
    try std.testing.expectEqualSlices(
        public.ObjId,
        &[_]public.ObjId{obj1},
        referencer_set,
    );
    std.testing.allocator.free(referencer_set);

    _cdb.destroyObject(ref_obj2);
    try _cdb.gc(std.testing.allocator, db);
    try expectGCStats(db, 3, 3);

    obj_reader = _cdb.readObj(obj1);
    set = _cdb.readRefSet(obj_reader.?, 0, std.testing.allocator);
    try std.testing.expect(set != null);
    try std.testing.expectEqualSlices(
        public.ObjId,
        &[_]public.ObjId{},
        set.?,
    );
    std.testing.allocator.free(set.?);

    _cdb.destroyObject(ref_obj1);
    _cdb.destroyObject(obj1);

    try _cdb.gc(std.testing.allocator, db);
    try expectGCStats(db, 3, 2);
}

test "cdb: Should read/write blob property " {
    try testInit();
    defer testDeinit();

    const db = try cdb_private.api.createDb("Test");
    defer cdb_private.api.destroyDb(db);

    const type_hash = try _cdb.addType(
        db,
        "foo",
        &.{
            .{ .prop_idx = 0, .name = "prop1", .type = public.PropType.BLOB },
        },
    );

    const obj1 = try _cdb.createObject(db, type_hash);
    defer _cdb.destroyObject(obj1);

    const writer = _cdb.writeObj(obj1).?;
    var blob = try _cdb.createBlob(writer, 0, 10);

    try std.testing.expect(blob != null);

    for (0..10) |idx| {
        blob.?[idx] = 1;
    }

    try _cdb.writeCommit(writer);

    const blob1 = _cdb.readBlob(_cdb.readObj(obj1).?, 0);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 }, blob1);
}

test "cdb: Should use prototype" {
    try testInit();
    defer testDeinit();

    const db = try cdb_private.api.createDb("Test");
    defer cdb_private.api.destroyDb(db);

    const type_hash = try _cdb.addType(
        db,
        "foo",
        &.{
            .{ .prop_idx = 0, .name = "prop1", .type = public.PropType.F64 },
        },
    );

    const obj1 = try _cdb.createObject(db, type_hash);
    var obj1_w = _cdb.writeObj(obj1).?;
    _cdb.setValue(f64, obj1_w, 0, 1);
    try _cdb.writeCommit(obj1_w);

    try std.testing.expectEqual(public.ObjId{}, _cdb.getPrototype(_cdb.readObj(obj1).?));

    const obj2 = try _cdb.createObjectFromPrototype(obj1);

    try std.testing.expectEqual(obj1, _cdb.getPrototype(_cdb.readObj(obj2).?));

    obj1_w = _cdb.writeObj(obj1).?;
    _cdb.setValue(f64, obj1_w, 0, 2);
    try _cdb.writeCommit(obj1_w);

    try std.testing.expect(!_cdb.isPropertyOverrided(_cdb.readObj(obj2).?, 0));

    try std.testing.expectEqual(
        @as(f64, 2),
        _cdb.readValue(f64, _cdb.readObj(obj2).?, 0),
    );

    // if change property on instance we read from this not prototypes
    var obj2_w = _cdb.writeObj(obj2).?;
    _cdb.setValue(f64, obj2_w, 0, 3);
    try _cdb.writeCommit(obj2_w);

    try std.testing.expect(_cdb.isPropertyOverrided(_cdb.readObj(obj2).?, 0));

    try std.testing.expectEqual(
        @as(f64, 3),
        _cdb.readValue(f64, _cdb.readObj(obj2).?, 0),
    );

    // is possible to reset override flag.
    obj2_w = _cdb.writeObj(obj2).?;
    _cdb.resetPropertyOveride(obj2_w, 0);
    try _cdb.writeCommit(obj2_w);

    try std.testing.expectEqual(
        @as(f64, 2),
        _cdb.readValue(f64, _cdb.readObj(obj2).?, 0),
    );

    _cdb.destroyObject(obj1);
    _cdb.destroyObject(obj2);

    try _cdb.gc(std.testing.allocator, db);
    try expectGCStats(db, 2, 6);
}

test "cdb: Should use prototype on sets" {
    try testInit();
    defer testDeinit();

    const db = try cdb_private.api.createDb("Test");
    defer cdb_private.api.destroyDb(db);

    const type_hash = try _cdb.addType(
        db,
        "foo",
        &.{
            .{ .prop_idx = 0, .name = "prop1", .type = public.PropType.REFERENCE_SET },
        },
    );

    const obj1 = try _cdb.createObject(db, type_hash);
    const obj2 = try _cdb.createObject(db, type_hash);
    const obj3 = try _cdb.createObject(db, type_hash);

    const obj1_w = _cdb.writeObj(obj1).?;
    try _cdb.addRefToSet(obj1_w, 0, &[_]public.ObjId{ obj2, obj3 });
    try _cdb.writeCommit(obj1_w);

    const new_obj = try _cdb.createObjectFromPrototype(obj1);

    // we see full set from prototype
    var set = _cdb.readRefSet(_cdb.readObj(new_obj).?, 0, std.testing.allocator);
    try std.testing.expect(set != null);
    try std.testing.expectEqualSlices(
        public.ObjId,
        &[_]public.ObjId{ obj2, obj3 },
        set.?,
    );
    std.testing.allocator.free(set.?);

    // Remove one object fro new set
    var new_obj1_w = _cdb.writeObj(new_obj).?;
    try _cdb.removeFromRefSet(new_obj1_w, 0, obj2);
    try _cdb.writeCommit(new_obj1_w);

    set = _cdb.readRefSet(_cdb.readObj(new_obj).?, 0, std.testing.allocator);
    try std.testing.expect(set != null);
    try std.testing.expectEqualSlices(
        public.ObjId,
        &[_]public.ObjId{obj3},
        set.?,
    );
    std.testing.allocator.free(set.?);

    // Remove one object fro new set
    new_obj1_w = _cdb.writeObj(new_obj).?;
    try _cdb.removeFromRefSet(new_obj1_w, 0, obj3);
    try _cdb.writeCommit(new_obj1_w);

    set = _cdb.readRefSet(_cdb.readObj(new_obj).?, 0, std.testing.allocator);
    try std.testing.expect(set != null);
    try std.testing.expectEqualSlices(
        public.ObjId,
        &[_]public.ObjId{},
        set.?,
    );
    std.testing.allocator.free(set.?);

    // Add new objet to instance set
    const obj4 = try _cdb.createObject(db, type_hash);
    new_obj1_w = _cdb.writeObj(new_obj).?;
    try _cdb.addRefToSet(new_obj1_w, 0, &[_]public.ObjId{obj4});
    try _cdb.writeCommit(new_obj1_w);

    // Instance see only obj4
    set = _cdb.readRefSet(_cdb.readObj(new_obj).?, 0, std.testing.allocator);
    try std.testing.expect(set != null);
    try std.testing.expectEqualSlices(
        public.ObjId,
        &[_]public.ObjId{obj4},
        set.?,
    );
    std.testing.allocator.free(set.?);

    // Protoype stil se obj2, obj3
    set = _cdb.readRefSet(_cdb.readObj(obj1).?, 0, std.testing.allocator);
    try std.testing.expect(set != null);
    try std.testing.expectEqualSlices(
        public.ObjId,
        &[_]public.ObjId{ obj2, obj3 },
        set.?,
    );
    std.testing.allocator.free(set.?);

    _cdb.destroyObject(obj1);
    _cdb.destroyObject(obj2);
    _cdb.destroyObject(obj3);
    _cdb.destroyObject(new_obj);
    _cdb.destroyObject(obj4);

    try _cdb.gc(std.testing.allocator, db);
    try expectGCStats(db, 5, 9);
}

test "cdb: Should instantiate subobject" {
    try testInit();
    defer testDeinit();

    const db = try cdb_private.api.createDb("Test");
    defer cdb_private.api.destroyDb(db);

    const type_hash = try _cdb.addType(
        db,
        "foo",
        &.{
            .{ .prop_idx = 0, .name = "prop1", .type = public.PropType.SUBOBJECT },
        },
    );

    const type_hash2 = try _cdb.addType(
        db,
        "foo2",
        &.{
            .{ .prop_idx = 0, .name = "prop1", .type = public.PropType.U64 },
        },
    );

    const obj1 = try _cdb.createObject(db, type_hash);
    const sub_obj1 = try _cdb.createObject(db, type_hash2);

    const obj1_w = _cdb.writeObj(obj1).?;
    const sub_obj1_w = _cdb.writeObj(sub_obj1).?;
    _cdb.setValue(u64, sub_obj1_w, 0, 10);
    try _cdb.setSubObj(obj1_w, 0, sub_obj1_w);
    try _cdb.writeCommit(sub_obj1_w);
    try _cdb.writeCommit(obj1_w);

    const obj2 = try _cdb.createObjectFromPrototype(obj1);
    var obj2_sub = _cdb.readSubObj(_cdb.readObj(obj2).?, 0).?;

    try std.testing.expectEqual(
        @as(u64, 10),
        _cdb.readValue(u64, _cdb.readObj(obj2_sub).?, 0),
    );

    const obj2_w = _cdb.writeObj(obj2).?;
    _ = try _cdb.instantiateSubObj(obj2_w, 0);
    try _cdb.writeCommit(obj2_w);

    try std.testing.expect(_cdb.isPropertyOverrided(_cdb.readObj(obj2).?, 0));

    obj2_sub = _cdb.readSubObj(_cdb.readObj(obj2).?, 0).?;
    const sub_obj2_w = _cdb.writeObj(obj2_sub).?;
    _cdb.setValue(u64, sub_obj2_w, 0, 20);
    try _cdb.writeCommit(sub_obj2_w);

    try std.testing.expectEqual(
        @as(u64, 10),
        _cdb.readValue(u64, _cdb.readObj(sub_obj1).?, 0),
    );

    try std.testing.expectEqual(
        @as(u64, 20),
        _cdb.readValue(u64, _cdb.readObj(obj2_sub).?, 0),
    );

    _cdb.destroyObject(obj1);
    _cdb.destroyObject(obj2);

    try _cdb.gc(std.testing.allocator, db);
    try expectGCStats(db, 4, 8);
}

test "cdb: Should deep instantiate subobject" {
    try testInit();
    defer testDeinit();

    const db = try cdb_private.api.createDb("Test");
    defer cdb_private.api.destroyDb(db);

    const type_hash = try _cdb.addType(
        db,
        "foo",
        &.{
            .{ .prop_idx = 0, .name = "prop1", .type = public.PropType.SUBOBJECT },
            .{ .prop_idx = 1, .name = "prop2", .type = public.PropType.F64 },
        },
    );

    const obj1 = try _cdb.createObject(db, type_hash);
    const sub_obj1 = try _cdb.createObject(db, type_hash);
    const sub_obj2 = try _cdb.createObject(db, type_hash);

    const obj1_w = _cdb.writeObj(obj1).?;
    const sub_obj1_w = _cdb.writeObj(sub_obj1).?;
    const sub_obj2_w = _cdb.writeObj(sub_obj2).?;
    try _cdb.setSubObj(obj1_w, 0, sub_obj1_w);
    try _cdb.setSubObj(sub_obj1_w, 0, sub_obj2_w);

    _cdb.setValue(f64, sub_obj1_w, 1, 666);
    _cdb.setValue(f64, sub_obj2_w, 1, 666);

    try _cdb.writeCommit(sub_obj1_w);
    try _cdb.writeCommit(sub_obj2_w);
    try _cdb.writeCommit(obj1_w);

    const obj2 = try _cdb.createObjectFromPrototype(obj1);

    const instasiated_obj = _cdb.inisitateDeep(std.testing.allocator, obj2, sub_obj2);
    try std.testing.expect(instasiated_obj != null);

    const instasiated_obj_w = _cdb.writeObj(instasiated_obj.?).?;
    _cdb.setValue(f64, instasiated_obj_w, 1, 22);
    try _cdb.writeCommit(instasiated_obj_w);

    const sub_obj2_r = _cdb.readObj(sub_obj2).?;
    const prop2_value = _cdb.readValue(f64, sub_obj2_r, 1);
    try std.testing.expectEqual(666, prop2_value);

    _cdb.destroyObject(obj1);
    _cdb.destroyObject(obj2);

    try _cdb.gc(std.testing.allocator, db);
    try expectGCStats(db, 6, 6);
}

test "cdb: Should deep instantiate subobject in set" {
    try testInit();
    defer testDeinit();

    const db = try cdb_private.api.createDb("Test");
    defer cdb_private.api.destroyDb(db);

    const type_hash = try _cdb.addType(
        db,
        "foo",
        &.{
            .{ .prop_idx = 0, .name = "prop1", .type = public.PropType.SUBOBJECT },
            .{ .prop_idx = 1, .name = "prop2", .type = public.PropType.F64 },
            .{ .prop_idx = 2, .name = "prop3", .type = public.PropType.SUBOBJECT_SET },
        },
    );

    const obj1 = try _cdb.createObject(db, type_hash);
    const sub_obj1 = try _cdb.createObject(db, type_hash);
    const sub_obj2 = try _cdb.createObject(db, type_hash);

    const obj1_w = _cdb.writeObj(obj1).?;
    const sub_obj1_w = _cdb.writeObj(sub_obj1).?;
    const sub_obj2_w = _cdb.writeObj(sub_obj2).?;
    try _cdb.setSubObj(obj1_w, 0, sub_obj1_w);

    try _cdb.addSubObjToSet(sub_obj1_w, 2, &.{sub_obj2_w});

    _cdb.setValue(f64, sub_obj2_w, 1, 666);

    try _cdb.writeCommit(sub_obj1_w);
    try _cdb.writeCommit(sub_obj2_w);
    try _cdb.writeCommit(obj1_w);

    const obj2 = try _cdb.createObjectFromPrototype(obj1);

    const instasiated_obj = _cdb.inisitateDeep(std.testing.allocator, obj2, sub_obj2);
    try std.testing.expect(instasiated_obj != null);

    const instasiated_obj_w = _cdb.writeObj(instasiated_obj.?).?;
    _cdb.setValue(f64, instasiated_obj_w, 1, 22);
    try _cdb.writeCommit(instasiated_obj_w);

    const sub_obj2_r = _cdb.readObj(sub_obj2).?;
    const prop2_value = _cdb.readValue(f64, sub_obj2_r, 1);
    try std.testing.expectEqual(666, prop2_value);

    _cdb.destroyObject(obj1);
    _cdb.destroyObject(obj2);

    try _cdb.gc(std.testing.allocator, db);
    try expectGCStats(db, 6, 6);
}

test "cdb: Should specify type_hash for ref/subobj base properties" {
    try testInit();
    defer testDeinit();

    const db = try cdb_private.api.createDb("Test");
    defer cdb_private.api.destroyDb(db);

    const sub_type_hash = try _cdb.addType(
        db,
        "foo2",
        &.{
            .{ .prop_idx = 0, .name = "prop1", .type = public.PropType.U64 },
        },
    );

    const another_sub_type_hash = try _cdb.addType(
        db,
        "foo3",
        &.{
            .{ .prop_idx = 0, .name = "prop1", .type = public.PropType.U64 },
        },
    );

    const type_hash = try _cdb.addType(
        db,
        "foo",
        &.{
            .{ .prop_idx = 0, .name = "prop1", .type = public.PropType.SUBOBJECT, .type_hash = strId32("foo2") },
            .{ .prop_idx = 1, .name = "prop2", .type = public.PropType.REFERENCE, .type_hash = strId32("foo2") },
            .{ .prop_idx = 2, .name = "prop3", .type = public.PropType.SUBOBJECT_SET, .type_hash = strId32("foo2") },
            .{ .prop_idx = 3, .name = "prop4", .type = public.PropType.REFERENCE_SET, .type_hash = strId32("foo2") },
        },
    );

    const obj1 = try _cdb.createObject(db, type_hash);
    const sub_obj1 = try _cdb.createObject(db, sub_type_hash);
    const sub_obj2 = try _cdb.createObject(db, another_sub_type_hash);

    const obj1_w = _cdb.writeObj(obj1).?;
    const sub_obj2_w = _cdb.writeObj(sub_obj2).?;

    try _cdb.setSubObj(obj1_w, 0, sub_obj2_w);
    try _cdb.setRef(obj1_w, 1, sub_obj2);
    try _cdb.addSubObjToSet(obj1_w, 2, &[_]*public.Obj{sub_obj2_w});
    try _cdb.addRefToSet(obj1_w, 3, &[_]public.ObjId{sub_obj2});

    try std.testing.expect(_cdb.readSubObj(_cdb.readObj(obj1).?, 0) == null);
    try std.testing.expect(_cdb.readRef(_cdb.readObj(obj1).?, 1) == null);

    var set = try _cdb.readSubObjSet(_cdb.readObj(obj1).?, 2, std.testing.allocator);
    try std.testing.expect(set != null);
    try std.testing.expect(set.?.len == 0);
    std.testing.allocator.free(set.?);

    set = _cdb.readRefSet(_cdb.readObj(obj1).?, 3, std.testing.allocator);
    try std.testing.expect(set != null);
    try std.testing.expect(set.?.len == 0);
    std.testing.allocator.free(set.?);

    try _cdb.writeCommit(sub_obj2_w);
    try _cdb.writeCommit(obj1_w);

    _cdb.destroyObject(obj1);
    _cdb.destroyObject(sub_obj1);
    _cdb.destroyObject(sub_obj2);

    try _cdb.gc(std.testing.allocator, db);
    try expectGCStats(db, 3, 5);
}

test "cdb: Should tracking changed objects" {
    try testInit();
    defer testDeinit();

    const db = try cdb_private.api.createDb("Test");
    defer cdb_private.api.destroyDb(db);

    const type_hash = try _cdb.addType(
        db,
        "foo",
        &.{
            .{ .prop_idx = 0, .name = "prop1", .type = public.PropType.BOOL },
            .{ .prop_idx = 1, .name = "prop2", .type = public.PropType.BOOL },
        },
    );

    const obj1 = try _cdb.createObject(db, type_hash);
    const obj2 = try _cdb.createObject(db, type_hash);

    // Make some changes to obj1 and 2
    const obj1_w = _cdb.writeObj(obj1).?;
    _cdb.setValue(bool, obj1_w, 0, true);
    try _cdb.writeCommit(obj1_w);

    const obj2_w = _cdb.writeObj(obj2).?;
    _cdb.setValue(bool, obj2_w, 0, true);
    try _cdb.writeCommit(obj2_w);
    // Call GC thas create populate changed objects.
    try _cdb.gc(std.testing.allocator, db);
    const changed_1 = try _cdb.getChangeObjects(std.testing.allocator, db, type_hash, 1);
    defer std.testing.allocator.free(changed_1.objects);
    try std.testing.expectEqualSlices(public.ObjId, &.{ obj1, obj2 }, changed_1.objects);
    try std.testing.expect(!changed_1.need_fullscan);

    // get from 0 version force to do fullscan
    const changed_0 = try _cdb.getChangeObjects(std.testing.allocator, db, type_hash, 0);
    defer std.testing.allocator.free(changed_0.objects);
    try std.testing.expect(changed_0.need_fullscan);

    // Destroy object
    _cdb.destroyObject(obj2);
    // Call GC thas create populate changed objects.
    try _cdb.gc(std.testing.allocator, db);
    const changed_2 = try _cdb.getChangeObjects(std.testing.allocator, db, type_hash, changed_0.last_version);
    defer std.testing.allocator.free(changed_2.objects);
    try std.testing.expect(!changed_2.need_fullscan);
    try std.testing.expectEqualSlices(public.ObjId, &.{obj2}, changed_2.objects);

    const changed_begin = try _cdb.getChangeObjects(std.testing.allocator, db, type_hash, 1);
    defer std.testing.allocator.free(changed_begin.objects);
    try std.testing.expect(!changed_begin.need_fullscan);
    try std.testing.expectEqualSlices(public.ObjId, &.{ obj1, obj2, obj2 }, changed_begin.objects);
}

test "cdb: Should get object realtion" {
    try testInit();
    defer testDeinit();

    const db = try cdb_private.api.createDb("Test");
    defer cdb_private.api.destroyDb(db);

    const type_hash = try _cdb.addType(
        db,
        "foo",
        &.{
            .{ .prop_idx = 0, .name = "prop1", .type = public.PropType.F64 },
            .{ .prop_idx = 1, .name = "prop2", .type = public.PropType.SUBOBJECT },
        },
    );

    const obj1 = try _cdb.createObject(db, type_hash);
    const obj2 = try _cdb.createObjectFromPrototype(obj1);
    const obj3 = try _cdb.createObject(db, type_hash);

    const obj1_w = _cdb.writeObj(obj1).?;
    const obj3_w = _cdb.writeObj(obj3).?;
    try _cdb.setSubObj(obj1_w, 1, obj3_w);
    try _cdb.writeCommit(obj1_w);
    try _cdb.writeCommit(obj3_w);

    const obj1_r = _cdb.readObj(obj1).?;
    _ = obj1_r; // autofix
    const obj2_r = _cdb.readObj(obj2).?;
    _ = obj2_r; // autofix
    const obj3_r = _cdb.readObj(obj3).?;
    _ = obj3_r; // autofix

    // // Obj2 does not have relation with Obj3
    // try std.testing.expectEqual(.none, db.getRelation(obj2_r, obj3_r));

    // // Obj3 does not have relation with Obj2
    // try std.testing.expectEqual(.none, db.getRelation(obj3_r, obj2_r));

    // // Obj1 is prototype for Obj2
    // try std.testing.expectEqual(.prototype, db.getRelation(obj1_r, obj2_r));

    // // Obj1 is parent for Obj3
    // try std.testing.expectEqual(.parent, db.getRelation(obj1_r, obj3_r));

    _cdb.destroyObject(obj1);
    _cdb.destroyObject(obj2);
    _cdb.destroyObject(obj3);

    try _cdb.gc(std.testing.allocator, db);
    try expectGCStats(db, 3, 5);
}

fn stressTest(comptime task_count: u32, task_based: bool) !void {
    const db = try cdb_private.api.createDb("Test");
    defer cdb_private.api.destroyDb(db);

    const type_hash = try cetech1.cdb_types.addBigType(_cdb, db, "foo", null);
    const type_hash2 = try cetech1.cdb_types.addBigType(_cdb, db, "foo2", null);

    const ref_obj1 = try _cdb.createObject(db, type_hash2);
    if (task_based) {
        var tasks: [task_count]cetech1.task.TaskID = undefined;

        const Task = struct {
            db: cdb.DbId,
            ref_obj1: cdb.ObjId,
            type_hash: cdb.TypeIdx,
            type_hash2: cdb.TypeIdx,
            pub fn exec(self: *@This()) !void {
                _cdb.stressIt(
                    self.db,
                    self.type_hash,
                    self.type_hash2,
                    self.ref_obj1,
                ) catch undefined;
            }
        };

        for (0..task_count) |idx| {
            tasks[idx] = try task.api.schedule(
                cetech1.task.TaskID.none,
                Task{
                    .db = db,
                    .ref_obj1 = ref_obj1,
                    .type_hash = type_hash,
                    .type_hash2 = type_hash2,
                },
                .{},
            );
        }

        task.api.waitMany(&tasks);
    } else {
        for (0..task_count) |_| {
            try _cdb.stressIt(
                db,
                type_hash,
                type_hash2,
                ref_obj1,
            );
        }
    }

    _cdb.destroyObject(ref_obj1);

    var true_db = cdb_private.toDbFromDbT(db);
    const storage = true_db.getTypeStorageByTypeIdx(type_hash).?;
    try std.testing.expectEqual(@as(u32, task_count + 1), storage.objid_pool.count.raw);
    try std.testing.expectEqual(@as(u32, task_count * 3), true_db.writersCount());
    try std.testing.expectEqual(@as(u32, task_count * 3), true_db.commitCount());

    _cdb.destroyObject(ref_obj1);

    try _cdb.gc(std.testing.allocator, db);
    try expectGCStats(db, (task_count * 3) + 1, (task_count * 3) * 2 + 1);
}

test "cdb: stress test single thread" {
    const task_count = 1000;

    try testInit();
    defer testDeinit();

    try stressTest(task_count, false);
}

test "cdb: stress test multithread" {
    const task_count = 1000;

    try testInit();
    defer testDeinit();

    try stressTest(task_count, true);
}
