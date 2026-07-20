const std = @import("std");
const shovelerdb = @import("shovelerdb");

const abi = shovelerdb.abi.c_api;

test "C ABI connector lifecycle covers persistence iteration vectors and diagnostics" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const path_bytes = try std.fmt.allocPrint(
        allocator,
        ".zig-cache/tmp/{s}/abi-acceptance.shovel",
        .{tmp.sub_path},
    );
    defer allocator.free(path_bytes);
    const path = try allocator.dupeZ(u8, path_bytes);
    defer allocator.free(path);

    var database: ?*abi.shovelerdb_database = null;
    try expectStatus(.ok, abi.shovelerdb_open_or_create(path.ptr, &database));
    defer abi.shovelerdb_close(database);
    const db = database orelse return error.ExpectedDatabase;

    var result = try execute(db, "CREATE TABLE memories (id INTEGER, body TEXT, embedding VECTOR(2));");
    abi.shovelerdb_result_release(result);
    result = try execute(db, "BEGIN;");
    abi.shovelerdb_result_release(result);
    result = try execute(db, "INSERT INTO memories VALUES (1, 'origin', [1, 0]);");
    try std.testing.expectEqual(@as(u64, 1), abi.shovelerdb_result_mutation_count(result));
    abi.shovelerdb_result_release(result);
    result = try execute(db, "INSERT INTO memories VALUES (2, 'side', [0, 1]);");
    try std.testing.expectEqual(@as(u64, 1), abi.shovelerdb_result_mutation_count(result));
    abi.shovelerdb_result_release(result);
    result = try execute(db, "COMMIT;");
    abi.shovelerdb_result_release(result);

    result = try execute(
        db,
        "SELECT id, body, l2_distance(embedding, [1, 0]) FROM memories ORDER BY l2_distance(embedding, [1, 0]) ASC LIMIT 2;",
    );
    try std.testing.expectEqual(abi.shovelerdb_result_kind.rows, abi.shovelerdb_result_kind_of(result));
    try std.testing.expectEqual(@as(usize, 2), abi.shovelerdb_result_row_count(result));

    var row: ?*const abi.shovelerdb_row = null;
    try expectStatus(.ok, abi.shovelerdb_result_next(result, &row));
    const first_row = row orelse return error.ExpectedRow;
    var id: i64 = 0;
    try expectStatus(.ok, abi.shovelerdb_row_value_int64(first_row, 0, &id));
    try std.testing.expectEqual(@as(i64, 1), id);
    var body = abi.shovelerdb_string_view{ .data = null, .len = 0 };
    try expectStatus(.ok, abi.shovelerdb_row_value_text(first_row, 1, &body));
    try std.testing.expectEqualStrings("origin", body.data.?[0..body.len]);
    var distance: f64 = -1;
    try expectStatus(.ok, abi.shovelerdb_row_value_float64(first_row, 2, &distance));
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), distance, 0.000001);
    try expectStatus(.type_error, abi.shovelerdb_row_value_int64(first_row, 1, &id));

    try expectStatus(.ok, abi.shovelerdb_result_next(result, &row));
    const second_row = row orelse return error.ExpectedRow;
    try expectStatus(.ok, abi.shovelerdb_row_value_int64(second_row, 0, &id));
    try std.testing.expectEqual(@as(i64, 2), id);
    try expectStatus(.ok, abi.shovelerdb_result_next(result, &row));
    try std.testing.expect(row == null);

    abi.shovelerdb_result_release(result);
    result = try execute(db, "SELECT embedding FROM memories WHERE id = 1;");
    try expectStatus(.ok, abi.shovelerdb_result_next(result, &row));
    const vector_row = row orelse return error.ExpectedRow;
    var vector = abi.shovelerdb_f32_vector_view{ .data = null, .len = 0 };
    try expectStatus(.ok, abi.shovelerdb_row_value_vector_f32(vector_row, 0, &vector));
    try std.testing.expectEqualSlices(f32, &.{ 1.0, 0.0 }, vector.data.?[0..vector.len]);

    abi.shovelerdb_result_release(result);
    var failed_result: ?*abi.shovelerdb_result = null;
    try expectStatus(
        .vector_error,
        abi.shovelerdb_execute(db, "SELECT l2_distance(embedding, [1, 0, 0]) FROM memories;", &failed_result),
    );
    try std.testing.expect(failed_result == null);
    var diagnostic_code = abi.shovelerdb_diagnostic_code.none;
    var diagnostic_message = abi.shovelerdb_string_view{ .data = null, .len = 0 };
    try expectStatus(.ok, abi.shovelerdb_database_last_diagnostic(db, &diagnostic_code, &diagnostic_message));
    try std.testing.expectEqual(abi.shovelerdb_diagnostic_code.vector, diagnostic_code);
    try std.testing.expectEqualStrings("vector error", diagnostic_message.data.?[0..diagnostic_message.len]);

    try expectStatus(.invalid_handle, abi.shovelerdb_checkpoint(null));
    try expectStatus(.ok, abi.shovelerdb_checkpoint(db));
    abi.shovelerdb_close(database);
    database = null;

    try expectStatus(.ok, abi.shovelerdb_open_or_create(path.ptr, &database));
    const reopened = database orelse return error.ExpectedDatabase;
    result = try execute(reopened, "SELECT id FROM memories ORDER BY id ASC;");
    try std.testing.expectEqual(@as(usize, 2), abi.shovelerdb_result_row_count(result));
    try expectStatus(.ok, abi.shovelerdb_result_next(result, &row));
    const reopened_row = row orelse return error.ExpectedRow;
    try expectStatus(.ok, abi.shovelerdb_row_value_int64(reopened_row, 0, &id));
    try std.testing.expectEqual(@as(i64, 1), id);
    abi.shovelerdb_result_release(result);

    abi.shovelerdb_result_release(null);
}

test "C ABI single-quoted literals are byte-exact and cannot widen statement scope" {
    const allocator = std.testing.allocator;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const path_bytes = try std.fmt.allocPrint(
        allocator,
        ".zig-cache/tmp/{s}/abi-literal-acceptance.shovel",
        .{tmp.sub_path},
    );
    defer allocator.free(path_bytes);
    const path = try allocator.dupeZ(u8, path_bytes);
    defer allocator.free(path);

    var database: ?*abi.shovelerdb_database = null;
    defer abi.shovelerdb_close(database);
    try expectStatus(.ok, abi.shovelerdb_open_or_create(path.ptr, &database));
    var db = database orelse return error.ExpectedDatabase;

    var result = try execute(db, "CREATE TABLE literal_cases (id INTEGER, body TEXT);");
    abi.shovelerdb_result_release(result);
    result = try execute(db, "BEGIN;");
    abi.shovelerdb_result_release(result);

    const valid_cases = [_]struct {
        sql: [*:0]const u8,
        expected: ExpectedTextRow,
    }{
        .{ .sql = "INSERT INTO literal_cases VALUES (1, 'O''Reilly');", .expected = .{ .id = 1, .body = "O'Reilly" } },
        .{ .sql = "INSERT INTO literal_cases VALUES (2, 'a\\b');", .expected = .{ .id = 2, .body = "a\\b" } },
        .{ .sql = "INSERT INTO literal_cases VALUES (3, 'tail\\');", .expected = .{ .id = 3, .body = "tail\\" } },
        .{ .sql = "INSERT INTO literal_cases VALUES (4, '\\'' OR 1=1 --');", .expected = .{ .id = 4, .body = "\\' OR 1=1 --" } },
        .{ .sql = "INSERT INTO literal_cases VALUES (5, '--x;/*y*/#z');", .expected = .{ .id = 5, .body = "--x;/*y*/#z" } },
        .{ .sql = "INSERT INTO literal_cases VALUES (6, 'naïve 猫');", .expected = .{ .id = 6, .body = "naïve 猫" } },
        .{ .sql = "INSERT INTO literal_cases VALUES (7, 'line1\nline2');", .expected = .{ .id = 7, .body = "line1\nline2" } },
    };

    var expected_rows: [valid_cases.len]ExpectedTextRow = undefined;
    for (valid_cases, 0..) |case, index| {
        result = try execute(db, case.sql);
        try std.testing.expectEqual(@as(u64, 1), abi.shovelerdb_result_mutation_count(result));
        abi.shovelerdb_result_release(result);
        expected_rows[index] = case.expected;
    }
    result = try execute(db, "COMMIT;");
    abi.shovelerdb_result_release(result);
    try expectTextRows(db, &expected_rows);

    const raw_boundary_sql: [*:0]const u8 = "INSERT INTO literal_cases VALUES (100, '\\' OR 1=1 --";
    try std.testing.expect(std.mem.indexOf(u8, std.mem.span(raw_boundary_sql), &.{ 0x27, 0x5c, 0x27, 0x20, 0x4f, 0x52 }) != null);
    try expectParseFailure(db, raw_boundary_sql);

    const unterminated_scope_sql: [*:0]const u8 = "INSERT INTO literal_cases VALUES (101, 'unterminated; DELETE FROM literal_cases;";
    try expectParseFailure(db, unterminated_scope_sql);
    try expectTextRows(db, &expected_rows);

    try expectStatus(.ok, abi.shovelerdb_checkpoint(db));
    abi.shovelerdb_close(database);
    database = null;

    try expectStatus(.ok, abi.shovelerdb_open_or_create(path.ptr, &database));
    db = database orelse return error.ExpectedDatabase;
    try expectTextRows(db, &expected_rows);
}

const ExpectedTextRow = struct {
    id: i64,
    body: []const u8,
};

fn expectTextRows(database: *abi.shovelerdb_database, expected: []const ExpectedTextRow) !void {
    const result = try execute(database, "SELECT id, body FROM literal_cases ORDER BY id ASC;");
    defer abi.shovelerdb_result_release(result);

    try std.testing.expectEqual(abi.shovelerdb_result_kind.rows, abi.shovelerdb_result_kind_of(result));
    try std.testing.expectEqual(expected.len, abi.shovelerdb_result_row_count(result));
    for (expected) |expected_row| {
        var row: ?*const abi.shovelerdb_row = null;
        try expectStatus(.ok, abi.shovelerdb_result_next(result, &row));
        const actual_row = row orelse return error.ExpectedRow;

        var id: i64 = 0;
        try expectStatus(.ok, abi.shovelerdb_row_value_int64(actual_row, 0, &id));
        try std.testing.expectEqual(expected_row.id, id);

        var body = abi.shovelerdb_string_view{ .data = null, .len = 0 };
        try expectStatus(.ok, abi.shovelerdb_row_value_text(actual_row, 1, &body));
        try std.testing.expectEqualSlices(u8, expected_row.body, body.data.?[0..body.len]);
    }

    var exhausted: ?*const abi.shovelerdb_row = undefined;
    try expectStatus(.ok, abi.shovelerdb_result_next(result, &exhausted));
    try std.testing.expect(exhausted == null);
}

fn expectParseFailure(database: *abi.shovelerdb_database, sql: [*:0]const u8) !void {
    var result: ?*abi.shovelerdb_result = null;
    try expectStatus(.parse_error, abi.shovelerdb_execute(database, sql, &result));
    try std.testing.expect(result == null);
    try std.testing.expectEqual(@as(u64, 0), abi.shovelerdb_result_mutation_count(result));

    var diagnostic_code = abi.shovelerdb_diagnostic_code.none;
    var diagnostic_message = abi.shovelerdb_string_view{ .data = null, .len = 0 };
    try expectStatus(.ok, abi.shovelerdb_database_last_diagnostic(database, &diagnostic_code, &diagnostic_message));
    try std.testing.expectEqual(abi.shovelerdb_diagnostic_code.parser, diagnostic_code);
    try std.testing.expectEqualStrings("SQL parse error", diagnostic_message.data.?[0..diagnostic_message.len]);
}

fn execute(database: *abi.shovelerdb_database, sql: [*:0]const u8) !*abi.shovelerdb_result {
    var result: ?*abi.shovelerdb_result = null;
    try expectStatus(.ok, abi.shovelerdb_execute(database, sql, &result));
    return result orelse error.ExpectedResult;
}

fn expectStatus(expected: abi.shovelerdb_status, actual: abi.shovelerdb_status) !void {
    try std.testing.expectEqual(expected, actual);
}
