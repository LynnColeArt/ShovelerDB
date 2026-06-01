const std = @import("std");
const catalog = @import("catalog.zig");
const row_store = @import("row_store.zig");
const value = @import("value.zig");

pub const TransactionState = enum {
    active,
    committed,
    rolled_back,
};

pub const TransactionError = error{
    AlreadyCommitted,
    AlreadyRolledBack,
    ColumnCountMismatch,
    DuplicateRow,
    UnknownRow,
    TypeMismatch,
    VectorDimensionMismatch,
    InvalidVectorDimension,
};

pub const DiagnosticKind = enum {
    already_committed,
    already_rolled_back,
    column_count_mismatch,
    duplicate_row,
    unknown_row,
    type_mismatch,
    vector_dimension_mismatch,
    invalid_vector_dimension,
};

pub fn diagnosticFromError(err: anyerror) ?DiagnosticKind {
    return switch (err) {
        error.AlreadyCommitted => .already_committed,
        error.AlreadyRolledBack => .already_rolled_back,
        error.ColumnCountMismatch => .column_count_mismatch,
        error.DuplicateRow => .duplicate_row,
        error.UnknownRow => .unknown_row,
        error.TypeMismatch => .type_mismatch,
        error.VectorDimensionMismatch => .vector_dimension_mismatch,
        error.InvalidVectorDimension => .invalid_vector_dimension,
        else => null,
    };
}

pub const Transaction = struct {
    allocator: std.mem.Allocator,
    store: *row_store.RowStore,
    state: TransactionState = .active,
    next_id: row_store.RowId,
    inserts: std.ArrayList(row_store.Row) = .empty,
    updates: std.ArrayList(row_store.Row) = .empty,
    deletes: std.ArrayList(row_store.RowId) = .empty,

    pub fn begin(allocator: std.mem.Allocator, store: *row_store.RowStore) Transaction {
        return .{
            .allocator = allocator,
            .store = store,
            .next_id = store.nextRowId(),
        };
    }

    pub fn deinit(self: *Transaction) void {
        self.clearLocalRows();
        self.inserts.deinit(self.allocator);
        self.updates.deinit(self.allocator);
        self.deletes.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn insert(self: *Transaction, values: []const value.Value) !row_store.RowId {
        try self.ensureActive();

        const id = self.next_id;
        var row = try row_store.Row.init(self.allocator, self.store.table, id, values);
        errdefer row.deinit(self.allocator);

        try self.inserts.append(self.allocator, row);
        self.next_id += 1;
        return id;
    }

    pub fn update(self: *Transaction, id: row_store.RowId, values: []const value.Value) !void {
        try self.ensureActive();

        if (self.findInsertedIndex(id)) |index| {
            try self.inserts.items[index].replaceValues(self.allocator, self.store.table, values);
            return;
        }

        if (self.isDeleted(id) or self.store.get(id) == null) return error.UnknownRow;

        if (self.findUpdatedIndex(id)) |index| {
            try self.updates.items[index].replaceValues(self.allocator, self.store.table, values);
            return;
        }

        var update_row = try row_store.Row.init(self.allocator, self.store.table, id, values);
        errdefer update_row.deinit(self.allocator);

        try self.updates.append(self.allocator, update_row);
    }

    pub fn delete(self: *Transaction, id: row_store.RowId) !void {
        try self.ensureActive();

        if (self.findInsertedIndex(id)) |index| {
            var row = self.inserts.orderedRemove(index);
            row.deinit(self.allocator);
            return;
        }

        if (self.store.get(id) == null or self.isDeleted(id)) return error.UnknownRow;

        if (self.findUpdatedIndex(id)) |index| {
            var row = self.updates.orderedRemove(index);
            row.deinit(self.allocator);
        }

        try self.deletes.append(self.allocator, id);
    }

    pub fn scan(self: *const Transaction) ![]row_store.Row {
        try self.ensureActive();

        var visible: std.ArrayList(row_store.Row) = .empty;
        errdefer deinitRowList(self.allocator, &visible);

        for (self.store.rows()) |committed| {
            if (self.isDeleted(committed.id)) continue;

            const visible_row = if (self.findUpdatedIndex(committed.id)) |index|
                self.updates.items[index]
            else
                committed;

            var cloned = try visible_row.clone(self.allocator, self.store.table);
            errdefer cloned.deinit(self.allocator);
            try visible.append(self.allocator, cloned);
        }

        for (self.inserts.items) |inserted| {
            var cloned = try inserted.clone(self.allocator, self.store.table);
            errdefer cloned.deinit(self.allocator);
            try visible.append(self.allocator, cloned);
        }

        return visible.toOwnedSlice(self.allocator);
    }

    pub fn commit(self: *Transaction) !void {
        try self.ensureActive();

        var next = try self.store.clone(self.allocator);
        errdefer next.deinit();

        for (self.deletes.items) |id| {
            try next.delete(id);
        }

        for (self.updates.items) |updated| {
            try next.update(updated.id, updated.values);
        }

        for (self.inserts.items) |inserted| {
            try next.insertWithId(inserted.id, inserted.values);
        }

        self.store.deinit();
        self.store.* = next;
        self.clearLocalRows();
        self.state = .committed;
    }

    pub fn rollback(self: *Transaction) !void {
        try self.ensureActive();
        self.clearLocalRows();
        self.state = .rolled_back;
    }

    fn ensureActive(self: *const Transaction) TransactionError!void {
        return switch (self.state) {
            .active => {},
            .committed => error.AlreadyCommitted,
            .rolled_back => error.AlreadyRolledBack,
        };
    }

    fn clearLocalRows(self: *Transaction) void {
        for (self.inserts.items) |*row| row.deinit(self.allocator);
        self.inserts.clearRetainingCapacity();

        for (self.updates.items) |*row| row.deinit(self.allocator);
        self.updates.clearRetainingCapacity();

        self.deletes.clearRetainingCapacity();
    }

    fn findInsertedIndex(self: *const Transaction, id: row_store.RowId) ?usize {
        for (self.inserts.items, 0..) |row, index| {
            if (row.id == id) return index;
        }
        return null;
    }

    fn findUpdatedIndex(self: *const Transaction, id: row_store.RowId) ?usize {
        for (self.updates.items, 0..) |row, index| {
            if (row.id == id) return index;
        }
        return null;
    }

    fn isDeleted(self: *const Transaction, id: row_store.RowId) bool {
        for (self.deletes.items) |deleted| {
            if (deleted == id) return true;
        }
        return false;
    }
};

fn deinitRowList(allocator: std.mem.Allocator, rows: *std.ArrayList(row_store.Row)) void {
    for (rows.items) |*row| row.deinit(allocator);
    rows.deinit(allocator);
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

fn makeRowValues(
    allocator: std.mem.Allocator,
    id: i64,
    body: []const u8,
    x: f32,
    y: f32,
) ![3]value.Value {
    var values: [3]value.Value = .{
        .{ .integer = id },
        .null,
        .null,
    };
    values[1] = try value.Value.initText(allocator, body);
    errdefer values[1].deinit(allocator);
    values[2] = try value.Value.initVector(allocator, .float32, 2, &.{ x, y });
    return values;
}

fn deinitRowValues(allocator: std.mem.Allocator, values: *[3]value.Value) void {
    for (values) |*runtime_value| runtime_value.deinit(allocator);
}

test "transaction local insert is invisible until commit" {
    const allocator = std.testing.allocator;

    var table = try makeMemoryTable(allocator);
    defer table.deinit(allocator);

    var store = row_store.RowStore.init(allocator, &table);
    defer store.deinit();

    var tx = Transaction.begin(allocator, &store);
    defer tx.deinit();

    var values = try makeRowValues(allocator, 1, "draft", 1.0, 0.0);
    defer deinitRowValues(allocator, &values);

    const id = try tx.insert(&values);
    try std.testing.expectEqual(@as(usize, 0), store.rows().len);

    const visible = try tx.scan();
    defer row_store.deinitRows(allocator, visible);

    try std.testing.expectEqual(@as(usize, 1), visible.len);
    try std.testing.expectEqual(id, visible[0].id);
    try std.testing.expectEqualStrings("draft", visible[0].values[1].text);

    try tx.commit();
    try std.testing.expectEqual(TransactionState.committed, tx.state);
    try std.testing.expectEqual(@as(usize, 1), store.rows().len);
    try std.testing.expectEqual(id, store.rows()[0].id);
}

test "transaction rollback discards inserts updates and deletes" {
    const allocator = std.testing.allocator;

    var table = try makeMemoryTable(allocator);
    defer table.deinit(allocator);

    var store = row_store.RowStore.init(allocator, &table);
    defer store.deinit();

    var committed = try makeRowValues(allocator, 1, "committed", 1.0, 0.0);
    defer deinitRowValues(allocator, &committed);

    const committed_id = try store.insert(&committed);

    var tx = Transaction.begin(allocator, &store);
    defer tx.deinit();

    var update_values = try makeRowValues(allocator, 1, "updated", 0.0, 1.0);
    defer deinitRowValues(allocator, &update_values);
    try tx.update(committed_id, &update_values);

    var insert_values = try makeRowValues(allocator, 2, "local", 0.5, 0.5);
    defer deinitRowValues(allocator, &insert_values);
    _ = try tx.insert(&insert_values);

    try tx.delete(committed_id);

    const visible_before = try tx.scan();
    defer row_store.deinitRows(allocator, visible_before);
    try std.testing.expectEqual(@as(usize, 1), visible_before.len);
    try std.testing.expectEqualStrings("local", visible_before[0].values[1].text);

    try tx.rollback();
    try std.testing.expectEqual(TransactionState.rolled_back, tx.state);
    try std.testing.expectEqual(@as(usize, 1), store.rows().len);
    try std.testing.expectEqualStrings("committed", store.get(committed_id).?.values[1].text);
    try std.testing.expectEqual(@as(row_store.RowId, 2), store.nextRowId());
}

test "transaction failed local insert does not reserve row id" {
    const allocator = std.testing.allocator;

    var table = try makeMemoryTable(allocator);
    defer table.deinit(allocator);

    var store = row_store.RowStore.init(allocator, &table);
    defer store.deinit();

    var tx = Transaction.begin(allocator, &store);
    defer tx.deinit();

    try std.testing.expectError(error.ColumnCountMismatch, tx.insert(&.{.{ .integer = 1 }}));
    try std.testing.expectEqual(@as(row_store.RowId, 1), store.nextRowId());
    try std.testing.expectEqual(@as(row_store.RowId, 1), tx.next_id);

    var values = try makeRowValues(allocator, 1, "valid", 1.0, 0.0);
    defer deinitRowValues(allocator, &values);

    const id = try tx.insert(&values);
    try std.testing.expectEqual(@as(row_store.RowId, 1), id);
}

test "two sessions get read-your-writes and commit visibility" {
    const allocator = std.testing.allocator;

    var table = try makeMemoryTable(allocator);
    defer table.deinit(allocator);

    var store = row_store.RowStore.init(allocator, &table);
    defer store.deinit();

    var writer = Transaction.begin(allocator, &store);
    defer writer.deinit();

    var reader = Transaction.begin(allocator, &store);
    defer reader.deinit();

    var values = try makeRowValues(allocator, 1, "visible after commit", 0.2, 0.8);
    defer deinitRowValues(allocator, &values);

    _ = try writer.insert(&values);

    const writer_view = try writer.scan();
    defer row_store.deinitRows(allocator, writer_view);
    try std.testing.expectEqual(@as(usize, 1), writer_view.len);

    const reader_before = try reader.scan();
    defer row_store.deinitRows(allocator, reader_before);
    try std.testing.expectEqual(@as(usize, 0), reader_before.len);

    try writer.commit();

    const reader_after = try reader.scan();
    defer row_store.deinitRows(allocator, reader_after);
    try std.testing.expectEqual(@as(usize, 1), reader_after.len);
    try std.testing.expectEqualStrings("visible after commit", reader_after[0].values[1].text);
}

test "transaction commit publishes updates and deletes atomically" {
    const allocator = std.testing.allocator;

    var table = try makeMemoryTable(allocator);
    defer table.deinit(allocator);

    var store = row_store.RowStore.init(allocator, &table);
    defer store.deinit();

    var first_values = try makeRowValues(allocator, 1, "first", 1.0, 0.0);
    defer deinitRowValues(allocator, &first_values);
    var second_values = try makeRowValues(allocator, 2, "second", 0.0, 1.0);
    defer deinitRowValues(allocator, &second_values);

    const first = try store.insert(&first_values);
    const second = try store.insert(&second_values);

    var tx = Transaction.begin(allocator, &store);
    defer tx.deinit();

    var updated_values = try makeRowValues(allocator, 2, "second updated", 0.5, 0.5);
    defer deinitRowValues(allocator, &updated_values);

    try tx.delete(first);
    try tx.update(second, &updated_values);
    try tx.commit();

    try std.testing.expect(store.get(first) == null);
    try std.testing.expectEqualStrings("second updated", store.get(second).?.values[1].text);
}

test "transaction rejects double commit and rollback after commit" {
    const allocator = std.testing.allocator;

    var table = try makeMemoryTable(allocator);
    defer table.deinit(allocator);

    var store = row_store.RowStore.init(allocator, &table);
    defer store.deinit();

    var tx = Transaction.begin(allocator, &store);
    defer tx.deinit();

    try tx.commit();
    try std.testing.expectError(error.AlreadyCommitted, tx.commit());
    try std.testing.expectError(error.AlreadyCommitted, tx.rollback());
    try std.testing.expectError(error.AlreadyCommitted, tx.scan());
}

test "transaction rejects mutation after rollback" {
    const allocator = std.testing.allocator;

    var table = try makeMemoryTable(allocator);
    defer table.deinit(allocator);

    var store = row_store.RowStore.init(allocator, &table);
    defer store.deinit();

    var tx = Transaction.begin(allocator, &store);
    defer tx.deinit();

    try tx.rollback();

    var values = try makeRowValues(allocator, 1, "late", 1.0, 0.0);
    defer deinitRowValues(allocator, &values);

    try std.testing.expectError(error.AlreadyRolledBack, tx.insert(&values));
    try std.testing.expectError(error.AlreadyRolledBack, tx.scan());
}

test "transaction diagnostics map stable typed errors" {
    try std.testing.expectEqual(DiagnosticKind.already_committed, diagnosticFromError(error.AlreadyCommitted).?);
    try std.testing.expectEqual(DiagnosticKind.already_rolled_back, diagnosticFromError(error.AlreadyRolledBack).?);
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
