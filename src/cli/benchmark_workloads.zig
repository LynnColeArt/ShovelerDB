const std = @import("std");
const shovelerdb = @import("shovelerdb");

const persistent = shovelerdb.db.database;
const row_store = shovelerdb.db.row_store;
const value = shovelerdb.db.value;

pub const metric_names = struct {
    pub const insert_commit = "insert_commit";
    pub const select_scan = "select_scan";
    pub const grouped_scan = "grouped_scan";
    pub const joined_filter = "joined_filter";
    pub const rollback_updates = "rollback_updates";
    pub const exact_vector_scan = "exact_vector_scan";
    pub const sql_vector_rank = "sql_vector_rank";
    pub const point_lookup = "point_lookup";
    pub const hybrid_filter_vector_rank = "hybrid_filter_vector_rank";
    pub const persistence_checkpoint_reopen = "persistence_checkpoint_reopen";
    pub const snapshot_begin = "snapshot_begin";
    pub const queued_commit = "queued_commit";
    pub const concurrent_read_write = "concurrent_read_write";
    pub const checkpoint_overlap = "checkpoint_overlap";
    pub const vector_overlay_visibility = "vector_overlay_visibility";
};

pub const missing_workload_metric_names = [_][]const u8{
    metric_names.point_lookup,
    metric_names.hybrid_filter_vector_rank,
    metric_names.persistence_checkpoint_reopen,
};

pub const phase6_metric_names = [_][]const u8{
    metric_names.snapshot_begin,
    metric_names.queued_commit,
    metric_names.concurrent_read_write,
    metric_names.checkpoint_overlap,
    metric_names.vector_overlay_visibility,
};

pub fn hasMetric(metrics: anytype, name: []const u8) bool {
    for (metrics) |metric| {
        if (std.mem.eql(u8, metric.name, name)) return true;
    }
    return false;
}

pub fn hasAllMetrics(metrics: anytype, names: []const []const u8) bool {
    for (names) |name| {
        if (!hasMetric(metrics, name)) return false;
    }
    return true;
}

pub fn runPersistenceCheckpointReopen(
    allocator: std.mem.Allocator,
    io: std.Io,
    row_count: usize,
) !usize {
    const cwd = std.Io.Dir.cwd();
    var dir = try cwd.createDirPathOpen(io, ".zig-cache/shovelerdb-benchmark", .{});
    defer dir.close(io);

    const path = "checkpoint-reopen.shovel";
    dir.deleteFile(io, path) catch |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    };
    defer dir.deleteFile(io, path) catch {};

    var db = try persistent.Database.openOrCreate(allocator, io, dir, path);
    defer db.deinit();
    try db.createTable(.{
        .name = "memories",
        .columns = &.{
            .{ .name = "id", .column_type = .integer, .nullable = false },
            .{ .name = "body", .column_type = .text, .nullable = false },
            .{ .name = "embedding", .column_type = .{ .vector = .{ .dimension = 2 } }, .nullable = false },
        },
    });

    var tx = try db.beginTransaction("memories");
    defer tx.deinit();
    for (0..row_count) |index| {
        const body_text = try std.fmt.allocPrint(allocator, "durable-{d}", .{index + 1});
        defer allocator.free(body_text);
        var body = try value.Value.initText(allocator, body_text);
        defer body.deinit(allocator);
        var embedding = try value.Value.initVector(
            allocator,
            .float32,
            2,
            &.{ @floatFromInt(index % 17), @floatFromInt((index + 1) % 17) },
        );
        defer embedding.deinit(allocator);

        _ = try tx.insert(&.{
            .{ .integer = @intCast(index + 1) },
            body,
            embedding,
        });
    }
    try tx.commit();
    try db.close();

    var reopened = try persistent.Database.open(allocator, io, dir, path);
    defer reopened.deinit();
    const table = (try reopened.table("MEMORIES")).?;
    if (table.columns.len != 3) return error.InvalidBenchmarkState;

    const rows = try reopened.rows("memories");
    if (rows.len != row_count) return error.InvalidBenchmarkState;
    if (row_count > 0) {
        if (rows[0].id != @as(row_store.RowId, 1)) return error.InvalidBenchmarkState;
        if (!std.mem.eql(u8, rows[0].values[1].text, "durable-1")) return error.InvalidBenchmarkState;
    }
    return rows.len;
}

test "workload metric groups expose missing workloads and Phase 6 names" {
    try std.testing.expectEqual(@as(usize, 3), missing_workload_metric_names.len);
    try std.testing.expectEqual(@as(usize, 5), phase6_metric_names.len);
    try std.testing.expectEqualStrings("point_lookup", metric_names.point_lookup);
    try std.testing.expectEqualStrings("vector_overlay_visibility", metric_names.vector_overlay_visibility);
}

test "metric presence checks validate complete groups" {
    const TestMetric = struct {
        name: []const u8,
    };
    const metrics = [_]TestMetric{
        .{ .name = metric_names.point_lookup },
        .{ .name = metric_names.hybrid_filter_vector_rank },
        .{ .name = metric_names.persistence_checkpoint_reopen },
        .{ .name = metric_names.snapshot_begin },
        .{ .name = metric_names.queued_commit },
        .{ .name = metric_names.concurrent_read_write },
        .{ .name = metric_names.checkpoint_overlap },
        .{ .name = metric_names.vector_overlay_visibility },
    };

    try std.testing.expect(hasAllMetrics(&metrics, &missing_workload_metric_names));
    try std.testing.expect(hasAllMetrics(&metrics, &phase6_metric_names));
    try std.testing.expect(!hasMetric(&metrics, "missing"));
}

test "persistence checkpoint reopen workload preserves committed rows" {
    const count = try runPersistenceCheckpointReopen(std.testing.allocator, std.testing.io, 2);
    try std.testing.expectEqual(@as(usize, 2), count);
}
