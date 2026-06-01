const std = @import("std");
const executor = @import("../db/executor.zig");

pub const MtrLiteError = error{
    MissingSqlBlock,
    UnsupportedDirective,
    ExpectedErrorMismatch,
    UnexpectedSuccess,
};

pub const DiagnosticKind = enum {
    missing_sql_block,
    unsupported_directive,
    expected_error_mismatch,
    unexpected_success,
};

pub const RunSummary = struct {
    statements: usize = 0,
    executed: usize = 0,
    expected_errors: usize = 0,
};

pub fn diagnosticFromError(err: anyerror) ?DiagnosticKind {
    return switch (err) {
        error.MissingSqlBlock => .missing_sql_block,
        error.UnsupportedDirective => .unsupported_directive,
        error.ExpectedErrorMismatch => .expected_error_mismatch,
        error.UnexpectedSuccess => .unexpected_success,
        else => null,
    };
}

pub fn runMarkdownFixture(allocator: std.mem.Allocator, contents: []const u8) !RunSummary {
    const script = try extractSqlBlocks(allocator, contents);
    defer allocator.free(script);

    var db = executor.Database.init(allocator);
    defer db.deinit();
    var session = executor.Session.init(allocator);
    defer session.deinit();

    return runSqlScript(allocator, &db, &session, script);
}

pub fn runSqlScript(
    allocator: std.mem.Allocator,
    db: *executor.Database,
    session: *executor.Session,
    script: []const u8,
) !RunSummary {
    var summary: RunSummary = .{};
    var statement: std.ArrayList(u8) = .empty;
    defer statement.deinit(allocator);

    var expected_error: ?[]const u8 = null;
    var index: usize = 0;
    while (index <= script.len) {
        const line_start = index;
        while (index < script.len and script[index] != '\n') : (index += 1) {}
        const line_end = index;
        if (index < script.len and script[index] == '\n') index += 1;
        if (line_start == script.len) break;

        const line = script[line_start..line_end];
        const trimmed = trim(line);
        if (trimmed.len == 0) continue;

        if (statement.items.len == 0) {
            if (std.mem.startsWith(u8, trimmed, "--error")) {
                if (expected_error != null) return error.UnsupportedDirective;
                expected_error = trim(trimmed["--error".len..]);
                if (expected_error.?.len == 0) return error.UnsupportedDirective;
                continue;
            }
            if (isUnsupportedDirective(trimmed)) return error.UnsupportedDirective;
        }

        if (statement.items.len != 0) try statement.append(allocator, '\n');
        try statement.appendSlice(allocator, line);

        if (!statementComplete(statement.items)) continue;

        const sql = stripTrailingSemicolon(trim(statement.items));
        if (sql.len != 0) {
            summary.statements += 1;
            try executeStatement(allocator, db, session, sql, expected_error, &summary);
            expected_error = null;
        }
        statement.clearRetainingCapacity();
    }

    if (trim(statement.items).len != 0) {
        const sql = stripTrailingSemicolon(trim(statement.items));
        summary.statements += 1;
        try executeStatement(allocator, db, session, sql, expected_error, &summary);
    } else if (expected_error != null) {
        return error.ExpectedErrorMismatch;
    }

    return summary;
}

fn executeStatement(
    allocator: std.mem.Allocator,
    db: *executor.Database,
    session: *executor.Session,
    sql: []const u8,
    expected_error: ?[]const u8,
    summary: *RunSummary,
) !void {
    var result = db.executeSql(session, sql) catch |err| {
        const expected = expected_error orelse return err;
        if (!std.ascii.eqlIgnoreCase(expected, @errorName(err))) return error.ExpectedErrorMismatch;
        summary.expected_errors += 1;
        summary.executed += 1;
        return;
    };
    defer result.deinit(allocator);

    if (expected_error != null) return error.UnexpectedSuccess;
    summary.executed += 1;
}

fn extractSqlBlocks(allocator: std.mem.Allocator, contents: []const u8) ![]u8 {
    var script: std.ArrayList(u8) = .empty;
    errdefer script.deinit(allocator);

    var in_sql = false;
    var saw_sql = false;
    var index: usize = 0;
    while (index <= contents.len) {
        const line_start = index;
        while (index < contents.len and contents[index] != '\n') : (index += 1) {}
        const line_end = index;
        if (index < contents.len and contents[index] == '\n') index += 1;
        if (line_start == contents.len) break;

        const line = contents[line_start..line_end];
        const trimmed = trim(line);
        if (std.mem.startsWith(u8, trimmed, "```")) {
            if (in_sql) {
                in_sql = false;
            } else if (std.ascii.eqlIgnoreCase(trim(trimmed["```".len..]), "sql")) {
                in_sql = true;
                saw_sql = true;
            }
            continue;
        }

        if (!in_sql) continue;
        try script.appendSlice(allocator, line);
        try script.append(allocator, '\n');
    }

    if (!saw_sql) return error.MissingSqlBlock;
    return script.toOwnedSlice(allocator);
}

fn statementComplete(statement: []const u8) bool {
    const stripped = trim(statement);
    if (!std.mem.endsWith(u8, stripped, ";")) return false;
    const without_semicolon = trim(stripped[0 .. stripped.len - 1]);

    if (startsWithWord(without_semicolon, "CREATE") and containsWord(without_semicolon, "PROCEDURE")) {
        return endsWithWord(without_semicolon, "END");
    }

    return true;
}

fn stripTrailingSemicolon(input: []const u8) []const u8 {
    const stripped = trim(input);
    if (!std.mem.endsWith(u8, stripped, ";")) return stripped;
    return trim(stripped[0 .. stripped.len - 1]);
}

fn isUnsupportedDirective(line: []const u8) bool {
    if (std.mem.startsWith(u8, line, "--")) return true;

    const commands = [_][]const u8{
        "append_file",
        "cat_file",
        "connect",
        "connection",
        "copy_file",
        "delimiter",
        "dirty_close",
        "disconnect",
        "echo",
        "exec",
        "let",
        "perl",
        "query_vertical",
        "replace_result",
        "send",
        "sleep",
        "source",
        "write_file",
    };

    inline for (commands) |command| {
        if (startsWithWord(line, command)) return true;
    }
    return false;
}

fn containsWord(input: []const u8, word: []const u8) bool {
    var index: usize = 0;
    while (index < input.len) {
        while (index < input.len and !isWordContinue(input[index])) index += 1;
        const start = index;
        while (index < input.len and isWordContinue(input[index])) index += 1;
        if (start == index) continue;
        if (std.ascii.eqlIgnoreCase(input[start..index], word)) return true;
    }
    return false;
}

fn startsWithWord(input: []const u8, word: []const u8) bool {
    if (input.len < word.len) return false;
    if (!std.ascii.eqlIgnoreCase(input[0..word.len], word)) return false;
    return input.len == word.len or !isWordContinue(input[word.len]);
}

fn endsWithWord(input: []const u8, word: []const u8) bool {
    if (input.len < word.len) return false;
    const start = input.len - word.len;
    if (!std.ascii.eqlIgnoreCase(input[start..], word)) return false;
    return start == 0 or !isWordContinue(input[start - 1]);
}

fn isWordContinue(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

fn trim(input: []const u8) []const u8 {
    return std.mem.trim(u8, input, &std.ascii.whitespace);
}

test "mtr-lite runs SQL blocks from adapted fixture descriptors" {
    const fixture =
        \\# Adapted Fixture
        \\
        \\```sql
        \\CREATE TABLE memories (id INTEGER, body TEXT, embedding VECTOR(2));
        \\BEGIN;
        \\INSERT INTO memories VALUES (1, 'alpha', [1, 0]);
        \\COMMIT;
        \\SELECT id, body FROM memories WHERE id = 1;
        \\```
    ;

    const summary = try runMarkdownFixture(std.testing.allocator, fixture);
    try std.testing.expectEqual(@as(usize, 5), summary.statements);
    try std.testing.expectEqual(@as(usize, 5), summary.executed);
    try std.testing.expectEqual(@as(usize, 0), summary.expected_errors);
}

test "mtr-lite supports expected error directives" {
    const script =
        \\CREATE TABLE memories (id INTEGER, embedding VECTOR(2));
        \\BEGIN;
        \\--error VectorDimensionMismatch
        \\INSERT INTO memories VALUES (1, [1, 2, 3]);
    ;

    var db = executor.Database.init(std.testing.allocator);
    defer db.deinit();
    var session = executor.Session.init(std.testing.allocator);
    defer session.deinit();

    const summary = try runSqlScript(std.testing.allocator, &db, &session, script);
    try std.testing.expectEqual(@as(usize, 3), summary.statements);
    try std.testing.expectEqual(@as(usize, 3), summary.executed);
    try std.testing.expectEqual(@as(usize, 1), summary.expected_errors);
}

test "mtr-lite rejects unsupported harness directives" {
    const script =
        \\connect con1,localhost,root,,;
    ;

    var db = executor.Database.init(std.testing.allocator);
    defer db.deinit();
    var session = executor.Session.init(std.testing.allocator);
    defer session.deinit();

    try std.testing.expectError(
        error.UnsupportedDirective,
        runSqlScript(std.testing.allocator, &db, &session, script),
    );
}
