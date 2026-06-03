const std = @import("std");
const concurrency = @import("../db/concurrency.zig");
const catalog = @import("../db/catalog.zig");
const row_store = @import("../db/row_store.zig");

pub const Delta = struct {
    generation: concurrency.SnapshotGeneration,
    table_name: []u8,
    column_name: []u8,
    row_id: row_store.RowId,
    vector: []f32,

    fn init(
        allocator: std.mem.Allocator,
        generation: concurrency.SnapshotGeneration,
        table_name: []const u8,
        column_name: []const u8,
        row_id: row_store.RowId,
        vector: []const f32,
    ) !Delta {
        return .{
            .generation = generation,
            .table_name = try allocator.dupe(u8, table_name),
            .column_name = try allocator.dupe(u8, column_name),
            .row_id = row_id,
            .vector = try allocator.dupe(f32, vector),
        };
    }

    fn clone(self: Delta, allocator: std.mem.Allocator) !Delta {
        return init(allocator, self.generation, self.table_name, self.column_name, self.row_id, self.vector);
    }

    fn replaceVector(
        self: *Delta,
        allocator: std.mem.Allocator,
        generation: concurrency.SnapshotGeneration,
        vector: []const f32,
    ) !void {
        const next = try allocator.dupe(f32, vector);
        allocator.free(self.vector);
        self.vector = next;
        self.generation = generation;
    }

    pub fn deinit(self: *Delta, allocator: std.mem.Allocator) void {
        allocator.free(self.table_name);
        allocator.free(self.column_name);
        allocator.free(self.vector);
        self.* = undefined;
    }
};

pub const Overlay = struct {
    allocator: std.mem.Allocator,
    deltas: std.ArrayList(Delta) = .empty,

    pub fn init(allocator: std.mem.Allocator) Overlay {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Overlay) void {
        for (self.deltas.items) |*delta| delta.deinit(self.allocator);
        self.deltas.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn recordCommittedStore(
        self: *Overlay,
        generation: concurrency.SnapshotGeneration,
        table_name: []const u8,
        table: *const catalog.TableDef,
        store: *const row_store.RowStore,
    ) !void {
        for (store.rows()) |row| {
            for (row.values, 0..) |runtime_value, column_index| {
                if (runtime_value != .vector) continue;
                const column = table.columnAt(column_index) orelse continue;
                try self.recordVector(generation, table_name, column.name, row.id, runtime_value.vector.values);
            }
        }
    }

    pub fn recordVector(
        self: *Overlay,
        generation: concurrency.SnapshotGeneration,
        table_name: []const u8,
        column_name: []const u8,
        row_id: row_store.RowId,
        vector: []const f32,
    ) !void {
        if (self.findIndex(table_name, column_name, row_id)) |index| {
            try self.deltas.items[index].replaceVector(self.allocator, generation, vector);
            return;
        }

        const delta = try Delta.init(self.allocator, generation, table_name, column_name, row_id, vector);
        errdefer {
            var owned = delta;
            owned.deinit(self.allocator);
        }
        try self.deltas.append(self.allocator, delta);
    }

    pub fn deltaCount(self: *const Overlay) usize {
        return self.deltas.items.len;
    }

    pub fn candidateCount(self: *const Overlay, table_name: []const u8, column_name: []const u8) usize {
        var count: usize = 0;
        for (self.deltas.items) |delta| {
            if (matches(delta, table_name, column_name)) count += 1;
        }
        return count;
    }

    pub fn drainReady(
        self: *Overlay,
        allocator: std.mem.Allocator,
        through_generation: concurrency.SnapshotGeneration,
        max_count: usize,
    ) ![]Delta {
        if (max_count == 0) return allocator.alloc(Delta, 0);

        var drained: std.ArrayList(Delta) = .empty;
        errdefer {
            for (drained.items) |*delta| delta.deinit(allocator);
            drained.deinit(allocator);
        }

        var index: usize = 0;
        while (index < self.deltas.items.len and drained.items.len < max_count) {
            if (self.deltas.items[index].generation > through_generation) {
                index += 1;
                continue;
            }

            var cloned: ?Delta = try self.deltas.items[index].clone(allocator);
            errdefer if (cloned) |*owned| {
                owned.deinit(allocator);
            };

            try drained.append(allocator, cloned.?);
            cloned = null;

            var removed = self.deltas.orderedRemove(index);
            removed.deinit(self.allocator);
        }

        return drained.toOwnedSlice(allocator);
    }

    pub fn deinitDrained(allocator: std.mem.Allocator, drained: []Delta) void {
        for (drained) |*delta| delta.deinit(allocator);
        allocator.free(drained);
    }

    fn findIndex(self: *const Overlay, table_name: []const u8, column_name: []const u8, row_id: row_store.RowId) ?usize {
        for (self.deltas.items, 0..) |delta, index| {
            if (delta.row_id == row_id and matches(delta, table_name, column_name)) return index;
        }
        return null;
    }
};

fn matches(delta: Delta, table_name: []const u8, column_name: []const u8) bool {
    return std.ascii.eqlIgnoreCase(delta.table_name, table_name) and
        std.ascii.eqlIgnoreCase(delta.column_name, column_name);
}

test "vector overlay records updates and drains by generation" {
    const allocator = std.testing.allocator;

    var overlay = Overlay.init(allocator);
    defer overlay.deinit();

    try overlay.recordVector(1, "memories", "embedding", 1, &.{ 1.0, 0.0 });
    try overlay.recordVector(2, "memories", "embedding", 2, &.{ 0.0, 1.0 });
    try overlay.recordVector(3, "memories", "embedding", 1, &.{ 0.5, 0.5 });

    try std.testing.expectEqual(@as(usize, 2), overlay.deltaCount());
    try std.testing.expectEqual(@as(usize, 2), overlay.candidateCount("MEMORIES", "EMBEDDING"));

    const drained = try overlay.drainReady(allocator, 2, 10);
    defer Overlay.deinitDrained(allocator, drained);

    try std.testing.expectEqual(@as(usize, 1), drained.len);
    try std.testing.expectEqual(@as(row_store.RowId, 2), drained[0].row_id);
    try std.testing.expectEqual(@as(usize, 1), overlay.deltaCount());
}
