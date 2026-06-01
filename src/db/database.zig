const std = @import("std");
const catalog = @import("catalog.zig");
const persistence = @import("persistence.zig");
const row_store = @import("row_store.zig");
const transaction = @import("transaction.zig");
const value = @import("value.zig");

pub const DatabaseError = error{
    DatabaseClosed,
    RowStoreMismatch,
    UnknownObject,
};

pub const DiagnosticKind = enum {
    database_closed,
    row_store_mismatch,
    unknown_object,
};

pub fn diagnosticFromError(err: anyerror) ?DiagnosticKind {
    return switch (err) {
        error.DatabaseClosed => .database_closed,
        error.RowStoreMismatch => .row_store_mismatch,
        error.UnknownObject => .unknown_object,
        else => null,
    };
}

/// Embedded API surface for WP08's CLI/executor wiring: callers can create
/// catalog objects, mutate committed row stores through transactions, then
/// checkpoint or close to persist the database file.
pub const Database = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    path: []u8,
    state: persistence.DatabaseSnapshot,
    closed: bool = false,

    pub fn create(
        allocator: std.mem.Allocator,
        io: std.Io,
        dir: std.Io.Dir,
        path: []const u8,
    ) !Database {
        const owned_path = try allocator.dupe(u8, path);
        errdefer allocator.free(owned_path);

        var db = Database{
            .allocator = allocator,
            .io = io,
            .dir = dir,
            .path = owned_path,
            .state = persistence.DatabaseSnapshot.init(allocator),
        };
        errdefer db.deinit();
        try db.checkpoint();
        return db;
    }

    pub fn open(
        allocator: std.mem.Allocator,
        io: std.Io,
        dir: std.Io.Dir,
        path: []const u8,
    ) !Database {
        const owned_path = try allocator.dupe(u8, path);
        errdefer allocator.free(owned_path);

        const state = try persistence.readSnapshot(allocator, io, dir, path);
        errdefer state.deinit();

        return .{
            .allocator = allocator,
            .io = io,
            .dir = dir,
            .path = owned_path,
            .state = state,
        };
    }

    pub fn openOrCreate(
        allocator: std.mem.Allocator,
        io: std.Io,
        dir: std.Io.Dir,
        path: []const u8,
    ) !Database {
        return open(allocator, io, dir, path) catch |err| switch (err) {
            error.FileNotFound => create(allocator, io, dir, path),
            else => return err,
        };
    }

    pub fn deinit(self: *Database) void {
        if (self.closed) return;
        self.state.deinit();
        self.allocator.free(self.path);
        self.closed = true;
    }

    pub fn close(self: *Database) !void {
        if (self.closed) return;
        try self.checkpoint();
        self.deinit();
    }

    pub fn checkpoint(self: *Database) !void {
        try self.ensureOpen();
        try persistence.writeSnapshot(self.allocator, self.io, self.dir, self.path, &self.state);
    }

    pub fn catalogView(self: *const Database) !*const catalog.DatabaseCatalog {
        try self.ensureOpen();
        return &self.state.catalog;
    }

    pub fn createTable(self: *Database, spec: catalog.TableSpec) !void {
        try self.ensureOpen();

        try self.state.catalog.createTable(spec);
        errdefer {
            self.state.catalog.dropTable(spec.name) catch {};
            self.state.refreshStoreTablePointers();
        }

        self.state.refreshStoreTablePointers();
        const table_def = self.state.catalog.getTable(spec.name) orelse return error.RowStoreMismatch;
        const store = row_store.RowStore.init(self.allocator, table_def);
        try self.state.stores.append(self.allocator, store);
        self.state.refreshStoreTablePointers();
    }

    pub fn dropTable(self: *Database, name: []const u8) !void {
        try self.ensureOpen();

        const index = self.state.tableIndex(name) orelse return error.UnknownObject;
        if (index >= self.state.stores.items.len) return error.RowStoreMismatch;

        var store = self.state.stores.orderedRemove(index);
        store.deinit();
        try self.state.catalog.dropTable(name);
        self.state.refreshStoreTablePointers();
    }

    pub fn table(self: *const Database, name: []const u8) !?*const catalog.TableDef {
        try self.ensureOpen();
        return self.state.catalog.getTable(name);
    }

    pub fn insert(self: *Database, table_name: []const u8, values: []const value.Value) !row_store.RowId {
        try self.ensureOpen();
        const store = self.state.storeForTable(table_name) orelse return error.UnknownObject;
        return store.insert(values);
    }

    pub fn beginTransaction(self: *Database, table_name: []const u8) !transaction.Transaction {
        try self.ensureOpen();
        const store = self.state.storeForTable(table_name) orelse return error.UnknownObject;
        return transaction.Transaction.begin(self.allocator, store);
    }

    pub fn rows(self: *const Database, table_name: []const u8) ![]const row_store.Row {
        try self.ensureOpen();
        const store = self.state.storeForTableConst(table_name) orelse return error.UnknownObject;
        return store.rows();
    }

    fn ensureOpen(self: *const Database) DatabaseError!void {
        if (self.closed) return error.DatabaseClosed;
    }
};

test "database creates checkpoints closes and reopens committed rows" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var db = try Database.openOrCreate(allocator, io, tmp.dir, "agent-memory.shovel");
    try db.createTable(.{
        .name = "memories",
        .columns = &.{
            .{ .name = "id", .column_type = .integer, .nullable = false },
            .{ .name = "body", .column_type = .text, .nullable = false },
            .{ .name = "embedding", .column_type = .{ .vector = .{ .dimension = 2 } } },
        },
    });

    var tx = try db.beginTransaction("memories");
    defer tx.deinit();

    var body = try value.Value.initText(allocator, "committed");
    defer body.deinit(allocator);
    var embedding = try value.Value.initVector(allocator, .float32, 2, &.{ 0.5, 0.5 });
    defer embedding.deinit(allocator);

    const row_id = try tx.insert(&.{ .{ .integer = 1 }, body, embedding });
    try tx.commit();
    try std.testing.expectEqual(@as(row_store.RowId, 1), row_id);

    try db.close();

    var reopened = try Database.open(allocator, io, tmp.dir, "agent-memory.shovel");
    defer reopened.deinit();

    const table = (try reopened.table("MEMORIES")).?;
    try std.testing.expectEqual(@as(usize, 3), table.columns.len);

    const rows = try reopened.rows("memories");
    try std.testing.expectEqual(@as(usize, 1), rows.len);
    try std.testing.expectEqual(@as(row_store.RowId, 1), rows[0].id);
    try std.testing.expectEqualStrings("committed", rows[0].values[1].text);
    try std.testing.expectEqualSlices(f32, &.{ 0.5, 0.5 }, rows[0].values[2].vector.values);
}

test "database open refuses corrupt files without touching existing handles" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var db = try Database.create(allocator, io, tmp.dir, "good.shovel");
    defer db.deinit();

    try db.createTable(.{
        .name = "memories",
        .columns = &.{.{ .name = "id", .column_type = .integer, .nullable = false }},
    });

    try tmp.dir.writeFile(io, .{ .sub_path = "bad.shovel", .data = "bad" });
    try std.testing.expectError(error.InvalidHeader, Database.open(allocator, io, tmp.dir, "bad.shovel"));

    try std.testing.expect((try db.table("memories")) != null);
    try std.testing.expectError(error.UnknownObject, db.rows("missing"));
}

test "database close is idempotent and prevents further mutation" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var db = try Database.create(allocator, io, tmp.dir, "closed.shovel");
    try db.close();
    try db.close();
    try std.testing.expectError(error.DatabaseClosed, db.createTable(.{
        .name = "memories",
        .columns = &.{.{ .name = "id", .column_type = .integer }},
    }));
}
