const std = @import("std");
const shovelerdb = @import("shovelerdb");

const executor = shovelerdb.db.executor;

fn exec(db: *executor.Database, session: *executor.Session, sql: []const u8) !executor.ExecutionResult {
    return db.executeSql(session, sql);
}

fn execOk(allocator: std.mem.Allocator, db: *executor.Database, session: *executor.Session, sql: []const u8) !void {
    var result = try exec(db, session, sql);
    result.deinit(allocator);
}

fn createProcedureFixture(allocator: std.mem.Allocator) !struct {
    db: executor.Database,
    writer: executor.Session,
    reader: executor.Session,
} {
    var db = executor.Database.init(allocator);
    errdefer db.deinit();
    var writer = executor.Session.init(allocator);
    errdefer writer.deinit();
    var reader = executor.Session.init(allocator);
    errdefer reader.deinit();

    try execOk(allocator, &db, &writer, "CREATE TABLE memories (id INTEGER, body TEXT);");
    try execOk(allocator, &db, &writer,
        \\CREATE PROCEDURE remember(IN p_id INT, IN p_body TEXT)
        \\BEGIN
        \\  INSERT INTO memories (id, body) VALUES (p_id, p_body);
        \\END;
    );

    return .{ .db = db, .writer = writer, .reader = reader };
}

test "procedure writes share caller transaction commit and rollback semantics" {
    const allocator = std.testing.allocator;
    var fixture = try createProcedureFixture(allocator);
    defer fixture.reader.deinit();
    defer fixture.writer.deinit();
    defer fixture.db.deinit();

    try execOk(allocator, &fixture.db, &fixture.writer, "BEGIN;");
    var result = try exec(&fixture.db, &fixture.writer, "CALL remember(1, 'committed');");
    try std.testing.expectEqual(@as(usize, 1), result.mutation_count);
    result.deinit(allocator);

    result = try exec(&fixture.db, &fixture.writer, "SELECT id, body FROM memories ORDER BY id ASC;");
    try std.testing.expectEqual(@as(usize, 1), result.result_set.rows.len);
    try std.testing.expectEqual(@as(i64, 1), result.result_set.rows[0].values[0].integer);
    try std.testing.expectEqualStrings("committed", result.result_set.rows[0].values[1].text);
    result.deinit(allocator);

    result = try exec(&fixture.db, &fixture.reader, "SELECT id, body FROM memories ORDER BY id ASC;");
    try std.testing.expectEqual(@as(usize, 0), result.result_set.rows.len);
    result.deinit(allocator);

    try execOk(allocator, &fixture.db, &fixture.writer, "COMMIT;");

    result = try exec(&fixture.db, &fixture.reader, "SELECT id, body FROM memories ORDER BY id ASC;");
    try std.testing.expectEqual(@as(usize, 1), result.result_set.rows.len);
    try std.testing.expectEqual(@as(i64, 1), result.result_set.rows[0].values[0].integer);
    try std.testing.expectEqualStrings("committed", result.result_set.rows[0].values[1].text);
    result.deinit(allocator);

    try execOk(allocator, &fixture.db, &fixture.writer, "BEGIN;");
    result = try exec(&fixture.db, &fixture.writer, "CALL remember(2, 'rolled back');");
    try std.testing.expectEqual(@as(usize, 1), result.mutation_count);
    result.deinit(allocator);

    result = try exec(&fixture.db, &fixture.writer, "SELECT id, body FROM memories ORDER BY id ASC;");
    try std.testing.expectEqual(@as(usize, 2), result.result_set.rows.len);
    try std.testing.expectEqual(@as(i64, 2), result.result_set.rows[1].values[0].integer);
    try std.testing.expectEqualStrings("rolled back", result.result_set.rows[1].values[1].text);
    result.deinit(allocator);

    try execOk(allocator, &fixture.db, &fixture.writer, "ROLLBACK;");

    result = try exec(&fixture.db, &fixture.reader, "SELECT id, body FROM memories ORDER BY id ASC;");
    defer result.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), result.result_set.rows.len);
    try std.testing.expectEqual(@as(i64, 1), result.result_set.rows[0].values[0].integer);
    try std.testing.expectEqualStrings("committed", result.result_set.rows[0].values[1].text);
}

test "procedure call diagnostics cover missing procedures arguments and type mismatches" {
    const allocator = std.testing.allocator;
    var fixture = try createProcedureFixture(allocator);
    defer fixture.reader.deinit();
    defer fixture.writer.deinit();
    defer fixture.db.deinit();

    try std.testing.expectError(error.UnknownObject, exec(&fixture.db, &fixture.writer, "CALL missing_proc();"));
    try std.testing.expectEqual(executor.DiagnosticKind.unknown_object, executor.diagnosticFromError(error.UnknownObject).?);

    try std.testing.expectError(error.ColumnCountMismatch, exec(&fixture.db, &fixture.writer, "CALL remember(1);"));
    try std.testing.expectEqual(
        executor.DiagnosticKind.column_count_mismatch,
        executor.diagnosticFromError(error.ColumnCountMismatch).?,
    );

    try std.testing.expectError(error.TypeMismatch, exec(&fixture.db, &fixture.writer, "CALL remember('bad id', 'body');"));
    try std.testing.expectEqual(executor.DiagnosticKind.type_mismatch, executor.diagnosticFromError(error.TypeMismatch).?);
}
