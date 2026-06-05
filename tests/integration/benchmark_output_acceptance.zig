const std = @import("std");
const benchmark_metrics = @import("benchmark_metrics");

test "benchmark JSON report exposes stable metric shape and allocation fields" {
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();

    const metric_values = [_]benchmark_metrics.Metric{
        .{
            .name = "insert_commit",
            .count = 123,
            .elapsed = .fromNanoseconds(1_000),
            .allocations = .{ .count = 7, .bytes = 4096 },
        },
        .{
            .name = "concurrent_read_write",
            .count = 11,
            .elapsed = .fromNanoseconds(2_000),
            .allocations = .{ .count = 3, .bytes = 1024 },
        },
    };

    try benchmark_metrics.writeJsonReport(&output.writer, .{
        .config = .{
            .preset = "acceptance-smoke",
            .rows = 123,
            .vectors = 32,
            .dimensions = 8,
            .operations = 11,
        },
        .metrics = &metric_values,
        .nearest = .{ .key = 1, .distance = 0.25 },
    });

    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, output.written(), .{});
    defer parsed.deinit();

    const root = parsed.value.object;
    const benchmark = root.get("benchmark").?.object;
    try std.testing.expectEqualStrings("acceptance-smoke", benchmark.get("preset").?.string);
    try std.testing.expectEqual(@as(i64, 123), benchmark.get("rows").?.integer);
    try std.testing.expectEqual(@as(i64, 32), benchmark.get("vectors").?.integer);
    try std.testing.expectEqual(@as(i64, 8), benchmark.get("dimensions").?.integer);
    try std.testing.expectEqual(@as(i64, 11), benchmark.get("operations").?.integer);

    const metrics = root.get("metrics").?.array.items;
    try std.testing.expectEqual(@as(usize, 2), metrics.len);
    try std.testing.expectEqualStrings("insert_commit", metrics[0].object.get("name").?.string);
    try std.testing.expectEqual(@as(i64, 123), metrics[0].object.get("count").?.integer);
    try std.testing.expectEqual(@as(i64, 7), metrics[0].object.get("allocation_count").?.integer);
    try std.testing.expectEqual(@as(i64, 4096), metrics[0].object.get("allocation_bytes").?.integer);
    try std.testing.expectEqualStrings("concurrent_read_write", metrics[1].object.get("name").?.string);
    try std.testing.expectEqual(@as(i64, 11), metrics[1].object.get("count").?.integer);
    try std.testing.expectEqual(@as(i64, 3), metrics[1].object.get("allocation_count").?.integer);
    try std.testing.expectEqual(@as(i64, 1024), metrics[1].object.get("allocation_bytes").?.integer);
}

test "benchmark text report includes allocation fields without timing assertions" {
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();

    const metric_values = [_]benchmark_metrics.Metric{
        .{
            .name = "queued_commit",
            .count = 4,
            .elapsed = .fromNanoseconds(2_000),
            .allocations = .{ .count = 3, .bytes = 96 },
        },
    };

    try benchmark_metrics.writeTextReport(&output.writer, .{
        .config = .{ .rows = 4, .vectors = 3, .dimensions = 2, .operations = 1 },
        .metrics = &metric_values,
        .nearest = null,
    });

    const rendered = output.written();
    try std.testing.expect(std.mem.startsWith(u8, rendered, "benchmark\n  rows: 4\n"));
    try std.testing.expect(std.mem.indexOf(u8, rendered, "  queued_commit:\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "    count: 4\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "    allocation_count: 3\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "    allocation_bytes: 96\n") != null);
}
