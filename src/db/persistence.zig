const std = @import("std");
const catalog = @import("catalog.zig");
const row_store = @import("row_store.zig");
const value = @import("value.zig");

pub const current_version: u32 = 1;
pub const max_snapshot_bytes: usize = 128 * 1024 * 1024;

const magic = "SHOVELERDB";
const header_size = magic.len + 4 + 8 + 4;

const ColumnTypeTag = enum(u8) {
    integer = 1,
    float = 2,
    boolean = 3,
    text = 4,
    blob = 5,
    vector = 6,
};

const ValueTag = enum(u8) {
    null = 0,
    integer = 1,
    float = 2,
    boolean = 3,
    text = 4,
    blob = 5,
    vector = 6,
};

const VectorElementTag = enum(u8) {
    float32 = 1,
};

pub const DiagnosticKind = enum {
    invalid_header,
    unsupported_version,
    truncated_payload,
    payload_length_mismatch,
    payload_checksum_mismatch,
    invalid_column_type,
    invalid_value_tag,
    invalid_boolean_encoding,
    invalid_vector_element_type,
    row_store_mismatch,
    value_too_large,
};

pub fn diagnosticFromError(err: anyerror) ?DiagnosticKind {
    return switch (err) {
        error.InvalidHeader => .invalid_header,
        error.UnsupportedVersion => .unsupported_version,
        error.TruncatedPayload => .truncated_payload,
        error.PayloadLengthMismatch => .payload_length_mismatch,
        error.PayloadChecksumMismatch => .payload_checksum_mismatch,
        error.InvalidColumnType => .invalid_column_type,
        error.InvalidValueTag => .invalid_value_tag,
        error.InvalidBooleanEncoding => .invalid_boolean_encoding,
        error.InvalidVectorElementType => .invalid_vector_element_type,
        error.RowStoreMismatch => .row_store_mismatch,
        error.ValueTooLarge => .value_too_large,
        else => null,
    };
}

pub const DatabaseSnapshot = struct {
    allocator: std.mem.Allocator,
    catalog: catalog.DatabaseCatalog,
    stores: std.ArrayList(row_store.RowStore) = .empty,

    pub fn init(allocator: std.mem.Allocator) DatabaseSnapshot {
        return .{
            .allocator = allocator,
            .catalog = catalog.DatabaseCatalog.init(allocator),
        };
    }

    pub fn deinit(self: *DatabaseSnapshot) void {
        for (self.stores.items) |*store| store.deinit();
        self.stores.deinit(self.allocator);
        self.catalog.deinit();
        self.* = undefined;
    }

    pub fn refreshStoreTablePointers(self: *DatabaseSnapshot) void {
        for (self.stores.items, 0..) |*store, index| {
            if (index < self.catalog.tables.items.len) {
                store.table = &self.catalog.tables.items[index];
            }
        }
    }

    pub fn storeForTable(self: *DatabaseSnapshot, name: []const u8) ?*row_store.RowStore {
        const index = self.tableIndex(name) orelse return null;
        if (index >= self.stores.items.len) return null;
        return &self.stores.items[index];
    }

    pub fn storeForTableConst(self: *const DatabaseSnapshot, name: []const u8) ?*const row_store.RowStore {
        const index = self.tableIndex(name) orelse return null;
        if (index >= self.stores.items.len) return null;
        return &self.stores.items[index];
    }

    pub fn tableIndex(self: *const DatabaseSnapshot, name: []const u8) ?usize {
        for (self.catalog.tables.items, 0..) |table, index| {
            if (std.ascii.eqlIgnoreCase(table.name, name)) return index;
        }
        return null;
    }
};

pub fn writeSnapshot(
    allocator: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    path: []const u8,
    snapshot: *const DatabaseSnapshot,
) !void {
    const bytes = try encodeSnapshot(allocator, snapshot);
    defer allocator.free(bytes);

    const tmp_path = try std.fmt.allocPrint(allocator, "{s}.tmp", .{path});
    defer allocator.free(tmp_path);

    dir.deleteFile(io, tmp_path) catch |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    };

    var file = try dir.createFile(io, tmp_path, .{ .truncate = true });
    var file_open = true;
    errdefer {
        if (file_open) file.close(io);
        dir.deleteFile(io, tmp_path) catch {};
    }

    try file.writeStreamingAll(io, bytes);
    try file.sync(io);
    file.close(io);
    file_open = false;

    try dir.rename(tmp_path, dir, path, io);
}

pub fn readSnapshot(
    allocator: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    path: []const u8,
) !DatabaseSnapshot {
    const bytes = try dir.readFileAlloc(io, path, allocator, .limited(max_snapshot_bytes));
    defer allocator.free(bytes);
    return decodeSnapshot(allocator, bytes);
}

pub fn encodeSnapshot(allocator: std.mem.Allocator, snapshot: *const DatabaseSnapshot) ![]u8 {
    const payload = try encodePayload(allocator, snapshot);
    defer allocator.free(payload);

    var bytes: std.ArrayList(u8) = .empty;
    errdefer bytes.deinit(allocator);

    try bytes.appendSlice(allocator, magic);
    try appendU32(allocator, &bytes, current_version);
    try appendU64(allocator, &bytes, @as(u64, @intCast(payload.len)));
    try appendU32(allocator, &bytes, std.hash.Crc32.hash(payload));
    try bytes.appendSlice(allocator, payload);

    return bytes.toOwnedSlice(allocator);
}

pub fn decodeSnapshot(allocator: std.mem.Allocator, bytes: []const u8) !DatabaseSnapshot {
    if (bytes.len < header_size) return error.InvalidHeader;

    var cursor = Cursor.init(bytes);
    const found_magic = try cursor.readBytes(magic.len);
    if (!std.mem.eql(u8, found_magic, magic)) return error.InvalidHeader;

    const version = try cursor.readU32();
    if (version != current_version) return error.UnsupportedVersion;

    const payload_len = try cursor.readU64();
    const checksum = try cursor.readU32();
    if (payload_len != bytes.len - header_size) return error.PayloadLengthMismatch;

    const payload = bytes[header_size..];
    if (std.hash.Crc32.hash(payload) != checksum) return error.PayloadChecksumMismatch;

    var payload_cursor = Cursor.init(payload);
    var snapshot = try decodePayload(allocator, &payload_cursor);
    errdefer snapshot.deinit();
    if (!payload_cursor.finished()) return error.PayloadLengthMismatch;
    return snapshot;
}

fn encodePayload(allocator: std.mem.Allocator, snapshot: *const DatabaseSnapshot) ![]u8 {
    if (snapshot.catalog.tables.items.len != snapshot.stores.items.len) {
        return error.RowStoreMismatch;
    }

    var payload: std.ArrayList(u8) = .empty;
    errdefer payload.deinit(allocator);

    try appendCount(allocator, &payload, snapshot.catalog.tables.items.len);
    for (snapshot.catalog.tables.items, snapshot.stores.items) |table, store| {
        try appendBytes(allocator, &payload, table.name);
        try appendCount(allocator, &payload, table.columns.len);

        for (table.columns) |column| {
            try appendBytes(allocator, &payload, column.name);
            try appendColumnType(allocator, &payload, column.column_type);
            try appendBool(allocator, &payload, column.nullable);
            if (column.default_value) |default_value| {
                try appendBool(allocator, &payload, true);
                try appendValue(allocator, &payload, default_value);
            } else {
                try appendBool(allocator, &payload, false);
            }
        }

        try appendU64(allocator, &payload, store.nextRowId());
        try appendCount(allocator, &payload, store.rows().len);
        for (store.rows()) |row| {
            try appendU64(allocator, &payload, row.id);
            try appendCount(allocator, &payload, row.values.len);
            for (row.values) |runtime_value| {
                try appendValue(allocator, &payload, runtime_value);
            }
        }
    }

    try appendCount(allocator, &payload, snapshot.catalog.views.items.len);
    for (snapshot.catalog.views.items) |view| {
        try appendBytes(allocator, &payload, view.name);
        try appendBytes(allocator, &payload, view.body);
    }

    try appendCount(allocator, &payload, snapshot.catalog.procedures.items.len);
    for (snapshot.catalog.procedures.items) |procedure| {
        try appendBytes(allocator, &payload, procedure.name);
        try appendBytes(allocator, &payload, procedure.body);
    }

    return payload.toOwnedSlice(allocator);
}

fn decodePayload(allocator: std.mem.Allocator, cursor: *Cursor) !DatabaseSnapshot {
    var snapshot = DatabaseSnapshot.init(allocator);
    errdefer snapshot.deinit();

    const table_count = try cursor.readU32();
    for (0..table_count) |_| {
        try decodeTable(allocator, cursor, &snapshot);
    }
    snapshot.refreshStoreTablePointers();

    const view_count = try cursor.readU32();
    for (0..view_count) |_| {
        const name = try cursor.readLengthPrefixedBytes();
        const body = try cursor.readLengthPrefixedBytes();
        try snapshot.catalog.registerView(name, body);
    }

    const procedure_count = try cursor.readU32();
    for (0..procedure_count) |_| {
        const name = try cursor.readLengthPrefixedBytes();
        const body = try cursor.readLengthPrefixedBytes();
        try snapshot.catalog.registerProcedure(name, body);
    }

    return snapshot;
}

fn decodeTable(
    allocator: std.mem.Allocator,
    cursor: *Cursor,
    snapshot: *DatabaseSnapshot,
) !void {
    const table_name = try cursor.readLengthPrefixedBytes();
    const column_count = try cursor.readU32();

    var specs = try allocator.alloc(catalog.ColumnSpec, column_count);
    defer allocator.free(specs);

    var initialized: usize = 0;
    errdefer deinitColumnSpecDefaults(allocator, specs[0..initialized]);
    defer deinitColumnSpecDefaults(allocator, specs[0..initialized]);

    for (specs) |*spec| {
        const column_name = try cursor.readLengthPrefixedBytes();
        const column_type = try decodeColumnType(cursor);
        const nullable = try cursor.readBool();
        const has_default = try cursor.readBool();

        spec.* = .{
            .name = column_name,
            .column_type = column_type,
            .nullable = nullable,
            .default_value = if (has_default) try decodeValue(allocator, cursor) else null,
        };
        initialized += 1;
    }

    try snapshot.catalog.createTable(.{
        .name = table_name,
        .columns = specs,
    });

    snapshot.refreshStoreTablePointers();
    const table = snapshot.catalog.getTable(table_name) orelse return error.RowStoreMismatch;
    var store = row_store.RowStore.init(allocator, table);
    errdefer store.deinit();
    store.next_id = try cursor.readU64();

    const row_count = try cursor.readU32();
    for (0..row_count) |_| {
        try decodeRow(allocator, cursor, &store);
    }

    try snapshot.stores.append(allocator, store);
}

fn decodeRow(allocator: std.mem.Allocator, cursor: *Cursor, store: *row_store.RowStore) !void {
    const id = try cursor.readU64();
    const value_count = try cursor.readU32();

    var values = try allocator.alloc(value.Value, value_count);
    defer allocator.free(values);

    var initialized: usize = 0;
    errdefer deinitValues(allocator, values[0..initialized]);
    defer deinitValues(allocator, values[0..initialized]);

    for (values) |*runtime_value| {
        runtime_value.* = try decodeValue(allocator, cursor);
        initialized += 1;
    }

    try store.insertWithId(id, values);
}

fn appendColumnType(
    allocator: std.mem.Allocator,
    bytes: *std.ArrayList(u8),
    column_type: catalog.ColumnType,
) !void {
    switch (column_type) {
        .integer => try appendU8(allocator, bytes, @intFromEnum(ColumnTypeTag.integer)),
        .float => try appendU8(allocator, bytes, @intFromEnum(ColumnTypeTag.float)),
        .boolean => try appendU8(allocator, bytes, @intFromEnum(ColumnTypeTag.boolean)),
        .text => try appendU8(allocator, bytes, @intFromEnum(ColumnTypeTag.text)),
        .blob => try appendU8(allocator, bytes, @intFromEnum(ColumnTypeTag.blob)),
        .vector => |vector_type| {
            try appendU8(allocator, bytes, @intFromEnum(ColumnTypeTag.vector));
            try appendVectorElementType(allocator, bytes, vector_type.element_type);
            try appendCount(allocator, bytes, vector_type.dimension);
        },
    }
}

fn decodeColumnType(cursor: *Cursor) !catalog.ColumnType {
    const tag: ColumnTypeTag = switch (try cursor.readU8()) {
        @intFromEnum(ColumnTypeTag.integer) => .integer,
        @intFromEnum(ColumnTypeTag.float) => .float,
        @intFromEnum(ColumnTypeTag.boolean) => .boolean,
        @intFromEnum(ColumnTypeTag.text) => .text,
        @intFromEnum(ColumnTypeTag.blob) => .blob,
        @intFromEnum(ColumnTypeTag.vector) => .vector,
        else => return error.InvalidColumnType,
    };

    return switch (tag) {
        .integer => .integer,
        .float => .float,
        .boolean => .boolean,
        .text => .text,
        .blob => .blob,
        .vector => .{
            .vector = .{
                .element_type = try decodeVectorElementType(cursor),
                .dimension = try cursor.readU32(),
            },
        },
    };
}

fn appendValue(
    allocator: std.mem.Allocator,
    bytes: *std.ArrayList(u8),
    runtime_value: value.Value,
) !void {
    switch (runtime_value) {
        .null => try appendU8(allocator, bytes, @intFromEnum(ValueTag.null)),
        .integer => |integer| {
            try appendU8(allocator, bytes, @intFromEnum(ValueTag.integer));
            try appendU64(allocator, bytes, @as(u64, @bitCast(integer)));
        },
        .float => |float| {
            try appendU8(allocator, bytes, @intFromEnum(ValueTag.float));
            try appendU64(allocator, bytes, @as(u64, @bitCast(float)));
        },
        .boolean => |boolean| {
            try appendU8(allocator, bytes, @intFromEnum(ValueTag.boolean));
            try appendBool(allocator, bytes, boolean);
        },
        .text => |text| {
            try appendU8(allocator, bytes, @intFromEnum(ValueTag.text));
            try appendBytes(allocator, bytes, text);
        },
        .blob => |blob| {
            try appendU8(allocator, bytes, @intFromEnum(ValueTag.blob));
            try appendBytes(allocator, bytes, blob);
        },
        .vector => |vector| {
            try appendU8(allocator, bytes, @intFromEnum(ValueTag.vector));
            try appendVectorElementType(allocator, bytes, vector.element_type);
            try appendCount(allocator, bytes, vector.dimension);
            for (vector.values) |element| {
                try appendU32(allocator, bytes, @as(u32, @bitCast(element)));
            }
        },
    }
}

fn decodeValue(allocator: std.mem.Allocator, cursor: *Cursor) !value.Value {
    const tag: ValueTag = switch (try cursor.readU8()) {
        @intFromEnum(ValueTag.null) => .null,
        @intFromEnum(ValueTag.integer) => .integer,
        @intFromEnum(ValueTag.float) => .float,
        @intFromEnum(ValueTag.boolean) => .boolean,
        @intFromEnum(ValueTag.text) => .text,
        @intFromEnum(ValueTag.blob) => .blob,
        @intFromEnum(ValueTag.vector) => .vector,
        else => return error.InvalidValueTag,
    };

    return switch (tag) {
        .null => .null,
        .integer => .{ .integer = @as(i64, @bitCast(try cursor.readU64())) },
        .float => .{ .float = @as(f64, @bitCast(try cursor.readU64())) },
        .boolean => .{ .boolean = try cursor.readBool() },
        .text => value.Value.initText(allocator, try cursor.readLengthPrefixedBytes()),
        .blob => value.Value.initBlob(allocator, try cursor.readLengthPrefixedBytes()),
        .vector => {
            const element_type = try decodeVectorElementType(cursor);
            const dimension = try cursor.readU32();
            const vector_values = try allocator.alloc(f32, dimension);
            defer allocator.free(vector_values);

            for (vector_values) |*element| {
                element.* = @as(f32, @bitCast(try cursor.readU32()));
            }

            return value.Value.initVector(allocator, element_type, dimension, vector_values);
        },
    };
}

fn appendVectorElementType(
    allocator: std.mem.Allocator,
    bytes: *std.ArrayList(u8),
    element_type: value.VectorElementType,
) !void {
    return switch (element_type) {
        .float32 => appendU8(allocator, bytes, @intFromEnum(VectorElementTag.float32)),
    };
}

fn decodeVectorElementType(cursor: *Cursor) !value.VectorElementType {
    return switch (try cursor.readU8()) {
        @intFromEnum(VectorElementTag.float32) => .float32,
        else => error.InvalidVectorElementType,
    };
}

fn appendBytes(allocator: std.mem.Allocator, bytes: *std.ArrayList(u8), data: []const u8) !void {
    try appendCount(allocator, bytes, data.len);
    try bytes.appendSlice(allocator, data);
}

fn appendBool(allocator: std.mem.Allocator, bytes: *std.ArrayList(u8), boolean: bool) !void {
    try appendU8(allocator, bytes, if (boolean) 1 else 0);
}

fn appendCount(allocator: std.mem.Allocator, bytes: *std.ArrayList(u8), count: usize) !void {
    if (count > std.math.maxInt(u32)) return error.ValueTooLarge;
    try appendU32(allocator, bytes, @as(u32, @intCast(count)));
}

fn appendU8(allocator: std.mem.Allocator, bytes: *std.ArrayList(u8), v: u8) !void {
    try bytes.append(allocator, v);
}

fn appendU32(allocator: std.mem.Allocator, bytes: *std.ArrayList(u8), v: u32) !void {
    try bytes.append(allocator, @as(u8, @intCast(v & 0xff)));
    try bytes.append(allocator, @as(u8, @intCast((v >> 8) & 0xff)));
    try bytes.append(allocator, @as(u8, @intCast((v >> 16) & 0xff)));
    try bytes.append(allocator, @as(u8, @intCast((v >> 24) & 0xff)));
}

fn appendU64(allocator: std.mem.Allocator, bytes: *std.ArrayList(u8), v: u64) !void {
    try bytes.append(allocator, @as(u8, @intCast(v & 0xff)));
    try bytes.append(allocator, @as(u8, @intCast((v >> 8) & 0xff)));
    try bytes.append(allocator, @as(u8, @intCast((v >> 16) & 0xff)));
    try bytes.append(allocator, @as(u8, @intCast((v >> 24) & 0xff)));
    try bytes.append(allocator, @as(u8, @intCast((v >> 32) & 0xff)));
    try bytes.append(allocator, @as(u8, @intCast((v >> 40) & 0xff)));
    try bytes.append(allocator, @as(u8, @intCast((v >> 48) & 0xff)));
    try bytes.append(allocator, @as(u8, @intCast((v >> 56) & 0xff)));
}

fn deinitColumnSpecDefaults(allocator: std.mem.Allocator, specs: []catalog.ColumnSpec) void {
    for (specs) |*spec| {
        if (spec.default_value) |*default_value| default_value.deinit(allocator);
    }
}

fn deinitValues(allocator: std.mem.Allocator, values: []value.Value) void {
    for (values) |*runtime_value| runtime_value.deinit(allocator);
}

const Cursor = struct {
    bytes: []const u8,
    index: usize = 0,

    fn init(bytes: []const u8) Cursor {
        return .{ .bytes = bytes };
    }

    fn finished(self: Cursor) bool {
        return self.index == self.bytes.len;
    }

    fn readLengthPrefixedBytes(self: *Cursor) ![]const u8 {
        const len = try self.readU32();
        return self.readBytes(len);
    }

    fn readBytes(self: *Cursor, len: usize) ![]const u8 {
        if (len > self.bytes.len - self.index) return error.TruncatedPayload;
        const start = self.index;
        self.index += len;
        return self.bytes[start..self.index];
    }

    fn readBool(self: *Cursor) !bool {
        return switch (try self.readU8()) {
            0 => false,
            1 => true,
            else => error.InvalidBooleanEncoding,
        };
    }

    fn readU8(self: *Cursor) !u8 {
        const bytes = try self.readBytes(1);
        return bytes[0];
    }

    fn readU32(self: *Cursor) !u32 {
        const bytes = try self.readBytes(4);
        return @as(u32, bytes[0]) |
            (@as(u32, bytes[1]) << 8) |
            (@as(u32, bytes[2]) << 16) |
            (@as(u32, bytes[3]) << 24);
    }

    fn readU64(self: *Cursor) !u64 {
        const bytes = try self.readBytes(8);
        return @as(u64, bytes[0]) |
            (@as(u64, bytes[1]) << 8) |
            (@as(u64, bytes[2]) << 16) |
            (@as(u64, bytes[3]) << 24) |
            (@as(u64, bytes[4]) << 32) |
            (@as(u64, bytes[5]) << 40) |
            (@as(u64, bytes[6]) << 48) |
            (@as(u64, bytes[7]) << 56);
    }
};

fn makeSnapshot(allocator: std.mem.Allocator) !DatabaseSnapshot {
    var snapshot = DatabaseSnapshot.init(allocator);
    errdefer snapshot.deinit();

    var default_body = try value.Value.initText(allocator, "seed");
    defer default_body.deinit(allocator);

    try snapshot.catalog.createTable(.{
        .name = "memories",
        .columns = &.{
            .{ .name = "id", .column_type = .integer, .nullable = false },
            .{ .name = "body", .column_type = .text, .nullable = false, .default_value = default_body },
            .{ .name = "embedding", .column_type = .{ .vector = .{ .dimension = 2 } } },
        },
    });
    try snapshot.catalog.registerView("recent_memories", "SELECT body FROM memories");
    try snapshot.catalog.registerProcedure("remember", "BEGIN INSERT INTO memories VALUES (1); END");

    const table = snapshot.catalog.getTable("memories").?;
    var store = row_store.RowStore.init(allocator, table);
    errdefer store.deinit();

    var body = try value.Value.initText(allocator, "hello");
    defer body.deinit(allocator);
    var vector_value = try value.Value.initVector(allocator, .float32, 2, &.{ 0.25, 0.75 });
    defer vector_value.deinit(allocator);

    try store.insertWithId(7, &.{ .{ .integer = 1 }, body, vector_value });
    try snapshot.stores.append(allocator, store);
    return snapshot;
}

test "snapshot header validates magic version length and checksum" {
    const allocator = std.testing.allocator;

    var snapshot = try makeSnapshot(allocator);
    defer snapshot.deinit();

    const bytes = try encodeSnapshot(allocator, &snapshot);
    defer allocator.free(bytes);

    var decoded = try decodeSnapshot(allocator, bytes);
    defer decoded.deinit();

    try std.testing.expectEqual(@as(usize, 1), decoded.catalog.listTables().len);
    try std.testing.expectEqualStrings("memories", decoded.catalog.listTables()[0].name);

    var bad_magic = try allocator.dupe(u8, bytes);
    defer allocator.free(bad_magic);
    bad_magic[0] = 'x';
    try std.testing.expectError(error.InvalidHeader, decodeSnapshot(allocator, bad_magic));

    var bad_version = try allocator.dupe(u8, bytes);
    defer allocator.free(bad_version);
    bad_version[magic.len] = 99;
    try std.testing.expectError(error.UnsupportedVersion, decodeSnapshot(allocator, bad_version));

    var bad_checksum = try allocator.dupe(u8, bytes);
    defer allocator.free(bad_checksum);
    bad_checksum[header_size] ^= 0xff;
    try std.testing.expectError(error.PayloadChecksumMismatch, decodeSnapshot(allocator, bad_checksum));
}

test "snapshot write and reopen preserves catalog and committed rows" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var snapshot = try makeSnapshot(allocator);
    defer snapshot.deinit();

    try writeSnapshot(allocator, io, tmp.dir, "db.shovel", &snapshot);

    var reopened = try readSnapshot(allocator, io, tmp.dir, "db.shovel");
    defer reopened.deinit();

    const table = reopened.catalog.getTable("memories").?;
    try std.testing.expectEqual(@as(usize, 3), table.columns.len);
    try std.testing.expectEqualStrings("seed", table.column("body").?.default_value.?.text);
    try std.testing.expectEqual(@as(usize, 1), reopened.catalog.listViews().len);
    try std.testing.expectEqual(@as(usize, 1), reopened.catalog.listProcedures().len);

    const store = reopened.storeForTableConst("memories").?;
    try std.testing.expectEqual(@as(row_store.RowId, 8), store.nextRowId());
    try std.testing.expectEqual(@as(usize, 1), store.rows().len);
    try std.testing.expectEqual(@as(row_store.RowId, 7), store.rows()[0].id);
    try std.testing.expectEqualStrings("hello", store.rows()[0].values[1].text);
    try std.testing.expectEqualSlices(f32, &.{ 0.25, 0.75 }, store.rows()[0].values[2].vector.values);
}

test "invalid and truncated files fail loudly" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(io, .{ .sub_path = "empty.shovel", .data = "" });
    try std.testing.expectError(error.InvalidHeader, readSnapshot(allocator, io, tmp.dir, "empty.shovel"));

    try tmp.dir.writeFile(io, .{ .sub_path = "bad-magic.shovel", .data = "not-shoveler-data" });
    try std.testing.expectError(error.InvalidHeader, readSnapshot(allocator, io, tmp.dir, "bad-magic.shovel"));

    var snapshot = try makeSnapshot(allocator);
    defer snapshot.deinit();

    const bytes = try encodeSnapshot(allocator, &snapshot);
    defer allocator.free(bytes);

    try tmp.dir.writeFile(io, .{ .sub_path = "truncated.shovel", .data = bytes[0 .. bytes.len - 3] });
    try std.testing.expectError(
        error.PayloadLengthMismatch,
        readSnapshot(allocator, io, tmp.dir, "truncated.shovel"),
    );

    var malformed_payload: std.ArrayList(u8) = .empty;
    defer malformed_payload.deinit(allocator);
    try malformed_payload.appendSlice(allocator, magic);
    try appendU32(allocator, &malformed_payload, current_version);
    try appendU64(allocator, &malformed_payload, 1);
    try appendU32(allocator, &malformed_payload, std.hash.Crc32.hash(&.{0}));
    try malformed_payload.append(allocator, 0);
    try std.testing.expectError(error.TruncatedPayload, decodeSnapshot(allocator, malformed_payload.items));
}

test "failed decode does not mutate an existing in-memory snapshot" {
    const allocator = std.testing.allocator;

    var snapshot = try makeSnapshot(allocator);
    defer snapshot.deinit();

    try std.testing.expectError(error.InvalidHeader, decodeSnapshot(allocator, "broken"));
    try std.testing.expectEqual(@as(usize, 1), snapshot.catalog.listTables().len);
    try std.testing.expectEqual(@as(usize, 1), snapshot.storeForTableConst("memories").?.rows().len);
}
