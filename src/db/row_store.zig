const std = @import("std");
const catalog = @import("catalog.zig");
const value = @import("value.zig");

pub const RowId = u64;

pub const RowStoreError = error{
    ColumnCountMismatch,
    DuplicateRow,
    UnknownRow,
    TypeMismatch,
    VectorDimensionMismatch,
    InvalidVectorDimension,
};

pub const DiagnosticKind = enum {
    column_count_mismatch,
    duplicate_row,
    unknown_row,
    type_mismatch,
    vector_dimension_mismatch,
    invalid_vector_dimension,
};

pub fn diagnosticFromError(err: anyerror) ?DiagnosticKind {
    return switch (err) {
        error.ColumnCountMismatch => .column_count_mismatch,
        error.DuplicateRow => .duplicate_row,
        error.UnknownRow => .unknown_row,
        error.TypeMismatch => .type_mismatch,
        error.VectorDimensionMismatch => .vector_dimension_mismatch,
        error.InvalidVectorDimension => .invalid_vector_dimension,
        else => null,
    };
}

pub const Row = struct {
    id: RowId,
    values: []value.Value,

    pub fn init(
        allocator: std.mem.Allocator,
        table: *const catalog.TableDef,
        id: RowId,
        values: []const value.Value,
    ) !Row {
        try validateValues(table, values);

        var owned = try allocator.alloc(value.Value, values.len);
        errdefer allocator.free(owned);

        var initialized: usize = 0;
        errdefer deinitValues(allocator, owned[0..initialized]);

        for (values, 0..) |runtime_value, index| {
            owned[index] = try runtime_value.clone(allocator);
            initialized += 1;
        }

        return .{ .id = id, .values = owned };
    }

    pub fn clone(self: Row, allocator: std.mem.Allocator, table: *const catalog.TableDef) !Row {
        return init(allocator, table, self.id, self.values);
    }

    pub fn deinit(self: *Row, allocator: std.mem.Allocator) void {
        deinitValues(allocator, self.values);
        allocator.free(self.values);
        self.* = undefined;
    }

    pub fn replaceValues(
        self: *Row,
        allocator: std.mem.Allocator,
        table: *const catalog.TableDef,
        next_values: []const value.Value,
    ) !void {
        var replacement = try Row.init(allocator, table, self.id, next_values);
        deinitValues(allocator, self.values);
        allocator.free(self.values);
        self.values = replacement.values;
        replacement.values = &.{};
    }
};

pub const RowStore = struct {
    allocator: std.mem.Allocator,
    table: *const catalog.TableDef,
    rows_list: std.ArrayList(Row) = .empty,
    next_id: RowId = 1,

    pub fn init(allocator: std.mem.Allocator, table: *const catalog.TableDef) RowStore {
        return .{
            .allocator = allocator,
            .table = table,
        };
    }

    pub fn deinit(self: *RowStore) void {
        for (self.rows_list.items) |*row| row.deinit(self.allocator);
        self.rows_list.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn clone(self: *const RowStore, allocator: std.mem.Allocator) !RowStore {
        var copy = RowStore.init(allocator, self.table);
        copy.next_id = self.next_id;
        errdefer copy.deinit();

        for (self.rows_list.items) |row| {
            var cloned = try row.clone(allocator, self.table);
            errdefer cloned.deinit(allocator);
            try copy.rows_list.append(allocator, cloned);
        }

        return copy;
    }

    pub fn nextRowId(self: *const RowStore) RowId {
        return self.next_id;
    }

    pub fn allocateRowId(self: *RowStore) RowId {
        const id = self.next_id;
        self.next_id += 1;
        return id;
    }

    pub fn insert(self: *RowStore, values: []const value.Value) !RowId {
        const id = self.nextRowId();
        try self.insertWithId(id, values);
        return id;
    }

    pub fn insertWithId(self: *RowStore, id: RowId, values: []const value.Value) !void {
        if (self.findRowIndex(id) != null) return error.DuplicateRow;

        var row = try Row.init(self.allocator, self.table, id, values);
        errdefer row.deinit(self.allocator);

        try self.rows_list.append(self.allocator, row);
        if (id >= self.next_id) self.next_id = id + 1;
    }

    pub fn update(self: *RowStore, id: RowId, values: []const value.Value) !void {
        const index = self.findRowIndex(id) orelse return error.UnknownRow;
        try self.rows_list.items[index].replaceValues(self.allocator, self.table, values);
    }

    pub fn delete(self: *RowStore, id: RowId) RowStoreError!void {
        const index = self.findRowIndex(id) orelse return error.UnknownRow;
        var row = self.rows_list.orderedRemove(index);
        row.deinit(self.allocator);
    }

    pub fn get(self: *const RowStore, id: RowId) ?*const Row {
        const index = self.findRowIndex(id) orelse return null;
        return &self.rows_list.items[index];
    }

    pub fn rows(self: *const RowStore) []const Row {
        return self.rows_list.items;
    }

    fn findRowIndex(self: *const RowStore, id: RowId) ?usize {
        for (self.rows_list.items, 0..) |row, index| {
            if (row.id == id) return index;
        }
        return null;
    }
};

pub fn deinitRows(allocator: std.mem.Allocator, rows: []Row) void {
    for (rows) |*row| row.deinit(allocator);
    allocator.free(rows);
}

fn validateValues(table: *const catalog.TableDef, values: []const value.Value) RowStoreError!void {
    if (values.len != table.columns.len) return error.ColumnCountMismatch;

    for (values, table.columns) |runtime_value, column| {
        column.validateValue(runtime_value) catch |err| switch (err) {
            error.TypeMismatch => return error.TypeMismatch,
            error.VectorDimensionMismatch => return error.VectorDimensionMismatch,
            error.InvalidVectorDimension => return error.InvalidVectorDimension,
            else => unreachable,
        };
    }
}

fn deinitValues(allocator: std.mem.Allocator, values: []value.Value) void {
    for (values) |*runtime_value| runtime_value.deinit(allocator);
}

fn makeMemoryTable(allocator: std.mem.Allocator) !catalog.TableDef {
    return catalog.TableDef.init(allocator, .{
        .name = "memories",
        .columns = &.{
            .{ .name = "id", .column_type = .integer, .nullable = false },
            .{ .name = "body", .column_type = .text, .nullable = false },
            .{ .name = "embedding", .column_type = .{ .vector = .{ .dimension = 2 } } },
        },
    });
}

test "row store allocates stable row ids and scans in insertion order" {
    const allocator = std.testing.allocator;

    var table = try makeMemoryTable(allocator);
    defer table.deinit(allocator);

    var store = RowStore.init(allocator, &table);
    defer store.deinit();

    var first_body = try value.Value.initText(allocator, "first");
    defer first_body.deinit(allocator);
    var first_vector = try value.Value.initVector(allocator, .float32, 2, &.{ 1.0, 0.0 });
    defer first_vector.deinit(allocator);

    const first = try store.insert(&.{
        .{ .integer = 1 },
        first_body,
        first_vector,
    });

    var second_body = try value.Value.initText(allocator, "second");
    defer second_body.deinit(allocator);
    var second_vector = try value.Value.initVector(allocator, .float32, 2, &.{ 0.0, 1.0 });
    defer second_vector.deinit(allocator);

    const second = try store.insert(&.{
        .{ .integer = 2 },
        second_body,
        second_vector,
    });

    try std.testing.expectEqual(@as(RowId, 1), first);
    try std.testing.expectEqual(@as(RowId, 2), second);
    try std.testing.expectEqual(@as(usize, 2), store.rows().len);
    try std.testing.expectEqual(first, store.rows()[0].id);
    try std.testing.expectEqual(second, store.rows()[1].id);
}

test "row store updates and deletes without reusing row ids" {
    const allocator = std.testing.allocator;

    var table = try makeMemoryTable(allocator);
    defer table.deinit(allocator);

    var store = RowStore.init(allocator, &table);
    defer store.deinit();

    var body = try value.Value.initText(allocator, "original");
    defer body.deinit(allocator);
    var vector_value = try value.Value.initVector(allocator, .float32, 2, &.{ 1.0, 0.0 });
    defer vector_value.deinit(allocator);

    const first = try store.insert(&.{ .{ .integer = 1 }, body, vector_value });

    var updated_body = try value.Value.initText(allocator, "updated");
    defer updated_body.deinit(allocator);
    var updated_vector = try value.Value.initVector(allocator, .float32, 2, &.{ 0.5, 0.5 });
    defer updated_vector.deinit(allocator);

    try store.update(first, &.{ .{ .integer = 1 }, updated_body, updated_vector });
    try std.testing.expectEqualStrings("updated", store.get(first).?.values[1].text);

    try store.delete(first);
    try std.testing.expect(store.get(first) == null);
    try std.testing.expectError(error.UnknownRow, store.delete(first));

    var next_body = try value.Value.initText(allocator, "next");
    defer next_body.deinit(allocator);
    var next_vector = try value.Value.initVector(allocator, .float32, 2, &.{ 0.25, 0.75 });
    defer next_vector.deinit(allocator);

    const next = try store.insert(&.{ .{ .integer = 2 }, next_body, next_vector });
    try std.testing.expectEqual(@as(RowId, 2), next);
}

test "row store validates column counts and typed vector dimensions before mutation" {
    const allocator = std.testing.allocator;

    var table = try makeMemoryTable(allocator);
    defer table.deinit(allocator);

    var store = RowStore.init(allocator, &table);
    defer store.deinit();

    try std.testing.expectError(error.ColumnCountMismatch, store.insert(&.{.{ .integer = 1 }}));
    try std.testing.expectEqual(@as(usize, 0), store.rows().len);

    var body = try value.Value.initText(allocator, "bad");
    defer body.deinit(allocator);
    var wrong_vector = try value.Value.initVector(allocator, .float32, 3, &.{ 1.0, 2.0, 3.0 });
    defer wrong_vector.deinit(allocator);

    try std.testing.expectError(
        error.VectorDimensionMismatch,
        store.insert(&.{ .{ .integer = 1 }, body, wrong_vector }),
    );
    try std.testing.expectEqual(@as(usize, 0), store.rows().len);
}

test "row store clone owns independent row values" {
    const allocator = std.testing.allocator;

    var table = try makeMemoryTable(allocator);
    defer table.deinit(allocator);

    var store = RowStore.init(allocator, &table);
    defer store.deinit();

    var body = try value.Value.initText(allocator, "clone me");
    defer body.deinit(allocator);
    var vector_value = try value.Value.initVector(allocator, .float32, 2, &.{ 0.2, 0.8 });
    defer vector_value.deinit(allocator);

    _ = try store.insert(&.{ .{ .integer = 1 }, body, vector_value });

    var copy = try store.clone(allocator);
    defer copy.deinit();

    try std.testing.expectEqual(@as(usize, 1), copy.rows().len);
    try std.testing.expectEqualStrings(store.rows()[0].values[1].text, copy.rows()[0].values[1].text);
    try std.testing.expect(store.rows()[0].values[1].text.ptr != copy.rows()[0].values[1].text.ptr);
}

test "row store diagnostics map stable typed errors" {
    try std.testing.expectEqual(DiagnosticKind.column_count_mismatch, diagnosticFromError(error.ColumnCountMismatch).?);
    try std.testing.expectEqual(DiagnosticKind.duplicate_row, diagnosticFromError(error.DuplicateRow).?);
    try std.testing.expectEqual(DiagnosticKind.unknown_row, diagnosticFromError(error.UnknownRow).?);
    try std.testing.expectEqual(DiagnosticKind.type_mismatch, diagnosticFromError(error.TypeMismatch).?);
    try std.testing.expectEqual(
        DiagnosticKind.vector_dimension_mismatch,
        diagnosticFromError(error.VectorDimensionMismatch).?,
    );
    try std.testing.expectEqual(
        DiagnosticKind.invalid_vector_dimension,
        diagnosticFromError(error.InvalidVectorDimension).?,
    );
    try std.testing.expect(diagnosticFromError(error.OutOfMemory) == null);
}
