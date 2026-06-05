const std = @import("std");
const executor = @import("../db/executor.zig");
const persistence = @import("../db/persistence.zig");

pub const StatusCode = enum(c_int) {
    ok = 0,
    invalid_argument = 1,
    invalid_handle = 2,
    allocation_failed = 3,
    parse_error = 4,
    object_error = 5,
    transaction_error = 6,
    type_error = 7,
    vector_error = 8,
    persistence_error = 9,
    io_error = 10,
    unsupported = 11,
    internal_error = 12,
};

pub const DiagnosticCode = enum(c_int) {
    none = 0,
    invalid_argument = 1,
    invalid_handle = 2,
    allocation = 3,
    parser = 4,
    object = 5,
    transaction = 6,
    type = 7,
    vector = 8,
    persistence = 9,
    io = 10,
    unsupported = 11,
    internal = 12,
};

pub const ResultKind = enum(c_int) {
    empty = 0,
    mutation_count = 1,
    rows = 2,
};

pub const ValueKind = enum(c_int) {
    null = 0,
    integer = 1,
    float = 2,
    boolean = 3,
    text = 4,
    blob = 5,
    vector_f32 = 6,
};

pub const StringView = extern struct {
    data: ?[*]const u8,
    len: usize,
};

pub const BytesView = extern struct {
    data: ?[*]const u8,
    len: usize,
};

pub const F32VectorView = extern struct {
    data: ?[*]const f32,
    len: usize,
};

pub const allocator = std.heap.smp_allocator;

var io_backend: std.Io.Threaded = std.Io.Threaded.init_single_threaded;

pub fn defaultIo() std.Io {
    return io_backend.io();
}

pub const DatabaseHandle = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    path: []u8,
    db: executor.Database,
    session: executor.Session,
    last_status: StatusCode = .ok,
    closed: bool = false,

    pub fn openOrCreate(
        allocator_arg: std.mem.Allocator,
        io_arg: std.Io,
        dir_arg: std.Io.Dir,
        path_arg: []const u8,
    ) !DatabaseHandle {
        const owned_path = try allocator_arg.dupe(u8, path_arg);
        var path_moved_to_handle = false;
        errdefer if (!path_moved_to_handle) allocator_arg.free(owned_path);

        var created = false;
        var db = openExecutorDatabase(allocator_arg, io_arg, dir_arg, path_arg) catch |err| switch (err) {
            error.FileNotFound => blk: {
                created = true;
                break :blk executor.Database.init(allocator_arg);
            },
            else => return err,
        };
        var db_moved_to_handle = false;
        errdefer if (!db_moved_to_handle) db.deinit();

        var handle = DatabaseHandle{
            .allocator = allocator_arg,
            .io = io_arg,
            .dir = dir_arg,
            .path = owned_path,
            .db = db,
            .session = executor.Session.init(allocator_arg),
        };
        path_moved_to_handle = true;
        db_moved_to_handle = true;
        errdefer handle.deinit();

        if (created) {
            try handle.checkpoint();
        }

        return handle;
    }

    pub fn deinit(self: *DatabaseHandle) void {
        if (self.closed) return;
        self.session.deinit();
        self.db.deinit();
        self.allocator.free(self.path);
        self.closed = true;
    }

    pub fn checkpoint(self: *DatabaseHandle) !void {
        if (self.closed) return error.InvalidHandle;
        var snapshot = try self.db.exportSnapshot();
        defer snapshot.deinit();
        try persistence.writeSnapshot(self.allocator, self.io, self.dir, self.path, &snapshot);
        self.last_status = .ok;
    }

    pub fn execute(self: *DatabaseHandle, sql: []const u8) !ResultHandle {
        if (self.closed) return error.InvalidHandle;
        var result = try self.db.executeSql(&self.session, sql);
        errdefer result.deinit(self.allocator);
        self.last_status = .ok;
        return .{
            .allocator = self.allocator,
            .result = result,
        };
    }
};

pub const ResultHandle = struct {
    allocator: std.mem.Allocator,
    result: executor.ExecutionResult,
    released: bool = false,

    pub fn deinit(self: *ResultHandle) void {
        if (self.released) return;
        self.result.deinit(self.allocator);
        self.released = true;
    }

    pub fn kind(self: *const ResultHandle) ResultKind {
        return switch (self.result) {
            .ok => .empty,
            .mutation_count => .mutation_count,
            .result_set => .rows,
        };
    }

    pub fn mutationCount(self: *const ResultHandle) u64 {
        return switch (self.result) {
            .mutation_count => |count| @intCast(count),
            else => 0,
        };
    }

    pub fn columnCount(self: *const ResultHandle) usize {
        return switch (self.result) {
            .result_set => |result_set| result_set.columns.len,
            else => 0,
        };
    }

    pub fn columnName(self: *const ResultHandle, index: usize) !StringView {
        return switch (self.result) {
            .result_set => |result_set| {
                if (index >= result_set.columns.len) return error.InvalidArgument;
                const name = result_set.columns[index];
                return .{ .data = name.ptr, .len = name.len };
            },
            else => error.InvalidArgument,
        };
    }
};

fn openExecutorDatabase(
    allocator_arg: std.mem.Allocator,
    io_arg: std.Io,
    dir_arg: std.Io.Dir,
    path_arg: []const u8,
) !executor.Database {
    var snapshot = try persistence.readSnapshot(allocator_arg, io_arg, dir_arg, path_arg);
    defer snapshot.deinit();
    return executor.Database.initFromSnapshot(allocator_arg, &snapshot);
}

test "ABI database handle opens creates checkpoints and reopens through executor" {
    const test_allocator = std.testing.allocator;
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var db = try DatabaseHandle.openOrCreate(test_allocator, io, tmp.dir, "abi.shovel");
    defer db.deinit();

    var result = try db.execute("CREATE TABLE memories (id INTEGER, body TEXT);");
    result.deinit();
    result = try db.execute("BEGIN;");
    result.deinit();
    result = try db.execute("INSERT INTO memories VALUES (1, 'hello');");
    try std.testing.expectEqual(ResultKind.mutation_count, result.kind());
    try std.testing.expectEqual(@as(u64, 1), result.mutationCount());
    result.deinit();
    result = try db.execute("COMMIT;");
    result.deinit();

    try db.checkpoint();
    db.deinit();

    var reopened = try DatabaseHandle.openOrCreate(test_allocator, io, tmp.dir, "abi.shovel");
    defer reopened.deinit();

    var selected = try reopened.execute("SELECT id, body FROM memories;");
    defer selected.deinit();
    try std.testing.expectEqual(ResultKind.rows, selected.kind());
    try std.testing.expectEqual(@as(usize, 2), selected.columnCount());
    const first_column = try selected.columnName(0);
    try std.testing.expectEqualStrings("id", first_column.data.?[0..first_column.len]);
}

test "ABI database handle cleans up once when initial checkpoint fails" {
    const test_allocator = std.testing.allocator;
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var db = DatabaseHandle.openOrCreate(test_allocator, io, tmp.dir, "missing/abi.shovel") catch |err| {
        try std.testing.expect(err == error.FileNotFound or err == error.NotDir);
        return;
    };
    defer db.deinit();

    return error.ExpectedCheckpointFailure;
}

test "ABI result cleanup is idempotent for owned handles" {
    const test_allocator = std.testing.allocator;
    var result = ResultHandle{
        .allocator = test_allocator,
        .result = .ok,
    };
    result.deinit();
    result.deinit();
    try std.testing.expect(result.released);
}
