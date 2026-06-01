const std = @import("std");
const benchmark = @import("benchmark.zig");
const shovelerdb = @import("shovelerdb");

const executor = shovelerdb.db.executor;
const value = shovelerdb.db.value;
const test_analyzer = shovelerdb.mariadb.test_analyzer;
const test_classifier = shovelerdb.mariadb.test_classifier;
const mtr_lite = shovelerdb.mariadb.mtr_lite;
const parser = shovelerdb.sql.parser;
const policy = shovelerdb.sql.policy;

const ClassificationSummary = struct {
    files: usize = 0,
    sacred_candidate: usize = 0,
    adaptation_candidate: usize = 0,
    rejected_by_policy: usize = 0,
    deferred_candidate: usize = 0,
    statements: usize = 0,
    accepted_statements: usize = 0,
    rejected_statements: usize = 0,

    fn add(
        self: *ClassificationSummary,
        classification: test_classifier.Classification,
        analysis: test_analyzer.Analysis,
    ) void {
        self.files += 1;
        self.statements += analysis.statements;
        self.accepted_statements += analysis.accepted_statements;
        self.rejected_statements += analysis.rejected_statements;

        switch (classification.bucket) {
            .sacred_candidate => self.sacred_candidate += 1,
            .adaptation_candidate => self.adaptation_candidate += 1,
            .rejected_by_policy => self.rejected_by_policy += 1,
            .deferred_candidate => self.deferred_candidate += 1,
        }
    }
};

pub fn run(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    var stdout_buffer: [2048]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    if (args.len == 1) {
        try printUsage(stdout);
        try stdout.flush();
        return;
    }

    if (std.mem.eql(u8, args[1], "check-sql")) return checkSql(stdout, args);
    if (std.mem.eql(u8, args[1], "parse")) return parseSql(arena, stdout, args);
    if (std.mem.eql(u8, args[1], "execute")) return executeSql(arena, stdout, args);
    if (std.mem.eql(u8, args[1], "analyze-test")) return analyzeTest(io, arena, stdout, args);
    if (std.mem.eql(u8, args[1], "classify-test")) return classifyTests(io, arena, stdout, args);
    if (std.mem.eql(u8, args[1], "run-adapted-test")) return runAdaptedTest(io, arena, stdout, args);
    if (std.mem.eql(u8, args[1], "benchmark")) return runBenchmark(io, arena, stdout, args);

    try stdout.print("unknown command: {s}\n", .{args[1]});
    try stdout.flush();
    std.process.exit(64);
}

pub fn printUsage(stdout: *std.Io.Writer) !void {
    try stdout.print("ShovelerDB: MariaDB-like SQL, implemented in Zig\n", .{});
    try stdout.print("usage: shoveler check-sql <sql>\n", .{});
    try stdout.print("       shoveler parse <sql>\n", .{});
    try stdout.print("       shoveler execute <sql> [sql...]\n", .{});
    try stdout.print("       shoveler analyze-test <path>\n", .{});
    try stdout.print("       shoveler classify-test <path> [path...]\n", .{});
    try stdout.print("       shoveler run-adapted-test <fixture.md>\n", .{});
    try stdout.print("       shoveler benchmark [--rows N] [--vectors N] [--dimensions N] [--operations N]\n", .{});
}

fn checkSql(stdout: *std.Io.Writer, args: []const []const u8) !void {
    if (args.len < 3) {
        try stdout.print("usage: shoveler check-sql <sql>\n", .{});
        try stdout.flush();
        std.process.exit(64);
    }

    const sql = args[2];
    if (policy.firstViolation(sql)) |found| {
        try stdout.print("rejected: {s} at byte {d} near `{s}`\n", .{
            found.message(),
            found.offset,
            found.token,
        });
        try stdout.flush();
        std.process.exit(2);
    }

    try stdout.print("accepted\n", .{});
    try stdout.flush();
}

fn parseSql(allocator: std.mem.Allocator, stdout: *std.Io.Writer, args: []const []const u8) !void {
    if (args.len < 3) {
        try stdout.print("usage: shoveler parse <sql>\n", .{});
        try stdout.flush();
        std.process.exit(64);
    }

    var parsed = try parser.parse(allocator, args[2]);
    defer parsed.deinit(allocator);

    switch (parsed) {
        .statement => |statement| {
            try stdout.print("statement: {s}\n", .{@tagName(std.meta.activeTag(statement))});
        },
        .diagnostic => |diagnostic| {
            try printParseDiagnostic(stdout, diagnostic);
            try stdout.flush();
            std.process.exit(2);
        },
    }

    try stdout.flush();
}

fn executeSql(allocator: std.mem.Allocator, stdout: *std.Io.Writer, args: []const []const u8) !void {
    if (args.len < 3) {
        try stdout.print("usage: shoveler execute <sql> [sql...]\n", .{});
        try stdout.flush();
        std.process.exit(64);
    }

    var db = executor.Database.init(allocator);
    defer db.deinit();
    var session = executor.Session.init(allocator);
    defer session.deinit();

    for (args[2..]) |sql| {
        try stdout.print("sql: {s}\n", .{sql});
        var result = db.executeSql(&session, sql) catch |err| {
            try stdout.print("error: {s}\n", .{@errorName(err)});
            if (executor.diagnosticFromError(err)) |diagnostic| {
                try stdout.print("diagnostic: {s}\n", .{@tagName(diagnostic)});
            }
            try stdout.flush();
            std.process.exit(2);
        };
        defer result.deinit(allocator);

        try printExecutionResult(stdout, &result);
    }

    try stdout.flush();
}

fn analyzeTest(
    io: std.Io,
    allocator: std.mem.Allocator,
    stdout: *std.Io.Writer,
    args: []const []const u8,
) !void {
    if (args.len < 3) {
        try stdout.print("usage: shoveler analyze-test <path>\n", .{});
        try stdout.flush();
        std.process.exit(64);
    }

    const path = args[2];
    const contents = try std.Io.Dir.cwd().readFileAlloc(
        io,
        path,
        allocator,
        .limited(100 * 1024 * 1024),
    );
    const analysis = try test_analyzer.analyze(allocator, contents);

    try stdout.print("{s}\n", .{path});
    try stdout.print("  statements: {d}\n", .{analysis.statements});
    try stdout.print("  accepted: {d}\n", .{analysis.accepted_statements});
    try stdout.print("  rejected: {d}\n", .{analysis.rejected_statements});
    try stdout.print("  directives: {d}\n", .{analysis.directives});
    try stdout.print("  harness commands: {d}\n", .{analysis.harness_commands});
    try stdout.print("  expected errors: {d}\n", .{analysis.expected_errors});
    try stdout.print("  delimiter changes: {d}\n", .{analysis.delimiter_changes});
    if (analysis.unterminated_statement) {
        try stdout.print("  warning: unterminated statement\n", .{});
    }
    if (analysis.first_violation) |found| {
        try stdout.print("  first rejection: {s} at line {d}, byte {d}, near `{s}`\n", .{
            found.feature.label(),
            found.line,
            found.offset,
            found.tokenText(),
        });
    }
    try stdout.flush();
}

fn classifyTests(
    io: std.Io,
    allocator: std.mem.Allocator,
    stdout: *std.Io.Writer,
    args: []const []const u8,
) !void {
    if (args.len < 3) {
        try stdout.print("usage: shoveler classify-test <path> [path...]\n", .{});
        try stdout.flush();
        std.process.exit(64);
    }

    var summary: ClassificationSummary = .{};
    const multi_file = args.len > 3;

    for (args[2..]) |path| {
        const contents = try std.Io.Dir.cwd().readFileAlloc(
            io,
            path,
            allocator,
            .limited(100 * 1024 * 1024),
        );
        const analysis = try test_analyzer.analyze(allocator, contents);
        const classification = test_classifier.classify(analysis);
        summary.add(classification, analysis);

        try stdout.print("{s}: {s}\n", .{ path, classification.bucket.label() });
        try stdout.print("  reason: {s}\n", .{classification.reason});
        try stdout.print("  statements: {d} accepted, {d} rejected, {d} total\n", .{
            analysis.accepted_statements,
            analysis.rejected_statements,
            analysis.statements,
        });
        if (analysis.first_violation) |found| {
            try stdout.print("  first rejection: {s} at line {d}, byte {d}, near `{s}`\n", .{
                found.feature.label(),
                found.line,
                found.offset,
                found.tokenText(),
            });
        }
    }

    if (multi_file) {
        try printClassificationSummary(stdout, summary);
    }

    try stdout.flush();
}

fn runBenchmark(
    io: std.Io,
    allocator: std.mem.Allocator,
    stdout: *std.Io.Writer,
    args: []const []const u8,
) !void {
    const options = benchmark.parseOptions(args[2..]) catch |err| {
        try stdout.print("benchmark option error: {s}\n", .{@errorName(err)});
        try benchmark.printUsage(stdout);
        try stdout.flush();
        std.process.exit(64);
    };

    benchmark.run(allocator, io, stdout, options) catch |err| {
        try stdout.print("benchmark error: {s}\n", .{@errorName(err)});
        try stdout.flush();
        std.process.exit(2);
    };
    try stdout.flush();
}

fn runAdaptedTest(
    io: std.Io,
    allocator: std.mem.Allocator,
    stdout: *std.Io.Writer,
    args: []const []const u8,
) !void {
    if (args.len < 3) {
        try stdout.print("usage: shoveler run-adapted-test <fixture.md>\n", .{});
        try stdout.flush();
        std.process.exit(64);
    }

    const path = args[2];
    const contents = try std.Io.Dir.cwd().readFileAlloc(
        io,
        path,
        allocator,
        .limited(100 * 1024 * 1024),
    );

    const summary = mtr_lite.runMarkdownFixture(allocator, contents) catch |err| {
        try stdout.print("fixture error: {s}\n", .{@errorName(err)});
        if (mtr_lite.diagnosticFromError(err)) |diagnostic| {
            try stdout.print("diagnostic: {s}\n", .{@tagName(diagnostic)});
        }
        try stdout.flush();
        std.process.exit(2);
    };

    try stdout.print("{s}\n", .{path});
    try stdout.print("  statements: {d}\n", .{summary.statements});
    try stdout.print("  executed: {d}\n", .{summary.executed});
    try stdout.print("  expected errors: {d}\n", .{summary.expected_errors});
    try stdout.flush();
}

fn printParseDiagnostic(stdout: *std.Io.Writer, diagnostic: parser.Diagnostic) !void {
    try stdout.print("diagnostic: {s} at byte {d}", .{
        @tagName(diagnostic.code),
        diagnostic.offset,
    });
    if (diagnostic.token.len > 0) {
        try stdout.print(" near `{s}`", .{diagnostic.token});
    }
    if (diagnostic.expected.len > 0) {
        try stdout.print(" expected {s}", .{diagnostic.expected});
    }
    if (diagnostic.policy_feature) |feature| {
        try stdout.print(" feature {s}", .{feature.label()});
    }
    try stdout.print("\n", .{});
}

fn printExecutionResult(stdout: *std.Io.Writer, result: *executor.ExecutionResult) !void {
    switch (result.*) {
        .ok => try stdout.print("ok\n", .{}),
        .mutation_count => |count| try stdout.print("mutated: {d}\n", .{count}),
        .result_set => |*result_set| {
            try stdout.print("columns:", .{});
            for (result_set.columns) |column| {
                try stdout.print(" {s}", .{column});
            }
            try stdout.print("\n", .{});
            for (result_set.rows) |row| {
                try stdout.print("row:", .{});
                for (row.values) |runtime_value| {
                    try stdout.print(" ", .{});
                    try printValue(stdout, runtime_value);
                }
                try stdout.print("\n", .{});
            }
            try stdout.print("rows: {d}\n", .{result_set.rows.len});
        },
    }
}

fn printValue(stdout: *std.Io.Writer, runtime_value: value.Value) !void {
    switch (runtime_value) {
        .null => try stdout.print("NULL", .{}),
        .integer => |v| try stdout.print("{d}", .{v}),
        .float => |v| try stdout.print("{d}", .{v}),
        .boolean => |v| try stdout.print("{s}", .{if (v) "TRUE" else "FALSE"}),
        .text => |v| try stdout.print("'{s}'", .{v}),
        .blob => |v| try stdout.print("<blob:{d}>", .{v.len}),
        .vector => |vector| {
            try stdout.print("[", .{});
            for (vector.values, 0..) |component, index| {
                if (index > 0) try stdout.print(",", .{});
                try stdout.print("{d}", .{component});
            }
            try stdout.print("]", .{});
        },
    }
}

fn printClassificationSummary(stdout: *std.Io.Writer, summary: ClassificationSummary) !void {
    try stdout.print("\nsummary\n", .{});
    try stdout.print("  files: {d}\n", .{summary.files});
    try stdout.print("  sacred-candidate: {d}\n", .{summary.sacred_candidate});
    try stdout.print("  adaptation-candidate: {d}\n", .{summary.adaptation_candidate});
    try stdout.print("  rejected-by-policy: {d}\n", .{summary.rejected_by_policy});
    try stdout.print("  deferred-candidate: {d}\n", .{summary.deferred_candidate});
    try stdout.print("  statements: {d} accepted, {d} rejected, {d} total\n", .{
        summary.accepted_statements,
        summary.rejected_statements,
        summary.statements,
    });
}

test "classification summary counts buckets and statements" {
    var summary: ClassificationSummary = .{};

    summary.add(
        .{ .bucket = .adaptation_candidate, .reason = "harnessed" },
        .{ .statements = 2, .accepted_statements = 2 },
    );
    summary.add(
        .{ .bucket = .rejected_by_policy, .reason = "policy" },
        .{ .statements = 3, .accepted_statements = 2, .rejected_statements = 1 },
    );

    try std.testing.expectEqual(@as(usize, 2), summary.files);
    try std.testing.expectEqual(@as(usize, 1), summary.adaptation_candidate);
    try std.testing.expectEqual(@as(usize, 1), summary.rejected_by_policy);
    try std.testing.expectEqual(@as(usize, 5), summary.statements);
    try std.testing.expectEqual(@as(usize, 4), summary.accepted_statements);
    try std.testing.expectEqual(@as(usize, 1), summary.rejected_statements);
}
