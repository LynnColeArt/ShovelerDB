const std = @import("std");

pub const AllocationStats = struct {
    count: usize = 0,
    bytes: usize = 0,
};

pub const CountingAllocator = struct {
    parent: std.mem.Allocator,
    stats: AllocationStats = .{},

    pub fn init(parent: std.mem.Allocator) CountingAllocator {
        return .{ .parent = parent };
    }

    pub fn allocator(self: *CountingAllocator) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .remap = remap,
                .free = free,
            },
        };
    }

    pub fn snapshot(self: *const CountingAllocator) AllocationStats {
        return self.stats;
    }

    pub fn delta(self: *const CountingAllocator, before: AllocationStats) AllocationStats {
        return .{
            .count = self.stats.count - before.count,
            .bytes = self.stats.bytes - before.bytes,
        };
    }

    fn addBytes(self: *CountingAllocator, bytes: usize) void {
        self.stats.bytes = std.math.add(usize, self.stats.bytes, bytes) catch std.math.maxInt(usize);
    }

    fn alloc(
        ctx: *anyopaque,
        len: usize,
        alignment: std.mem.Alignment,
        ret_addr: usize,
    ) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        const result = self.parent.rawAlloc(len, alignment, ret_addr) orelse return null;
        self.stats.count = std.math.add(usize, self.stats.count, 1) catch std.math.maxInt(usize);
        self.addBytes(len);
        return result;
    }

    fn resize(
        ctx: *anyopaque,
        memory: []u8,
        alignment: std.mem.Alignment,
        new_len: usize,
        ret_addr: usize,
    ) bool {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        if (!self.parent.rawResize(memory, alignment, new_len, ret_addr)) return false;
        if (new_len > memory.len) self.addBytes(new_len - memory.len);
        return true;
    }

    fn remap(
        ctx: *anyopaque,
        memory: []u8,
        alignment: std.mem.Alignment,
        new_len: usize,
        ret_addr: usize,
    ) ?[*]u8 {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        const result = self.parent.rawRemap(memory, alignment, new_len, ret_addr) orelse return null;
        if (new_len > memory.len) self.addBytes(new_len - memory.len);
        return result;
    }

    fn free(
        ctx: *anyopaque,
        memory: []u8,
        alignment: std.mem.Alignment,
        ret_addr: usize,
    ) void {
        const self: *CountingAllocator = @ptrCast(@alignCast(ctx));
        self.parent.rawFree(memory, alignment, ret_addr);
    }
};

pub const Metric = struct {
    name: []const u8,
    count: usize,
    elapsed: std.Io.Duration,
    allocations: AllocationStats = .{},

    fn elapsedNanoseconds(self: Metric) i96 {
        return self.elapsed.toNanoseconds();
    }

    fn throughputPerSecond(self: Metric) u64 {
        return computeThroughputPerSecond(self.count, self.elapsed);
    }
};

pub const NearestSummary = struct {
    key: u64,
    distance: f64,
};

pub const BenchmarkConfig = struct {
    preset: ?[]const u8 = null,
    rows: usize,
    vectors: usize,
    dimensions: usize,
    operations: usize,
};

pub const BenchmarkReport = struct {
    config: BenchmarkConfig,
    metrics: []const Metric,
    nearest: ?NearestSummary,
};

pub fn writeTextReport(writer: *std.Io.Writer, report: BenchmarkReport) !void {
    try writer.print("benchmark\n", .{});
    try writer.print("  rows: {d}\n", .{report.config.rows});
    try writer.print("  vectors: {d}\n", .{report.config.vectors});
    try writer.print("  dimensions: {d}\n", .{report.config.dimensions});
    try writer.print("  operations: {d}\n", .{report.config.operations});

    for (report.metrics) |metric| try printMetric(writer, metric);
    if (report.nearest) |nearest| {
        try writer.print("  nearest_key: {d}\n", .{nearest.key});
        try writer.print("  nearest_distance: {d}\n", .{nearest.distance});
    }
}

pub fn writeJsonReport(writer: *std.Io.Writer, report: BenchmarkReport) !void {
    try writer.writeAll("{\"benchmark\":{\"preset\":");
    if (report.config.preset) |preset| {
        try writer.print("\"{s}\"", .{preset});
    } else {
        try writer.writeAll("null");
    }
    try writer.print(
        ",\"rows\":{d},\"vectors\":{d},\"dimensions\":{d},\"operations\":{d}",
        .{ report.config.rows, report.config.vectors, report.config.dimensions, report.config.operations },
    );
    try writer.writeAll("},\"metrics\":[");
    for (report.metrics, 0..) |metric, index| {
        if (index > 0) try writer.writeAll(",");
        try writer.print(
            "{{\"name\":\"{s}\",\"count\":{d},\"elapsed_ns\":{d},\"throughput_per_s\":{d},\"allocation_count\":{d},\"allocation_bytes\":{d}}}",
            .{
                metric.name,
                metric.count,
                metric.elapsedNanoseconds(),
                metric.throughputPerSecond(),
                metric.allocations.count,
                metric.allocations.bytes,
            },
        );
    }
    try writer.writeAll("],\"nearest\":");
    if (report.nearest) |nearest| {
        try writer.print("{{\"key\":{d},\"distance\":{d}}}", .{ nearest.key, nearest.distance });
    } else {
        try writer.writeAll("null");
    }
    try writer.writeAll("}\n");
}

fn printMetric(writer: *std.Io.Writer, metric: Metric) !void {
    try writer.print("  {s}:\n", .{metric.name});
    try writer.print("    count: {d}\n", .{metric.count});
    try writer.print("    elapsed_ns: {d}\n", .{metric.elapsedNanoseconds()});
    try writer.print("    throughput_per_s: {d}\n", .{metric.throughputPerSecond()});
    try writer.print("    allocation_count: {d}\n", .{metric.allocations.count});
    try writer.print("    allocation_bytes: {d}\n", .{metric.allocations.bytes});
}

fn computeThroughputPerSecond(count: usize, elapsed: std.Io.Duration) u64 {
    const ns = elapsed.toNanoseconds();
    if (ns <= 0) return 0;
    const rate = (@as(u128, count) * std.time.ns_per_s) / @as(u128, @intCast(ns));
    return @intCast(@min(rate, std.math.maxInt(u64)));
}

test "counting allocator reports allocation deltas" {
    var counter = CountingAllocator.init(std.testing.allocator);
    const allocator = counter.allocator();

    const before = counter.snapshot();
    const bytes = try allocator.alloc(u8, 12);
    defer allocator.free(bytes);

    const after = counter.delta(before);
    try std.testing.expectEqual(@as(usize, 1), after.count);
    try std.testing.expect(after.bytes >= 12);
}

test "benchmark metrics render JSON allocation fields" {
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();

    const metrics = [_]Metric{
        .{
            .name = "insert_commit",
            .count = 5,
            .elapsed = .fromNanoseconds(1_000),
            .allocations = .{ .count = 2, .bytes = 64 },
        },
        .{
            .name = "snapshot_begin",
            .count = 2,
            .elapsed = .fromNanoseconds(2_000),
            .allocations = .{ .count = 1, .bytes = 32 },
        },
    };
    try writeJsonReport(&output.writer, .{
        .config = .{
            .preset = "local-smoke",
            .rows = 5,
            .vectors = 3,
            .dimensions = 2,
            .operations = 2,
        },
        .metrics = &metrics,
        .nearest = .{ .key = 9, .distance = 1.25 },
    });

    const rendered = output.written();
    try std.testing.expect(try std.json.validate(std.testing.allocator, rendered));
    try std.testing.expect(std.mem.indexOf(u8, rendered, "\"preset\":\"local-smoke\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "\"name\":\"insert_commit\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "\"allocation_count\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "\"allocation_bytes\":64") != null);
}

test "benchmark metrics keep text metric shape with allocations" {
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();

    const metrics = [_]Metric{
        .{
            .name = "queued_commit",
            .count = 4,
            .elapsed = .fromNanoseconds(2_000),
            .allocations = .{ .count = 3, .bytes = 96 },
        },
    };
    try writeTextReport(&output.writer, .{
        .config = .{ .rows = 4, .vectors = 3, .dimensions = 2, .operations = 1 },
        .metrics = &metrics,
        .nearest = null,
    });

    const rendered = output.written();
    try std.testing.expect(std.mem.startsWith(u8, rendered, "benchmark\n  rows: 4\n"));
    try std.testing.expect(std.mem.indexOf(u8, rendered, "  queued_commit:\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "    count: 4\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "    elapsed_ns: 2000\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "    allocation_count: 3\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "    allocation_bytes: 96\n") != null);
}
