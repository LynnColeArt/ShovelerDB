const std = @import("std");
const benchmark_metrics = @import("benchmark_metrics");
const benchmark_workloads = @import("benchmark_workloads");

test "benchmark workload contract includes missing and Phase 6 metrics" {
    const metric_values = [_]benchmark_metrics.Metric{
        .{ .name = benchmark_workloads.metric_names.insert_commit, .count = 10, .elapsed = .fromNanoseconds(1) },
        .{ .name = benchmark_workloads.metric_names.point_lookup, .count = 4, .elapsed = .fromNanoseconds(1) },
        .{ .name = benchmark_workloads.metric_names.hybrid_filter_vector_rank, .count = 8, .elapsed = .fromNanoseconds(1) },
        .{ .name = benchmark_workloads.metric_names.persistence_checkpoint_reopen, .count = 2, .elapsed = .fromNanoseconds(1) },
        .{ .name = benchmark_workloads.metric_names.snapshot_begin, .count = 4, .elapsed = .fromNanoseconds(1) },
        .{ .name = benchmark_workloads.metric_names.queued_commit, .count = 4, .elapsed = .fromNanoseconds(1) },
        .{ .name = benchmark_workloads.metric_names.concurrent_read_write, .count = 4, .elapsed = .fromNanoseconds(1) },
        .{ .name = benchmark_workloads.metric_names.checkpoint_overlap, .count = 4, .elapsed = .fromNanoseconds(1) },
        .{ .name = benchmark_workloads.metric_names.vector_overlay_visibility, .count = 4, .elapsed = .fromNanoseconds(1) },
    };

    try std.testing.expect(benchmark_workloads.hasAllMetrics(
        &metric_values,
        &benchmark_workloads.missing_workload_metric_names,
    ));
    try std.testing.expect(benchmark_workloads.hasAllMetrics(
        &metric_values,
        &benchmark_workloads.phase6_metric_names,
    ));
}

test "benchmark JSON output preserves missing workload and Phase 6 names" {
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();

    const metric_values = [_]benchmark_metrics.Metric{
        .{
            .name = benchmark_workloads.metric_names.point_lookup,
            .count = 4,
            .elapsed = .fromNanoseconds(1_000),
            .allocations = .{ .count = 2, .bytes = 64 },
        },
        .{
            .name = benchmark_workloads.metric_names.hybrid_filter_vector_rank,
            .count = 8,
            .elapsed = .fromNanoseconds(2_000),
            .allocations = .{ .count = 3, .bytes = 96 },
        },
        .{
            .name = benchmark_workloads.metric_names.persistence_checkpoint_reopen,
            .count = 2,
            .elapsed = .fromNanoseconds(3_000),
            .allocations = .{ .count = 4, .bytes = 128 },
        },
        .{
            .name = benchmark_workloads.metric_names.snapshot_begin,
            .count = 4,
            .elapsed = .fromNanoseconds(4_000),
            .allocations = .{ .count = 5, .bytes = 160 },
        },
        .{
            .name = benchmark_workloads.metric_names.vector_overlay_visibility,
            .count = 4,
            .elapsed = .fromNanoseconds(5_000),
            .allocations = .{ .count = 6, .bytes = 192 },
        },
    };

    try benchmark_metrics.writeJsonReport(&output.writer, .{
        .config = .{ .rows = 10, .vectors = 8, .dimensions = 2, .operations = 4 },
        .metrics = &metric_values,
        .nearest = null,
    });

    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, output.written(), .{});
    defer parsed.deinit();

    const metrics = parsed.value.object.get("metrics").?.array.items;
    try expectJsonMetric(metrics, benchmark_workloads.metric_names.point_lookup, 4);
    try expectJsonMetric(metrics, benchmark_workloads.metric_names.hybrid_filter_vector_rank, 8);
    try expectJsonMetric(metrics, benchmark_workloads.metric_names.persistence_checkpoint_reopen, 2);
    try expectJsonMetric(metrics, benchmark_workloads.metric_names.snapshot_begin, 4);
    try expectJsonMetric(metrics, benchmark_workloads.metric_names.vector_overlay_visibility, 4);
}

test "persistence workload checkpoints and reopens durable rows" {
    const count = try benchmark_workloads.runPersistenceCheckpointReopen(std.testing.allocator, std.testing.io, 3);
    try std.testing.expectEqual(@as(usize, 3), count);
}

fn expectJsonMetric(metrics: []const std.json.Value, name: []const u8, count: i64) !void {
    for (metrics) |metric| {
        const object = metric.object;
        if (!std.mem.eql(u8, object.get("name").?.string, name)) continue;
        try std.testing.expectEqual(count, object.get("count").?.integer);
        try std.testing.expect(object.get("allocation_count") != null);
        try std.testing.expect(object.get("allocation_bytes") != null);
        return;
    }
    return error.MissingMetric;
}
