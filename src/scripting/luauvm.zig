/// Lua <-> Zig api binding is based (copy&paste) on [zlua](https://github.com/natecraddock/ziglua).
const std = @import("std");
const cetech1 = @import("../cetech1.zig");
const cdb = cetech1.cdb;
const ecs = cetech1.ecs;
const apidb = cetech1.apidb;

pub const LuauScriptCdb = cdb.CdbTypeDecl(
    "ct_luau",
    enum(u32) {
        Bytecode = 0,
    },
    struct {},
);

pub const registry_index: i32 = -8000 - 2000;

pub const Lua = opaque {
    pub fn create(allocator: std.mem.Allocator) !*Lua {
        return try luaustate_api.create(allocator);
    }

    pub fn destroy(lua: *Lua) void {
        luaustate_api.destroy(lua);
    }

    pub fn loadBytecode(lua: *Lua, chunkname: [:0]const u8, bytecode: []const u8) error{InvalidBytecode}!void {
        return luaustate_api.loadBytecode(lua, chunkname, bytecode);
    }

    pub fn absIndex(lua: *Lua, index: i32) i32 {
        return luaustate_api.absIndex(lua, index);
    }
    pub fn call(lua: *Lua, args: CallArgs) void {
        return luaustate_api.call(lua, args);
    }
    pub fn checkStack(lua: *Lua, n: i32) error{NoSpace}!void {
        return luaustate_api.checkStack(lua, n);
    }
    pub fn concat(lua: *Lua, n: i32) void {
        return luaustate_api.concat(lua, n);
    }
    pub fn cProtectedCall(lua: *Lua, c_fn: CFn, userdata: *anyopaque) CProtectedCallError!void {
        return luaustate_api.cProtectedCall(lua, c_fn, userdata);
    }
    pub fn createTable(lua: *Lua, num_arr: i32, num_rec: i32) void {
        return luaustate_api.createTable(lua, num_arr, num_rec);
    }
    pub fn equal(lua: *Lua, index1: i32, index2: i32) bool {
        return luaustate_api.equal(lua, index1, index2);
    }
    pub fn raiseError(lua: *Lua) noreturn {
        return luaustate_api.raiseError(lua);
    }
    pub fn getFnEnvironment(lua: *Lua, index: i32) void {
        return luaustate_api.getFnEnvironment(lua, index);
    }
    pub fn getField(lua: *Lua, index: i32, key: [:0]const u8) LuaType {
        return luaustate_api.getField(lua, index, key);
    }
    pub fn getGlobal(lua: *Lua, name: [:0]const u8) error{LuaError}!LuaType {
        return luaustate_api.getGlobal(lua, name);
    }
    pub fn getMetatable(lua: *Lua, index: i32) error{NoMetatable}!void {
        return luaustate_api.getMetatable(lua, index);
    }
    pub fn getTable(lua: *Lua, index: i32) LuaType {
        return luaustate_api.getTable(lua, index);
    }
    pub fn getTop(lua: *Lua) i32 {
        return luaustate_api.getTop(lua);
    }
    pub fn setReadonly(lua: *Lua, idx: i32, enabled: bool) void {
        return luaustate_api.setReadonly(lua, idx, enabled);
    }
    pub fn getReadonly(lua: *Lua, idx: i32) bool {
        return luaustate_api.getReadonly(lua, idx);
    }
    pub fn insert(lua: *Lua, index: i32) void {
        return luaustate_api.insert(lua, index);
    }
    pub fn isBoolean(lua: *Lua, index: i32) bool {
        return luaustate_api.isBoolean(lua, index);
    }
    pub fn isCFunction(lua: *Lua, index: i32) bool {
        return luaustate_api.isCFunction(lua, index);
    }
    pub fn isFunction(lua: *Lua, index: i32) bool {
        return luaustate_api.isFunction(lua, index);
    }
    pub fn isLightUserdata(lua: *Lua, index: i32) bool {
        return luaustate_api.isLightUserdata(lua, index);
    }
    pub fn isNil(lua: *Lua, index: i32) bool {
        return luaustate_api.isNil(lua, index);
    }
    pub fn isNone(lua: *Lua, index: i32) bool {
        return luaustate_api.isNone(lua, index);
    }
    pub fn isNoneOrNil(lua: *Lua, index: i32) bool {
        return luaustate_api.isNoneOrNil(lua, index);
    }
    pub fn isNumber(lua: *Lua, index: i32) bool {
        return luaustate_api.isNumber(lua, index);
    }
    pub fn isString(lua: *Lua, index: i32) bool {
        return luaustate_api.isString(lua, index);
    }
    pub fn isTable(lua: *Lua, index: i32) bool {
        return luaustate_api.isTable(lua, index);
    }
    pub fn isThread(lua: *Lua, index: i32) bool {
        return luaustate_api.isThread(lua, index);
    }
    pub fn isUserdata(lua: *Lua, index: i32) bool {
        return luaustate_api.isUserdata(lua, index);
    }
    pub fn isVector(lua: *Lua, index: i32) bool {
        return luaustate_api.isVector(lua, index);
    }
    pub fn isYieldable(lua: *Lua) bool {
        return luaustate_api.isYieldable(lua);
    }
    pub fn lessThan(lua: *Lua, index1: i32, index2: i32) bool {
        return luaustate_api.lessThan(lua, index1, index2);
    }
    pub fn newTable(lua: *Lua) void {
        return luaustate_api.newTable(lua);
    }
    pub fn newThread(lua: *Lua) *Lua {
        return luaustate_api.newThread(lua);
    }
    pub fn getUserdataTag(lua: *Lua, index: i32) error{ExpectedTaggedUserdata}!i32 {
        return luaustate_api.getUserdataTag(lua, index);
    }
    pub fn next(lua: *Lua, index: i32) bool {
        return luaustate_api.next(lua, index);
    }
    pub fn objectLen(lua: *Lua, index: i32) i32 {
        return luaustate_api.objectLen(lua, index);
    }
    pub fn protectedCall(lua: *Lua, args: ProtectedCallArgs) CallError!void {
        return luaustate_api.protectedCall(lua, args);
    }
    pub fn pop(lua: *Lua, n: i32) void {
        return luaustate_api.pop(lua, n);
    }
    pub fn pushBoolean(lua: *Lua, b: bool) void {
        return luaustate_api.pushBoolean(lua, b);
    }
    pub fn pushClosure(lua: *Lua, c_fn: CFn, n: i32) void {
        return luaustate_api.pushClosure(lua, c_fn, n);
    }
    pub fn pushClosureNamed(lua: *Lua, c_fn: CFn, debugname: [:0]const u8, n: i32) void {
        return luaustate_api.pushClosureNamed(lua, c_fn, debugname, n);
    }
    pub fn pushFunction(lua: *Lua, c_fn: CFn) void {
        return luaustate_api.pushFunction(lua, c_fn);
    }
    pub fn pushFunctionNamed(lua: *Lua, c_fn: CFn, debugname: [:0]const u8) void {
        return luaustate_api.pushFunctionNamed(lua, c_fn, debugname);
    }
    pub fn pushInteger(lua: *Lua, n: Integer) void {
        return luaustate_api.pushInteger(lua, n);
    }
    pub fn pushInteger64(lua: *Lua, n: i64) void {
        return luaustate_api.pushInteger64(lua, n);
    }
    pub fn pushLightUserdata(lua: *Lua, ptr: *const anyopaque) void {
        return luaustate_api.pushLightUserdata(lua, ptr);
    }
    pub fn pushString(lua: *Lua, str: []const u8) [:0]const u8 {
        return luaustate_api.pushString(lua, str);
    }
    pub fn pushNil(lua: *Lua) void {
        return luaustate_api.pushNil(lua);
    }
    pub fn pushNumber(lua: *Lua, n: Number) void {
        return luaustate_api.pushNumber(lua, n);
    }
    pub fn pushStringZ(lua: *Lua, str: [:0]const u8) [:0]const u8 {
        return luaustate_api.pushStringZ(lua, str);
    }
    pub fn pushThread(lua: *Lua) bool {
        return luaustate_api.pushThread(lua);
    }
    pub fn pushUnsigned(lua: *Lua, n: Unsigned) void {
        return luaustate_api.pushUnsigned(lua, n);
    }
    pub fn pushValue(lua: *Lua, index: i32) void {
        return luaustate_api.pushValue(lua, index);
    }
    pub fn pushVector(lua: *Lua, x: f32, y: f32, z: f32) void {
        return luaustate_api.pushVector(lua, x, y, z);
    }
    pub fn rawEqual(lua: *Lua, index1: i32, index2: i32) bool {
        return luaustate_api.rawEqual(lua, index1, index2);
    }
    pub fn rawGetTable(lua: *Lua, index: i32) LuaType {
        return luaustate_api.rawGetTable(lua, index);
    }
    pub fn rawGetIndex(lua: *Lua, index: i32, n: RawGetIndexNType) LuaType {
        return luaustate_api.rawGetIndex(lua, index, n);
    }
    pub fn rawGetPtr(lua: *Lua, index: i32, p: *const anyopaque) LuaType {
        return luaustate_api.rawGetPtr(lua, index, p);
    }
    pub fn rawGetPtrTagged(lua: *Lua, index: i32, p: *const anyopaque, tag: i32) LuaType {
        return luaustate_api.rawGetPtrTagged(lua, index, p, tag);
    }
    pub fn rawLen(lua: *Lua, index: i32) usize {
        return luaustate_api.rawLen(lua, index);
    }
    pub fn rawSetTable(lua: *Lua, index: i32) void {
        return luaustate_api.rawSetTable(lua, index);
    }
    pub fn rawSetIndex(lua: *Lua, index: i32, i: RawSetIndexIType) void {
        return luaustate_api.rawSetIndex(lua, index, i);
    }
    pub fn rawSetPtr(lua: *Lua, index: i32, p: *const anyopaque) void {
        return luaustate_api.rawSetPtr(lua, index, p);
    }
    pub fn rawSetPtrTagged(lua: *Lua, index: i32, p: *const anyopaque, tag: i32) void {
        return luaustate_api.rawSetPtrTagged(lua, index, p, tag);
    }
    pub fn register(lua: *Lua, name: [:0]const u8, f: CFn) void {
        return luaustate_api.register(lua, name, f);
    }
    pub fn remove(lua: *Lua, index: i32) void {
        return luaustate_api.remove(lua, index);
    }
    pub fn replace(lua: *Lua, index: i32) void {
        return luaustate_api.replace(lua, index);
    }
    pub fn setFnEnvironment(lua: *Lua, index: i32) error{InvalidValue}!void {
        return luaustate_api.setFnEnvironment(lua, index);
    }
    pub fn setField(lua: *Lua, index: i32, k: [:0]const u8) void {
        return luaustate_api.setField(lua, index, k);
    }
    pub fn setGlobal(lua: *Lua, name: [:0]const u8) void {
        return luaustate_api.setGlobal(lua, name);
    }
    pub fn setMetatable(lua: *Lua, index: i32) void {
        return luaustate_api.setMetatable(lua, index);
    }
    pub fn setTable(lua: *Lua, index: i32) void {
        return luaustate_api.setTable(lua, index);
    }
    pub fn setTop(lua: *Lua, index: i32) void {
        return luaustate_api.setTop(lua, index);
    }
    pub fn setUserdataTag(lua: *Lua, index: i32, tag: i32) void {
        return luaustate_api.setUserdataTag(lua, index, tag);
    }
    pub fn toBoolean(lua: *Lua, index: i32) bool {
        return luaustate_api.toBoolean(lua, index);
    }
    pub fn toCFunction(lua: *Lua, index: i32) error{ExpectedFunction}!CFn {
        return luaustate_api.toCFunction(lua, index);
    }
    pub fn toInteger(lua: *Lua, index: i32) error{ExpectedInteger}!Integer {
        return luaustate_api.toInteger(lua, index);
    }
    pub fn toInteger64(lua: *Lua, index: i32) error{ExpectedInteger64}!i64 {
        return luaustate_api.toInteger64(lua, index);
    }
    pub fn toNumber(lua: *Lua, index: i32) error{ExpectedNumber}!Number {
        return luaustate_api.toNumber(lua, index);
    }
    pub fn toPointer(lua: *Lua, index: i32) ?*const anyopaque {
        return luaustate_api.toPointer(lua, index);
    }
    pub fn toString(lua: *Lua, index: i32) error{ExpectedString}![:0]const u8 {
        return luaustate_api.toString(lua, index);
    }
    pub fn toThread(lua: *Lua, index: i32) error{ExpectedThread}!*Lua {
        return luaustate_api.toThread(lua, index);
    }
    pub fn toUnsigned(lua: *Lua, index: i32) error{ExpectedNumber}!Unsigned {
        return luaustate_api.toUnsigned(lua, index);
    }
    pub fn toVector(lua: *Lua, index: i32) error{ExpectedVector}![3]f32 {
        return luaustate_api.toVector(lua, index);
    }
    pub fn toStringAtom(lua: *Lua, index: i32) error{ExpectedString}!struct { i32, [:0]const u8 } {
        return luaustate_api.toStringAtom(lua, index);
    }
    pub fn toUserdata(lua: *Lua, comptime T: type, index: i32) error{ExpectedUserdata}!*T {
        if (luaustate_api.lua_touserdata(@ptrCast(lua), index)) |ptr| return @ptrCast(@alignCast(ptr));
        return error.ExpectedUserdata;
    }
    pub fn namecallAtom(lua: *Lua) error{ExpectedNamecall}!struct { i32, [:0]const u8 } {
        return luaustate_api.namecallAtom(lua);
    }
    pub fn typeOf(lua: *Lua, index: i32) LuaType {
        return luaustate_api.typeOf(lua, index);
    }
    pub fn typeName(lua: *Lua, t: LuaType) [:0]const u8 {
        return luaustate_api.typeName(lua, t);
    }
    pub fn upvalueIndex(i: i32) i32 {
        return luaustate_api.upvalueIndex(i);
    }
    pub fn xMove(lua: *Lua, to: *Lua, num: i32) void {
        return luaustate_api.xMove(lua, to, num);
    }
    pub fn yield(lua: *Lua, num_results: i32) i32 {
        return luaustate_api.yield(lua, num_results);
    }
    pub fn argCheck(lua: *Lua, cond: bool, arg: i32, extra_msg: [:0]const u8) void {
        return luaustate_api.argCheck(lua, cond, arg, extra_msg);
    }
    pub fn argError(lua: *Lua, arg: i32, extra_msg: [:0]const u8) noreturn {
        return luaustate_api.argError(lua, arg, extra_msg);
    }
    pub fn argExpected(lua: *Lua, cond: bool, arg: i32, type_name: [:0]const u8) void {
        return luaustate_api.argExpected(lua, cond, arg, type_name);
    }
    pub fn callMeta(lua: *Lua, obj: i32, field: [:0]const u8) error{NoMetamethod}!void {
        return luaustate_api.callMeta(lua, obj, field);
    }
    pub fn checkAny(lua: *Lua, arg: i32) void {
        return luaustate_api.checkAny(lua, arg);
    }
    pub fn checkInteger(lua: *Lua, arg: i32) Integer {
        return luaustate_api.checkInteger(lua, arg);
    }
    pub fn checkInteger64(lua: *Lua, arg: i32) i64 {
        return luaustate_api.checkInteger64(lua, arg);
    }
    pub fn checkNumber(lua: *Lua, arg: i32) Number {
        return luaustate_api.checkNumber(lua, arg);
    }
    pub fn checkStackErr(lua: *Lua, size: i32, msg: ?[:0]const u8) void {
        return luaustate_api.checkStackErr(lua, size, msg);
    }
    pub fn checkString(lua: *Lua, arg: i32) [:0]const u8 {
        return luaustate_api.checkString(lua, arg);
    }
    pub fn checkType(lua: *Lua, arg: i32, t: LuaType) void {
        return luaustate_api.checkType(lua, arg, t);
    }
    pub fn checkUnsigned(lua: *Lua, arg: i32) Unsigned {
        return luaustate_api.checkUnsigned(lua, arg);
    }
    pub fn checkVector(lua: *Lua, arg: i32) [3]f32 {
        return luaustate_api.checkVector(lua, arg);
    }
    pub fn getMetaField(lua: *Lua, obj: i32, field: [:0]const u8) anyerror!LuaType {
        return luaustate_api.getMetaField(lua, obj, field);
    }
    pub fn newLibTable(lua: *Lua, list: []const FnReg) void {
        return luaustate_api.newLibTable(lua, list);
    }
    pub fn newMetatable(lua: *Lua, key: [:0]const u8) error{KeyInRegistry}!void {
        return luaustate_api.newMetatable(lua, key);
    }
    pub fn optInteger(lua: *Lua, arg: i32) ?Integer {
        return luaustate_api.optInteger(lua, arg);
    }
    pub fn optInteger64(lua: *Lua, arg: i32) ?i64 {
        return luaustate_api.optInteger64(lua, arg);
    }
    pub fn optNumber(lua: *Lua, arg: i32) ?Number {
        return luaustate_api.optNumber(lua, arg);
    }
    pub fn optString(lua: *Lua, arg: i32) ?[:0]const u8 {
        return luaustate_api.optString(lua, arg);
    }
    pub fn optUnsigned(lua: *Lua, arg: i32) ?Unsigned {
        return luaustate_api.optUnsigned(lua, arg);
    }
    pub fn ref(lua: *Lua, index: i32) i32 {
        return luaustate_api.ref(lua, index);
    }
    pub fn registerFns(lua: *Lua, libname: ?[:0]const u8, funcs: []const FnReg) void {
        return luaustate_api.registerFns(lua, libname, funcs);
    }
    pub fn requireF(lua: *Lua, mod_name: [:0]const u8, open_fn: CFn, global: bool) void {
        return luaustate_api.requireF(lua, mod_name, open_fn, global);
    }
    pub fn setFuncs(lua: *Lua, funcs: []const FnReg, num_upvalues: i32) void {
        return luaustate_api.setFuncs(lua, funcs, num_upvalues);
    }
    pub fn toStringEx(lua: *Lua, index: i32) [:0]const u8 {
        return luaustate_api.toStringEx(lua, index);
    }
    pub fn traceback(lua: *Lua, state: *Lua, msg: ?[:0]const u8, level: i32) void {
        return luaustate_api.traceback(lua, state, msg, level);
    }
    pub fn typeError(lua: *Lua, arg: i32, type_name: [:0]const u8) noreturn {
        return luaustate_api.typeError(lua, arg, type_name);
    }
    pub fn typeNameIndex(lua: *Lua, index: i32) [:0]const u8 {
        return luaustate_api.typeNameIndex(lua, index);
    }
    pub fn unref(lua: *Lua, r: i32) void {
        return luaustate_api.unref(lua, r);
    }
    pub fn where(lua: *Lua, level: i32) void {
        return luaustate_api.where(lua, level);
    }
    pub fn sandbox(lua: *Lua) void {
        luaustate_api.luaL_sandbox(lua);
    }
    pub fn sandboxThread(lua: *Lua) void {
        luaustate_api.luaL_sandboxthread(lua);
    }

    fn pushAnyString(lua: *Lua, value: anytype) error{OutOfMemory}!void {
        const info = @typeInfo(@TypeOf(value)).pointer;
        switch (info.size) {
            .one => {
                const childinfo = @typeInfo(info.child).array;
                std.debug.assert(childinfo.child == u8);
                std.debug.assert(childinfo.sentinel() != null);

                if (childinfo.sentinel()) |sentinel| {
                    if (sentinel != 0) {
                        @compileError("Sentinel of slice must be a null terminator");
                    }
                }
                _ = lua.pushStringZ(value);
            },
            .c, .many, .slice => {
                std.debug.assert(info.child == u8);
                if (info.sentinel()) |sentinel| {
                    if (sentinel != 0) {
                        @compileError("Sentinel of slice must be a null terminator");
                    }
                    _ = lua.pushStringZ(value);
                } else {
                    const allocator = try cetech1.tempalloc.create();
                    defer cetech1.tempalloc.destroy(allocator);

                    const null_terminated = try allocator.dupeZ(u8, value);
                    defer allocator.free(null_terminated);
                    _ = lua.pushStringZ(null_terminated);
                }
            },
        }
    }

    pub fn pushAny(lua: *Lua, value: anytype) !void {
        const T = @TypeOf(value);
        const type_info = @typeInfo(T);

        if (type_info == .@"struct" or type_info == .@"union" or type_info == .@"enum") {
            if (@hasDecl(T, "toLua")) {
                const toLuaArgs = .{ value, lua };
                const fnSignature = comptime fn_sign: {
                    var b: []const u8 = "pub fn toLua(";

                    for (0..toLuaArgs.len) |i| {
                        b = b ++ std.fmt.comptimePrint("{s}{s}", .{ @typeName(@TypeOf(toLuaArgs[i])), if (i == (toLuaArgs.len - 1)) "" else ", " });
                    }

                    b = b ++ ") !void";

                    break :fn_sign b;
                };

                const fl = @field(T, "toLua");
                const flt = @TypeOf(fl);
                const fli = @typeInfo(flt);
                switch (fli) {
                    .@"fn" => |f| {
                        const args_ok = comptime args_ok: {
                            const f_params = f.params;

                            if (f_params.len != toLuaArgs.len) break :args_ok false;

                            for (0..toLuaArgs.len) |i| {
                                if (f_params[i].type != @TypeOf(toLuaArgs[i])) break :args_ok false;
                            }

                            break :args_ok true;
                        };

                        if (args_ok) {
                            if (f.return_type) |rt| {
                                const rti = @typeInfo(rt);
                                switch (rti) {
                                    .error_union => {
                                        if (rti.error_union.payload == void) {
                                            return try @call(.auto, fl, toLuaArgs);
                                        } else {
                                            @compileError("toLua invalid return type, required fn signature: " ++ fnSignature);
                                        }
                                    },
                                    .void => {
                                        return @call(.auto, fl, toLuaArgs);
                                    },
                                    else => {
                                        @compileError("toLua invalid return type, required fn signature: " ++ fnSignature);
                                    },
                                }
                            } else {
                                return @call(.auto, fl, toLuaArgs);
                            }
                        } else {
                            @compileError("toLua has invalid args, required fn signature: " ++ fnSignature);
                        }
                    },
                    else => {
                        @compileError("toLua is not a function, required fn signature: " ++ fnSignature);
                    },
                }
            }
        }

        switch (type_info) {
            .comptime_int => {
                lua.pushInteger(@intCast(value));
            },
            .int => |info| {
                if (info.bits == 64) {
                    lua.pushInteger64(@bitCast(value));
                } else {
                    lua.pushInteger(@intCast(value));
                }
            },
            .float, .comptime_float => {
                lua.pushNumber(@floatCast(value));
            },
            .pointer => |info| {
                if (comptime isTypeString(info)) {
                    try lua.pushAnyString(value);
                } else switch (info.size) {
                    .one => {
                        if (info.is_const) {
                            @compileLog(value);
                            @compileLog("Lua cannot guarantee that references will not be modified");
                            @compileError("Pointer must not be const");
                        }
                        lua.pushLightUserdata(@ptrCast(value));
                    },
                    .c, .many, .slice => {
                        lua.createTable(0, 0);
                        for (value, 0..) |index_value, i| {
                            try lua.pushAny(i + 1);
                            try lua.pushAny(index_value);
                            lua.setTable(-3);
                        }
                    },
                }
            },
            .array => {
                lua.createTable(0, 0);
                for (value, 0..) |index_value, i| {
                    try lua.pushAny(i + 1);
                    try lua.pushAny(index_value);
                    lua.setTable(-3);
                }
            },
            .vector => |info| {
                try lua.pushAny(@as([info.len]info.child, value));
            },
            .bool => {
                lua.pushBoolean(value);
            },
            .@"enum" => {
                _ = lua.pushStringZ(@tagName(value));
            },
            .optional, .null => {
                if (value == null) {
                    lua.pushNil();
                } else {
                    try lua.pushAny(value.?);
                }
            },
            .@"struct" => |info| {
                lua.createTable(0, 0);
                if (info.is_tuple) {
                    inline for (0..info.fields.len) |i| {
                        try lua.pushAny(i + 1);
                        try lua.pushAny(value[i]);
                        lua.setTable(-3);
                    }
                } else {
                    inline for (info.fields) |field| {
                        try lua.pushAny(field.name);
                        try lua.pushAny(@field(value, field.name));
                        lua.setTable(-3);
                    }
                }
            },
            .@"union" => |info| {
                if (info.tag_type == null) @compileError("Parameter type is not a tagged union");
                lua.createTable(0, 0);
                errdefer lua.pop(1);
                try lua.pushAnyString(@tagName(value));

                inline for (info.fields) |field| {
                    if (std.mem.eql(u8, field.name, @tagName(value))) {
                        try lua.pushAny(@field(value, field.name));
                    }
                }
                lua.setTable(-3);
            },
            .@"fn" => {
                lua.autoPushFunction(value);
            },
            .void => {
                lua.createTable(0, 0);
            },
            else => {
                @compileLog(value);
                @compileError("Invalid type given");
            },
        }
    }

    pub fn toAnyAlloc(lua: *Lua, comptime T: type, index: i32) !Parsed(T) {
        const allocator = try cetech1.tempalloc.create();
        defer cetech1.tempalloc.destroy(allocator);

        var parsed = Parsed(T){
            .arena = try allocator.create(std.heap.ArenaAllocator),
            .value = undefined,
        };
        errdefer allocator.destroy(parsed.arena);
        parsed.arena.* = std.heap.ArenaAllocator.init(allocator);
        errdefer parsed.arena.deinit();

        parsed.value = try lua.toAnyInternal(T, parsed.arena.allocator(), true, index);

        return parsed;
    }

    pub inline fn toAny(lua: *Lua, comptime T: type, index: i32) !T {
        return lua.toAnyInternal(T, null, false, index);
    }

    pub fn toAnyInternal(lua: *Lua, comptime T: type, a: ?std.mem.Allocator, comptime allow_alloc: bool, index: i32) !T {
        const stack_size_on_entry = lua.getTop();
        defer {
            if (lua.getTop() != stack_size_on_entry) {
                std.debug.print("Type that filed to parse was: {any}\n", .{T});
                std.debug.print("Expected stack size: {}, Actual Stack Size: {}\n\n", .{ stack_size_on_entry, lua.getTop() });
                @panic("internal parsing error");
            }
        }

        const type_info = @typeInfo(T);

        if (type_info == .@"struct" or type_info == .@"union" or type_info == .@"enum") {
            if (@hasDecl(T, "fromLua")) {
                const fromLuaArgs = .{ lua, a, index };
                const fnSignature = comptime fn_sign: {
                    var b: []const u8 = "pub fn fromLua(";

                    for (0..fromLuaArgs.len) |i| {
                        b = b ++ std.fmt.comptimePrint("{s}{s}", .{ @typeName(@TypeOf(fromLuaArgs[i])), if (i == (fromLuaArgs.len - 1)) "" else ", " });
                    }

                    b = b ++ ") !" ++ @typeName(T);

                    break :fn_sign b;
                };

                const fl = @field(T, "fromLua");
                const flt = @TypeOf(fl);
                const fli = @typeInfo(flt);
                switch (fli) {
                    .@"fn" => |f| {
                        const args_ok = comptime args_ok: {
                            const f_params = f.params;

                            if (f_params.len != fromLuaArgs.len) break :args_ok false;

                            for (0..fromLuaArgs.len) |i| {
                                if (f_params[i].type != @TypeOf(fromLuaArgs[i])) break :args_ok false;
                            }

                            break :args_ok true;
                        };

                        if (args_ok) {
                            if (f.return_type) |rt| {
                                if (rt == T) {
                                    return @call(.auto, fl, fromLuaArgs);
                                } else {
                                    const rti = @typeInfo(rt);
                                    switch (rti) {
                                        .error_union => {
                                            if (rti.error_union.payload == T) {
                                                return try @call(.auto, fl, fromLuaArgs);
                                            } else {
                                                @compileError("fromLua invalid return type, required fn signature: " ++ fnSignature);
                                            }
                                        },
                                        else => {
                                            @compileError("fromLua invalid return type, required fn signature: " ++ fnSignature);
                                        },
                                    }
                                }
                            } else {
                                @compileError("fromLua require a fn signature: " ++ fnSignature);
                            }
                        } else {
                            @compileError("fromLua has invalid args, required fn signature: " ++ fnSignature);
                        }
                    },
                    else => {
                        @compileError("fromLua is not a function, required fn signature: " ++ fnSignature);
                    },
                }
            }
        }

        switch (type_info) {
            .int => |info| {
                if (info.bits == 64) {
                    const result = try lua.toInteger64(index);
                    return @as(T, @bitCast(result));
                } else {
                    const result = try lua.toInteger(index);
                    return @as(T, @intCast(result));
                }
            },
            .float => {
                const result = try lua.toNumber(index);
                return @as(T, @floatCast(result));
            },
            .array, .vector => {
                const child = std.meta.Child(T);
                const arr_len = switch (@typeInfo(T)) {
                    inline else => |i| i.len,
                };
                var result: [arr_len]child = undefined;
                lua.pushValue(index);
                defer lua.pop(1);

                for (0..arr_len) |i| {
                    if (lua.getMetaField(-1, "__index")) |_| {
                        lua.pushValue(-2);
                        lua.pushInteger(@intCast(i + 1));
                        lua.call(.{ .args = 1, .results = 1 });
                    } else |_| {
                        _ = lua.rawGetIndex(-1, @intCast(i + 1));
                    }
                    defer lua.pop(1);
                    result[i] = try lua.toAny(child, -1);
                }
                return result;
            },
            .pointer => |info| {
                if (comptime isTypeString(info)) {
                    const string: [*:0]const u8 = try lua.toString(index);
                    const end = std.mem.indexOfSentinel(u8, 0, string);

                    if (!info.is_const) {
                        if (!allow_alloc) {
                            @compileError("toAny cannot allocate memory, try using toAnyAlloc");
                        }

                        if (info.sentinel() != null) {
                            return try a.?.dupeZ(u8, string[0..end]);
                        } else {
                            return try a.?.dupe(u8, string[0..end]);
                        }
                    } else {
                        return if (info.sentinel() == null) string[0..end] else string[0..end :0];
                    }
                } else switch (info.size) {
                    .slice, .many => {
                        if (!allow_alloc) {
                            @compileError("toAny cannot allocate memory, try using toAnyAlloc");
                        }
                        return try lua.toSlice(info.child, a.?, index);
                    },
                    else => {
                        return try lua.toUserdata(info.child, index);
                    },
                }
            },
            .bool => {
                return lua.toBoolean(index);
            },
            .@"enum" => |info| {
                const string = try lua.toAnyInternal([]const u8, a, allow_alloc, index);
                inline for (info.fields) |enum_member| {
                    if (std.mem.eql(u8, string, enum_member.name)) {
                        return @field(T, enum_member.name);
                    }
                }
                return error.LuaInvalidEnumTagName;
            },
            .@"struct" => {
                if (type_info.@"struct".is_tuple) {
                    return try lua.toTuple(T, a, allow_alloc, index);
                } else {
                    return try lua.toStruct(T, a, allow_alloc, index);
                }
            },
            .@"union" => |u| {
                if (u.tag_type == null) @compileError("Parameter type is not a tagged union");
                if (!lua.isTable(index)) return error.LuaValueIsNotATable;

                lua.pushValue(index);
                defer lua.pop(1);
                lua.pushNil();
                if (lua.next(-2)) {
                    defer lua.pop(2);
                    const key = try lua.toAny([]const u8, -2);
                    inline for (u.fields) |field| {
                        if (std.mem.eql(u8, key, field.name)) {
                            return @unionInit(T, field.name, try lua.toAny(field.type, -1));
                        }
                    }
                    return error.LuaInvalidTagName;
                }
                return error.LuaTableIsEmpty;
            },
            .optional => {
                if (lua.isNil(index)) {
                    return null;
                } else {
                    return try lua.toAnyInternal(@typeInfo(T).optional.child, a, allow_alloc, index);
                }
            },
            .void => {
                if (!lua.isTable(index)) return error.LuaValueIsNotATable;
                lua.pushValue(index);
                defer lua.pop(1);
                lua.pushNil();
                if (lua.next(-2)) {
                    lua.pop(2);
                    return error.LuaVoidTableIsNotEmpty;
                }
                return void{};
            },
            else => {
                @compileError("Invalid parameter type");
            },
        }
    }

    pub fn toSlice(lua: *Lua, comptime ChildType: type, a: std.mem.Allocator, raw_index: i32) ![]ChildType {
        const index = lua.absIndex(raw_index);

        if (!lua.isTable(index)) {
            return error.LuaValueNotATable;
        }

        const size = lua.rawLen(index);
        var result = try a.alloc(ChildType, size);

        for (1..size + 1) |i| {
            _ = try lua.pushAny(i);
            _ = lua.getTable(index);
            defer lua.pop(1);
            result[i - 1] = try lua.toAnyInternal(ChildType, a, true, -1);
        }

        return result;
    }

    pub fn toTuple(lua: *Lua, comptime T: type, a: ?std.mem.Allocator, comptime allow_alloc: bool, raw_index: i32) !T {
        const stack_size_on_entry = lua.getTop();
        defer std.debug.assert(lua.getTop() == stack_size_on_entry);

        const info = @typeInfo(T).@"struct";
        const index = lua.absIndex(raw_index);

        var result: T = undefined;

        if (lua.isTable(index)) {
            lua.pushValue(index);
            defer lua.pop(1);

            inline for (info.fields, 0..) |field, i| {
                if (lua.getMetaField(-1, "__index")) |_| {
                    lua.pushValue(-2);
                    lua.pushInteger(@intCast(i + 1));
                    lua.call(.{ .args = 1, .results = 1 });
                } else |_| {
                    _ = lua.rawGetIndex(-1, @intCast(i + 1));
                }
                defer lua.pop(1);
                result[i] = try lua.toAnyInternal(field.type, a, allow_alloc, -1);
            }
        } else {
            // taking it as vararg
            const in_range = if (raw_index < 0) (index - @as(i32, info.fields.len)) >= 0 else ((index + @as(i32, info.fields.len)) - 1) <= stack_size_on_entry;
            if (in_range) {
                inline for (info.fields, 0..) |field, i| {
                    const stack_size_before_call = lua.getTop();
                    const idx = if (raw_index < 0) index - @as(i32, @intCast(i)) else index + @as(i32, @intCast(i));
                    result[i] = try lua.toAnyInternal(field.type, a, allow_alloc, idx);
                    std.debug.assert(stack_size_before_call == lua.getTop());
                }
            } else {
                return error.NotInRange;
            }
        }

        return result;
    }

    pub fn toStruct(lua: *Lua, comptime T: type, a: ?std.mem.Allocator, comptime allow_alloc: bool, raw_index: i32) !T {
        const stack_size_on_entry = lua.getTop();
        defer std.debug.assert(lua.getTop() == stack_size_on_entry);

        const index = lua.absIndex(raw_index);

        if (!lua.isTable(index)) {
            return error.LuaValueNotATable;
        }

        var result: T = undefined;

        inline for (@typeInfo(T).@"struct".fields) |field| {
            const field_type_info = comptime @typeInfo(field.type);
            const field_name = comptime field.name ++ "";
            _ = lua.pushStringZ(field_name);

            const lua_field_type = lua.getTable(index);
            defer lua.pop(1);
            if (lua_field_type == .nil) {
                if (field.defaultValue()) |default| {
                    @field(result, field.name) = default;
                } else if (field_type_info != .optional) {
                    return error.LuaTableMissingValue;
                } else {
                    @field(result, field.name) = null;
                }
            } else {
                const stack_size_before_call = lua.getTop();
                @field(result, field.name) = try lua.toAnyInternal(field.type, a, allow_alloc, -1);
                std.debug.assert(stack_size_before_call == lua.getTop());
            }
        }

        return result;
    }

    fn autoCallAndPush(lua: *Lua, comptime ReturnType: type, func_name: [:0]const u8, args: anytype) !void {
        if (try lua.getGlobal(func_name) != LuaType.function) return error.LuaInvalidFunctionName;

        inline for (args) |arg| {
            try lua.pushAny(arg);
        }

        const num_results = if (ReturnType == void) 0 else 1;
        try lua.protectedCall(.{ .args = args.len, .results = num_results });
    }

    fn autoCallAndPushRef(lua: *Lua, comptime ReturnType: type, ref_idx: i32, args: anytype) !void {
        if (lua.rawGetIndex(registry_index, ref_idx) != LuaType.function) return error.LuaInvalidFunctionRef;

        inline for (args) |arg| {
            try lua.pushAny(arg);
        }

        const num_results = if (ReturnType == void) 0 else 1;
        try lua.protectedCall(.{ .args = args.len, .results = num_results });
    }

    pub fn autoCall(lua: *Lua, comptime ReturnType: type, func_name: [:0]const u8, args: anytype) !ReturnType {
        try lua.autoCallAndPush(ReturnType, func_name, args);
        const result = try lua.toAny(ReturnType, -1);
        lua.setTop(0);
        return result;
    }

    pub fn autoCallRef(lua: *Lua, comptime ReturnType: type, ref_idx: i32, args: anytype) !ReturnType {
        try lua.autoCallAndPushRef(ReturnType, ref_idx, args);
        const result = try lua.toAny(ReturnType, -1);
        lua.setTop(0);
        return result;
    }

    pub fn autoPushFunction(lua: *Lua, function: anytype) void {
        const Interface = GenerateInterface(function);
        lua.pushFunction(wrap(Interface.interface));
    }

    pub fn get(lua: *Lua, comptime ReturnType: type, name: [:0]const u8) !ReturnType {
        _ = try lua.getGlobal(name);
        return try lua.toAny(ReturnType, -1);
    }

    pub fn set(lua: *Lua, name: [:0]const u8, value: anytype) !void {
        try lua.pushAny(value);
        lua.setGlobal(name);
    }

    pub fn raiseErrorStr(lua: *Lua, fmt: [:0]const u8, args: anytype) noreturn {
        _ = @call(
            .auto,
            luaustate_api.luaL_errorL,
            .{ @as(*Lua, @ptrCast(lua)), fmt.ptr } ++ args,
        );
        unreachable;
    }

    pub fn registerLuaApi(lua: *Lua, name: [:0]const u8, comptime T: type) void {
        const decls = switch (@typeInfo(T)) {
            inline .@"struct" => |info| info.decls,
            else => @compileError("Type " ++ @typeName(T) ++ "does not allow declarations"),
        };
        comptime var funcs: []const FnReg = &.{};
        inline for (decls) |d| {
            if (@typeInfo(@TypeOf(@field(T, d.name))) == .@"fn") {
                const reg: []const FnReg = &.{.{
                    .name = d.name,
                    .func = comptime wrap(GenerateInterface(@field(T, d.name)).interface),
                }};
                funcs = funcs ++ reg;
            }
        }
        lua.registerFns(name, funcs);
    }

    pub fn gcCollect(lua: *Lua) void {
        luaustate_api.gcCollect(lua);
    }

    pub fn gcStop(lua: *Lua) void {
        luaustate_api.gcStop(lua);
    }

    pub fn gcRestart(lua: *Lua) void {
        luaustate_api.gcRestart(lua);
    }

    pub fn gcStep(lua: *Lua, step_size: i32) void {
        luaustate_api.gcStep(lua, step_size);
    }

    pub fn gcCount(lua: *Lua) i32 {
        return luaustate_api.gcCount(lua);
    }

    pub fn gcCountB(lua: *Lua) i32 {
        return luaustate_api.gcCountB(lua);
    }

    pub fn gcIsRunning(lua: *Lua) bool {
        return luaustate_api.gcIsRunning(lua);
    }
};

const ArithOperator = enum(u4) {
    add = 0,
    sub,
    mul,
    div,
    mod,
    pow,
    negate,
};

pub const CompareOperator = enum(u2) {
    eq = 0,
    lt,
    le,
};

pub const CFn = *const fn (state: ?*Lua) callconv(.c) c_int;
pub const LuaType = enum(i5) {
    none = 0,
    nil,
    boolean,
    light_userdata,
    number,
    vector,
    string,
    table,
    function,
    userdata,
    thread,
};

pub const FnReg = struct {
    name: [:0]const u8,
    func: ?CFn,
};
pub const Integer = c_int;
pub const Unsigned = c_uint;
pub const Number = f64;

pub const CUserAtomCallbackFn = *const fn (state: ?*Lua, str: [*c]const u8, len: usize) callconv(.c) i16;
pub const CUserdataDtorFn = *const fn (userdata: *anyopaque) callconv(.c) void;
//
pub const CallArgs = struct {
    args: i32 = 0,
    results: i32 = 0,
};
const CProtectedCallError = error{ LuaRuntime, OutOfMemory, LuaMsgHandler };
pub const ProtectedCallArgs = struct {
    args: i32 = 0,
    results: i32 = 0,
    msg_handler: i32 = 0,
};
const CallError = error{ LuaRuntime, OutOfMemory, LuaMsgHandler };
const RawGetIndexNType = i32;
const RawSetIndexIType = i32;
const ToNumericError = error{ Overflow, ExpectedNumber, ExpectedInteger };

pub const LuauStateAPI = struct {
    create: *const fn (allocator: std.mem.Allocator) anyerror!*Lua,
    destroy: *const fn (lua: *Lua) void,

    //
    absIndex: *const fn (lua: *Lua, index: i32) i32,
    call: *const fn (lua: *Lua, args: CallArgs) void,
    checkStack: *const fn (lua: *Lua, n: i32) error{NoSpace}!void,
    concat: *const fn (lua: *Lua, n: i32) void,
    cProtectedCall: *const fn (lua: *Lua, c_fn: CFn, userdata: *anyopaque) CProtectedCallError!void,
    createTable: *const fn (lua: *Lua, num_arr: i32, num_rec: i32) void,
    equal: *const fn (lua: *Lua, index1: i32, index2: i32) bool,
    raiseError: *const fn (lua: *Lua) noreturn,
    getFnEnvironment: *const fn (lua: *Lua, index: i32) void,
    getField: *const fn (lua: *Lua, index: i32, key: [:0]const u8) LuaType,
    getGlobal: *const fn (lua: *Lua, name: [:0]const u8) error{LuaError}!LuaType,
    getMetatable: *const fn (lua: *Lua, index: i32) error{NoMetatable}!void,
    getTable: *const fn (lua: *Lua, index: i32) LuaType,
    getTop: *const fn (lua: *Lua) i32,
    setReadonly: *const fn (lua: *Lua, idx: i32, enabled: bool) void,
    getReadonly: *const fn (lua: *Lua, idx: i32) bool,
    insert: *const fn (lua: *Lua, index: i32) void,
    isBoolean: *const fn (lua: *Lua, index: i32) bool,
    isCFunction: *const fn (lua: *Lua, index: i32) bool,
    isFunction: *const fn (lua: *Lua, index: i32) bool,
    isLightUserdata: *const fn (lua: *Lua, index: i32) bool,
    isNil: *const fn (lua: *Lua, index: i32) bool,
    isNone: *const fn (lua: *Lua, index: i32) bool,
    isNoneOrNil: *const fn (lua: *Lua, index: i32) bool,
    isNumber: *const fn (lua: *Lua, index: i32) bool,
    isString: *const fn (lua: *Lua, index: i32) bool,
    isTable: *const fn (lua: *Lua, index: i32) bool,
    isThread: *const fn (lua: *Lua, index: i32) bool,
    isUserdata: *const fn (lua: *Lua, index: i32) bool,
    isVector: *const fn (lua: *Lua, index: i32) bool,
    isYieldable: *const fn (lua: *Lua) bool,
    lessThan: *const fn (lua: *Lua, index1: i32, index2: i32) bool,
    newTable: *const fn (lua: *Lua) void,
    newThread: *const fn (lua: *Lua) *Lua,
    getUserdataTag: *const fn (lua: *Lua, index: i32) error{ExpectedTaggedUserdata}!i32,
    next: *const fn (lua: *Lua, index: i32) bool,
    objectLen: *const fn (lua: *Lua, index: i32) i32,
    protectedCall: *const fn (lua: *Lua, args: ProtectedCallArgs) CallError!void,
    pop: *const fn (lua: *Lua, n: i32) void,
    pushBoolean: *const fn (lua: *Lua, b: bool) void,
    pushClosure: *const fn (lua: *Lua, c_fn: CFn, n: i32) void,
    pushClosureNamed: *const fn (lua: *Lua, c_fn: CFn, debugname: [:0]const u8, n: i32) void,
    pushFunction: *const fn (lua: *Lua, c_fn: CFn) void,
    pushFunctionNamed: *const fn (lua: *Lua, c_fn: CFn, debugname: [:0]const u8) void,
    pushInteger: *const fn (lua: *Lua, n: Integer) void,
    pushInteger64: *const fn (lua: *Lua, n: i64) void,
    pushLightUserdata: *const fn (lua: *Lua, ptr: *const anyopaque) void,
    pushString: *const fn (lua: *Lua, str: []const u8) [:0]const u8,
    pushNil: *const fn (lua: *Lua) void,
    pushNumber: *const fn (lua: *Lua, n: Number) void,
    pushStringZ: *const fn (lua: *Lua, str: [:0]const u8) [:0]const u8,
    pushThread: *const fn (lua: *Lua) bool,
    pushUnsigned: *const fn (lua: *Lua, n: Unsigned) void,
    pushValue: *const fn (lua: *Lua, index: i32) void,
    pushVector: *const fn (lua: *Lua, x: f32, y: f32, z: f32) void,
    rawEqual: *const fn (lua: *Lua, index1: i32, index2: i32) bool,
    rawGetTable: *const fn (lua: *Lua, index: i32) LuaType,
    rawGetIndex: *const fn (lua: *Lua, index: i32, n: RawGetIndexNType) LuaType,
    rawGetPtr: *const fn (lua: *Lua, index: i32, p: *const anyopaque) LuaType,
    rawGetPtrTagged: *const fn (lua: *Lua, index: i32, p: *const anyopaque, tag: i32) LuaType,
    rawLen: *const fn (lua: *Lua, index: i32) usize,
    rawSetTable: *const fn (lua: *Lua, index: i32) void,
    rawSetIndex: *const fn (lua: *Lua, index: i32, i: RawSetIndexIType) void,
    rawSetPtr: *const fn (lua: *Lua, index: i32, p: *const anyopaque) void,
    rawSetPtrTagged: *const fn (lua: *Lua, index: i32, p: *const anyopaque, tag: i32) void,
    register: *const fn (lua: *Lua, name: [:0]const u8, f: CFn) void,
    remove: *const fn (lua: *Lua, index: i32) void,
    replace: *const fn (lua: *Lua, index: i32) void,
    setFnEnvironment: *const fn (lua: *Lua, index: i32) error{InvalidValue}!void,
    setField: *const fn (lua: *Lua, index: i32, k: [:0]const u8) void,
    setGlobal: *const fn (lua: *Lua, name: [:0]const u8) void,
    setMetatable: *const fn (lua: *Lua, index: i32) void,
    setTable: *const fn (lua: *Lua, index: i32) void,
    setTop: *const fn (lua: *Lua, index: i32) void,
    setUserdataTag: *const fn (lua: *Lua, index: i32, tag: i32) void,
    toBoolean: *const fn (lua: *Lua, index: i32) bool,
    toCFunction: *const fn (lua: *Lua, index: i32) error{ExpectedFunction}!CFn,
    toInteger: *const fn (lua: *Lua, index: i32) error{ExpectedInteger}!Integer,
    toInteger64: *const fn (lua: *Lua, index: i32) error{ExpectedInteger64}!i64,
    toNumber: *const fn (lua: *Lua, index: i32) error{ExpectedNumber}!Number,
    toPointer: *const fn (lua: *Lua, index: i32) ?*const anyopaque,
    toString: *const fn (lua: *Lua, index: i32) error{ExpectedString}![:0]const u8,
    toThread: *const fn (lua: *Lua, index: i32) error{ExpectedThread}!*Lua,
    toUnsigned: *const fn (lua: *Lua, index: i32) error{ExpectedNumber}!Unsigned,
    toVector: *const fn (lua: *Lua, index: i32) error{ExpectedVector}![3]f32,
    toStringAtom: *const fn (lua: *Lua, index: i32) error{ExpectedString}!struct { i32, [:0]const u8 },
    namecallAtom: *const fn (lua: *Lua) error{ExpectedNamecall}!struct { i32, [:0]const u8 },
    typeOf: *const fn (lua: *Lua, index: i32) LuaType,
    typeName: *const fn (lua: *Lua, t: LuaType) [:0]const u8,
    upvalueIndex: *const fn (i: i32) i32,
    xMove: *const fn (lua: *Lua, to: *Lua, num: i32) void,
    yield: *const fn (lua: *Lua, num_results: i32) i32,
    argCheck: *const fn (lua: *Lua, cond: bool, arg: i32, extra_msg: [:0]const u8) void,
    argError: *const fn (lua: *Lua, arg: i32, extra_msg: [:0]const u8) noreturn,
    argExpected: *const fn (lua: *Lua, cond: bool, arg: i32, type_name: [:0]const u8) void,
    callMeta: *const fn (lua: *Lua, obj: i32, field: [:0]const u8) error{NoMetamethod}!void,
    checkAny: *const fn (lua: *Lua, arg: i32) void,
    checkInteger: *const fn (lua: *Lua, arg: i32) Integer,
    checkInteger64: *const fn (lua: *Lua, arg: i32) i64,
    checkNumber: *const fn (lua: *Lua, arg: i32) Number,
    checkStackErr: *const fn (lua: *Lua, size: i32, msg: ?[:0]const u8) void,
    checkString: *const fn (lua: *Lua, arg: i32) [:0]const u8,
    checkType: *const fn (lua: *Lua, arg: i32, t: LuaType) void,
    checkUnsigned: *const fn (lua: *Lua, arg: i32) Unsigned,
    checkVector: *const fn (lua: *Lua, arg: i32) [3]f32,
    getMetaField: *const fn (lua: *Lua, obj: i32, field: [:0]const u8) anyerror!LuaType,
    newLibTable: *const fn (lua: *Lua, list: []const FnReg) void,
    newMetatable: *const fn (lua: *Lua, key: [:0]const u8) error{KeyInRegistry}!void,
    optInteger: *const fn (lua: *Lua, arg: i32) ?Integer,
    optInteger64: *const fn (lua: *Lua, arg: i32) ?i64,
    optNumber: *const fn (lua: *Lua, arg: i32) ?Number,
    optString: *const fn (lua: *Lua, arg: i32) ?[:0]const u8,
    optUnsigned: *const fn (lua: *Lua, arg: i32) ?Unsigned,
    ref: *const fn (lua: *Lua, index: i32) i32,
    registerFns: *const fn (lua: *Lua, libname: ?[:0]const u8, funcs: []const FnReg) void,
    requireF: *const fn (lua: *Lua, mod_name: [:0]const u8, open_fn: CFn, global: bool) void,
    setFuncs: *const fn (lua: *Lua, funcs: []const FnReg, num_upvalues: i32) void,
    toStringEx: *const fn (lua: *Lua, index: i32) [:0]const u8,
    traceback: *const fn (lua: *Lua, state: *Lua, msg: ?[:0]const u8, level: i32) void,
    typeError: *const fn (lua: *Lua, arg: i32, type_name: [:0]const u8) noreturn,
    typeNameIndex: *const fn (lua: *Lua, index: i32) [:0]const u8,
    unref: *const fn (lua: *Lua, r: i32) void,
    where: *const fn (lua: *Lua, level: i32) void,

    luaL_errorL: *const fn (lua: *Lua, fmt: [*c]const u8, ...) callconv(.c) void,
    lua_touserdata: *const fn (lua: *Lua, idx: i32) callconv(.c) ?*anyopaque,
    luaL_sandbox: *const fn (lua: *Lua) callconv(.c) void,
    luaL_sandboxthread: *const fn (lua: *Lua) callconv(.c) void,

    loadBytecode: *const fn (lua: *Lua, chunkname: [:0]const u8, bytecode: []const u8) error{InvalidBytecode}!void,

    gcCollect: *const fn (lua: *Lua) void,
    gcStop: *const fn (lua: *Lua) void,
    gcRestart: *const fn (lua: *Lua) void,
    gcStep: *const fn (lua: *Lua, step_size: i32) void,
    gcCount: *const fn (lua: *Lua) i32,
    gcCountB: *const fn (lua: *Lua) i32,
    gcIsRunning: *const fn (lua: *Lua) bool,
};

pub const LuauVMAPI = struct {};

pub var luaustate_api: *const LuauStateAPI = undefined;
pub var luauvm_api: *const LuauVMAPI = undefined;

pub fn loadAPI(comptime module: @EnumLiteral()) !void {
    luauvm_api = apidb.getZigApi(module, LuauVMAPI).?;
    luaustate_api = apidb.getZigApi(module, LuauStateAPI).?;
}

pub fn Parsed(comptime T: type) type {
    return struct {
        arena: *std.heap.ArenaAllocator,
        value: T,

        pub fn deinit(self: @This()) void {
            const allocator_ = self.arena.child_allocator;
            self.arena.deinit();
            allocator_.destroy(self.arena);
        }
    };
}

pub fn GenerateInterface(comptime function: anytype) type {
    const info = @typeInfo(@TypeOf(function));
    if (info != .@"fn") {
        @compileLog(info);
        @compileLog(function);
        @compileError("function pointer must be passed");
    }
    return struct {
        pub fn interface(lua: *Lua) i32 {
            var parameters: std.meta.ArgsTuple(@TypeOf(function)) = undefined;

            inline for (info.@"fn".params, 0..) |param, i| {
                const param_info = @typeInfo(param.type.?);
                //only use the overhead of creating the arena allocator if needed
                if (comptime param_info == .pointer and param_info.pointer.size != .one) {
                    const parsed = lua.toAnyAlloc(param.type.?, (i + 1)) catch |err| {
                        lua.raiseErrorStr(@errorName(err), .{});
                    };

                    defer parsed.deinit();

                    parameters[i] = parsed.value;
                } else {
                    const parsed = lua.toAny(param.type.?, (i + 1)) catch |err| {
                        lua.raiseErrorStr(@errorName(err), .{});
                    };

                    parameters[i] = parsed;
                }
            }

            if (@typeInfo(info.@"fn".return_type.?) == .error_union) {
                const result = @call(.auto, function, parameters) catch |err| {
                    lua.raiseErrorStr(@errorName(err), .{});
                };
                lua.pushAny(result) catch |err| {
                    lua.raiseErrorStr(@errorName(err), .{});
                };
            } else {
                const result = @call(.auto, function, parameters);
                lua.pushAny(result) catch |err| {
                    lua.raiseErrorStr(@errorName(err), .{});
                };
            }

            return 1;
        }
    };
}

pub fn fnRegsFromType(comptime T: type) []const FnReg {
    const decls = switch (@typeInfo(T)) {
        inline .@"struct", .@"enum", .@"union", .@"opaque" => |info| info.decls,
        else => @compileError("Type " ++ @typeName(T) ++ "does not allow declarations"),
    };
    comptime var funcs: []const FnReg = &.{};
    inline for (decls) |d| {
        if (@typeInfo(@TypeOf(@field(T, d.name))) == .@"fn") {
            const reg: []const FnReg = &.{.{
                .name = d.name,
                .func = comptime wrap(@field(T, d.name)),
            }};
            funcs = funcs ++ reg;
        }
    }
    const final = funcs;
    return final;
}

fn isTypeString(typeinfo: std.builtin.Type.Pointer) bool {
    const childinfo = @typeInfo(typeinfo.child);
    if (typeinfo.child == u8 and typeinfo.size != .one) {
        return true;
    } else if (typeinfo.size == .one and childinfo == .array and childinfo.array.child == u8) {
        return true;
    }
    return false;
}

fn TypeOfWrap(comptime function: anytype) type {
    const params = @typeInfo(@TypeOf(function)).@"fn".params;
    if (params.len == 1) {
        if (params[0].type.? == *Lua) return CFn;
        if (params[0].type.? == *anyopaque) return CUserdataDtorFn;
    }
    if (params.len == 2) {
        if (params[0].type.? == *Lua) {
            // if (params[1].type.? == i32) return CInterruptCallbackFn;
            if (params[1].type.? == []const u8) return CUserAtomCallbackFn;
            // if (params[1].type.? == *anyopaque) return CReaderFn;
        }
    }
    if (params.len == 3) {
        // if (params[0].type.? == ?*anyopaque and params[1].type.? == []const u8 and params[2].type.? == bool) return CWarnFn;
        if (params[0].type.? == *Lua) {
            // if (params[1].type.? == Event and params[2].type.? == *DebugInfo) return CHookFn;
            // if (params[1].type.? == Status and params[2].type.? == Context) return CContFn;
            // if (params[1].type.? == []const u8 and params[2].type.? == *anyopaque) return CWriterFn;
        }
    }
    return {
        @compileLog(@TypeOf(function));
        @compileError("Unsupported function given to wrap.");
    };
}

pub fn wrap(comptime function: anytype) TypeOfWrap(function) {
    const info = @typeInfo(@TypeOf(function)).@"fn";

    const has_error_union = @typeInfo(info.return_type.?) == .error_union;

    const Return = TypeOfWrap(function);
    return switch (Return) {
        CFn => struct {
            fn inner(state: ?*Lua) callconv(.c) c_int {
                // this is called by Lua, state should never be null
                var lua: *Lua = @ptrCast(state.?);
                if (has_error_union) {
                    return @call(.always_inline, function, .{lua}) catch |err| {
                        lua.raiseErrorStr(@errorName(err), .{});
                    };
                } else {
                    return @call(.always_inline, function, .{lua});
                }
            }
        }.inner,
        // CHookFn => struct {
        //     fn inner(state: ?*Lua, ar: ?*Debug) callconv(.c) void {
        //         // this is called by Lua, state should never be null
        //         var lua: *Lua = @ptrCast(state.?);
        //         var debug_info: DebugInfo = .{
        //             .current_line = if (ar.?.currentline == -1) null else ar.?.currentline,
        //             .private = switch (lang) {
        //                 .lua51, .luajit => ar.?.i_ci,
        //                 else => @ptrCast(ar.?.i_ci),
        //             },
        //         };
        //         if (has_error_union) {
        //             @call(.always_inline, function, .{ lua, @as(Event, @enumFromInt(ar.?.event)), &debug_info }) catch |err| {
        //                 lua.raiseErrorStr(@errorName(err), .{});
        //             };
        //         } else {
        //             @call(.always_inline, function, .{ lua, @as(Event, @enumFromInt(ar.?.event)), &debug_info });
        //         }
        //     }
        // }.inner,
        // CContFn => struct {
        //     fn inner(state: ?*Lua, status: c_int, ctx: Context) callconv(.c) c_int {
        //         // this is called by Lua, state should never be null
        //         var lua: *Lua = @ptrCast(state.?);
        //         if (has_error_union) {
        //             return @call(.always_inline, function, .{ lua, @as(Status, @enumFromInt(status)), ctx }) catch |err| {
        //                 lua.raiseErrorStr(@errorName(err), .{});
        //             };
        //         } else {
        //             return @call(.always_inline, function, .{ lua, @as(Status, @enumFromInt(status)), ctx });
        //         }
        //     }
        // }.inner,
        // CReaderFn => struct {
        //     fn inner(state: ?*Lua, data: ?*anyopaque, size: [*c]usize) callconv(.c) [*c]const u8 {
        //         // this is called by Lua, state should never be null
        //         var lua: *Lua = @ptrCast(state.?);
        //         if (has_error_union) {
        //             const result = @call(.always_inline, function, .{ lua, data.? }) catch |err| {
        //                 lua.raiseErrorStr(@errorName(err), .{});
        //             };
        //             if (result) |buffer| {
        //                 size.* = buffer.len;
        //                 return buffer.ptr;
        //             } else {
        //                 size.* = 0;
        //                 return null;
        //             }
        //         } else {
        //             if (@call(.always_inline, function, .{ lua, data.? })) |buffer| {
        //                 size.* = buffer.len;
        //                 return buffer.ptr;
        //             } else {
        //                 size.* = 0;
        //                 return null;
        //             }
        //         }
        //     }
        // }.inner,
        CUserdataDtorFn => struct {
            fn inner(userdata: *anyopaque) callconv(.c) void {
                return @call(.always_inline, function, .{userdata});
            }
        }.inner,
        // CInterruptCallbackFn => struct {
        //     fn inner(state: ?*Lua, gc: c_int) callconv(.c) void {
        //         // this is called by Lua, state should never be null
        //         var lua: *Lua = @ptrCast(state.?);
        //         if (has_error_union) {
        //             @call(.always_inline, function, .{ lua, gc }) catch |err| {
        //                 lua.raiseErrorStr(@errorName(err), .{});
        //             };
        //         } else {
        //             @call(.always_inline, function, .{ lua, gc });
        //         }
        //     }
        // }.inner,
        CUserAtomCallbackFn => struct {
            fn inner(state: ?*Lua, str: [*c]const u8, len: usize) callconv(.c) i16 {
                // This is called by Lua, state should never be null.
                const lua: *Lua = @ptrCast(state.?);
                if (str) |s| {
                    const buf = s[0..len];
                    return @call(.always_inline, function, .{ lua, buf });
                }
                return -1;
            }
        }.inner,
        // CWarnFn => if (lang != .lua54) @compileError("CWarnFn is only valid in Lua >= 5.4") else struct {
        //     fn inner(data: ?*anyopaque, msg: [*c]const u8, to_cont: c_int) callconv(.c) void {
        //         // warning messages emitted from Lua should be null-terminated for display
        //         const message = std.mem.span(@as([*:0]const u8, @ptrCast(msg)));
        //         @call(.always_inline, function, .{ data, message, to_cont != 0 });
        //     }
        // }.inner,
        // CWriterFn => struct {
        //     fn inner(state: ?*Lua, buf: ?*const anyopaque, size: usize, data: ?*anyopaque) callconv(.c) c_int {
        //         // Lua 5.5 calls the writer with null at the end of dump
        //         if (lang == .lua55 and buf == null) return 0;
        //         // this is called by Lua, state should never be null
        //         var lua: *Lua = @ptrCast(state.?);
        //         const buffer = @as([*]const u8, @ptrCast(buf))[0..size];
        //
        //         const result = if (has_error_union) blk: {
        //             break :blk @call(.always_inline, function, .{ lua, buffer, data.? }) catch |err| {
        //                 lua.raiseErrorStr(@errorName(err), .{});
        //             };
        //         } else blk: {
        //             break :blk @call(.always_inline, function, .{ lua, buffer, data.? });
        //         };
        //
        //         // it makes more sense for the inner writer function to return false for failure,
        //         // so negate the result here
        //         return @intFromBool(!result);
        //     }
        // }.inner,
        else => unreachable,
    };
}
