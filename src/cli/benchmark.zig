const std = @import("std");
const shovelerdb = @import("shovelerdb");

const executor = shovelerdb.db.executor;
const search = shovelerdb.vector.search;

pub const BenchmarkError = error{
    InvalidOption,
    MissingOptionValue,
};

pub const Options = struct {
    rows: usize = 10_000,
    vectors: usize = 1_000,
    dimensions: usize = 128,
    operations: usize = 1_000,
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
        \\usage: shoveler benchmark [--rows N] [--vectors N] [--dimensions N] [--operations N]
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

    try writer.print("benchmark\n", .{});
    try writer.print("  rows: {d}\n", .{options.rows});
    try writer.print("  vectors: {d}\n", .{options.vectors});
    try writer.print("  dimensions: {d}\n", .{options.dimensions});
    try writer.print("  operations: {d}\n", .{options.operations});

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

    try printMetric(writer, "insert_commit", options.rows, insert_elapsed);
    try printMetric(writer, "select_scan", options.rows, scan_elapsed);
    try printMetric(writer, "grouped_scan", options.rows, grouped_elapsed);
    try printMetric(writer, "joined_filter", options.rows, joined_elapsed);
    try printMetric(writer, "rollback_updates", rollback_ops, rollback_elapsed);
    try printMetric(writer, "exact_vector_scan", options.vectors, vector_elapsed);
    try printMetric(writer, "sql_vector_rank", options.vectors, sql_vector_elapsed);
    if (nearest.len > 0) {
        try writer.print("  nearest_key: {d}\n", .{nearest[0].key});
        try writer.print("  nearest_distance: {d}\n", .{nearest[0].distance});
    }
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
    return null;
}

fn setOption(options: *Options, name: []const u8, raw_value: []const u8) !void {
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

fn now(io: std.Io) std.Io.Timestamp {
    return std.Io.Clock.awake.now(io);
}

fn elapsedSince(io: std.Io, start: std.Io.Timestamp) std.Io.Duration {
    return start.durationTo(now(io));
}

fn printMetric(writer: *std.Io.Writer, name: []const u8, count: usize, elapsed: std.Io.Duration) !void {
    try writer.print("  {s}:\n", .{name});
    try writer.print("    count: {d}\n", .{count});
    try writer.print("    elapsed_ns: {d}\n", .{elapsed.toNanoseconds()});
    try writer.print("    throughput_per_s: {d}\n", .{throughputPerSecond(count, elapsed)});
}

fn throughputPerSecond(count: usize, elapsed: std.Io.Duration) u64 {
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
}

test "benchmark rejects unknown and incomplete options" {
    try std.testing.expectError(error.InvalidOption, parseOptions(&.{"--wat"}));
    try std.testing.expectError(error.MissingOptionValue, parseOptions(&.{"--rows"}));
    try std.testing.expectError(error.InvalidOption, parseOptions(&.{ "--rows", "nope" }));
}

test "benchmark sql vector literal uses requested dimensions" {
    const literal = try makeSqlVectorLiteral(std.testing.allocator, 4, 2);
    defer std.testing.allocator.free(literal);

    try std.testing.expectEqualStrings("[2, 3, 4, 5]", literal);
}
