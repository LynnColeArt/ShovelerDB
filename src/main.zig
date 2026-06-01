const std = @import("std");
const shovelerdb = @import("shovelerdb");

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
        classification: shovelerdb.mariadb.test_classifier.Classification,
        analysis: shovelerdb.mariadb.test_analyzer.Analysis,
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

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    if (args.len == 1) {
        try stdout.print("{s}: {s}, implemented in {s}\n", .{
            shovelerdb.Project.name,
            shovelerdb.Project.dialect,
            shovelerdb.Project.implementation_language,
        });
        try stdout.print("usage: shoveler check-sql <sql>\n", .{});
        try stdout.print("       shoveler analyze-test <path>\n", .{});
        try stdout.print("       shoveler classify-test <path> [path...]\n", .{});
        try stdout.flush();
        return;
    }

    if (std.mem.eql(u8, args[1], "check-sql")) {
        if (args.len < 3) {
            try stdout.print("usage: shoveler check-sql <sql>\n", .{});
            try stdout.flush();
            std.process.exit(64);
        }

        const sql = args[2];
        if (shovelerdb.sql.policy.firstViolation(sql)) |found| {
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
        return;
    }

    if (std.mem.eql(u8, args[1], "analyze-test")) {
        if (args.len < 3) {
            try stdout.print("usage: shoveler analyze-test <path>\n", .{});
            try stdout.flush();
            std.process.exit(64);
        }

        const path = args[2];
        const contents = try std.Io.Dir.cwd().readFileAlloc(
            io,
            path,
            arena,
            .limited(100 * 1024 * 1024),
        );
        const analysis = try shovelerdb.mariadb.test_analyzer.analyze(arena, contents);

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
        return;
    }

    if (std.mem.eql(u8, args[1], "classify-test")) {
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
                arena,
                .limited(100 * 1024 * 1024),
            );
            const analysis = try shovelerdb.mariadb.test_analyzer.analyze(arena, contents);
            const classification = shovelerdb.mariadb.test_classifier.classify(analysis);
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

        try stdout.flush();
        return;
    }

    try stdout.print("unknown command: {s}\n", .{args[1]});
    try stdout.flush();
    std.process.exit(64);
}

test "main module imports project metadata" {
    try std.testing.expectEqualStrings("ShovelerDB", shovelerdb.Project.name);
    try std.testing.expect(shovelerdb.FeaturePolicy.transactions);
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
