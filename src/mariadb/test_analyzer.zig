const std = @import("std");
const sql_policy = @import("../sql/policy.zig");

pub const StatementViolation = struct {
    feature: sql_policy.UnsupportedFeature,
    line: usize,
    offset: usize,
    token: [64]u8,
    token_len: usize,

    pub fn tokenText(self: *const StatementViolation) []const u8 {
        return self.token[0..self.token_len];
    }
};

pub const Analysis = struct {
    statements: usize = 0,
    accepted_statements: usize = 0,
    rejected_statements: usize = 0,
    directives: usize = 0,
    harness_commands: usize = 0,
    comments: usize = 0,
    blank_lines: usize = 0,
    expected_errors: usize = 0,
    delimiter_changes: usize = 0,
    unterminated_statement: bool = false,
    first_violation: ?StatementViolation = null,
};

pub fn analyze(gpa: std.mem.Allocator, contents: []const u8) !Analysis {
    var result: Analysis = .{};
    var statement: std.ArrayList(u8) = .empty;
    defer statement.deinit(gpa);

    var delimiter: []const u8 = ";";
    var statement_start_line: usize = 0;
    var index: usize = 0;
    var line_number: usize = 1;

    while (index <= contents.len) : (line_number += 1) {
        const line_start = index;
        while (index < contents.len and contents[index] != '\n') : (index += 1) {}
        const line_end = index;
        const line = contents[line_start..line_end];
        if (index < contents.len and contents[index] == '\n') {
            index += 1;
        } else if (line_start == contents.len) {
            break;
        }

        const trimmed = trim(line);

        if (statement.items.len == 0) {
            if (trimmed.len == 0) {
                result.blank_lines += 1;
                continue;
            }
            if (std.mem.startsWith(u8, trimmed, "#")) {
                result.comments += 1;
                continue;
            }
            if (std.mem.startsWith(u8, trimmed, "--")) {
                result.directives += 1;
                if (startsWithWord(trimmed[2..], "error")) result.expected_errors += 1;
                continue;
            }
            if (parseDelimiterCommand(trimmed, delimiter)) |next_delimiter| {
                delimiter = next_delimiter;
                result.delimiter_changes += 1;
                result.harness_commands += 1;
                continue;
            }
            if (sqlAfterHarnessPrefix(trimmed)) |sql| {
                result.harness_commands += 1;
                statement_start_line = line_number;
                try appendLine(gpa, &statement, sql);
            } else {
                if (isHarnessCommandLine(trimmed)) {
                    result.harness_commands += 1;
                    if (startsWithWord(trimmed, "error")) result.expected_errors += 1;
                    continue;
                }
                statement_start_line = line_number;
                try appendLine(gpa, &statement, trimmed);
            }
        } else {
            try appendLine(gpa, &statement, line);
        }

        const statement_trimmed = trim(statement.items);
        if (endsWithDelimiter(statement_trimmed, delimiter)) {
            const without_delimiter = trim(statement_trimmed[0 .. statement_trimmed.len - delimiter.len]);
            inspectStatement(&result, without_delimiter, statement_start_line);
            statement.clearRetainingCapacity();
            statement_start_line = 0;
        }
    }

    if (trim(statement.items).len != 0) {
        result.unterminated_statement = true;
        inspectStatement(&result, trim(statement.items), statement_start_line);
    }

    return result;
}

fn inspectStatement(result: *Analysis, statement: []const u8, line: usize) void {
    if (statement.len == 0) return;

    result.statements += 1;
    if (sql_policy.firstViolation(statement)) |found| {
        result.rejected_statements += 1;
        if (result.first_violation == null) {
            var token: [64]u8 = undefined;
            const token_len = @min(token.len, found.token.len);
            @memcpy(token[0..token_len], found.token[0..token_len]);
            result.first_violation = .{
                .feature = found.feature,
                .line = line,
                .offset = found.offset,
                .token = token,
                .token_len = token_len,
            };
        }
    } else {
        result.accepted_statements += 1;
    }
}

fn appendLine(gpa: std.mem.Allocator, statement: *std.ArrayList(u8), line: []const u8) !void {
    if (statement.items.len != 0) try statement.append(gpa, '\n');
    try statement.appendSlice(gpa, line);
}

fn trim(input: []const u8) []const u8 {
    return std.mem.trim(u8, input, &std.ascii.whitespace);
}

fn endsWithDelimiter(input: []const u8, delimiter: []const u8) bool {
    return delimiter.len != 0 and std.mem.endsWith(u8, input, delimiter);
}

fn parseDelimiterCommand(line: []const u8, current_delimiter: []const u8) ?[]const u8 {
    const prefix = "delimiter";
    if (!startsWithWord(line, prefix)) return null;

    var rest = trim(line[prefix.len..]);
    if (rest.len == 0) return null;
    if (endsWithDelimiter(rest, current_delimiter)) {
        rest = trim(rest[0 .. rest.len - current_delimiter.len]);
    }
    if (rest.len == 0) return null;
    return rest;
}

fn sqlAfterHarnessPrefix(line: []const u8) ?[]const u8 {
    const prefixes = [_][]const u8{
        "query_vertical",
        "query_horizontal",
        "sorted_result",
    };

    inline for (prefixes) |prefix| {
        if (startsWithWord(line, prefix)) {
            const rest = trim(line[prefix.len..]);
            return if (rest.len == 0) null else rest;
        }
    }

    return null;
}

fn isHarnessCommandLine(line: []const u8) bool {
    const commands = [_][]const u8{
        "append_file",
        "cat_file",
        "connect",
        "connection",
        "copy_file",
        "dec",
        "delimiter",
        "dirty_close",
        "disable_info",
        "disable_query_log",
        "disable_result_log",
        "disable_warnings",
        "disconnect",
        "echo",
        "enable_info",
        "enable_query_log",
        "enable_result_log",
        "enable_warnings",
        "error",
        "exec",
        "if",
        "inc",
        "let",
        "list_files",
        "mkdir",
        "move_file",
        "perl",
        "query_vertical",
        "reap",
        "remove_file",
        "replace_result",
        "rmdir",
        "send",
        "sleep",
        "source",
        "write_file",
        "}",
    };

    inline for (commands) |command| {
        if (startsWithWord(line, command)) return true;
    }
    return false;
}

fn startsWithWord(input: []const u8, word: []const u8) bool {
    if (word.len == 1 and word[0] == '}') {
        return input.len > 0 and input[0] == '}';
    }

    if (input.len < word.len) return false;
    if (!std.ascii.eqlIgnoreCase(input[0..word.len], word)) return false;
    if (input.len == word.len) return true;

    return std.ascii.isWhitespace(input[word.len]);
}

test "analyzer counts directives, statements, and policy rejections" {
    const text =
        \\# vector reference
        \\--error ER_NO_INDEX_ON_TEMPORARY
        \\create temporary table t1 (id int);
        \\
        \\create table t2 (id int);
    ;

    const result = try analyze(std.testing.allocator, text);
    try std.testing.expectEqual(@as(usize, 2), result.statements);
    try std.testing.expectEqual(@as(usize, 1), result.accepted_statements);
    try std.testing.expectEqual(@as(usize, 1), result.rejected_statements);
    try std.testing.expectEqual(@as(usize, 1), result.directives);
    try std.testing.expectEqual(@as(usize, 1), result.expected_errors);
    try std.testing.expectEqual(sql_policy.UnsupportedFeature.temporary_table, result.first_violation.?.feature);
}

test "analyzer handles procedure delimiters" {
    const text =
        \\delimiter |;
        \\create procedure p()
        \\begin
        \\  insert into t values (1);
        \\end|
        \\delimiter ;|
        \\call p();
    ;

    const result = try analyze(std.testing.allocator, text);
    try std.testing.expectEqual(@as(usize, 2), result.statements);
    try std.testing.expectEqual(@as(usize, 2), result.accepted_statements);
    try std.testing.expectEqual(@as(usize, 0), result.rejected_statements);
    try std.testing.expectEqual(@as(usize, 2), result.delimiter_changes);
}

test "analyzer strips query_vertical harness prefix before policy check" {
    const text =
        \\query_vertical select * from memories;
    ;

    const result = try analyze(std.testing.allocator, text);
    try std.testing.expectEqual(@as(usize, 1), result.statements);
    try std.testing.expectEqual(@as(usize, 1), result.harness_commands);
    try std.testing.expectEqual(@as(usize, 1), result.accepted_statements);
}
