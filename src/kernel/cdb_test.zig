const builtin = @import("builtin");
const std = @import("std");

const cetech1 = @import("cetech1");
const public = cetech1.cdb;
const task = cetech1.task;
const apidb = cetech1.apidb;

const StrId32 = cetech1.StrId32;
const strId32 = cetech1.strId32;

const cdb = cetech1.cdb;

const cdb_private = @import("cdb.zig");
const log_private = @import("log.zig");
const apidb_private = @import("apidb.zig");
const profiler_private = @import("profiler.zig");
const task_private = @import("task.zig");
const uuid_private = @import("uuid.zig");
const metrics_private = @import("metrics.zig");

const _cdb = cdb;

pub fn testInit() !void {
    try task_private.init(std.testing.allocator);
    try apidb_private.init(std.testing.allocator);
    try metrics_private.init(std.testing.allocator);
    try cdb_private.init(std.testing.allocator);
    try task_private.start(null);
}

pub fn testDeinit() void {
    cdb_private.deinit();
    apidb_private.deinit();
    task_private.stop();
    task_private.deinit();
    metrics_private.deinit();
}

pub fn expectGCStats(db: cdb.DbId, alocated_objids: u32, free_object: u32) !void {
    const true_db = cdb_private.toDbFromDbT(db);
    try std.testing.expectEqual(alocated_objids, true_db.objids_alocated);
    try std.testing.expectEqual(@as(u32, free_object), true_db.free_objects);
}

test "cdb: Should create cdb DB" {
    try testInit();
    defer testDeinit();

    const db = try cdb.createDb("Test");
    defer cdb.destroyDb(db);
}

test "cdb: Should register type" {
    try testInit();
    defer testDeinit();

    const db = try cdb.createDb("Test");
    defer cdb.destroyDb(db);

    const type_hash = try cdb.addType(
        db,
        "foo",
        &.{},
    );

    try std.testing.expectEqual(cdb.getTypeIdx(db, strId32("foo")).?, type_hash);

    const props = cdb.getTypePropDef(db, type_hash);
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
            const type_hash = cdb.addType(
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

    try apidb.implOrRemove(.foo, public.CreateTypesI, &create_cdb_types_i, true);

    const db = try cdb.createDb("Test");
    defer cdb.destroyDb(db);

    const type_hash = strId32("foo");

    const props = cdb.getTypePropDef(db, cdb.getTypeIdx(db, type_hash).?);
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
            const type_hash = cdb.addType(
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

    try apidb.implOrRemove(.foo, public.CreateTypesI, &create_cdb_types_i, true);

    const db = try cdb.createDb("Test");
    defer cdb.destroyDb(db);

    const type_hash = strId32("foo");
    const type_idx = cdb.getTypeIdx(db, type_hash).?;

    var aspect = cdb.getAspect(FooAspect, db, cdb.getTypeIdx(db, type_hash).?);
    try std.testing.expect(aspect == null);

    try cdb.addAspect(FooAspect, db, type_idx, &foo_aspect);

    aspect = cdb.getAspect(FooAspect, db, type_idx);
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
            _ = db_;
        }

        pub fn bar(self: *Self, db_: public.DbId) void {
            return self.barFn(db_);
        }
    };

    var foo_aspect = FooAspect{ .barFn = &FooAspect.barImpl };

    var create_cdb_types_i = public.CreateTypesI.implement(struct {
        pub fn createTypes(db: cdb.DbId) !void {
            const type_hash = cdb.addType(
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
    try apidb.implOrRemove(.foo, public.CreateTypesI, &create_cdb_types_i, true);

    const db = try cdb.createDb("Test");
    defer cdb.destroyDb(db);

    const type_hash = strId32("foo");
    const type_idx = cdb.getTypeIdx(db, type_hash).?;

    var aspect = cdb.getPropertyAspect(FooAspect, db, type_idx, 0);
    try std.testing.expect(aspect == null);
    aspect = cdb.getPropertyAspect(FooAspect, db, type_idx, 1);
    try std.testing.expect(aspect == null);

    try cdb.addPropertyAspect(FooAspect, db, type_idx, 1, &foo_aspect);

    aspect = cdb.getPropertyAspect(FooAspect, db, type_idx, 0);
    try std.testing.expect(aspect == null);

    aspect = cdb.getPropertyAspect(FooAspect, db, type_idx, 1);
    try std.testing.expect(aspect != null);
    try std.testing.expectEqual(&foo_aspect, aspect.?);

    aspect.?.bar(db);
}

test "cdb: Should create object from type" {
    try testInit();
    defer testDeinit();

    const db = try cdb.createDb("Test");
    defer cdb.destroyDb(db);

    const type_hash = try cdb.addType(
        db,
        "foo",
        &.{},
    );

    const obj1 = try cdb.createObject(db, type_hash);
    const obj2 = try cdb.createObject(db, type_hash);

    try std.testing.expect(cdb.isAlive(obj1));
    try std.testing.expect(cdb.isAlive(obj2));

    try std.testing.expectEqual(type_hash.idx, obj1.type_idx.idx);
    try std.testing.expectEqual(type_hash.idx, obj2.type_idx.idx);
    try std.testing.expect(obj1.id != obj2.id);

    cdb.destroyObject(obj1);
    cdb.destroyObject(obj2);

    try cdb.gc(std.testing.allocator, db);
    try expectGCStats(db, 2, 2);

    try std.testing.expect(!cdb.isAlive(obj1));
    try std.testing.expect(!cdb.isAlive(obj2));
}

// test "cdb: Should create object from type with uuid" {
//     try testInit();
//     defer testDeinit();

//     const db = try cdb.createDb("Test");
//     defer cdb.destroyDb(db);

//     const type_hash = try cdb.addType(db,
//         "foo",
//         &.{},
//     );

//     var uuid1 = uuid.api.newUUID7();
//     var obj1 = try db.createObjectWithUuid(type_hash, uuid1);
//     var obj1_uuid = db.getObjUuid(obj1);
//     try std.testing.expectEqualSlices(u8, &uuid1.bytes, &obj1_uuid.bytes);

//     cdb.destroyObject(obj1);

//     try cdb.gc(std.testing.allocator, db);
//     try expectGCStats(db, 1, 1);
// }

// test "cdb: Should find objid by uuid" {
//     try testInit();
//     defer testDeinit();

//     const db = try cdb.createDb("Test");
//     defer cdb.destroyDb(db);

//     const type_hash = try cdb.addType(db,
//         "foo",
//         &.{},
//     );

//     var uuid1 = uuid.api.newUUID7();
//     var obj1 = try db.createObjectWithUuid(type_hash, uuid1);

//     var obj2 = try cdb.createObject(db, type_hash);
//     var uuid2 = db.getObjUuid(obj2);

//     try std.testing.expectEqual(obj1, db.getObjIdFromUuid(uuid1).?);
//     try std.testing.expectEqual(obj2, db.getObjIdFromUuid(uuid2).?);

//     cdb.destroyObject(obj1);
//     cdb.destroyObject(obj2);

//     try cdb.gc(std.testing.allocator, db);
//     try expectGCStats(db, 2, 2);
// }

test "cdb: Should create object from default obj" {
    try testInit();
    defer testDeinit();

    const db = try cdb.createDb("Test");
    defer cdb.destroyDb(db);

    const type_hash = try cdb.addType(
        db,
        "foo",
        &.{
            .{ .prop_idx = 0, .name = "prop1", .type = public.PropType.U64 },
        },
    );

    const obj1 = try cdb.createObject(db, type_hash);

    {
        const w = cdb.writeObj(obj1).?;
        cdb.setValue(u64, w, 0, 20);
        try cdb.writeCommit(w);
    }

    cdb.setDefaultObject(obj1);

    const obj2 = try cdb.createObject(db, type_hash);
    try std.testing.expectEqual(@as(u64, 20), cdb.readValue(u64, cdb.readObj(obj2).?, 0));

    cdb.destroyObject(obj1);
    cdb.destroyObject(obj2);

    try cdb.gc(std.testing.allocator, db);
    try expectGCStats(db, 2, 3);
}

test "cdb: Should clone object" {
    try testInit();
    defer testDeinit();

    const db = try cdb.createDb("Test");
    defer cdb.destroyDb(db);

    const type_hash = try cdb.addType(
        db,
        "foo",
        &.{
            .{ .prop_idx = 0, .name = "prop1", .type = public.PropType.U64 },
            .{ .prop_idx = 1, .name = "prop2", .type = public.PropType.SUBOBJECT },
            .{ .prop_idx = 2, .name = "prop3", .type = public.PropType.SUBOBJECT_SET },
            .{ .prop_idx = 3, .name = "prop4", .type = public.PropType.REFERENCE_SET },
        },
    );

    const obj1 = try cdb.createObject(db, type_hash);
    const sub_obj1 = try cdb.createObject(db, type_hash);
    const sub_obj2 = try cdb.createObject(db, type_hash);
    const sub_obj3 = try cdb.createObject(db, type_hash);
    const ref_obj1 = try cdb.createObject(db, type_hash);
    const ref_obj2 = try cdb.createObject(db, type_hash);

    {
        const w = cdb.writeObj(obj1).?;
        const subobj1_w = cdb.writeObj(sub_obj1).?;
        const subobj2_w = cdb.writeObj(sub_obj2).?;
        const subobj3_w = cdb.writeObj(sub_obj3).?;

        cdb.setValue(u64, w, 0, 10);
        try cdb.setSubObj(w, 1, subobj1_w);

        try cdb.addSubObjToSet(w, 2, &.{ subobj2_w, subobj3_w });
        try cdb.addRefToSet(w, 3, &.{ ref_obj1, ref_obj2 });

        try cdb.writeCommit(w);
        try cdb.writeCommit(subobj1_w);
        try cdb.writeCommit(subobj2_w);
        try cdb.writeCommit(subobj3_w);
    }

    const obj2 = try cdb.cloneObject(obj1);

    try std.testing.expectEqual(type_hash.idx, obj1.type_idx.idx);
    try std.testing.expectEqual(obj1.type_idx.idx, obj2.type_idx.idx);
    try std.testing.expect(obj1.id != obj2.id);

    try std.testing.expectEqual(@as(u64, 10), cdb.readValue(u64, cdb.readObj(obj2).?, 0));

    const subobj_obj2 = cdb.readSubObj(cdb.readObj(obj2).?, 1).?;
    try std.testing.expect(subobj_obj2.id != sub_obj1.id);

    {
        const w = cdb.writeObj(obj2).?;
        cdb.setValue(u64, w, 0, 20);
        try cdb.writeCommit(w);
    }

    try std.testing.expectEqual(@as(u64, 10), cdb.readValue(u64, cdb.readObj(obj1).?, 0));
    try std.testing.expectEqual(@as(u64, 20), cdb.readValue(u64, cdb.readObj(obj2).?, 0));

    // subobject set
    const set = try cdb.readSubObjSet(cdb.readObj(obj2).?, 2, std.testing.allocator);
    try std.testing.expect(set != null);
    //try std.testing.expect(set.?.len == 2);
    for (set.?) |subobj| {
        try std.testing.expect(subobj.id != sub_obj2.id);
        try std.testing.expect(subobj.id != sub_obj3.id);
    }
    std.testing.allocator.free(set.?);

    // ref set
    const ref_set = cdb.readRefSet(cdb.readObj(obj2).?, 3, std.testing.allocator);
    try std.testing.expect(ref_set != null);
    try std.testing.expectEqualSlices(
        public.ObjId,
        &[_]public.ObjId{ ref_obj1, ref_obj2 },
        ref_set.?,
    );
    std.testing.allocator.free(ref_set.?);

    cdb.destroyObject(obj1);
    cdb.destroyObject(obj2);
    cdb.destroyObject(ref_obj1);
    cdb.destroyObject(ref_obj2);

    try cdb.gc(std.testing.allocator, db);
    try expectGCStats(db, 10, 15);
}

test "cdb: Should create retarget write" {
    try testInit();
    defer testDeinit();

    const db = try cdb.createDb("Test");
    defer cdb.destroyDb(db);

    const type_hash = try cdb.addType(
        db,
        "foo",
        &.{
            .{ .prop_idx = 0, .name = "prop1", .type = public.PropType.U64 },
        },
    );

    const obj1 = try cdb.createObject(db, type_hash);
    const obj2 = try cdb.createObject(db, type_hash);

    var obj1_w = cdb.writeObj(obj1).?;
    cdb.setValue(u64, obj1_w, 0, 11);
    try cdb.writeCommit(obj1_w);

    const obj2_w = cdb.writeObj(obj2).?;
    cdb.setValue(u64, obj2_w, 0, 22);
    try cdb.writeCommit(obj2_w);

    obj1_w = cdb.writeObj(obj1).?;
    cdb.setValue(u64, obj1_w, 0, 42);
    try cdb.retargetWrite(obj1_w, obj2);
    try cdb.writeCommit(obj1_w);

    const value = cdb.readValue(u64, cdb.readObj(obj2).?, 0);

    try std.testing.expectEqual(@as(u64, 42), value);

    cdb.destroyObject(obj1);
    cdb.destroyObject(obj2);

    try cdb.gc(std.testing.allocator, db);
    try expectGCStats(db, 2, 5);
}

fn testNumericValues(
    comptime T: type,
    db: cdb.DbId,
    type_hash: cdb.TypeIdx,
) !void {
    const obj1 = try cdb.createObject(db, type_hash);

    var obj_reader = cdb.readObj(obj1);
    try std.testing.expect(obj_reader != null);

    var value = cdb.readValue(T, obj_reader.?, 0);
    try std.testing.expectEqual(@as(T, 0), value);

    value = cdb.readValue(T, obj_reader.?, 1);
    try std.testing.expectEqual(@as(T, 0), value);

    {
        const writer = cdb.writeObj(obj1).?;
        cdb.setValue(T, writer, 0, 1);
        try cdb.writeCommit(writer);
    }

    obj_reader = cdb.readObj(obj1);
    try std.testing.expect(obj_reader != null);

    value = cdb.readValue(T, obj_reader.?, 0);
    try std.testing.expectEqual(@as(T, 1), value);

    value = cdb.readValue(T, obj_reader.?, 1);
    try std.testing.expectEqual(@as(T, 0), value);

    {
        const writer = cdb.writeObj(obj1).?;
        cdb.setValue(T, writer, 1, 2);
        try cdb.writeCommit(writer);
    }

    obj_reader = cdb.readObj(obj1);
    try std.testing.expect(obj_reader != null);

    value = cdb.readValue(T, obj_reader.?, 0);
    try std.testing.expectEqual(@as(T, 1), value);

    value = cdb.readValue(T, obj_reader.?, 1);
    try std.testing.expectEqual(@as(T, 2), value);

    cdb.destroyObject(obj1);

    try cdb.gc(std.testing.allocator, db);
    try expectGCStats(db, 1, 3);
}

test "cdb: Should read/write U64 property " {
    try testInit();
    defer testDeinit();

    const db = try cdb.createDb("Test");
    defer cdb.destroyDb(db);

    const type_hash = try cdb.addType(
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

    const db = try cdb.createDb("Test");
    defer cdb.destroyDb(db);

    const type_hash = try cdb.addType(
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

    const db = try cdb.createDb("Test");
    defer cdb.destroyDb(db);

    const type_hash = try cdb.addType(
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

    const db = try cdb.createDb("Test");
    defer cdb.destroyDb(db);

    const type_hash = try cdb.addType(
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

    const db = try cdb.createDb("Test");
    defer cdb.destroyDb(db);

    const type_hash = try cdb.addType(
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

    const db = try cdb.createDb("Test");
    defer cdb.destroyDb(db);

    const type_hash = try cdb.addType(
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

    const db = try cdb.createDb("Test");
    defer cdb.destroyDb(db);

    const type_hash = try cdb.addType(
        db,
        "foo",
        &.{
            .{ .prop_idx = 0, .name = "prop1", .type = public.PropType.STR },
            .{ .prop_idx = 1, .name = "prop2", .type = public.PropType.STR },
        },
    );

    const obj1 = try cdb.createObject(db, type_hash);

    var obj_reader = cdb.readObj(obj1);
    try std.testing.expect(obj_reader != null);

    var value = cdb.readStr(obj_reader.?, 0);

    {
        const writer = cdb.writeObj(obj1).?;
        const str = "FOO";
        try cdb.setStr(writer, 0, str);
        try cdb.writeCommit(writer);
    }

    obj_reader = cdb.readObj(obj1);
    try std.testing.expect(obj_reader != null);

    value = cdb.readStr(obj_reader.?, 0);
    try std.testing.expect(value != null);
    try std.testing.expectEqualSlices(u8, "FOO", value.?);

    cdb.destroyObject(obj1);

    try cdb.gc(std.testing.allocator, db);
    try expectGCStats(db, 1, 2);
}

test "cdb: Should read/write bool property " {
    try testInit();
    defer testDeinit();

    const db = try cdb.createDb("Test");
    defer cdb.destroyDb(db);

    const type_hash = try cdb.addType(
        db,
        "foo",
        &.{
            .{ .prop_idx = 0, .name = "prop1", .type = public.PropType.BOOL },
            .{ .prop_idx = 1, .name = "prop2", .type = public.PropType.BOOL },
        },
    );

    const obj1 = try cdb.createObject(db, type_hash);

    var obj_reader = cdb.readObj(obj1);
    try std.testing.expect(obj_reader != null);

    var value = cdb.readValue(bool, obj_reader.?, 0);
    try std.testing.expect(!value);

    {
        const writer = cdb.writeObj(obj1).?;
        cdb.setValue(bool, writer, 0, true);
        try cdb.writeCommit(writer);
    }

    obj_reader = cdb.readObj(obj1);
    try std.testing.expect(obj_reader != null);

    value = cdb.readValue(bool, obj_reader.?, 0);
    try std.testing.expect(value);

    cdb.destroyObject(obj1);

    try cdb.gc(std.testing.allocator, db);
    try expectGCStats(db, 1, 2);
}

test "cdb: Should get object version" {
    try testInit();
    defer testDeinit();

    const db = try cdb.createDb("Test");
    defer cdb.destroyDb(db);

    const type_hash = try cdb.addType(
        db,
        "foo",
        &.{
            .{ .prop_idx = 0, .name = "prop1", .type = public.PropType.BOOL },
            .{ .prop_idx = 1, .name = "prop2", .type = public.PropType.BOOL },
        },
    );

    const obj1 = try cdb.createObject(db, type_hash);
    const init_version = cdb.getVersion(obj1);

    try std.testing.expectEqual(init_version, cdb.getVersion(obj1));

    {
        const writer = cdb.writeObj(obj1).?;
        cdb.setValue(bool, writer, 0, true);
        try cdb.writeCommit(writer);
    }

    try std.testing.expect(init_version != cdb.getVersion(obj1));

    cdb.destroyObject(obj1);
    try cdb.gc(std.testing.allocator, db);
    try expectGCStats(db, 1, 2);
}

test "cdb: Should read/write subobject property " {
    try testInit();
    defer testDeinit();

    const db = try cdb.createDb("Test");
    defer cdb.destroyDb(db);

    const type_hash = try cdb.addType(
        db,
        "foo",
        &.{
            .{ .prop_idx = 0, .name = "prop1", .type = public.PropType.SUBOBJECT },
        },
    );

    const type_hash2 = try cdb.addType(
        db,
        "foo2",
        &.{
            .{ .prop_idx = 0, .name = "prop1", .type = public.PropType.F64 },
        },
    );

    const obj1 = try cdb.createObject(db, type_hash);
    defer cdb.destroyObject(obj1);

    const sub_obj1 = try cdb.createObject(db, type_hash2);
    defer cdb.destroyObject(sub_obj1);

    var obj_reader = cdb.readObj(obj1);
    try std.testing.expect(obj_reader != null);

    {
        const writer = cdb.writeObj(obj1).?;

        const sub_writer = cdb.writeObj(sub_obj1).?;

        try cdb.setSubObj(writer, 0, sub_writer);

        try cdb.writeCommit(sub_writer);
        try cdb.writeCommit(writer);
    }

    obj_reader = cdb.readObj(obj1);
    try std.testing.expect(obj_reader != null);

    const value = cdb.readSubObj(obj_reader.?, 0);
    try std.testing.expect(value != null);
    try std.testing.expectEqual(sub_obj1, value.?);

    // Test if destroy parent destroy of subobjects
    cdb.destroyObject(obj1);

    try cdb.gc(std.testing.allocator, db);
    try expectGCStats(db, 2, 4);

    obj_reader = cdb.readObj(obj1);
    try std.testing.expectEqual(@as(?*public.Obj, null), obj_reader);

    obj_reader = cdb.readObj(sub_obj1);
    try std.testing.expectEqual(@as(?*public.Obj, null), obj_reader);
}

test "cdb: Should delete subobject" {
    try testInit();
    defer testDeinit();

    const db = try cdb.createDb("Test");
    defer cdb.destroyDb(db);

    const type_hash = try cdb.addType(
        db,
        "foo",
        &.{
            .{ .prop_idx = 0, .name = "prop1", .type = public.PropType.SUBOBJECT },
        },
    );

    const type_hash2 = try cdb.addType(
        db,
        "foo2",
        &.{
            .{ .prop_idx = 0, .name = "prop1", .type = public.PropType.SUBOBJECT },
        },
    );

    const obj1 = try cdb.createObject(db, type_hash);

    const sub_obj1 = try cdb.createObject(db, type_hash2);

    {
        const writer = cdb.writeObj(obj1).?;

        const sub_writer = cdb.writeObj(sub_obj1).?;

        try cdb.setSubObj(writer, 0, sub_writer);

        try cdb.writeCommit(sub_writer);
        try cdb.writeCommit(writer);
    }

    // Test if destroy subobjects set parent property to 0
    cdb.destroyObject(sub_obj1);

    try cdb.gc(std.testing.allocator, db);
    try expectGCStats(db, 2, 3);

    const obj_reader = cdb.readObj(obj1).?;
    const sub_obj1_read = cdb.readSubObj(obj_reader, 0);
    try std.testing.expectEqual(@as(?public.ObjId, null), sub_obj1_read);

    cdb.destroyObject(obj1);
    try cdb.gc(std.testing.allocator, db);
    try expectGCStats(db, 2, 1);
}

test "cdb: Should read/write subobj set property " {
    try testInit();
    defer testDeinit();

    const db = try cdb.createDb("Test");
    defer cdb.destroyDb(db);

    const type_hash = try cdb.addType(
        db,
        "foo",
        &.{
            .{ .prop_idx = 0, .name = "prop1", .type = public.PropType.SUBOBJECT_SET },
        },
    );

    const obj1 = try cdb.createObject(db, type_hash);
    const sub_obj1 = try cdb.createObject(db, type_hash);
    const sub_obj2 = try cdb.createObject(db, type_hash);

    var obj_reader = cdb.readObj(obj1);
    try std.testing.expect(obj_reader != null);

    {
        const writer = cdb.writeObj(obj1).?;
        const sub_obj1_writer = cdb.writeObj(sub_obj1).?;
        const sub_obj2_writer = cdb.writeObj(sub_obj2).?;

        try cdb.addSubObjToSet(writer, 0, &[_]*public.Obj{ sub_obj1_writer, sub_obj2_writer });

        try cdb.writeCommit(sub_obj2_writer);
        try cdb.writeCommit(sub_obj1_writer);
        try cdb.writeCommit(writer);
    }

    obj_reader = cdb.readObj(obj1);
    try std.testing.expect(obj_reader != null);

    var set = try cdb.readSubObjSet(obj_reader.?, 0, std.testing.allocator);

    try std.testing.expect(set != null);
    try std.testing.expectEqualSlices(
        public.ObjId,
        &[_]public.ObjId{ sub_obj1, sub_obj2 },
        set.?,
    );

    std.testing.allocator.free(set.?);

    // Remove object
    {
        const writer = cdb.writeObj(obj1).?;
        const sub_obj1_writer = cdb.writeObj(sub_obj1).?;

        try cdb.removeFromSubObjSet(writer, 0, sub_obj1_writer);

        try cdb.writeCommit(sub_obj1_writer);
        try cdb.writeCommit(writer);
    }

    obj_reader = cdb.readObj(obj1);
    try std.testing.expect(obj_reader != null);

    set = try cdb.readSubObjSet(obj_reader.?, 0, std.testing.allocator);

    try std.testing.expect(set != null);
    try std.testing.expectEqualSlices(
        public.ObjId,
        &[_]public.ObjId{sub_obj2},
        set.?,
    );

    std.testing.allocator.free(set.?);

    cdb.destroyObject(sub_obj1);
    cdb.destroyObject(sub_obj2);

    // object is removed from parent after gc
    try cdb.gc(std.testing.allocator, db);
    try expectGCStats(db, 3, 7);

    obj_reader = cdb.readObj(obj1);
    set = try cdb.readSubObjSet(obj_reader.?, 0, std.testing.allocator);
    try std.testing.expect(set != null);
    try std.testing.expectEqualSlices(
        public.ObjId,
        &[_]public.ObjId{},
        set.?,
    );

    std.testing.allocator.free(set.?);

    cdb.destroyObject(obj1);
    try cdb.gc(std.testing.allocator, db);
    try expectGCStats(db, 3, 1);
}

test "cdb: Should read/write reference property" {
    try testInit();
    defer testDeinit();

    const db = try cdb.createDb("Test");
    defer cdb.destroyDb(db);

    const type_hash = try cdb.addType(
        db,
        "foo",
        &.{
            .{ .prop_idx = 0, .name = "prop1", .type = public.PropType.REFERENCE },
        },
    );

    const obj1 = try cdb.createObject(db, type_hash);

    const ref_obj1 = try cdb.createObject(db, type_hash);

    var obj_reader = cdb.readObj(obj1);
    try std.testing.expect(obj_reader != null);

    {
        const writer = cdb.writeObj(obj1).?;
        try cdb.setRef(writer, 0, ref_obj1);
        try cdb.writeCommit(writer);
    }

    obj_reader = cdb.readObj(obj1);
    try std.testing.expect(obj_reader != null);

    const value = cdb.readRef(obj_reader.?, 0);
    try std.testing.expect(value != null);
    try std.testing.expectEqual(ref_obj1, value.?);

    // Ref has obj1 as referencer
    var referencer_set = try cdb.getReferencerSet(std.testing.allocator, ref_obj1);
    try std.testing.expectEqualSlices(
        public.ObjId,
        &[_]public.ObjId{obj1},
        referencer_set,
    );
    std.testing.allocator.free(referencer_set);

    // Delete object does not delete reference.
    cdb.destroyObject(obj1);
    try cdb.gc(std.testing.allocator, db);

    obj_reader = cdb.readObj(obj1);
    try std.testing.expectEqual(@as(?*public.Obj, null), obj_reader);

    obj_reader = cdb.readObj(ref_obj1);
    try std.testing.expect(obj_reader != null);

    // Ref has empty referencers
    referencer_set = try cdb.getReferencerSet(std.testing.allocator, ref_obj1);
    try std.testing.expectEqualSlices(
        public.ObjId,
        &[_]public.ObjId{},
        referencer_set,
    );
    std.testing.allocator.free(referencer_set);

    // if refcounter work good we can delete object. if not shit hapends and you have bad day.
    cdb.destroyObject(ref_obj1);
    try cdb.gc(std.testing.allocator, db);
    try expectGCStats(db, 2, 1);

    obj_reader = cdb.readObj(ref_obj1);
    try std.testing.expect(obj_reader == null);

    try cdb.gc(std.testing.allocator, db);
    try expectGCStats(db, 2, 0);
}

test "cdb: Should read/write reference set property " {
    try testInit();
    defer testDeinit();

    const db = try cdb.createDb("Test");
    defer cdb.destroyDb(db);

    const type_hash = try cdb.addType(
        db,
        "foo",
        &.{
            .{ .prop_idx = 0, .name = "prop1", .type = public.PropType.REFERENCE_SET },
        },
    );

    const obj1 = try cdb.createObject(db, type_hash);
    const ref_obj1 = try cdb.createObject(db, type_hash);
    const ref_obj2 = try cdb.createObject(db, type_hash);

    var obj_reader = cdb.readObj(obj1);
    try std.testing.expect(obj_reader != null);

    {
        const writer = cdb.writeObj(obj1).?;
        try cdb.addRefToSet(writer, 0, &[_]public.ObjId{ ref_obj1, ref_obj2 });

        // try add same items
        try cdb.addRefToSet(writer, 0, &[_]public.ObjId{ ref_obj1, ref_obj2 });
        try cdb.writeCommit(writer);
    }

    obj_reader = cdb.readObj(obj1);
    try std.testing.expect(obj_reader != null);

    var set = cdb.readRefSet(obj_reader.?, 0, std.testing.allocator);
    try std.testing.expect(set != null);
    try std.testing.expectEqualSlices(
        public.ObjId,
        &[_]public.ObjId{ ref_obj1, ref_obj2 },
        set.?,
    );
    std.testing.allocator.free(set.?);

    // Ref1 has obj1 as referencer
    var referencer_set = try cdb.getReferencerSet(std.testing.allocator, ref_obj1);
    try std.testing.expectEqualSlices(
        public.ObjId,
        &[_]public.ObjId{obj1},
        referencer_set,
    );
    std.testing.allocator.free(referencer_set);
    // Ref2 has obj1 as referencer
    referencer_set = try cdb.getReferencerSet(std.testing.allocator, ref_obj2);
    try std.testing.expectEqualSlices(
        public.ObjId,
        &[_]public.ObjId{obj1},
        referencer_set,
    );
    std.testing.allocator.free(referencer_set);

    const writer = cdb.writeObj(obj1).?;
    try cdb.removeFromRefSet(writer, 0, ref_obj1);
    try cdb.writeCommit(writer);

    obj_reader = cdb.readObj(obj1);
    try std.testing.expect(obj_reader != null);

    set = cdb.readRefSet(obj_reader.?, 0, std.testing.allocator);
    try std.testing.expect(set != null);
    try std.testing.expectEqualSlices(
        public.ObjId,
        &[_]public.ObjId{ref_obj2},
        set.?,
    );
    std.testing.allocator.free(set.?);

    // Ref1 has empty referencer
    referencer_set = try cdb.getReferencerSet(std.testing.allocator, ref_obj1);
    try std.testing.expectEqualSlices(
        public.ObjId,
        &[_]public.ObjId{},
        referencer_set,
    );
    std.testing.allocator.free(referencer_set);
    // Ref2 has obj1 as referencer
    referencer_set = try cdb.getReferencerSet(std.testing.allocator, ref_obj2);
    try std.testing.expectEqualSlices(
        public.ObjId,
        &[_]public.ObjId{obj1},
        referencer_set,
    );
    std.testing.allocator.free(referencer_set);

    cdb.destroyObject(ref_obj2);
    try cdb.gc(std.testing.allocator, db);
    try expectGCStats(db, 3, 3);

    obj_reader = cdb.readObj(obj1);
    set = cdb.readRefSet(obj_reader.?, 0, std.testing.allocator);
    try std.testing.expect(set != null);
    try std.testing.expectEqualSlices(
        public.ObjId,
        &[_]public.ObjId{},
        set.?,
    );
    std.testing.allocator.free(set.?);

    cdb.destroyObject(ref_obj1);
    cdb.destroyObject(obj1);

    try cdb.gc(std.testing.allocator, db);
    try expectGCStats(db, 3, 2);
}

test "cdb: Should read/write blob property " {
    try testInit();
    defer testDeinit();

    const db = try cdb.createDb("Test");
    defer cdb.destroyDb(db);

    const type_hash = try cdb.addType(
        db,
        "foo",
        &.{
            .{ .prop_idx = 0, .name = "prop1", .type = public.PropType.BLOB },
        },
    );

    const obj1 = try cdb.createObject(db, type_hash);
    defer cdb.destroyObject(obj1);

    const writer = cdb.writeObj(obj1).?;
    var blob = try cdb.createBlob(writer, 0, 10);

    try std.testing.expect(blob != null);

    for (0..10) |idx| {
        blob.?[idx] = 1;
    }

    try cdb.writeCommit(writer);

    const blob1 = cdb.readBlob(cdb.readObj(obj1).?, 0);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 }, blob1);
}

test "cdb: Should use prototype" {
    try testInit();
    defer testDeinit();

    const db = try cdb.createDb("Test");
    defer cdb.destroyDb(db);

    const type_hash = try cdb.addType(
        db,
        "foo",
        &.{
            .{ .prop_idx = 0, .name = "prop1", .type = public.PropType.F64 },
        },
    );

    const obj1 = try cdb.createObject(db, type_hash);
    var obj1_w = cdb.writeObj(obj1).?;
    cdb.setValue(f64, obj1_w, 0, 1);
    try cdb.writeCommit(obj1_w);

    try std.testing.expectEqual(public.ObjId{}, cdb.getPrototype(cdb.readObj(obj1).?));

    const obj2 = try cdb.createObjectFromPrototype(obj1);

    try std.testing.expectEqual(obj1, cdb.getPrototype(cdb.readObj(obj2).?));

    obj1_w = cdb.writeObj(obj1).?;
    cdb.setValue(f64, obj1_w, 0, 2);
    try cdb.writeCommit(obj1_w);

    try std.testing.expect(!cdb.isPropertyOverrided(cdb.readObj(obj2).?, 0));

    try std.testing.expectEqual(
        @as(f64, 2),
        cdb.readValue(f64, cdb.readObj(obj2).?, 0),
    );

    // if change property on instance we read from this not prototypes
    var obj2_w = cdb.writeObj(obj2).?;
    cdb.setValue(f64, obj2_w, 0, 3);
    try cdb.writeCommit(obj2_w);

    try std.testing.expect(cdb.isPropertyOverrided(cdb.readObj(obj2).?, 0));

    try std.testing.expectEqual(
        @as(f64, 3),
        cdb.readValue(f64, cdb.readObj(obj2).?, 0),
    );

    // is possible to reset override flag.
    obj2_w = cdb.writeObj(obj2).?;
    cdb.resetPropertyOveride(obj2_w, 0);
    try cdb.writeCommit(obj2_w);

    try std.testing.expectEqual(
        @as(f64, 2),
        cdb.readValue(f64, cdb.readObj(obj2).?, 0),
    );

    cdb.destroyObject(obj1);
    cdb.destroyObject(obj2);

    try cdb.gc(std.testing.allocator, db);
    try expectGCStats(db, 2, 6);
}

test "cdb: Should use prototype on sets" {
    try testInit();
    defer testDeinit();

    const db = try cdb.createDb("Test");
    defer cdb.destroyDb(db);

    const type_hash = try cdb.addType(
        db,
        "foo",
        &.{
            .{ .prop_idx = 0, .name = "prop1", .type = public.PropType.REFERENCE_SET },
        },
    );

    const obj1 = try cdb.createObject(db, type_hash);
    const obj2 = try cdb.createObject(db, type_hash);
    const obj3 = try cdb.createObject(db, type_hash);

    const obj1_w = cdb.writeObj(obj1).?;
    try cdb.addRefToSet(obj1_w, 0, &[_]public.ObjId{ obj2, obj3 });
    try cdb.writeCommit(obj1_w);

    const new_obj = try cdb.createObjectFromPrototype(obj1);

    // we see full set from prototype
    var set = cdb.readRefSet(cdb.readObj(new_obj).?, 0, std.testing.allocator);
    try std.testing.expect(set != null);
    try std.testing.expectEqualSlices(
        public.ObjId,
        &[_]public.ObjId{ obj2, obj3 },
        set.?,
    );
    std.testing.allocator.free(set.?);

    // Remove one object fro new set
    var new_obj1_w = cdb.writeObj(new_obj).?;
    try cdb.removeFromRefSet(new_obj1_w, 0, obj2);
    try cdb.writeCommit(new_obj1_w);

    set = cdb.readRefSet(cdb.readObj(new_obj).?, 0, std.testing.allocator);
    try std.testing.expect(set != null);
    try std.testing.expectEqualSlices(
        public.ObjId,
        &[_]public.ObjId{obj3},
        set.?,
    );
    std.testing.allocator.free(set.?);

    // Remove one object fro new set
    new_obj1_w = cdb.writeObj(new_obj).?;
    try cdb.removeFromRefSet(new_obj1_w, 0, obj3);
    try cdb.writeCommit(new_obj1_w);

    set = cdb.readRefSet(cdb.readObj(new_obj).?, 0, std.testing.allocator);
    try std.testing.expect(set != null);
    try std.testing.expectEqualSlices(
        public.ObjId,
        &[_]public.ObjId{},
        set.?,
    );
    std.testing.allocator.free(set.?);

    // Add new objet to instance set
    const obj4 = try cdb.createObject(db, type_hash);
    new_obj1_w = cdb.writeObj(new_obj).?;
    try cdb.addRefToSet(new_obj1_w, 0, &[_]public.ObjId{obj4});
    try cdb.writeCommit(new_obj1_w);

    // Instance see only obj4
    set = cdb.readRefSet(cdb.readObj(new_obj).?, 0, std.testing.allocator);
    try std.testing.expect(set != null);
    try std.testing.expectEqualSlices(
        public.ObjId,
        &[_]public.ObjId{obj4},
        set.?,
    );
    std.testing.allocator.free(set.?);

    // Protoype stil se obj2, obj3
    set = cdb.readRefSet(cdb.readObj(obj1).?, 0, std.testing.allocator);
    try std.testing.expect(set != null);
    try std.testing.expectEqualSlices(
        public.ObjId,
        &[_]public.ObjId{ obj2, obj3 },
        set.?,
    );
    std.testing.allocator.free(set.?);

    cdb.destroyObject(obj1);
    cdb.destroyObject(obj2);
    cdb.destroyObject(obj3);
    cdb.destroyObject(new_obj);
    cdb.destroyObject(obj4);

    try cdb.gc(std.testing.allocator, db);
    try expectGCStats(db, 5, 9);
}

test "cdb: Should instantiate subobject" {
    try testInit();
    defer testDeinit();

    const db = try cdb.createDb("Test");
    defer cdb.destroyDb(db);

    const type_hash = try cdb.addType(
        db,
        "foo",
        &.{
            .{ .prop_idx = 0, .name = "prop1", .type = public.PropType.SUBOBJECT },
        },
    );

    const type_hash2 = try cdb.addType(
        db,
        "foo2",
        &.{
            .{ .prop_idx = 0, .name = "prop1", .type = public.PropType.U64 },
        },
    );

    const obj1 = try cdb.createObject(db, type_hash);
    const sub_obj1 = try cdb.createObject(db, type_hash2);

    const obj1_w = cdb.writeObj(obj1).?;
    const sub_obj1_w = cdb.writeObj(sub_obj1).?;
    cdb.setValue(u64, sub_obj1_w, 0, 10);
    try cdb.setSubObj(obj1_w, 0, sub_obj1_w);
    try cdb.writeCommit(sub_obj1_w);
    try cdb.writeCommit(obj1_w);

    const obj2 = try cdb.createObjectFromPrototype(obj1);
    var obj2_sub = cdb.readSubObj(cdb.readObj(obj2).?, 0).?;

    try std.testing.expectEqual(
        @as(u64, 10),
        cdb.readValue(u64, cdb.readObj(obj2_sub).?, 0),
    );

    const obj2_w = cdb.writeObj(obj2).?;
    _ = try cdb.instantiateSubObj(obj2_w, 0);
    try cdb.writeCommit(obj2_w);

    try std.testing.expect(cdb.isPropertyOverrided(cdb.readObj(obj2).?, 0));

    obj2_sub = cdb.readSubObj(cdb.readObj(obj2).?, 0).?;
    const sub_obj2_w = cdb.writeObj(obj2_sub).?;
    cdb.setValue(u64, sub_obj2_w, 0, 20);
    try cdb.writeCommit(sub_obj2_w);

    try std.testing.expectEqual(
        @as(u64, 10),
        cdb.readValue(u64, cdb.readObj(sub_obj1).?, 0),
    );

    try std.testing.expectEqual(
        @as(u64, 20),
        cdb.readValue(u64, cdb.readObj(obj2_sub).?, 0),
    );

    cdb.destroyObject(obj1);
    cdb.destroyObject(obj2);

    try cdb.gc(std.testing.allocator, db);
    try expectGCStats(db, 4, 8);
}

test "cdb: Should deep instantiate subobject" {
    try testInit();
    defer testDeinit();

    const db = try cdb.createDb("Test");
    defer cdb.destroyDb(db);

    const type_hash = try cdb.addType(
        db,
        "foo",
        &.{
            .{ .prop_idx = 0, .name = "prop1", .type = public.PropType.SUBOBJECT },
            .{ .prop_idx = 1, .name = "prop2", .type = public.PropType.F64 },
        },
    );

    const obj1 = try cdb.createObject(db, type_hash);
    const sub_obj1 = try cdb.createObject(db, type_hash);
    const sub_obj2 = try cdb.createObject(db, type_hash);

    const obj1_w = cdb.writeObj(obj1).?;
    const sub_obj1_w = cdb.writeObj(sub_obj1).?;
    const sub_obj2_w = cdb.writeObj(sub_obj2).?;
    try cdb.setSubObj(obj1_w, 0, sub_obj1_w);
    try cdb.setSubObj(sub_obj1_w, 0, sub_obj2_w);

    cdb.setValue(f64, sub_obj1_w, 1, 666);
    cdb.setValue(f64, sub_obj2_w, 1, 666);

    try cdb.writeCommit(sub_obj1_w);
    try cdb.writeCommit(sub_obj2_w);
    try cdb.writeCommit(obj1_w);

    const obj2 = try cdb.createObjectFromPrototype(obj1);

    const instasiated_obj = cdb.inisitateDeep(std.testing.allocator, obj2, sub_obj2);
    try std.testing.expect(instasiated_obj != null);

    const instasiated_obj_w = cdb.writeObj(instasiated_obj.?).?;
    cdb.setValue(f64, instasiated_obj_w, 1, 22);
    try cdb.writeCommit(instasiated_obj_w);

    const sub_obj2_r = cdb.readObj(sub_obj2).?;
    const prop2_value = cdb.readValue(f64, sub_obj2_r, 1);
    try std.testing.expectEqual(666, prop2_value);

    cdb.destroyObject(obj1);
    cdb.destroyObject(obj2);

    try cdb.gc(std.testing.allocator, db);
    try expectGCStats(db, 6, 6);
}

test "cdb: Should deep instantiate subobject in set" {
    try testInit();
    defer testDeinit();

    const db = try cdb.createDb("Test");
    defer cdb.destroyDb(db);

    const type_hash = try cdb.addType(
        db,
        "foo",
        &.{
            .{ .prop_idx = 0, .name = "prop1", .type = public.PropType.SUBOBJECT },
            .{ .prop_idx = 1, .name = "prop2", .type = public.PropType.F64 },
            .{ .prop_idx = 2, .name = "prop3", .type = public.PropType.SUBOBJECT_SET },
        },
    );

    const obj1 = try cdb.createObject(db, type_hash);
    const sub_obj1 = try cdb.createObject(db, type_hash);
    const sub_obj2 = try cdb.createObject(db, type_hash);

    const obj1_w = cdb.writeObj(obj1).?;
    const sub_obj1_w = cdb.writeObj(sub_obj1).?;
    const sub_obj2_w = cdb.writeObj(sub_obj2).?;
    try cdb.setSubObj(obj1_w, 0, sub_obj1_w);

    try cdb.addSubObjToSet(sub_obj1_w, 2, &.{sub_obj2_w});

    cdb.setValue(f64, sub_obj2_w, 1, 666);

    try cdb.writeCommit(sub_obj1_w);
    try cdb.writeCommit(sub_obj2_w);
    try cdb.writeCommit(obj1_w);

    const obj2 = try cdb.createObjectFromPrototype(obj1);

    const instasiated_obj = cdb.inisitateDeep(std.testing.allocator, obj2, sub_obj2);
    try std.testing.expect(instasiated_obj != null);

    const instasiated_obj_w = cdb.writeObj(instasiated_obj.?).?;
    cdb.setValue(f64, instasiated_obj_w, 1, 22);
    try cdb.writeCommit(instasiated_obj_w);

    const sub_obj2_r = cdb.readObj(sub_obj2).?;
    const prop2_value = cdb.readValue(f64, sub_obj2_r, 1);
    try std.testing.expectEqual(666, prop2_value);

    cdb.destroyObject(obj1);
    cdb.destroyObject(obj2);

    try cdb.gc(std.testing.allocator, db);
    try expectGCStats(db, 6, 6);
}

test "cdb: Should specify type_hash for ref/subobj base properties" {
    try testInit();
    defer testDeinit();

    const db = try cdb.createDb("Test");
    defer cdb.destroyDb(db);

    const sub_type_hash = try cdb.addType(
        db,
        "foo2",
        &.{
            .{ .prop_idx = 0, .name = "prop1", .type = public.PropType.U64 },
        },
    );

    const another_sub_type_hash = try cdb.addType(
        db,
        "foo3",
        &.{
            .{ .prop_idx = 0, .name = "prop1", .type = public.PropType.U64 },
        },
    );

    const type_hash = try cdb.addType(
        db,
        "foo",
        &.{
            .{ .prop_idx = 0, .name = "prop1", .type = public.PropType.SUBOBJECT, .type_hash = strId32("foo2") },
            .{ .prop_idx = 1, .name = "prop2", .type = public.PropType.REFERENCE, .type_hash = strId32("foo2") },
            .{ .prop_idx = 2, .name = "prop3", .type = public.PropType.SUBOBJECT_SET, .type_hash = strId32("foo2") },
            .{ .prop_idx = 3, .name = "prop4", .type = public.PropType.REFERENCE_SET, .type_hash = strId32("foo2") },
        },
    );

    const obj1 = try cdb.createObject(db, type_hash);
    const sub_obj1 = try cdb.createObject(db, sub_type_hash);
    const sub_obj2 = try cdb.createObject(db, another_sub_type_hash);

    const obj1_w = cdb.writeObj(obj1).?;
    const sub_obj2_w = cdb.writeObj(sub_obj2).?;

    try cdb.setSubObj(obj1_w, 0, sub_obj2_w);
    try cdb.setRef(obj1_w, 1, sub_obj2);
    try cdb.addSubObjToSet(obj1_w, 2, &[_]*public.Obj{sub_obj2_w});
    try cdb.addRefToSet(obj1_w, 3, &[_]public.ObjId{sub_obj2});

    try std.testing.expect(cdb.readSubObj(cdb.readObj(obj1).?, 0) == null);
    try std.testing.expect(cdb.readRef(cdb.readObj(obj1).?, 1) == null);

    var set = try cdb.readSubObjSet(cdb.readObj(obj1).?, 2, std.testing.allocator);
    try std.testing.expect(set != null);
    try std.testing.expect(set.?.len == 0);
    std.testing.allocator.free(set.?);

    set = cdb.readRefSet(cdb.readObj(obj1).?, 3, std.testing.allocator);
    try std.testing.expect(set != null);
    try std.testing.expect(set.?.len == 0);
    std.testing.allocator.free(set.?);

    try cdb.writeCommit(sub_obj2_w);
    try cdb.writeCommit(obj1_w);

    cdb.destroyObject(obj1);
    cdb.destroyObject(sub_obj1);
    cdb.destroyObject(sub_obj2);

    try cdb.gc(std.testing.allocator, db);
    try expectGCStats(db, 3, 5);
}

test "cdb: Should tracking changed objects" {
    try testInit();
    defer testDeinit();

    const db = try cdb.createDb("Test");
    defer cdb.destroyDb(db);

    const type_hash = try cdb.addType(
        db,
        "foo",
        &.{
            .{ .prop_idx = 0, .name = "prop1", .type = public.PropType.BOOL },
            .{ .prop_idx = 1, .name = "prop2", .type = public.PropType.BOOL },
        },
    );

    const obj1 = try cdb.createObject(db, type_hash);
    const obj2 = try cdb.createObject(db, type_hash);

    // Make some changes to obj1 and 2
    const obj1_w = cdb.writeObj(obj1).?;
    cdb.setValue(bool, obj1_w, 0, true);
    try cdb.writeCommit(obj1_w);

    const obj2_w = cdb.writeObj(obj2).?;
    cdb.setValue(bool, obj2_w, 0, true);
    try cdb.writeCommit(obj2_w);
    // Call GC thas create populate changed objects.
    try cdb.gc(std.testing.allocator, db);
    const changed_1 = try cdb.getChangeObjects(std.testing.allocator, db, type_hash, 1);
    defer std.testing.allocator.free(changed_1.objects);
    try std.testing.expectEqualSlices(public.ObjId, &.{ obj1, obj2 }, changed_1.objects);
    try std.testing.expect(!changed_1.need_fullscan);

    // get from 0 version force to do fullscan
    const changed_0 = try cdb.getChangeObjects(std.testing.allocator, db, type_hash, 0);
    defer std.testing.allocator.free(changed_0.objects);
    try std.testing.expect(changed_0.need_fullscan);

    // Destroy object
    cdb.destroyObject(obj2);
    // Call GC thas create populate changed objects.
    try cdb.gc(std.testing.allocator, db);
    const changed_2 = try cdb.getChangeObjects(std.testing.allocator, db, type_hash, changed_0.last_version);
    defer std.testing.allocator.free(changed_2.objects);
    try std.testing.expect(!changed_2.need_fullscan);
    try std.testing.expectEqualSlices(public.ObjId, &.{obj2}, changed_2.objects);

    const changed_begin = try cdb.getChangeObjects(std.testing.allocator, db, type_hash, 1);
    defer std.testing.allocator.free(changed_begin.objects);
    try std.testing.expect(!changed_begin.need_fullscan);
    try std.testing.expectEqualSlices(public.ObjId, &.{ obj1, obj2, obj2 }, changed_begin.objects);
}

test "cdb: Should get object realtion" {
    try testInit();
    defer testDeinit();

    const db = try cdb.createDb("Test");
    defer cdb.destroyDb(db);

    const type_hash = try cdb.addType(
        db,
        "foo",
        &.{
            .{ .prop_idx = 0, .name = "prop1", .type = public.PropType.F64 },
            .{ .prop_idx = 1, .name = "prop2", .type = public.PropType.SUBOBJECT },
        },
    );

    const obj1 = try cdb.createObject(db, type_hash);
    const obj2 = try cdb.createObjectFromPrototype(obj1);
    const obj3 = try cdb.createObject(db, type_hash);

    const obj1_w = cdb.writeObj(obj1).?;
    const obj3_w = cdb.writeObj(obj3).?;
    try cdb.setSubObj(obj1_w, 1, obj3_w);
    try cdb.writeCommit(obj1_w);
    try cdb.writeCommit(obj3_w);

    const obj1_r = cdb.readObj(obj1).?;
    _ = obj1_r;
    const obj2_r = cdb.readObj(obj2).?;
    _ = obj2_r;
    const obj3_r = cdb.readObj(obj3).?;
    _ = obj3_r;

    // // Obj2 does not have relation with Obj3
    // try std.testing.expectEqual(.none, db.getRelation(obj2_r, obj3_r));

    // // Obj3 does not have relation with Obj2
    // try std.testing.expectEqual(.none, db.getRelation(obj3_r, obj2_r));

    // // Obj1 is prototype for Obj2
    // try std.testing.expectEqual(.prototype, db.getRelation(obj1_r, obj2_r));

    // // Obj1 is parent for Obj3
    // try std.testing.expectEqual(.parent, db.getRelation(obj1_r, obj3_r));

    cdb.destroyObject(obj1);
    cdb.destroyObject(obj2);
    cdb.destroyObject(obj3);

    try cdb.gc(std.testing.allocator, db);
    try expectGCStats(db, 3, 5);
}

fn stressTest(comptime task_count: u32, task_based: bool) !void {
    const db = try cdb.createDb("Test");
    defer cdb.destroyDb(db);

    const type_hash = try cetech1.cdb_types.addBigType(db, "foo", null);
    const type_hash2 = try cetech1.cdb_types.addBigType(db, "foo2", null);

    const ref_obj1 = try cdb.createObject(db, type_hash2);
    if (task_based) {
        var tasks: [task_count]cetech1.task.TaskID = undefined;

        const Task = struct {
            db: cdb.DbId,
            ref_obj1: cdb.ObjId,
            type_hash: cdb.TypeIdx,
            type_hash2: cdb.TypeIdx,
            pub fn exec(self: *@This()) !void {
                cdb.stressIt(
                    self.db,
                    self.type_hash,
                    self.type_hash2,
                    self.ref_obj1,
                ) catch undefined;
            }
        };

        for (0..task_count) |idx| {
            tasks[idx] = try task.schedule(
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

        task.waitMany(&tasks);
    } else {
        for (0..task_count) |_| {
            try cdb.stressIt(
                db,
                type_hash,
                type_hash2,
                ref_obj1,
            );
        }
    }

    cdb.destroyObject(ref_obj1);

    var true_db = cdb_private.toDbFromDbT(db);
    const storage = true_db.getTypeStorageByTypeIdx(type_hash).?;
    try std.testing.expectEqual(@as(u32, task_count + 1), storage.objid_pool.count.raw);
    try std.testing.expectEqual(@as(u32, task_count * 3), true_db.writersCount());
    try std.testing.expectEqual(@as(u32, task_count * 3), true_db.commitCount());

    cdb.destroyObject(ref_obj1);

    try cdb.gc(std.testing.allocator, db);
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
