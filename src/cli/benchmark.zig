const std = @import("std");
const benchmark_metrics = @import("benchmark_metrics.zig");
const shovelerdb = @import("shovelerdb");

const executor = shovelerdb.db.executor;
const search = shovelerdb.vector.search;
const vector_overlay = shovelerdb.vector.overlay;
const AllocationStats = benchmark_metrics.AllocationStats;
const BenchmarkConfig = benchmark_metrics.BenchmarkConfig;
const BenchmarkReport = benchmark_metrics.BenchmarkReport;
const Metric = benchmark_metrics.Metric;
const NearestSummary = benchmark_metrics.NearestSummary;

pub const BenchmarkError = error{
    InvalidOption,
    MissingOptionValue,
};

pub const OutputFormat = enum {
    text,
    json,

    fn parse(raw: []const u8) !OutputFormat {
        if (std.mem.eql(u8, raw, "text")) return .text;
        if (std.mem.eql(u8, raw, "json")) return .json;
        return error.InvalidOption;
    }
};

pub const Preset = enum {
    local_smoke,
    acceptance_smoke,

    fn parse(raw: []const u8) !Preset {
        if (std.mem.eql(u8, raw, "local-smoke")) return .local_smoke;
        if (std.mem.eql(u8, raw, "acceptance-smoke")) return .acceptance_smoke;
        return error.InvalidOption;
    }

    fn label(self: Preset) []const u8 {
        return switch (self) {
            .local_smoke => "local-smoke",
            .acceptance_smoke => "acceptance-smoke",
        };
    }
};

pub const Options = struct {
    rows: usize = 10_000,
    vectors: usize = 1_000,
    dimensions: usize = 128,
    operations: usize = 1_000,
    format: OutputFormat = .text,
    preset: ?Preset = null,
};

pub fn parseOptions(args: []const []const u8) !Options {
    var options: Options = .{};
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (try parseInlineOption(&options, arg)) continue;

        const name = optionName(arg) orelse return error.InvalidOption;
        index += 1;
        if (index >= args.len) return error.MissingOptionValue;
        try setOption(&options, name, args[index]);
    }
    return options;
}

pub fn printUsage(writer: *std.Io.Writer) !void {
    try writer.print(
        \\usage: shoveler benchmark [--preset local-smoke|acceptance-smoke] [--format text|json] [--rows N] [--vectors N] [--dimensions N] [--operations N]
        \\       defaults: --rows 10000 --vectors 1000 --dimensions 128 --operations 1000
        \\
    , .{});
}

pub fn run(
    allocator: std.mem.Allocator,
    io: std.Io,
    writer: *std.Io.Writer,
    options: Options,
) !void {
    if (options.rows == 0 or options.vectors == 0 or options.dimensions == 0 or options.operations == 0) {
        return error.InvalidOption;
    }

    var allocation_counter = benchmark_metrics.CountingAllocator.init(allocator);
    const benchmark_allocator = allocation_counter.allocator();

    var db = executor.Database.init(benchmark_allocator);
    defer db.deinit();
    var session = executor.Session.init(benchmark_allocator);
    defer session.deinit();

    var result = try db.executeSql(&session, "CREATE TABLE scalar_memory (id INTEGER, body TEXT, score FLOAT);");
    result.deinit(benchmark_allocator);
    result = try db.executeSql(&session, "CREATE TABLE memory_tags (id INTEGER, memory_id INTEGER, name TEXT);");
    result.deinit(benchmark_allocator);
    const create_vector_table = try std.fmt.allocPrint(
        benchmark_allocator,
        "CREATE TABLE vector_memory (id INTEGER, embedding VECTOR({d}));",
        .{options.dimensions},
    );
    defer benchmark_allocator.free(create_vector_table);
    result = try db.executeSql(&session, create_vector_table);
    result.deinit(benchmark_allocator);

    const insert_allocations_start = allocation_counter.snapshot();
    const insert_start = now(io);
    result = try db.executeSql(&session, "BEGIN;");
    result.deinit(benchmark_allocator);
    for (0..options.rows) |index| {
        const statement = try std.fmt.allocPrint(
            benchmark_allocator,
            "INSERT INTO scalar_memory VALUES ({d}, 'memory-{d}', {d}.25);",
            .{ index + 1, index + 1, index % 97 },
        );
        defer benchmark_allocator.free(statement);
        result = try db.executeSql(&session, statement);
        result.deinit(benchmark_allocator);
    }
    result = try db.executeSql(&session, "COMMIT;");
    result.deinit(benchmark_allocator);
    const insert_elapsed = elapsedSince(io, insert_start);
    const insert_allocations = allocation_counter.delta(insert_allocations_start);

    try loadJoinRows(benchmark_allocator, &db, &session, options.rows);
    try loadSqlVectorRows(benchmark_allocator, &db, &session, options.vectors, options.dimensions);

    const scan_allocations_start = allocation_counter.snapshot();
    const scan_start = now(io);
    result = try db.executeSql(&session, "SELECT * FROM scalar_memory;");
    result.deinit(benchmark_allocator);
    const scan_elapsed = elapsedSince(io, scan_start);
    const scan_allocations = allocation_counter.delta(scan_allocations_start);

    const grouped_allocations_start = allocation_counter.snapshot();
    const grouped_start = now(io);
    result = try db.executeSql(&session, "SELECT score, COUNT(*) AS total FROM scalar_memory GROUP BY score HAVING total > 1 ORDER BY total DESC LIMIT 5;");
    result.deinit(benchmark_allocator);
    const grouped_elapsed = elapsedSince(io, grouped_start);
    const grouped_allocations = allocation_counter.delta(grouped_allocations_start);

    const joined_allocations_start = allocation_counter.snapshot();
    const joined_start = now(io);
    result = try db.executeSql(&session, "SELECT m.id, t.name FROM scalar_memory AS m JOIN memory_tags AS t ON t.memory_id = m.id WHERE t.name = 'project' ORDER BY m.id ASC LIMIT 10;");
    result.deinit(benchmark_allocator);
    const joined_elapsed = elapsedSince(io, joined_start);
    const joined_allocations = allocation_counter.delta(joined_allocations_start);

    const rollback_allocations_start = allocation_counter.snapshot();
    const rollback_start = now(io);
    result = try db.executeSql(&session, "BEGIN;");
    result.deinit(benchmark_allocator);
    const rollback_ops = @min(options.operations, options.rows);
    for (0..rollback_ops) |index| {
        const statement = try std.fmt.allocPrint(
            benchmark_allocator,
            "UPDATE scalar_memory SET score = {d}.5 WHERE id = {d};",
            .{ index % 113, index + 1 },
        );
        defer benchmark_allocator.free(statement);
        result = try db.executeSql(&session, statement);
        result.deinit(benchmark_allocator);
    }
    result = try db.executeSql(&session, "ROLLBACK;");
    result.deinit(benchmark_allocator);
    const rollback_elapsed = elapsedSince(io, rollback_start);
    const rollback_allocations = allocation_counter.delta(rollback_allocations_start);

    const candidates = try makeVectorCandidates(benchmark_allocator, options.vectors, options.dimensions);
    defer freeVectorCandidates(benchmark_allocator, candidates);
    const query = try makeQueryVector(benchmark_allocator, options.dimensions);
    defer benchmark_allocator.free(query);

    const vector_allocations_start = allocation_counter.snapshot();
    const vector_start = now(io);
    const nearest = try search.topK(benchmark_allocator, query, candidates, @min(@as(usize, 10), options.vectors), .squared_l2);
    defer benchmark_allocator.free(nearest);
    const vector_elapsed = elapsedSince(io, vector_start);
    const vector_allocations = allocation_counter.delta(vector_allocations_start);

    const query_vector_literal = try makeSqlVectorLiteral(benchmark_allocator, options.dimensions, 0);
    defer benchmark_allocator.free(query_vector_literal);
    const sql_vector_query = try std.fmt.allocPrint(
        benchmark_allocator,
        "SELECT id, l2_distance(embedding, {s}) AS distance FROM vector_memory ORDER BY distance ASC LIMIT 10;",
        .{query_vector_literal},
    );
    defer benchmark_allocator.free(sql_vector_query);
    const sql_vector_allocations_start = allocation_counter.snapshot();
    const sql_vector_start = now(io);
    result = try db.executeSql(&session, sql_vector_query);
    result.deinit(benchmark_allocator);
    const sql_vector_elapsed = elapsedSince(io, sql_vector_start);
    const sql_vector_allocations = allocation_counter.delta(sql_vector_allocations_start);

    const phase6_ops = @min(options.operations, options.rows);
    const snapshot_begin_allocations_start = allocation_counter.snapshot();
    const snapshot_begin_start = now(io);
    try runSnapshotBeginWorkload(benchmark_allocator, &db, phase6_ops);
    const snapshot_begin_elapsed = elapsedSince(io, snapshot_begin_start);
    const snapshot_begin_allocations = allocation_counter.delta(snapshot_begin_allocations_start);

    const queued_commit_allocations_start = allocation_counter.snapshot();
    const queued_commit_start = now(io);
    try runQueuedCommitWorkload(benchmark_allocator, &db, phase6_ops, 2_000_000);
    const queued_commit_elapsed = elapsedSince(io, queued_commit_start);
    const queued_commit_allocations = allocation_counter.delta(queued_commit_allocations_start);

    const concurrent_allocations_start = allocation_counter.snapshot();
    const concurrent_start = now(io);
    try runConcurrentReadWriteWorkload(benchmark_allocator, &db, phase6_ops, 3_000_000);
    const concurrent_elapsed = elapsedSince(io, concurrent_start);
    const concurrent_allocations = allocation_counter.delta(concurrent_allocations_start);

    const checkpoint_overlap_allocations_start = allocation_counter.snapshot();
    const checkpoint_overlap_start = now(io);
    const checkpoint_overlap_count = try runCheckpointOverlapWorkload(benchmark_allocator, &db, phase6_ops);
    const checkpoint_overlap_elapsed = elapsedSince(io, checkpoint_overlap_start);
    const checkpoint_overlap_allocations = allocation_counter.delta(checkpoint_overlap_allocations_start);

    const vector_overlay_allocations_start = allocation_counter.snapshot();
    const vector_overlay_start = now(io);
    const vector_overlay_count = try runVectorOverlayVisibilityWorkload(benchmark_allocator, &db, phase6_ops);
    const vector_overlay_elapsed = elapsedSince(io, vector_overlay_start);
    const vector_overlay_allocations = allocation_counter.delta(vector_overlay_allocations_start);

    const metrics = [_]Metric{
        metric("insert_commit", options.rows, insert_elapsed, insert_allocations),
        metric("select_scan", options.rows, scan_elapsed, scan_allocations),
        metric("grouped_scan", options.rows, grouped_elapsed, grouped_allocations),
        metric("joined_filter", options.rows, joined_elapsed, joined_allocations),
        metric("rollback_updates", rollback_ops, rollback_elapsed, rollback_allocations),
        metric("exact_vector_scan", options.vectors, vector_elapsed, vector_allocations),
        metric("sql_vector_rank", options.vectors, sql_vector_elapsed, sql_vector_allocations),
        metric("snapshot_begin", phase6_ops, snapshot_begin_elapsed, snapshot_begin_allocations),
        metric("queued_commit", phase6_ops, queued_commit_elapsed, queued_commit_allocations),
        metric("concurrent_read_write", phase6_ops, concurrent_elapsed, concurrent_allocations),
        metric("checkpoint_overlap", checkpoint_overlap_count, checkpoint_overlap_elapsed, checkpoint_overlap_allocations),
        metric("vector_overlay_visibility", vector_overlay_count, vector_overlay_elapsed, vector_overlay_allocations),
    };
    const nearest_summary: ?NearestSummary = if (nearest.len > 0)
        .{ .key = nearest[0].key, .distance = nearest[0].distance }
    else
        null;

    const report: BenchmarkReport = .{
        .config = .{
            .preset = if (options.preset) |preset| preset.label() else null,
            .rows = options.rows,
            .vectors = options.vectors,
            .dimensions = options.dimensions,
            .operations = options.operations,
        },
        .metrics = &metrics,
        .nearest = nearest_summary,
    };
    switch (options.format) {
        .text => try benchmark_metrics.writeTextReport(writer, report),
        .json => try benchmark_metrics.writeJsonReport(writer, report),
    }
}

fn metric(
    name: []const u8,
    count: usize,
    elapsed: std.Io.Duration,
    allocations: AllocationStats,
) Metric {
    return .{
        .name = name,
        .count = count,
        .elapsed = elapsed,
        .allocations = allocations,
    };
}

fn executeAndDiscard(
    allocator: std.mem.Allocator,
    db: *executor.Database,
    session: *executor.Session,
    sql: []const u8,
) !void {
    var result = try db.executeSql(session, sql);
    result.deinit(allocator);
}

fn loadJoinRows(
    allocator: std.mem.Allocator,
    db: *executor.Database,
    session: *executor.Session,
    row_count: usize,
) !void {
    try executeAndDiscard(allocator, db, session, "BEGIN;");
    for (0..row_count) |index| {
        const tag = if (index % 2 == 0) "project" else "personal";
        const statement = try std.fmt.allocPrint(
            allocator,
            "INSERT INTO memory_tags VALUES ({d}, {d}, '{s}');",
            .{ index + 1, index + 1, tag },
        );
        defer allocator.free(statement);
        try executeAndDiscard(allocator, db, session, statement);
    }
    try executeAndDiscard(allocator, db, session, "COMMIT;");
}

fn runSnapshotBeginWorkload(
    allocator: std.mem.Allocator,
    db: *executor.Database,
    operation_count: usize,
) !void {
    for (0..operation_count) |_| {
        var reader = executor.Session.init(allocator);
        defer reader.deinit();

        try executeAndDiscard(allocator, db, &reader, "BEGIN;");
        try executeAndDiscard(allocator, db, &reader, "ROLLBACK;");
    }
}

fn runQueuedCommitWorkload(
    allocator: std.mem.Allocator,
    db: *executor.Database,
    operation_count: usize,
    id_base: usize,
) !void {
    var writer = executor.Session.init(allocator);
    defer writer.deinit();

    for (0..operation_count) |index| {
        try executeAndDiscard(allocator, db, &writer, "BEGIN;");
        const statement = try std.fmt.allocPrint(
            allocator,
            "INSERT INTO scalar_memory VALUES ({d}, 'queued-{d}', {d}.125);",
            .{ id_base + index, index + 1, index % 89 },
        );
        defer allocator.free(statement);
        try executeAndDiscard(allocator, db, &writer, statement);
        try executeAndDiscard(allocator, db, &writer, "COMMIT;");
    }
}

fn runConcurrentReadWriteWorkload(
    allocator: std.mem.Allocator,
    db: *executor.Database,
    operation_count: usize,
    id_base: usize,
) !void {
    var reader = executor.Session.init(allocator);
    defer reader.deinit();
    var writer = executor.Session.init(allocator);
    defer writer.deinit();

    try executeAndDiscard(allocator, db, &reader, "BEGIN;");
    for (0..operation_count) |index| {
        try executeAndDiscard(allocator, db, &writer, "BEGIN;");
        const statement = try std.fmt.allocPrint(
            allocator,
            "INSERT INTO scalar_memory VALUES ({d}, 'concurrent-{d}', {d}.75);",
            .{ id_base + index, index + 1, index % 101 },
        );
        defer allocator.free(statement);
        try executeAndDiscard(allocator, db, &writer, statement);
        try executeAndDiscard(allocator, db, &writer, "COMMIT;");

        var result = try db.executeSql(&reader, "SELECT id FROM scalar_memory ORDER BY id ASC LIMIT 1;");
        result.deinit(allocator);
    }
    try executeAndDiscard(allocator, db, &reader, "COMMIT;");
}

fn runCheckpointOverlapWorkload(
    allocator: std.mem.Allocator,
    db: *executor.Database,
    operation_count: usize,
) !usize {
    var reader = executor.Session.init(allocator);
    defer reader.deinit();

    try executeAndDiscard(allocator, db, &reader, "BEGIN;");
    var checkpoint = try db.beginCheckpoint();
    var completed = false;
    defer if (!completed) checkpoint.fail();

    var attempts: usize = 0;
    for (0..operation_count) |_| {
        if (db.beginCheckpoint()) |overlap| {
            var unexpected = overlap;
            unexpected.fail();
            return error.InvalidBenchmarkState;
        } else |err| switch (err) {
            error.CheckpointAlreadyRunning => attempts += 1,
            else => return err,
        }

        var result = try db.executeSql(&reader, "SELECT id FROM scalar_memory ORDER BY id ASC LIMIT 1;");
        result.deinit(allocator);
    }

    checkpoint.complete();
    completed = true;
    try executeAndDiscard(allocator, db, &reader, "COMMIT;");
    return attempts;
}

fn runVectorOverlayVisibilityWorkload(
    allocator: std.mem.Allocator,
    db: *executor.Database,
    max_count: usize,
) !usize {
    const drain_count = @min(db.vectorOverlayCandidateCount("vector_memory", "embedding"), max_count);
    const drained = try db.drainVectorOverlay(allocator, db.currentCommitSequence(), drain_count);
    defer vector_overlay.Overlay.deinitDrained(allocator, drained);
    return drained.len;
}

fn loadSqlVectorRows(
    allocator: std.mem.Allocator,
    db: *executor.Database,
    session: *executor.Session,
    vector_count: usize,
    dimensions: usize,
) !void {
    try executeAndDiscard(allocator, db, session, "BEGIN;");
    for (0..vector_count) |index| {
        const literal = try makeSqlVectorLiteral(allocator, dimensions, index);
        defer allocator.free(literal);
        const statement = try std.fmt.allocPrint(
            allocator,
            "INSERT INTO vector_memory VALUES ({d}, {s});",
            .{ index + 1, literal },
        );
        defer allocator.free(statement);
        try executeAndDiscard(allocator, db, session, statement);
    }
    try executeAndDiscard(allocator, db, session, "COMMIT;");
}

fn makeSqlVectorLiteral(
    allocator: std.mem.Allocator,
    dimensions: usize,
    seed: usize,
) ![]u8 {
    var literal: std.ArrayList(u8) = .empty;
    errdefer literal.deinit(allocator);

    try literal.append(allocator, '[');
    for (0..dimensions) |dimension| {
        if (dimension > 0) try literal.appendSlice(allocator, ", ");
        const component = try std.fmt.allocPrint(allocator, "{d}", .{(seed + dimension) % 17});
        defer allocator.free(component);
        try literal.appendSlice(allocator, component);
    }
    try literal.append(allocator, ']');

    return literal.toOwnedSlice(allocator);
}

fn parseInlineOption(options: *Options, arg: []const u8) !bool {
    if (!std.mem.startsWith(u8, arg, "--")) return false;
    const equals = std.mem.indexOfScalar(u8, arg, '=') orelse return false;
    try setOption(options, arg[0..equals], arg[equals + 1 ..]);
    return true;
}

fn optionName(arg: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, arg, "--rows")) return arg;
    if (std.mem.eql(u8, arg, "--vectors")) return arg;
    if (std.mem.eql(u8, arg, "--dimensions")) return arg;
    if (std.mem.eql(u8, arg, "--operations")) return arg;
    if (std.mem.eql(u8, arg, "--preset")) return arg;
    if (std.mem.eql(u8, arg, "--format")) return arg;
    return null;
}

fn setOption(options: *Options, name: []const u8, raw_value: []const u8) !void {
    if (std.mem.eql(u8, name, "--preset")) {
        applyPreset(options, try Preset.parse(raw_value));
        return;
    }
    if (std.mem.eql(u8, name, "--format")) {
        options.format = try OutputFormat.parse(raw_value);
        return;
    }

    const parsed = std.fmt.parseUnsigned(usize, raw_value, 10) catch return error.InvalidOption;
    if (std.mem.eql(u8, name, "--rows")) {
        options.rows = parsed;
    } else if (std.mem.eql(u8, name, "--vectors")) {
        options.vectors = parsed;
    } else if (std.mem.eql(u8, name, "--dimensions")) {
        options.dimensions = parsed;
    } else if (std.mem.eql(u8, name, "--operations")) {
        options.operations = parsed;
    } else {
        return error.InvalidOption;
    }
}

fn applyPreset(options: *Options, preset: Preset) void {
    const format = options.format;
    options.* = presetOptions(preset);
    options.format = format;
}

fn presetOptions(preset: Preset) Options {
    return switch (preset) {
        .local_smoke => .{
            .rows = 1_000,
            .vectors = 256,
            .dimensions = 16,
            .operations = 100,
            .preset = preset,
        },
        .acceptance_smoke => .{
            .rows = 2_000,
            .vectors = 512,
            .dimensions = 32,
            .operations = 200,
            .preset = preset,
        },
    };
}

fn now(io: std.Io) std.Io.Timestamp {
    return std.Io.Clock.awake.now(io);
}

fn elapsedSince(io: std.Io, start: std.Io.Timestamp) std.Io.Duration {
    return start.durationTo(now(io));
}

fn makeVectorCandidates(
    allocator: std.mem.Allocator,
    vector_count: usize,
    dimensions: usize,
) ![]search.Candidate {
    var candidates = try allocator.alloc(search.Candidate, vector_count);
    errdefer allocator.free(candidates);

    var initialized: usize = 0;
    errdefer {
        for (candidates[0..initialized]) |candidate| allocator.free(candidate.vector);
    }

    for (candidates, 0..) |*candidate, index| {
        const vector = try allocator.alloc(f32, dimensions);
        for (vector, 0..) |*component, dim| {
            component.* = @floatFromInt((index + dim) % 17);
        }
        candidate.* = .{ .key = @intCast(index + 1), .vector = vector };
        initialized += 1;
    }

    return candidates;
}

fn freeVectorCandidates(allocator: std.mem.Allocator, candidates: []search.Candidate) void {
    for (candidates) |candidate| allocator.free(candidate.vector);
    allocator.free(candidates);
}

fn makeQueryVector(allocator: std.mem.Allocator, dimensions: usize) ![]f32 {
    const query = try allocator.alloc(f32, dimensions);
    for (query, 0..) |*component, index| {
        component.* = @floatFromInt(index % 7);
    }
    return query;
}

test "benchmark options parse split and inline flags" {
    const options = try parseOptions(&.{ "--rows", "42", "--vectors=7", "--dimensions", "3", "--operations=5" });
    try std.testing.expectEqual(@as(usize, 42), options.rows);
    try std.testing.expectEqual(@as(usize, 7), options.vectors);
    try std.testing.expectEqual(@as(usize, 3), options.dimensions);
    try std.testing.expectEqual(@as(usize, 5), options.operations);
    try std.testing.expectEqual(OutputFormat.text, options.format);
    try std.testing.expectEqual(@as(?Preset, null), options.preset);
}

test "benchmark options parse presets and format" {
    const local = try parseOptions(&.{ "--preset", "local-smoke", "--format=json" });
    try std.testing.expectEqual(@as(usize, 1_000), local.rows);
    try std.testing.expectEqual(@as(usize, 256), local.vectors);
    try std.testing.expectEqual(@as(usize, 16), local.dimensions);
    try std.testing.expectEqual(@as(usize, 100), local.operations);
    try std.testing.expectEqual(OutputFormat.json, local.format);
    try std.testing.expectEqual(Preset.local_smoke, local.preset.?);

    const overridden = try parseOptions(&.{ "--preset=acceptance-smoke", "--rows", "25" });
    try std.testing.expectEqual(@as(usize, 25), overridden.rows);
    try std.testing.expectEqual(@as(usize, 512), overridden.vectors);
    try std.testing.expectEqual(@as(usize, 32), overridden.dimensions);
    try std.testing.expectEqual(@as(usize, 200), overridden.operations);
    try std.testing.expectEqual(Preset.acceptance_smoke, overridden.preset.?);
}

test "benchmark rejects unknown and incomplete options" {
    try std.testing.expectError(error.InvalidOption, parseOptions(&.{"--wat"}));
    try std.testing.expectError(error.MissingOptionValue, parseOptions(&.{"--rows"}));
    try std.testing.expectError(error.InvalidOption, parseOptions(&.{ "--rows", "nope" }));
    try std.testing.expectError(error.InvalidOption, parseOptions(&.{ "--preset", "tiny" }));
    try std.testing.expectError(error.InvalidOption, parseOptions(&.{"--format=xml"}));
}

test "benchmark sql vector literal uses requested dimensions" {
    const literal = try makeSqlVectorLiteral(std.testing.allocator, 4, 2);
    defer std.testing.allocator.free(literal);

    try std.testing.expectEqualStrings("[2, 3, 4, 5]", literal);
}
