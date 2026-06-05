const std = @import("std");
const shovelerdb = @import("shovelerdb");

const executor = shovelerdb.db.executor;
const search = shovelerdb.vector.search;
const vector_overlay = shovelerdb.vector.overlay;

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

    var db = executor.Database.init(allocator);
    defer db.deinit();
    var session = executor.Session.init(allocator);
    defer session.deinit();

    var result = try db.executeSql(&session, "CREATE TABLE scalar_memory (id INTEGER, body TEXT, score FLOAT);");
    result.deinit(allocator);
    result = try db.executeSql(&session, "CREATE TABLE memory_tags (id INTEGER, memory_id INTEGER, name TEXT);");
    result.deinit(allocator);
    const create_vector_table = try std.fmt.allocPrint(
        allocator,
        "CREATE TABLE vector_memory (id INTEGER, embedding VECTOR({d}));",
        .{options.dimensions},
    );
    defer allocator.free(create_vector_table);
    result = try db.executeSql(&session, create_vector_table);
    result.deinit(allocator);

    const insert_start = now(io);
    result = try db.executeSql(&session, "BEGIN;");
    result.deinit(allocator);
    for (0..options.rows) |index| {
        const statement = try std.fmt.allocPrint(
            allocator,
            "INSERT INTO scalar_memory VALUES ({d}, 'memory-{d}', {d}.25);",
            .{ index + 1, index + 1, index % 97 },
        );
        defer allocator.free(statement);
        result = try db.executeSql(&session, statement);
        result.deinit(allocator);
    }
    result = try db.executeSql(&session, "COMMIT;");
    result.deinit(allocator);
    const insert_elapsed = elapsedSince(io, insert_start);

    try loadJoinRows(allocator, &db, &session, options.rows);
    try loadSqlVectorRows(allocator, &db, &session, options.vectors, options.dimensions);

    const scan_start = now(io);
    result = try db.executeSql(&session, "SELECT * FROM scalar_memory;");
    result.deinit(allocator);
    const scan_elapsed = elapsedSince(io, scan_start);

    const grouped_start = now(io);
    result = try db.executeSql(&session, "SELECT score, COUNT(*) AS total FROM scalar_memory GROUP BY score HAVING total > 1 ORDER BY total DESC LIMIT 5;");
    result.deinit(allocator);
    const grouped_elapsed = elapsedSince(io, grouped_start);

    const joined_start = now(io);
    result = try db.executeSql(&session, "SELECT m.id, t.name FROM scalar_memory AS m JOIN memory_tags AS t ON t.memory_id = m.id WHERE t.name = 'project' ORDER BY m.id ASC LIMIT 10;");
    result.deinit(allocator);
    const joined_elapsed = elapsedSince(io, joined_start);

    const rollback_start = now(io);
    result = try db.executeSql(&session, "BEGIN;");
    result.deinit(allocator);
    const rollback_ops = @min(options.operations, options.rows);
    for (0..rollback_ops) |index| {
        const statement = try std.fmt.allocPrint(
            allocator,
            "UPDATE scalar_memory SET score = {d}.5 WHERE id = {d};",
            .{ index % 113, index + 1 },
        );
        defer allocator.free(statement);
        result = try db.executeSql(&session, statement);
        result.deinit(allocator);
    }
    result = try db.executeSql(&session, "ROLLBACK;");
    result.deinit(allocator);
    const rollback_elapsed = elapsedSince(io, rollback_start);

    const candidates = try makeVectorCandidates(allocator, options.vectors, options.dimensions);
    defer freeVectorCandidates(allocator, candidates);
    const query = try makeQueryVector(allocator, options.dimensions);
    defer allocator.free(query);

    const vector_start = now(io);
    const nearest = try search.topK(allocator, query, candidates, @min(@as(usize, 10), options.vectors), .squared_l2);
    defer allocator.free(nearest);
    const vector_elapsed = elapsedSince(io, vector_start);

    const query_vector_literal = try makeSqlVectorLiteral(allocator, options.dimensions, 0);
    defer allocator.free(query_vector_literal);
    const sql_vector_query = try std.fmt.allocPrint(
        allocator,
        "SELECT id, l2_distance(embedding, {s}) AS distance FROM vector_memory ORDER BY distance ASC LIMIT 10;",
        .{query_vector_literal},
    );
    defer allocator.free(sql_vector_query);
    const sql_vector_start = now(io);
    result = try db.executeSql(&session, sql_vector_query);
    result.deinit(allocator);
    const sql_vector_elapsed = elapsedSince(io, sql_vector_start);

    const phase6_ops = @min(options.operations, options.rows);
    const snapshot_begin_start = now(io);
    try runSnapshotBeginWorkload(allocator, &db, phase6_ops);
    const snapshot_begin_elapsed = elapsedSince(io, snapshot_begin_start);

    const queued_commit_start = now(io);
    try runQueuedCommitWorkload(allocator, &db, phase6_ops, 2_000_000);
    const queued_commit_elapsed = elapsedSince(io, queued_commit_start);

    const concurrent_start = now(io);
    try runConcurrentReadWriteWorkload(allocator, &db, phase6_ops, 3_000_000);
    const concurrent_elapsed = elapsedSince(io, concurrent_start);

    const checkpoint_overlap_start = now(io);
    const checkpoint_overlap_count = try runCheckpointOverlapWorkload(allocator, &db, phase6_ops);
    const checkpoint_overlap_elapsed = elapsedSince(io, checkpoint_overlap_start);

    const vector_overlay_start = now(io);
    const vector_overlay_count = try runVectorOverlayVisibilityWorkload(allocator, &db, phase6_ops);
    const vector_overlay_elapsed = elapsedSince(io, vector_overlay_start);

    const metrics = [_]Metric{
        .{ .name = "insert_commit", .count = options.rows, .elapsed = insert_elapsed },
        .{ .name = "select_scan", .count = options.rows, .elapsed = scan_elapsed },
        .{ .name = "grouped_scan", .count = options.rows, .elapsed = grouped_elapsed },
        .{ .name = "joined_filter", .count = options.rows, .elapsed = joined_elapsed },
        .{ .name = "rollback_updates", .count = rollback_ops, .elapsed = rollback_elapsed },
        .{ .name = "exact_vector_scan", .count = options.vectors, .elapsed = vector_elapsed },
        .{ .name = "sql_vector_rank", .count = options.vectors, .elapsed = sql_vector_elapsed },
        .{ .name = "snapshot_begin", .count = phase6_ops, .elapsed = snapshot_begin_elapsed },
        .{ .name = "queued_commit", .count = phase6_ops, .elapsed = queued_commit_elapsed },
        .{ .name = "concurrent_read_write", .count = phase6_ops, .elapsed = concurrent_elapsed },
        .{ .name = "checkpoint_overlap", .count = checkpoint_overlap_count, .elapsed = checkpoint_overlap_elapsed },
        .{ .name = "vector_overlay_visibility", .count = vector_overlay_count, .elapsed = vector_overlay_elapsed },
    };
    const nearest_summary: ?NearestSummary = if (nearest.len > 0)
        .{ .key = nearest[0].key, .distance = nearest[0].distance }
    else
        null;

    try writeReport(writer, .{
        .options = options,
        .metrics = &metrics,
        .nearest = nearest_summary,
    });
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

const Metric = struct {
    name: []const u8,
    count: usize,
    elapsed: std.Io.Duration,

    fn elapsedNanoseconds(self: Metric) i96 {
        return self.elapsed.toNanoseconds();
    }

    fn throughputPerSecond(self: Metric) u64 {
        return computeThroughputPerSecond(self.count, self.elapsed);
    }
};

const NearestSummary = struct {
    key: u64,
    distance: f64,
};

const BenchmarkReport = struct {
    options: Options,
    metrics: []const Metric,
    nearest: ?NearestSummary,
};

fn writeReport(writer: *std.Io.Writer, report: BenchmarkReport) !void {
    switch (report.options.format) {
        .text => try writeTextReport(writer, report),
        .json => try writeJsonReport(writer, report),
    }
}

fn writeTextReport(writer: *std.Io.Writer, report: BenchmarkReport) !void {
    try writer.print("benchmark\n", .{});
    try writer.print("  rows: {d}\n", .{report.options.rows});
    try writer.print("  vectors: {d}\n", .{report.options.vectors});
    try writer.print("  dimensions: {d}\n", .{report.options.dimensions});
    try writer.print("  operations: {d}\n", .{report.options.operations});

    for (report.metrics) |metric| try printMetric(writer, metric);
    if (report.nearest) |nearest| {
        try writer.print("  nearest_key: {d}\n", .{nearest.key});
        try writer.print("  nearest_distance: {d}\n", .{nearest.distance});
    }
}

fn writeJsonReport(writer: *std.Io.Writer, report: BenchmarkReport) !void {
    try writer.writeAll("{\"benchmark\":{\"preset\":");
    if (report.options.preset) |preset| {
        try writer.print("\"{s}\"", .{preset.label()});
    } else {
        try writer.writeAll("null");
    }
    try writer.print(
        ",\"rows\":{d},\"vectors\":{d},\"dimensions\":{d},\"operations\":{d}",
        .{ report.options.rows, report.options.vectors, report.options.dimensions, report.options.operations },
    );
    try writer.writeAll("},\"metrics\":[");
    for (report.metrics, 0..) |metric, index| {
        if (index > 0) try writer.writeAll(",");
        try writer.print(
            "{{\"name\":\"{s}\",\"count\":{d},\"elapsed_ns\":{d},\"throughput_per_s\":{d}}}",
            .{ metric.name, metric.count, metric.elapsedNanoseconds(), metric.throughputPerSecond() },
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
}

fn computeThroughputPerSecond(count: usize, elapsed: std.Io.Duration) u64 {
    const ns = elapsed.toNanoseconds();
    if (ns <= 0) return 0;
    const rate = (@as(u128, count) * std.time.ns_per_s) / @as(u128, @intCast(ns));
    return @intCast(@min(rate, std.math.maxInt(u64)));
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

test "benchmark report renders JSON metrics" {
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();

    const metrics = [_]Metric{
        .{ .name = "insert_commit", .count = 5, .elapsed = .fromNanoseconds(1_000) },
        .{ .name = "snapshot_begin", .count = 2, .elapsed = .fromNanoseconds(2_000) },
    };
    try writeReport(&output.writer, .{
        .options = .{
            .rows = 5,
            .vectors = 3,
            .dimensions = 2,
            .operations = 2,
            .format = .json,
            .preset = .local_smoke,
        },
        .metrics = &metrics,
        .nearest = .{ .key = 9, .distance = 1.25 },
    });

    const rendered = output.written();
    try std.testing.expect(try std.json.validate(std.testing.allocator, rendered));
    try std.testing.expect(std.mem.indexOf(u8, rendered, "\"preset\":\"local-smoke\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "\"name\":\"insert_commit\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "\"name\":\"snapshot_begin\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "\"throughput_per_s\"") != null);
}

test "benchmark report keeps text metric shape" {
    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();

    const metrics = [_]Metric{
        .{ .name = "queued_commit", .count = 4, .elapsed = .fromNanoseconds(2_000) },
    };
    try writeReport(&output.writer, .{
        .options = .{ .rows = 4, .vectors = 3, .dimensions = 2, .operations = 1 },
        .metrics = &metrics,
        .nearest = null,
    });

    const rendered = output.written();
    try std.testing.expect(std.mem.startsWith(u8, rendered, "benchmark\n  rows: 4\n"));
    try std.testing.expect(std.mem.indexOf(u8, rendered, "  queued_commit:\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "    count: 4\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered, "    elapsed_ns: 2000\n") != null);
}
