const std = @import("std");
const catalog = @import("catalog.zig");
const concurrency = @import("concurrency.zig");
const row_store = @import("row_store.zig");

pub const SnapshotHandle = struct {
    generation: concurrency.SnapshotGeneration,
    registry: *Registry,
    released: bool = false,

    pub fn release(self: *SnapshotHandle) void {
        if (self.released) return;
        self.registry.releaseGeneration(self.generation);
        self.released = true;
    }
};

pub const TableSource = struct {
    table: *const catalog.TableDef,
    store: *const row_store.RowStore,
};

pub const RetainedTable = struct {
    table: catalog.TableDef,
    store: row_store.RowStore,

    fn init(allocator: std.mem.Allocator, source: TableSource) !RetainedTable {
        var table = try cloneTableDef(allocator, source.table.*);
        errdefer table.deinit(allocator);

        var store = row_store.RowStore.init(allocator, &table);
        errdefer store.deinit();

        for (source.store.rows()) |row| {
            try store.insertWithId(row.id, row.values);
        }
        store.next_id = source.store.nextRowId();

        return .{
            .table = table,
            .store = store,
        };
    }

    fn deinit(self: *RetainedTable, allocator: std.mem.Allocator) void {
        self.store.deinit();
        self.table.deinit(allocator);
        self.* = undefined;
    }
};

pub const RetainedGeneration = struct {
    generation: concurrency.SnapshotGeneration,
    tables: std.ArrayList(RetainedTable) = .empty,

    fn init(generation: concurrency.SnapshotGeneration) RetainedGeneration {
        return .{ .generation = generation };
    }

    fn capture(
        self: *RetainedGeneration,
        allocator: std.mem.Allocator,
        sources: []const TableSource,
    ) !void {
        try self.tables.ensureTotalCapacity(allocator, sources.len);
        for (sources) |source| {
            var table = try RetainedTable.init(allocator, source);
            errdefer table.deinit(allocator);
            try self.tables.append(allocator, table);
        }
        self.refreshStorePointers();
    }

    fn deinit(self: *RetainedGeneration, allocator: std.mem.Allocator) void {
        for (self.tables.items) |*table| table.deinit(allocator);
        self.tables.deinit(allocator);
        self.* = undefined;
    }

    fn storeForTable(self: *const RetainedGeneration, table_name: []const u8) ?*const row_store.RowStore {
        for (self.tables.items) |*table| {
            if (std.ascii.eqlIgnoreCase(table.table.name, table_name)) return &table.store;
        }
        return null;
    }

    fn refreshStorePointers(self: *RetainedGeneration) void {
        for (self.tables.items) |*table| {
            table.store.table = &table.table;
        }
    }
};

const ActiveGeneration = struct {
    generation: concurrency.SnapshotGeneration,
    ref_count: usize = 0,
};

pub const Registry = struct {
    allocator: std.mem.Allocator,
    retention_limit: usize,
    active: std.ArrayList(ActiveGeneration) = .empty,
    retained: std.ArrayList(RetainedGeneration) = .empty,

    pub fn init(allocator: std.mem.Allocator, config: concurrency.Config) Registry {
        return .{
            .allocator = allocator,
            .retention_limit = config.snapshot_retention_generations,
        };
    }

    pub fn deinit(self: *Registry) void {
        for (self.retained.items) |*generation| generation.deinit(self.allocator);
        self.retained.deinit(self.allocator);
        self.active.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn acquire(self: *Registry, generation: concurrency.SnapshotGeneration) !SnapshotHandle {
        if (self.findActiveIndex(generation)) |index| {
            self.active.items[index].ref_count += 1;
        } else {
            try self.active.append(self.allocator, .{
                .generation = generation,
                .ref_count = 1,
            });
        }

        return .{
            .generation = generation,
            .registry = self,
        };
    }

    pub fn needsRetention(
        self: *const Registry,
        generation: concurrency.SnapshotGeneration,
        excluding: ?SnapshotHandle,
    ) bool {
        var refs = self.activeRefCount(generation);
        if (excluding) |handle| {
            if (!handle.released and handle.generation == generation and refs > 0) refs -= 1;
        }
        return refs > 0 and self.findRetainedIndex(generation) == null;
    }

    pub fn retainGeneration(
        self: *Registry,
        generation: concurrency.SnapshotGeneration,
        sources: []const TableSource,
    ) !void {
        if (self.findRetainedIndex(generation) != null) return;
        self.sweepReleasedGenerations();

        if (self.retained.items.len >= self.retention_limit) {
            return error.SnapshotRetentionExceeded;
        }

        var retained = RetainedGeneration.init(generation);
        errdefer retained.deinit(self.allocator);
        try retained.capture(self.allocator, sources);
        try self.retained.append(self.allocator, retained);
    }

    pub fn retainedStoreForTable(
        self: *const Registry,
        generation: concurrency.SnapshotGeneration,
        table_name: []const u8,
    ) ?*const row_store.RowStore {
        const index = self.findRetainedIndex(generation) orelse return null;
        return self.retained.items[index].storeForTable(table_name);
    }

    pub fn activeRefCount(self: *const Registry, generation: concurrency.SnapshotGeneration) usize {
        const index = self.findActiveIndex(generation) orelse return 0;
        return self.active.items[index].ref_count;
    }

    pub fn retainedGenerationCount(self: *const Registry) usize {
        return self.retained.items.len;
    }

    pub fn retainedRowCount(
        self: *const Registry,
        generation: concurrency.SnapshotGeneration,
        table_name: []const u8,
    ) ?usize {
        const store = self.retainedStoreForTable(generation, table_name) orelse return null;
        return store.rows().len;
    }

    fn releaseGeneration(self: *Registry, generation: concurrency.SnapshotGeneration) void {
        const index = self.findActiveIndex(generation) orelse return;
        if (self.active.items[index].ref_count > 1) {
            self.active.items[index].ref_count -= 1;
        } else {
            _ = self.active.orderedRemove(index);
        }
        self.sweepReleasedGenerations();
    }

    fn sweepReleasedGenerations(self: *Registry) void {
        var index: usize = 0;
        while (index < self.retained.items.len) {
            const generation = self.retained.items[index].generation;
            if (self.activeRefCount(generation) != 0) {
                index += 1;
                continue;
            }

            var retained = self.retained.orderedRemove(index);
            retained.deinit(self.allocator);
        }
    }

    fn findActiveIndex(self: *const Registry, generation: concurrency.SnapshotGeneration) ?usize {
        for (self.active.items, 0..) |active, index| {
            if (active.generation == generation) return index;
        }
        return null;
    }

    fn findRetainedIndex(self: *const Registry, generation: concurrency.SnapshotGeneration) ?usize {
        for (self.retained.items, 0..) |retained, index| {
            if (retained.generation == generation) return index;
        }
        return null;
    }
};

fn cloneTableDef(allocator: std.mem.Allocator, source: catalog.TableDef) !catalog.TableDef {
    var columns = try allocator.alloc(catalog.ColumnSpec, source.columns.len);
    defer allocator.free(columns);
    for (source.columns, 0..) |column, index| {
        columns[index] = .{
            .name = column.name,
            .column_type = column.column_type,
            .nullable = column.nullable,
            .default_value = column.default_value,
            .primary_key = column.primary_key,
            .auto_increment = column.auto_increment,
        };
    }

    var indexes = try allocator.alloc(catalog.IndexSpec, source.indexes.len);
    defer allocator.free(indexes);
    for (source.indexes, 0..) |index, offset| {
        indexes[offset] = .{
            .name = index.name,
            .columns = index.columns,
            .kind = index.kind,
        };
    }

    return catalog.TableDef.init(allocator, .{
        .name = source.name,
        .columns = columns,
        .indexes = indexes,
    });
}

fn makeMemoryTable(allocator: std.mem.Allocator) !catalog.TableDef {
    return catalog.TableDef.init(allocator, .{
        .name = "memories",
        .columns = &.{
            .{ .name = "id", .column_type = .integer, .nullable = false },
            .{ .name = "body", .column_type = .text, .nullable = false },
        },
    });
}

test "snapshot registry retains and releases committed generation rows" {
    const allocator = std.testing.allocator;

    var table = try makeMemoryTable(allocator);
    defer table.deinit(allocator);

    var store = row_store.RowStore.init(allocator, &table);
    defer store.deinit();

    var body = try @import("value.zig").Value.initText(allocator, "seed");
    defer body.deinit(allocator);
    _ = try store.insert(&.{ .{ .integer = 1 }, body });

    var registry = Registry.init(allocator, concurrency.default_config);
    defer registry.deinit();

    var handle = try registry.acquire(1);
    try std.testing.expectEqual(@as(usize, 1), registry.activeRefCount(1));
    try std.testing.expect(registry.needsRetention(1, null));

    try registry.retainGeneration(1, &.{.{
        .table = &table,
        .store = &store,
    }});
    try std.testing.expectEqual(@as(usize, 1), registry.retainedGenerationCount());
    try std.testing.expectEqual(@as(usize, 1), registry.retainedRowCount(1, "memories").?);

    handle.release();
    try std.testing.expectEqual(@as(usize, 0), registry.activeRefCount(1));
    try std.testing.expectEqual(@as(usize, 0), registry.retainedGenerationCount());
}
