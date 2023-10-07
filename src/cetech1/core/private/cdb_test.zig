const builtin = @import("builtin");
const std = @import("std");

const public = @import("../cdb.zig");
const cdb = @import("cdb.zig");

const c = @import("../c.zig");
const cetech1 = @import("../cetech1.zig");

const StrId32 = @import("../strid.zig").StrId32;
const strId32 = @import("../strid.zig").strId32;

const log = @import("log.zig");
const apidb = @import("apidb.zig");
const profiler = @import("profiler.zig");
const task = @import("task.zig");
const uuid = @import("uuid.zig");

pub fn testInit() !void {
    try task.init(std.testing.allocator);
    try apidb.init(std.testing.allocator);
    try cdb.init(std.testing.allocator);
    try task.start();
}

pub fn testDeinit() void {
    cdb.deinit();
    apidb.deinit();
    task.deinit();
}

fn expectGCStats(db: cetech1.cdb.CdbDb, alocated: u32, free: u32) !void {
    var true_db = cdb.toDbFromDbT(db.db);
    try std.testing.expectEqual(alocated, true_db.obj_alocated);
    try std.testing.expectEqual(@as(u32, free), true_db.free_objects);
}

test "cdb: Should create cdb DB" {
    try testInit();
    defer testDeinit();

    var db = try cdb.api.createDb("Test");
    defer cdb.api.destroyDb(db);
}

test "cdb: Should register type" {
    try testInit();
    defer testDeinit();

    var db = try cdb.api.createDb("Test");
    defer cdb.api.destroyDb(db);

    const type_hash = try db.addType(
        "foo",
        &.{},
    );

    try std.testing.expectEqual(strId32("foo").id, type_hash.id);

    var props = db.getTypePropDef(type_hash);
    try std.testing.expect(props != null);

    const expected_num: u32 = 0;
    _ = expected_num;
    try std.testing.expectEqual(@as(usize, 0), props.?.len);
}

test "cdb: Should register create types handler " {
    try testInit();
    defer testDeinit();

    const Handler = struct {
        pub fn load_types(db_: ?*c.c.struct_ct_cdb_db_t) callconv(.C) void {
            var db = public.CdbDb.fromDbT(@ptrCast(db_), &cdb.api);

            const type_hash = db.addType(
                "foo",
                &.{
                    .{ .name = "prop1", .type = public.PropType.F32 },
                    .{ .name = "prop2", .type = public.PropType.F64 },
                },
            ) catch unreachable;
            _ = type_hash;
        }
    };
    var create_types_i = c.c.ct_cdb_create_types_i{ .create_types = Handler.load_types };

    try apidb.api.implOrRemove(c.c.ct_cdb_create_types_i, &create_types_i, true);

    var db = try cdb.api.createDb("Test");
    defer cdb.api.destroyDb(db);

    const type_hash = strId32("foo");

    var props = db.getTypePropDef(type_hash);
    try std.testing.expect(props != null);
    try std.testing.expectEqual(@as(usize, 2), props.?.len);
}

test "cdb: Should register aspect" {
    try testInit();
    defer testDeinit();

    const FooAspect = struct {
        const Self = @This();
        barFn: *const fn (db_: ?*public.Db) callconv(.C) void,

        pub fn barImpl(db_: ?*public.Db) callconv(.C) void {
            var db = public.CdbDb.fromDbT(@ptrCast(db_), &cdb.api);
            _ = db;
        }

        pub fn bar(self: *Self, db_: ?*public.Db) void {
            return self.barFn(db_);
        }
    };

    var foo_aspect = FooAspect{ .barFn = &FooAspect.barImpl };

    const Handler = struct {
        pub fn load_types(db_: ?*public.Db) callconv(.C) void {
            var db = public.CdbDb.fromDbT(@ptrCast(db_), &cdb.api);

            const type_hash = db.addType(
                "foo",
                &.{
                    .{ .name = "prop1", .type = public.PropType.F32 },
                    .{ .name = "prop2", .type = public.PropType.F32 },
                },
            ) catch unreachable;
            _ = type_hash;
        }
    };
    var create_types_i = c.c.ct_cdb_create_types_i{ .create_types = @ptrCast(&Handler.load_types) };
    try apidb.api.implOrRemove(c.c.ct_cdb_create_types_i, &create_types_i, true);

    var db = try cdb.api.createDb("Test");
    defer cdb.api.destroyDb(db);

    const type_hash = strId32("foo");

    var aspect = db.getAspect(FooAspect, type_hash);
    try std.testing.expect(aspect == null);

    try db.addAspect(FooAspect, type_hash, &foo_aspect);

    aspect = db.getAspect(FooAspect, type_hash);
    try std.testing.expect(aspect != null);
    try std.testing.expectEqual(&foo_aspect, aspect.?);

    aspect.?.bar(db.db);
}

test "cdb: Should register property aspect" {
    try testInit();
    defer testDeinit();

    const FooAspect = struct {
        const Self = @This();
        barFn: *const fn (db_: ?*public.Db) callconv(.C) void,

        pub fn barImpl(db_: ?*public.Db) callconv(.C) void {
            var db = public.CdbDb.fromDbT(@ptrCast(db_), &cdb.api);
            _ = db;
        }

        pub fn bar(self: *Self, db_: ?*public.Db) void {
            return self.barFn(db_);
        }
    };

    var foo_aspect = FooAspect{ .barFn = &FooAspect.barImpl };

    const Handler = struct {
        pub fn load_types(db_: ?*public.Db) callconv(.C) void {
            var db = public.CdbDb.fromDbT(@ptrCast(db_), &cdb.api);

            const type_hash = db.addType(
                "foo",
                &.{
                    .{ .name = "prop1", .type = public.PropType.F32 },
                    .{ .name = "prop2", .type = public.PropType.F32 },
                },
            ) catch unreachable;
            _ = type_hash;
        }
    };
    var create_types_i = c.c.ct_cdb_create_types_i{ .create_types = @ptrCast(&Handler.load_types) };
    try apidb.api.implOrRemove(c.c.ct_cdb_create_types_i, &create_types_i, true);

    var db = try cdb.api.createDb("Test");
    defer cdb.api.destroyDb(db);

    const type_hash = strId32("foo");

    var aspect = db.getPropertyAspect(FooAspect, type_hash, 0);
    try std.testing.expect(aspect == null);
    aspect = db.getPropertyAspect(FooAspect, type_hash, 1);
    try std.testing.expect(aspect == null);

    try db.addPropertyAspect(FooAspect, type_hash, 1, &foo_aspect);

    aspect = db.getPropertyAspect(FooAspect, type_hash, 0);
    try std.testing.expect(aspect == null);

    aspect = db.getPropertyAspect(FooAspect, type_hash, 1);
    try std.testing.expect(aspect != null);
    try std.testing.expectEqual(&foo_aspect, aspect.?);

    aspect.?.bar(db.db);
}

test "cdb: Should create object from type" {
    try testInit();
    defer testDeinit();

    var db = try cdb.api.createDb("Test");
    defer cdb.api.destroyDb(db);

    const type_hash = try db.addType(
        "foo",
        &.{},
    );

    var obj1 = try db.createObject(type_hash);
    var obj2 = try db.createObject(type_hash);

    try std.testing.expectEqual(type_hash.id, obj1.type_hash.id);
    try std.testing.expectEqual(type_hash.id, obj2.type_hash.id);
    try std.testing.expect(obj1.id != obj2.id);

    db.destroyObject(obj1);
    db.destroyObject(obj2);

    try db.gc(std.testing.allocator);
    try expectGCStats(db, 2, 2);
}

test "cdb: Should create object from type with uuid" {
    try testInit();
    defer testDeinit();

    var db = try cdb.api.createDb("Test");
    defer cdb.api.destroyDb(db);

    const type_hash = try db.addType(
        "foo",
        &.{},
    );

    var uuid1 = uuid.api.newUUID7();
    var obj1 = try db.createObjectWithUuid(type_hash, uuid1);
    var obj1_uuid = db.getObjUuid(obj1);

    try std.testing.expectEqualSlices(u8, &uuid1.bytes, &obj1_uuid.bytes);

    db.destroyObject(obj1);

    try db.gc(std.testing.allocator);
    try expectGCStats(db, 1, 1);
}

test "cdb: Should find objid by uuid" {
    try testInit();
    defer testDeinit();

    var db = try cdb.api.createDb("Test");
    defer cdb.api.destroyDb(db);

    const type_hash = try db.addType(
        "foo",
        &.{},
    );

    var uuid1 = uuid.api.newUUID7();
    var obj1 = try db.createObjectWithUuid(type_hash, uuid1);

    var obj2 = try db.createObject(type_hash);
    var uuid2 = db.getObjUuid(obj2);

    try std.testing.expectEqual(obj1, db.getObjIdFromUuid(uuid1).?);
    try std.testing.expectEqual(obj2, db.getObjIdFromUuid(uuid2).?);

    db.destroyObject(obj1);
    db.destroyObject(obj2);

    try db.gc(std.testing.allocator);
    try expectGCStats(db, 2, 2);
}

test "cdb: Should create object from default obj" {
    try testInit();
    defer testDeinit();

    var db = try cdb.api.createDb("Test");
    defer cdb.api.destroyDb(db);

    const type_hash = try db.addType(
        "foo",
        &.{
            .{ .name = "prop1", .type = public.PropType.U64 },
        },
    );

    var obj1 = try db.createObject(type_hash);

    {
        var w = db.writeObj(obj1).?;
        defer db.writeCommit(w);
        db.setValue(u64, w, 0, 20);
    }

    db.setDefaultObject(obj1);

    var obj2 = try db.createObject(type_hash);
    try std.testing.expectEqual(@as(u64, 20), db.readValue(u64, db.readObj(obj2).?, 0));

    db.destroyObject(obj1);
    db.destroyObject(obj2);

    try db.gc(std.testing.allocator);
    try expectGCStats(db, 2, 3);
}

test "cdb: Should clone object" {
    try testInit();
    defer testDeinit();

    var db = try cdb.api.createDb("Test");
    defer cdb.api.destroyDb(db);

    const type_hash = try db.addType(
        "foo",
        &.{
            .{ .name = "prop1", .type = public.PropType.U64 },
        },
    );

    var obj1 = try db.createObject(type_hash);

    {
        var w = db.writeObj(obj1).?;
        defer db.writeCommit(w);
        db.setValue(u64, w, 0, 10);
    }

    var obj2 = try db.cloneObject(obj1);

    try std.testing.expectEqual(type_hash.id, obj1.type_hash.id);
    try std.testing.expectEqual(obj1.type_hash.id, obj2.type_hash.id);
    try std.testing.expect(obj1.id != obj2.id);

    try std.testing.expectEqual(@as(u64, 10), db.readValue(u64, db.readObj(obj2).?, 0));

    {
        var w = db.writeObj(obj2).?;
        defer db.writeCommit(w);
        db.setValue(u64, w, 0, 20);
    }

    try std.testing.expectEqual(@as(u64, 10), db.readValue(u64, db.readObj(obj1).?, 0));
    try std.testing.expectEqual(@as(u64, 20), db.readValue(u64, db.readObj(obj2).?, 0));

    db.destroyObject(obj1);
    db.destroyObject(obj2);

    try db.gc(std.testing.allocator);
    try expectGCStats(db, 2, 4);
}

test "cdb: Should create retarget write" {
    try testInit();
    defer testDeinit();

    var db = try cdb.api.createDb("Test");
    defer cdb.api.destroyDb(db);

    const type_hash = try db.addType(
        "foo",
        &.{
            .{ .name = "prop1", .type = public.PropType.U64 },
        },
    );

    var obj1 = try db.createObject(type_hash);
    var obj2 = try db.createObject(type_hash);

    var obj1_w = db.writeObj(obj1).?;
    db.setValue(u64, obj1_w, 0, 11);
    db.writeCommit(obj1_w);

    var obj2_w = db.writeObj(obj2).?;
    db.setValue(u64, obj2_w, 0, 22);
    db.writeCommit(obj2_w);

    obj1_w = db.writeObj(obj1).?;
    db.setValue(u64, obj1_w, 0, 42);
    db.retargetWrite(obj1_w, obj2);
    db.writeCommit(obj1_w);

    var value = db.readValue(u64, db.readObj(obj2).?, 0);

    try std.testing.expectEqual(@as(u64, 42), value);

    db.destroyObject(obj1);
    db.destroyObject(obj2);

    try db.gc(std.testing.allocator);
    try expectGCStats(db, 2, 5);
}

fn testNumericValues(
    comptime T: type,
    db: *cetech1.cdb.CdbDb,
    type_hash: cetech1.strid.StrId32,
) !void {
    var obj1 = try db.createObject(type_hash);

    var obj_reader = db.readObj(obj1);
    try std.testing.expect(obj_reader != null);

    var value = db.readValue(T, obj_reader.?, 0);
    try std.testing.expectEqual(@as(T, 0), value);

    value = db.readValue(T, obj_reader.?, 1);
    try std.testing.expectEqual(@as(T, 0), value);

    {
        var writer = db.writeObj(obj1).?;
        defer db.writeCommit(writer);
        db.setValue(T, writer, 0, 1);
    }

    obj_reader = db.readObj(obj1);
    try std.testing.expect(obj_reader != null);

    value = db.readValue(T, obj_reader.?, 0);
    try std.testing.expectEqual(@as(T, 1), value);

    value = db.readValue(T, obj_reader.?, 1);
    try std.testing.expectEqual(@as(T, 0), value);

    {
        var writer = db.writeObj(obj1).?;
        defer db.writeCommit(writer);
        db.setValue(T, writer, 1, 2);
    }

    obj_reader = db.readObj(obj1);
    try std.testing.expect(obj_reader != null);

    value = db.readValue(T, obj_reader.?, 0);
    try std.testing.expectEqual(@as(T, 1), value);

    value = db.readValue(T, obj_reader.?, 1);
    try std.testing.expectEqual(@as(T, 2), value);

    db.destroyObject(obj1);

    try db.gc(std.testing.allocator);
    try expectGCStats(db.*, 1, 3);
}

test "cdb: Should read/write U64 property " {
    try testInit();
    defer testDeinit();

    var db = try cdb.api.createDb("Test");
    defer cdb.api.destroyDb(db);

    const type_hash = try db.addType(
        "foo",
        &.{
            .{ .name = "prop1", .type = public.PropType.U64 },
            .{ .name = "prop2", .type = public.PropType.U64 },
        },
    );

    try testNumericValues(u64, &db, type_hash);
}
test "cdb: Should read/write F64 property " {
    try testInit();
    defer testDeinit();

    var db = try cdb.api.createDb("Test");
    defer cdb.api.destroyDb(db);

    const type_hash = try db.addType(
        "foo",
        &.{
            .{ .name = "prop1", .type = public.PropType.F64 },
            .{ .name = "prop2", .type = public.PropType.F64 },
        },
    );

    try testNumericValues(f64, &db, type_hash);
}

test "cdb: Should read/write F32 property " {
    try testInit();
    defer testDeinit();

    var db = try cdb.api.createDb("Test");
    defer cdb.api.destroyDb(db);

    const type_hash = try db.addType(
        "foo",
        &.{
            .{ .name = "prop1", .type = public.PropType.F32 },
            .{ .name = "prop2", .type = public.PropType.F32 },
        },
    );

    try testNumericValues(f32, &db, type_hash);
}

test "cdb: Should read/write string property " {
    try testInit();
    defer testDeinit();

    var db = try cdb.api.createDb("Test");
    defer cdb.api.destroyDb(db);

    const type_hash = try db.addType(
        "foo",
        &.{
            .{ .name = "prop1", .type = public.PropType.STR },
            .{ .name = "prop2", .type = public.PropType.STR },
        },
    );

    var obj1 = try db.createObject(type_hash);

    var obj_reader = db.readObj(obj1);
    try std.testing.expect(obj_reader != null);

    var value = db.readStr(obj_reader.?, 0);

    {
        var writer = db.writeObj(obj1).?;
        defer db.writeCommit(writer);
        var str = "FOO";
        try db.setStr(writer, 0, str);
    }

    obj_reader = db.readObj(obj1);
    try std.testing.expect(obj_reader != null);

    value = db.readStr(obj_reader.?, 0);
    try std.testing.expect(value != null);
    try std.testing.expectEqualSlices(u8, "FOO", value.?);

    db.destroyObject(obj1);

    try db.gc(std.testing.allocator);
    try expectGCStats(db, 1, 2);
}

test "cdb: Should read/write subobject property " {
    try testInit();
    defer testDeinit();

    var db = try cdb.api.createDb("Test");
    defer cdb.api.destroyDb(db);

    const type_hash = try db.addType(
        "foo",
        &.{
            .{ .name = "prop1", .type = public.PropType.SUBOBJECT },
        },
    );

    const type_hash2 = try db.addType(
        "foo2",
        &.{
            .{ .name = "prop1", .type = public.PropType.F64 },
        },
    );

    var obj1 = try db.createObject(type_hash);
    defer db.destroyObject(obj1);

    var sub_obj1 = try db.createObject(type_hash2);
    defer db.destroyObject(sub_obj1);

    var obj_reader = db.readObj(obj1);
    try std.testing.expect(obj_reader != null);

    {
        var writer = db.writeObj(obj1).?;
        defer db.writeCommit(writer);

        var sub_writer = db.writeObj(sub_obj1).?;
        defer db.writeCommit(sub_writer);

        try db.setSubObj(writer, 0, sub_writer);
    }

    obj_reader = db.readObj(obj1);
    try std.testing.expect(obj_reader != null);

    var value = db.readSubObj(obj_reader.?, 0);
    try std.testing.expect(value != null);
    try std.testing.expectEqual(sub_obj1, value.?);

    // Test if destroy parent destroy of subobjects
    db.destroyObject(obj1);

    try db.gc(std.testing.allocator);
    try expectGCStats(db, 2, 4);

    obj_reader = db.readObj(obj1);
    try std.testing.expectEqual(@as(?*public.Obj, null), obj_reader);

    obj_reader = db.readObj(sub_obj1);
    try std.testing.expectEqual(@as(?*public.Obj, null), obj_reader);
}

test "cdb: Should delete subobject" {
    try testInit();
    defer testDeinit();

    var db = try cdb.api.createDb("Test");
    defer cdb.api.destroyDb(db);

    const type_hash = try db.addType(
        "foo",
        &.{
            .{ .name = "prop1", .type = public.PropType.SUBOBJECT },
        },
    );

    const type_hash2 = try db.addType(
        "foo2",
        &.{
            .{ .name = "prop1", .type = public.PropType.SUBOBJECT },
        },
    );

    var obj1 = try db.createObject(type_hash);

    var sub_obj1 = try db.createObject(type_hash2);

    {
        var writer = db.writeObj(obj1).?;
        defer db.writeCommit(writer);

        var sub_writer = db.writeObj(obj1).?;
        defer db.writeCommit(sub_writer);

        try db.setSubObj(writer, 0, sub_writer);
    }

    // Test if destroy subobjects set parent property to 0
    db.destroyObject(sub_obj1);

    try db.gc(std.testing.allocator);
    try expectGCStats(db, 2, 3);

    var obj_reader = db.readObj(obj1).?;
    var sub_obj1_read = db.readSubObj(obj_reader, 0);
    try std.testing.expectEqual(@as(?public.ObjId, null), sub_obj1_read);

    db.destroyObject(obj1);
    try db.gc(std.testing.allocator);
    try expectGCStats(db, 2, 1);
}

test "cdb: Should read/write subobj set property " {
    try testInit();
    defer testDeinit();

    var db = try cdb.api.createDb("Test");
    defer cdb.api.destroyDb(db);

    const type_hash = try db.addType(
        "foo",
        &.{
            .{ .name = "prop1", .type = public.PropType.SUBOBJECT_SET },
        },
    );

    var obj1 = try db.createObject(type_hash);
    var sub_obj1 = try db.createObject(type_hash);
    var sub_obj2 = try db.createObject(type_hash);

    var obj_reader = db.readObj(obj1);
    try std.testing.expect(obj_reader != null);

    {
        var writer = db.writeObj(obj1).?;
        defer db.writeCommit(writer);

        var sub_obj1_writer = db.writeObj(sub_obj1).?;
        defer db.writeCommit(sub_obj1_writer);

        var sub_obj2_writer = db.writeObj(sub_obj2).?;
        defer db.writeCommit(sub_obj2_writer);

        try db.addSubObjToSet(writer, 0, &[_]*public.Obj{ sub_obj1_writer, sub_obj2_writer });
    }

    obj_reader = db.readObj(obj1);
    try std.testing.expect(obj_reader != null);

    var set = try db.readSubObjSet(obj_reader.?, 0, std.testing.allocator);

    try std.testing.expect(set != null);
    try std.testing.expectEqualSlices(
        public.ObjId,
        &[_]public.ObjId{ sub_obj1, sub_obj2 },
        set.?,
    );

    std.testing.allocator.free(set.?);

    // Remove object
    {
        var writer = db.writeObj(obj1).?;
        var sub_obj1_writer = db.writeObj(sub_obj1).?;

        try db.removeFromSubObjSet(writer, 0, sub_obj1_writer);

        db.writeCommit(sub_obj1_writer);
        db.writeCommit(writer);
    }

    obj_reader = db.readObj(obj1);
    try std.testing.expect(obj_reader != null);

    set = try db.readSubObjSet(obj_reader.?, 0, std.testing.allocator);

    try std.testing.expect(set != null);
    try std.testing.expectEqualSlices(
        public.ObjId,
        &[_]public.ObjId{sub_obj2},
        set.?,
    );

    std.testing.allocator.free(set.?);

    db.destroyObject(sub_obj1);
    db.destroyObject(sub_obj2);

    // object is removed from parent after gc
    try db.gc(std.testing.allocator);
    try expectGCStats(db, 3, 7);

    obj_reader = db.readObj(obj1);
    set = try db.readSubObjSet(obj_reader.?, 0, std.testing.allocator);
    try std.testing.expect(set != null);
    try std.testing.expectEqualSlices(
        public.ObjId,
        &[_]public.ObjId{},
        set.?,
    );

    std.testing.allocator.free(set.?);

    db.destroyObject(obj1);
    try db.gc(std.testing.allocator);
    try expectGCStats(db, 3, 1);
}

test "cdb: Should read/write reference property" {
    try testInit();
    defer testDeinit();

    var db = try cdb.api.createDb("Test");
    defer cdb.api.destroyDb(db);

    const type_hash = try db.addType(
        "foo",
        &.{
            .{ .name = "prop1", .type = public.PropType.REFERENCE },
        },
    );

    var obj1 = try db.createObject(type_hash);

    var sub_obj1 = try db.createObject(type_hash);

    var obj_reader = db.readObj(obj1);
    try std.testing.expect(obj_reader != null);

    {
        var writer = db.writeObj(obj1).?;
        defer db.writeCommit(writer);
        try db.setRef(writer, 0, sub_obj1);
    }

    obj_reader = db.readObj(obj1);
    try std.testing.expect(obj_reader != null);

    var value = db.readRef(obj_reader.?, 0);
    try std.testing.expect(value != null);
    try std.testing.expectEqual(sub_obj1, value.?);

    // Delete object does not delete reference.
    db.destroyObject(obj1);
    try db.gc(std.testing.allocator);

    obj_reader = db.readObj(obj1);
    try std.testing.expectEqual(@as(?*public.Obj, null), obj_reader);

    obj_reader = db.readObj(sub_obj1);
    try std.testing.expect(obj_reader != null);

    // if refcounter work good we can delete object. if not shit hapends and you have bad day.
    db.destroyObject(sub_obj1);
    try db.gc(std.testing.allocator);
    try expectGCStats(db, 2, 1);

    obj_reader = db.readObj(sub_obj1);
    try std.testing.expect(obj_reader == null);

    try db.gc(std.testing.allocator);
    try expectGCStats(db, 2, 0);
}

test "cdb: Should read/write reference set property " {
    try testInit();
    defer testDeinit();

    var db = try cdb.api.createDb("Test");
    defer cdb.api.destroyDb(db);

    const type_hash = try db.addType(
        "foo",
        &.{
            .{ .name = "prop1", .type = public.PropType.REFERENCE_SET },
        },
    );

    var obj1 = try db.createObject(type_hash);
    var ref_obj1 = try db.createObject(type_hash);
    var ref_obj2 = try db.createObject(type_hash);

    var obj_reader = db.readObj(obj1);
    try std.testing.expect(obj_reader != null);

    {
        var writer = db.writeObj(obj1).?;
        defer db.writeCommit(writer);
        try db.addRefToSet(writer, 0, &[_]public.ObjId{ ref_obj1, ref_obj2 });

        // try add same items
        try db.addRefToSet(writer, 0, &[_]public.ObjId{ ref_obj1, ref_obj2 });
    }

    obj_reader = db.readObj(obj1);
    try std.testing.expect(obj_reader != null);

    var set = db.readRefSet(obj_reader.?, 0, std.testing.allocator);
    try std.testing.expect(set != null);
    try std.testing.expectEqualSlices(
        public.ObjId,
        &[_]public.ObjId{ ref_obj1, ref_obj2 },
        set.?,
    );
    std.testing.allocator.free(set.?);

    var writer = db.writeObj(obj1).?;
    try db.removeFromRefSet(writer, 0, ref_obj1);
    db.writeCommit(writer);

    obj_reader = db.readObj(obj1);
    try std.testing.expect(obj_reader != null);

    set = db.readRefSet(obj_reader.?, 0, std.testing.allocator);
    try std.testing.expect(set != null);
    try std.testing.expectEqualSlices(
        public.ObjId,
        &[_]public.ObjId{ref_obj2},
        set.?,
    );
    std.testing.allocator.free(set.?);

    db.destroyObject(ref_obj1);
    db.destroyObject(ref_obj2);
    db.destroyObject(obj1);

    try db.gc(std.testing.allocator);
    try expectGCStats(db, 3, 5);
}

test "cdb: Should read/write blob property " {
    try testInit();
    defer testDeinit();

    var db = try cdb.api.createDb("Test");
    defer cdb.api.destroyDb(db);

    const type_hash = try db.addType(
        "foo",
        &.{
            .{ .name = "prop1", .type = public.PropType.BLOB },
        },
    );

    var obj1 = try db.createObject(type_hash);
    defer db.destroyObject(obj1);

    var writer = db.writeObj(obj1).?;
    var blob = try db.createBlob(writer, 0, 10);

    try std.testing.expect(blob != null);

    for (0..10) |idx| {
        blob.?[idx] = 1;
    }

    db.writeCommit(writer);

    var blob1 = db.readBlob(db.readObj(obj1).?, 0);
    try std.testing.expectEqualSlices(u8, &[_]u8{ 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 }, blob1);
}

test "cdb: Should use prototype" {
    try testInit();
    defer testDeinit();

    var db = try cdb.api.createDb("Test");
    defer cdb.api.destroyDb(db);

    const type_hash = try db.addType(
        "foo",
        &.{
            .{ .name = "prop1", .type = public.PropType.F64 },
        },
    );

    var obj1 = try db.createObject(type_hash);
    var obj1_w = db.writeObj(obj1).?;
    db.setValue(f64, obj1_w, 0, 1);
    db.writeCommit(obj1_w);

    try std.testing.expectEqual(public.OBJID_ZERO, db.getPrototype(db.readObj(obj1).?));

    var obj2 = try db.createObjectFromPrototype(obj1);

    try std.testing.expectEqual(obj1, db.getPrototype(db.readObj(obj2).?));

    obj1_w = db.writeObj(obj1).?;
    db.setValue(f64, obj1_w, 0, 2);
    db.writeCommit(obj1_w);

    try std.testing.expect(!db.isPropertyOverrided(db.readObj(obj2).?, 0));

    try std.testing.expectEqual(
        @as(f64, 2),
        db.readValue(f64, db.readObj(obj2).?, 0),
    );

    // if change property on instance we read from this not prototypes
    var obj2_w = db.writeObj(obj2).?;
    db.setValue(f64, obj2_w, 0, 3);
    db.writeCommit(obj2_w);

    try std.testing.expect(db.isPropertyOverrided(db.readObj(obj2).?, 0));

    try std.testing.expectEqual(
        @as(f64, 3),
        db.readValue(f64, db.readObj(obj2).?, 0),
    );

    // is possible to reset override flag.
    obj2_w = db.writeObj(obj2).?;
    db.resetPropertyOveride(obj2_w, 0);
    db.writeCommit(obj2_w);

    try std.testing.expectEqual(
        @as(f64, 2),
        db.readValue(f64, db.readObj(obj2).?, 0),
    );

    db.destroyObject(obj1);
    db.destroyObject(obj2);

    try db.gc(std.testing.allocator);
    try expectGCStats(db, 2, 6);
}

test "cdb: Should use prototype on sets" {
    try testInit();
    defer testDeinit();

    var db = try cdb.api.createDb("Test");
    defer cdb.api.destroyDb(db);

    const type_hash = try db.addType(
        "foo",
        &.{
            .{ .name = "prop1", .type = public.PropType.REFERENCE_SET },
        },
    );

    var obj1 = try db.createObject(type_hash);
    var obj2 = try db.createObject(type_hash);
    var obj3 = try db.createObject(type_hash);

    var obj1_w = db.writeObj(obj1).?;
    try db.addRefToSet(obj1_w, 0, &[_]public.ObjId{ obj2, obj3 });
    db.writeCommit(obj1_w);

    var new_obj = try db.createObjectFromPrototype(obj1);

    // we see full set from prototype
    var set = db.readRefSet(db.readObj(new_obj).?, 0, std.testing.allocator);
    try std.testing.expect(set != null);
    try std.testing.expectEqualSlices(
        public.ObjId,
        &[_]public.ObjId{ obj2, obj3 },
        set.?,
    );
    std.testing.allocator.free(set.?);

    // Remove one object fro new set
    var new_obj1_w = db.writeObj(new_obj).?;
    try db.removeFromRefSet(new_obj1_w, 0, obj2);
    db.writeCommit(new_obj1_w);

    set = db.readRefSet(db.readObj(new_obj).?, 0, std.testing.allocator);
    try std.testing.expect(set != null);
    try std.testing.expectEqualSlices(
        public.ObjId,
        &[_]public.ObjId{obj3},
        set.?,
    );
    std.testing.allocator.free(set.?);

    // Remove one object fro new set
    new_obj1_w = db.writeObj(new_obj).?;
    try db.removeFromRefSet(new_obj1_w, 0, obj3);
    db.writeCommit(new_obj1_w);

    set = db.readRefSet(db.readObj(new_obj).?, 0, std.testing.allocator);
    try std.testing.expect(set != null);
    try std.testing.expectEqualSlices(
        public.ObjId,
        &[_]public.ObjId{},
        set.?,
    );
    std.testing.allocator.free(set.?);

    // Add new objet to instance set
    var obj4 = try db.createObject(type_hash);
    new_obj1_w = db.writeObj(new_obj).?;
    try db.addRefToSet(new_obj1_w, 0, &[_]public.ObjId{obj4});
    db.writeCommit(new_obj1_w);

    // Instance see only obj4
    set = db.readRefSet(db.readObj(new_obj).?, 0, std.testing.allocator);
    try std.testing.expect(set != null);
    try std.testing.expectEqualSlices(
        public.ObjId,
        &[_]public.ObjId{obj4},
        set.?,
    );
    std.testing.allocator.free(set.?);

    // Protoype stil se obj2, obj3
    set = db.readRefSet(db.readObj(obj1).?, 0, std.testing.allocator);
    try std.testing.expect(set != null);
    try std.testing.expectEqualSlices(
        public.ObjId,
        &[_]public.ObjId{ obj2, obj3 },
        set.?,
    );
    std.testing.allocator.free(set.?);

    db.destroyObject(obj1);
    db.destroyObject(obj2);
    db.destroyObject(obj3);
    db.destroyObject(new_obj);
    db.destroyObject(obj4);

    try db.gc(std.testing.allocator);
    try expectGCStats(db, 5, 9);
}

test "cdb: Should instantiate subobject" {
    try testInit();
    defer testDeinit();

    var db = try cdb.api.createDb("Test");
    defer cdb.api.destroyDb(db);

    const type_hash = try db.addType(
        "foo",
        &.{
            .{ .name = "prop1", .type = public.PropType.SUBOBJECT },
        },
    );

    const type_hash2 = try db.addType(
        "foo2",
        &.{
            .{ .name = "prop1", .type = public.PropType.U64 },
        },
    );

    var obj1 = try db.createObject(type_hash);
    var sub_obj1 = try db.createObject(type_hash2);

    var obj1_w = db.writeObj(obj1).?;
    var sub_obj1_w = db.writeObj(sub_obj1).?;
    db.setValue(u64, sub_obj1_w, 0, 10);
    try db.setSubObj(obj1_w, 0, sub_obj1_w);
    db.writeCommit(sub_obj1_w);
    db.writeCommit(obj1_w);

    var obj2 = try db.createObjectFromPrototype(obj1);
    var obj2_sub = db.readSubObj(db.readObj(obj2).?, 0).?;

    try std.testing.expectEqual(
        @as(u64, 10),
        db.readValue(u64, db.readObj(obj2_sub).?, 0),
    );

    var obj2_w = db.writeObj(obj2).?;
    try db.instantiateSubObj(obj2_w, 0);
    db.writeCommit(obj2_w);

    try std.testing.expect(db.isPropertyOverrided(db.readObj(obj2).?, 0));

    obj2_sub = db.readSubObj(db.readObj(obj2).?, 0).?;
    var sub_obj2_w = db.writeObj(obj2_sub).?;
    db.setValue(u64, sub_obj2_w, 0, 20);
    db.writeCommit(sub_obj2_w);

    try std.testing.expectEqual(
        @as(u64, 10),
        db.readValue(u64, db.readObj(sub_obj1).?, 0),
    );

    try std.testing.expectEqual(
        @as(u64, 20),
        db.readValue(u64, db.readObj(obj2_sub).?, 0),
    );

    db.destroyObject(obj1);
    db.destroyObject(obj2);

    try db.gc(std.testing.allocator);
    try expectGCStats(db, 4, 8);
}

test "cdb: Should specify type_hash for ref/subobj base properties" {
    try testInit();
    defer testDeinit();

    var db = try cdb.api.createDb("Test");
    defer cdb.api.destroyDb(db);

    const sub_type_hash = try db.addType(
        "foo2",
        &.{
            .{ .name = "prop1", .type = public.PropType.U64 },
        },
    );

    const another_sub_type_hash = try db.addType(
        "foo3",
        &.{
            .{ .name = "prop1", .type = public.PropType.U64 },
        },
    );

    const type_hash = try db.addType(
        "foo",
        &.{
            .{ .name = "prop1", .type = public.PropType.SUBOBJECT, .type_hash = sub_type_hash },
            .{ .name = "prop2", .type = public.PropType.REFERENCE, .type_hash = sub_type_hash },
            .{ .name = "prop3", .type = public.PropType.SUBOBJECT_SET, .type_hash = sub_type_hash },
            .{ .name = "prop4", .type = public.PropType.REFERENCE_SET, .type_hash = sub_type_hash },
        },
    );

    var obj1 = try db.createObject(type_hash);
    var sub_obj1 = try db.createObject(sub_type_hash);
    var sub_obj2 = try db.createObject(another_sub_type_hash);

    var obj1_w = db.writeObj(obj1).?;
    var sub_obj2_w = db.writeObj(sub_obj2).?;

    try db.setSubObj(obj1_w, 0, sub_obj2_w);
    try db.setRef(obj1_w, 1, sub_obj2);
    try db.addSubObjToSet(obj1_w, 2, &[_]*public.Obj{sub_obj2_w});
    try db.addRefToSet(obj1_w, 3, &[_]public.ObjId{sub_obj2});

    try std.testing.expect(db.readSubObj(db.readObj(obj1).?, 0) == null);
    try std.testing.expect(db.readRef(db.readObj(obj1).?, 1) == null);

    var set = try db.readSubObjSet(db.readObj(obj1).?, 2, std.testing.allocator);
    try std.testing.expect(set != null);
    try std.testing.expect(set.?.len == 0);
    std.testing.allocator.free(set.?);

    set = db.readRefSet(db.readObj(obj1).?, 3, std.testing.allocator);
    try std.testing.expect(set != null);
    try std.testing.expect(set.?.len == 0);
    std.testing.allocator.free(set.?);

    db.writeCommit(sub_obj2_w);
    db.writeCommit(obj1_w);

    db.destroyObject(obj1);
    db.destroyObject(sub_obj1);
    db.destroyObject(sub_obj2);

    try db.gc(std.testing.allocator);
    try expectGCStats(db, 3, 5);
}

fn stressTest(comptime task_count: u32, task_based: bool) !void {
    var db = try cdb.api.createDb("Test");
    defer cdb.api.destroyDb(db);

    const type_hash = try cetech1.cdb.addBigType(&db, "foo");
    const type_hash2 = try cetech1.cdb.addBigType(&db, "foo2");

    const ref_obj1 = try db.createObject(type_hash2);
    if (task_based) {
        var tasks: [task_count]cetech1.task.TaskID = undefined;

        const Task = struct {
            db: cetech1.cdb.CdbDb,
            ref_obj1: cetech1.cdb.ObjId,
            type_hash: cetech1.strid.StrId32,
            type_hash2: cetech1.strid.StrId32,
            pub fn exec(self: *@This()) void {
                self.db.stressIt(
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
            );
        }

        task.api.wait(try task.api.combine(&tasks));
    } else {
        for (0..task_count) |_| {
            try db.stressIt(
                type_hash,
                type_hash2,
                ref_obj1,
            );
        }
    }

    db.destroyObject(ref_obj1);

    var true_db = cdb.toDbFromDbT(db.db);
    var storage = true_db.getTypeStorage(type_hash).?;
    try std.testing.expectEqual(@as(u32, task_count + 1), storage.objid_pool.count.value);
    try std.testing.expectEqual(@as(u32, task_count * 3), true_db.writers_count.value);
    try std.testing.expectEqual(@as(u32, task_count * 3), true_db.write_commit_count.value);

    db.destroyObject(ref_obj1);

    try db.gc(std.testing.allocator);
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