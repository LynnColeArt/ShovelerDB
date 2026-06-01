const std = @import("std");
const shovelerdb = @import("shovelerdb");

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
        try stdout.print("       shoveler classify-test <path>\n", .{});
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
            try stdout.print("usage: shoveler classify-test <path>\n", .{});
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
        const classification = shovelerdb.mariadb.test_classifier.classify(analysis);

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
