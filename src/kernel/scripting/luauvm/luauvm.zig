const std = @import("std");
const Allocator = std.mem.Allocator;

const cetech1 = @import("cetech1");

const cdb = cetech1.cdb;
const ecs = cetech1.ecs;
const gpu = cetech1.gpu;
const task = cetech1.task;
const coreui = cetech1.coreui;
const apidb = cetech1.apidb;
const tempalloc = cetech1.tempalloc;
const assetdb = cetech1.assetdb;

const zlua = @import("zlua");

const luaapi = @import("luaapi.zig");
const public = cetech1.luauvm;

const module_name = .luauvm;

// Need for logging from std.
pub const std_options: std.Options = .{
    .logFn = cetech1.log.zigLogFnGen(),
};
// Log for module
const log = std.log.scoped(module_name);

// Basic cetech "import".
var _allocator: Allocator = undefined;

var _luau_asset_io_i = assetdb.AssetIOI.implement(struct {
    pub fn canImport(filename: []const u8, _: []const u8) bool {
        const extension = std.fs.path.extension(filename);
        return std.ascii.eqlIgnoreCase(extension, ".luau");
    }

    pub fn importAsset(
        io: std.Io,
        db: cdb.DbId,
        prereq: cetech1.task.TaskID,
        dir: std.Io.Dir,
        folder: cdb.ObjId,
        filename: []const u8,
        reimport_to: ?cdb.ObjId,
    ) !cetech1.task.TaskID {
        const Task = struct {
            io: std.Io,
            db: cdb.DbId,
            dir: std.Io.Dir,
            folder: cdb.ObjId,
            filename: []const u8,
            reimport_to: ?cdb.ObjId,
            pub fn exec(self: *@This()) !void {
                const allocator = tempalloc.create() catch undefined;
                defer tempalloc.destroy(allocator);

                const full_path = self.dir.realPathFileAlloc(self.io, self.filename, allocator) catch undefined;
                defer allocator.free(full_path);

                log.debug("Importing luau asset {s}", .{full_path});

                var asset_file = self.dir.openFile(self.io, self.filename, .{ .mode = .read_only }) catch |err| {
                    log.err("Could not import luau {}", .{err});
                    return;
                };

                defer asset_file.close(self.io);
                // defer self.dir.close(self.io);

                var buffer: [1024]u8 = undefined;
                var rb = asset_file.reader(self.io, &buffer);
                const asset_reader = &rb.interface;

                const asset_obj = if (self.reimport_to) |to| assetdb.getObjForAsset(to).? else try public.LuauScriptCdb.createObject(self.db);

                const content = try asset_reader.readAlloc(allocator, try asset_file.length(self.io));
                defer allocator.free(content);

                const bytecode = try zlua.compile(allocator, content, .{});
                defer allocator.free(bytecode);

                {
                    const w = public.LuauScriptCdb.write(asset_obj).?;
                    const blob = (try public.LuauScriptCdb.createBlob(w, .Bytecode, bytecode.len)).?;
                    @memcpy(blob, bytecode);
                    try public.LuauScriptCdb.commit(w);
                }

                const asset_name = std.fs.path.stem(std.fs.path.stem(self.filename));
                const asset = self.reimport_to orelse assetdb.createImportedAsset(asset_name, self.folder, asset_obj, self.filename).?;
                try assetdb.saveAsset(allocator, asset);
            }
        };

        return try task.schedule(
            prereq,
            Task{
                .io = io,
                .db = db,
                .dir = dir,
                .folder = folder,
                .filename = filename,
                .reimport_to = reimport_to,
            },
            .{},
        );
    }
});

var _luau_script_type_idx: cdb.TypeIdx = undefined;

fn pushInteger64(L: *public.Lua, n: i64) void {
    zlua.c.lua_pushinteger64(@ptrCast(L), n);
}

fn toInteger64(L: *public.Lua, idx: i32) error{ExpectedInteger64}!i64 {
    var is_integer: i32 = 0;
    const result = zlua.c.lua_tointeger64(@ptrCast(L), idx, &is_integer);
    if (is_integer != 0) return result;
    return error.ExpectedInteger64;
}

fn checkInteger64(L: *public.Lua, arg: i32) i64 {
    return zlua.c.luaL_checkinteger64(@ptrCast(L), arg);
}

fn optInteger64(L: *public.Lua, arg: i32) ?i64 {
    if (L.isNoneOrNil(arg)) return null;
    return checkInteger64(L, arg);
}

const luastate_api = public.LuauStateAPI{
    .absIndex = @ptrCast(&zlua.Lua.absIndex),
    .call = @ptrCast(&zlua.Lua.call),
    .checkStack = @ptrCast(&zlua.Lua.checkStack),
    .concat = @ptrCast(&zlua.Lua.concat),
    .cProtectedCall = @ptrCast(&zlua.Lua.cProtectedCall),
    .createTable = @ptrCast(&zlua.Lua.createTable),
    .equal = @ptrCast(&zlua.Lua.equal),
    .raiseError = @ptrCast(&zlua.Lua.raiseError),
    .getFnEnvironment = @ptrCast(&zlua.Lua.getFnEnvironment),
    .getField = @ptrCast(&zlua.Lua.getField),
    .getGlobal = @ptrCast(&zlua.Lua.getGlobal),
    .getMetatable = @ptrCast(&zlua.Lua.getMetatable),
    .getTable = @ptrCast(&zlua.Lua.getTable),
    .getTop = @ptrCast(&zlua.Lua.getTop),
    .setReadonly = @ptrCast(&zlua.Lua.setReadonly),
    .getReadonly = @ptrCast(&zlua.Lua.getReadonly),
    .insert = @ptrCast(&zlua.Lua.insert),
    .isBoolean = @ptrCast(&zlua.Lua.isBoolean),
    .isCFunction = @ptrCast(&zlua.Lua.isCFunction),
    .isFunction = @ptrCast(&zlua.Lua.isFunction),
    .isLightUserdata = @ptrCast(&zlua.Lua.isLightUserdata),
    .isNil = @ptrCast(&zlua.Lua.isNil),
    .isNone = @ptrCast(&zlua.Lua.isNone),
    .isNoneOrNil = @ptrCast(&zlua.Lua.isNoneOrNil),
    .isNumber = @ptrCast(&zlua.Lua.isNumber),
    .isString = @ptrCast(&zlua.Lua.isString),
    .isTable = @ptrCast(&zlua.Lua.isTable),
    .isThread = @ptrCast(&zlua.Lua.isThread),
    .isUserdata = @ptrCast(&zlua.Lua.isUserdata),
    .isVector = @ptrCast(&zlua.Lua.isVector),
    .isYieldable = @ptrCast(&zlua.Lua.isYieldable),
    .lessThan = @ptrCast(&zlua.Lua.lessThan),
    .newTable = @ptrCast(&zlua.Lua.newTable),
    .newThread = @ptrCast(&zlua.Lua.newThread),
    .getUserdataTag = @ptrCast(&zlua.Lua.getUserdataTag),
    .next = @ptrCast(&zlua.Lua.next),
    .objectLen = @ptrCast(&zlua.Lua.objectLen),
    .protectedCall = @ptrCast(&zlua.Lua.protectedCall),
    .pop = @ptrCast(&zlua.Lua.pop),
    .pushBoolean = @ptrCast(&zlua.Lua.pushBoolean),
    .pushClosure = @ptrCast(&zlua.Lua.pushClosure),
    .pushClosureNamed = @ptrCast(&zlua.Lua.pushClosureNamed),
    .pushFunction = @ptrCast(&zlua.Lua.pushFunction),
    .pushFunctionNamed = @ptrCast(&zlua.Lua.pushFunctionNamed),
    .pushInteger = @ptrCast(&zlua.Lua.pushInteger),
    .pushInteger64 = pushInteger64,
    .pushLightUserdata = @ptrCast(&zlua.Lua.pushLightUserdata),
    .pushString = @ptrCast(&zlua.Lua.pushString),
    .pushNil = @ptrCast(&zlua.Lua.pushNil),
    .pushNumber = @ptrCast(&zlua.Lua.pushNumber),
    .pushStringZ = @ptrCast(&zlua.Lua.pushStringZ),
    .pushThread = @ptrCast(&zlua.Lua.pushThread),
    .pushUnsigned = @ptrCast(&zlua.Lua.pushUnsigned),
    .pushValue = @ptrCast(&zlua.Lua.pushValue),
    .pushVector = @ptrCast(&zlua.Lua.pushVector),
    .rawEqual = @ptrCast(&zlua.Lua.rawEqual),
    .rawGetTable = @ptrCast(&zlua.Lua.rawGetTable),
    .rawGetIndex = @ptrCast(&zlua.Lua.rawGetIndex),
    .rawGetPtr = @ptrCast(&zlua.Lua.rawGetPtr),
    .rawGetPtrTagged = @ptrCast(&zlua.Lua.rawGetPtrTagged),
    .rawLen = @ptrCast(&zlua.Lua.rawLen),
    .rawSetTable = @ptrCast(&zlua.Lua.rawSetTable),
    .rawSetIndex = @ptrCast(&zlua.Lua.rawSetIndex),
    .rawSetPtr = @ptrCast(&zlua.Lua.rawSetPtr),
    .rawSetPtrTagged = @ptrCast(&zlua.Lua.rawSetPtrTagged),
    .register = @ptrCast(&zlua.Lua.register),
    .remove = @ptrCast(&zlua.Lua.remove),
    .replace = @ptrCast(&zlua.Lua.replace),
    .setFnEnvironment = @ptrCast(&zlua.Lua.setFnEnvironment),
    .setField = @ptrCast(&zlua.Lua.setField),
    .setGlobal = @ptrCast(&zlua.Lua.setGlobal),
    .setMetatable = @ptrCast(&zlua.Lua.setMetatable),
    .setTable = @ptrCast(&zlua.Lua.setTable),
    .setTop = @ptrCast(&zlua.Lua.setTop),
    .setUserdataTag = @ptrCast(&zlua.Lua.setUserdataTag),
    .toBoolean = @ptrCast(&zlua.Lua.toBoolean),
    .toCFunction = @ptrCast(&zlua.Lua.toCFunction),
    .toInteger = @ptrCast(&zlua.Lua.toInteger),
    .toInteger64 = toInteger64,
    .toNumber = @ptrCast(&zlua.Lua.toNumber),
    .toPointer = @ptrCast(&zlua.Lua.toPointer),
    .toString = @ptrCast(&zlua.Lua.toString),
    .toThread = @ptrCast(&zlua.Lua.toThread),
    .toUnsigned = @ptrCast(&zlua.Lua.toUnsigned),
    .toVector = @ptrCast(&zlua.Lua.toVector),
    .toStringAtom = @ptrCast(&zlua.Lua.toStringAtom),
    .namecallAtom = @ptrCast(&zlua.Lua.namecallAtom),
    .typeOf = @ptrCast(&zlua.Lua.typeOf),
    .typeName = @ptrCast(&zlua.Lua.typeName),
    .upvalueIndex = @ptrCast(&zlua.Lua.upvalueIndex),
    .xMove = @ptrCast(&zlua.Lua.xMove),
    .yield = @ptrCast(&zlua.Lua.yield),
    .argCheck = @ptrCast(&zlua.Lua.argCheck),
    .argError = @ptrCast(&zlua.Lua.argError),
    .argExpected = @ptrCast(&zlua.Lua.argExpected),
    .callMeta = @ptrCast(&zlua.Lua.callMeta),
    .checkAny = @ptrCast(&zlua.Lua.checkAny),
    .checkInteger = @ptrCast(&zlua.Lua.checkInteger),
    .checkInteger64 = checkInteger64,
    .checkNumber = @ptrCast(&zlua.Lua.checkNumber),
    .checkStackErr = @ptrCast(&zlua.Lua.checkStackErr),
    .checkString = @ptrCast(&zlua.Lua.checkString),
    .checkType = @ptrCast(&zlua.Lua.checkType),
    .checkUnsigned = @ptrCast(&zlua.Lua.checkUnsigned),
    .checkVector = @ptrCast(&zlua.Lua.checkVector),
    .getMetaField = @ptrCast(&zlua.Lua.getMetaField),
    .newLibTable = @ptrCast(&zlua.Lua.newLibTable),
    .newMetatable = @ptrCast(&zlua.Lua.newMetatable),
    .optInteger = @ptrCast(&zlua.Lua.optInteger),
    .optInteger64 = optInteger64,
    .optNumber = @ptrCast(&zlua.Lua.optNumber),
    .optString = @ptrCast(&zlua.Lua.optString),
    .optUnsigned = @ptrCast(&zlua.Lua.optUnsigned),
    .ref = @ptrCast(&zlua.Lua.ref),
    .registerFns = @ptrCast(&zlua.Lua.registerFns),
    .requireF = @ptrCast(&zlua.Lua.requireF),
    .setFuncs = @ptrCast(&zlua.Lua.setFuncs),
    .toStringEx = @ptrCast(&zlua.Lua.toStringEx),
    .traceback = @ptrCast(&zlua.Lua.traceback),
    .typeError = @ptrCast(&zlua.Lua.typeError),
    .typeNameIndex = @ptrCast(&zlua.Lua.typeNameIndex),
    .unref = @ptrCast(&zlua.Lua.unref),
    .where = @ptrCast(&zlua.Lua.where),
    .luaL_errorL = @ptrCast(&zlua.c.luaL_errorL),
    .lua_touserdata = @ptrCast(&zlua.c.lua_touserdata),
    .luaL_sandbox = @ptrCast(&zlua.c.luaL_sandbox),
    .luaL_sandboxthread = @ptrCast(&zlua.c.luaL_sandboxthread),
    .create = create,
    .destroy = destroy,
    .loadBytecode = @ptrCast(&zlua.Lua.loadBytecode),

    .gcCollect = @ptrCast(&zlua.Lua.gcCollect),
    .gcStop = @ptrCast(&zlua.Lua.gcStop),
    .gcRestart = @ptrCast(&zlua.Lua.gcRestart),
    .gcStep = @ptrCast(&zlua.Lua.gcStep),
    .gcCount = @ptrCast(&zlua.Lua.gcCount),
    .gcCountB = @ptrCast(&zlua.Lua.gcCountB),
    .gcIsRunning = @ptrCast(&zlua.Lua.gcIsRunning),
};

fn require(l: *zlua.Lua) i32 {
    const module_path = l.checkString(1);
    log.debug("require: {s}", .{module_path});

    return 0;
}

fn create(allocator: std.mem.Allocator) !*public.Lua {
    const l = try zlua.Lua.init(allocator);
    l.openLibs();
    luaapi.openApis(@ptrCast(l));

    l.pushFunction(zlua.wrap(require));
    l.setGlobal("require");

    return @ptrCast(l);
}

fn destroy(lua: *public.Lua) void {
    const l: *zlua.Lua = @ptrCast(lua);
    l.deinit();
}

// Register all cdb stuff in this method
var create_cdb_types_i = cdb.CreateTypesI.implement(struct {
    pub fn createTypes(db: cdb.DbId) !void {
        _luau_script_type_idx = try cdb.addType(
            db,
            public.LuauScriptCdb.name,
            &[_]cdb.PropDef{
                .{
                    .prop_idx = public.LuauScriptCdb.propIdx(.Bytecode),
                    .name = "bytecode",
                    .type = .BLOB,
                },
            },
        );
    }
});

// Create types, register api, interfaces etc...
pub fn load_module_zig(io: std.Io, allocator: Allocator, load: bool, reload: bool) anyerror!bool {
    _ = reload;
    _ = io;
    public.luaustate_api = &luastate_api;

    // basic
    _allocator = allocator;

    // impl interface
    try apidb.implOrRemove(module_name, cdb.CreateTypesI, &create_cdb_types_i, load);
    try apidb.implOrRemove(module_name, assetdb.AssetIOI, &_luau_asset_io_i, load);

    return true;
}

// This is only one fce that cetech1 need to load/unload/reload module.
pub export fn ct_load_module_luauvm(io: *const std.Io, apidb_: *const cetech1.apidb.ApiDbAPI, allocator: *const std.mem.Allocator, load: bool, reload: bool) callconv(.c) bool {
    return cetech1.modules.loadModuleZigHelper(load_module_zig, module_name, io, apidb_, allocator, load, reload);
}

comptime {
    std.debug.assert(public.registry_index == zlua.registry_index);
}
