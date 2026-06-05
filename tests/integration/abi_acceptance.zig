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

fn execute(database: *abi.shovelerdb_database, sql: [*:0]const u8) !*abi.shovelerdb_result {
    var result: ?*abi.shovelerdb_result = null;
    try expectStatus(.ok, abi.shovelerdb_execute(database, sql, &result));
    return result orelse error.ExpectedResult;
}

fn expectStatus(expected: abi.shovelerdb_status, actual: abi.shovelerdb_status) !void {
    try std.testing.expectEqual(expected, actual);
}
