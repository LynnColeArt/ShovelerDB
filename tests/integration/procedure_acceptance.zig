const std = @import("std");
const shovelerdb = @import("shovelerdb");

const executor = shovelerdb.db.executor;

fn exec(db: *executor.Database, session: *executor.Session, sql: []const u8) !executor.ExecutionResult {
    return db.executeSql(session, sql);
}

test "mysql-style stored procedure control flow executes in caller transaction" {
    const allocator = std.testing.allocator;

    var db = executor.Database.init(allocator);
    defer db.deinit();
    var writer = executor.Session.init(allocator);
    defer writer.deinit();
    var reader = executor.Session.init(allocator);
    defer reader.deinit();

    var result = try exec(&db, &writer, "CREATE TABLE memories (id INTEGER, body TEXT);");
    result.deinit(allocator);
    result = try exec(&db, &writer,
        \\CREATE PROCEDURE remember(IN p_id INT, IN p_body TEXT)
        \\BEGIN
        \\  DECLARE attempts INT DEFAULT 0;
        \\  IF p_id > 0 THEN
        \\    WHILE attempts < 1 DO
        \\      INSERT INTO memories (id, body) VALUES (p_id, p_body);
        \\      SET attempts = attempts + 1;
        \\    END WHILE;
        \\  END IF;
        \\END;
    );
    result.deinit(allocator);

    result = try exec(&db, &writer, "BEGIN;");
    result.deinit(allocator);
    result = try exec(&db, &writer, "CALL remember(1, 'from proc');");
    try std.testing.expectEqual(@as(usize, 1), result.mutation_count);
    result.deinit(allocator);

    result = try exec(&db, &writer, "SELECT id, body FROM memories;");
    try std.testing.expectEqual(@as(usize, 1), result.result_set.rows.len);
    try std.testing.expectEqual(@as(i64, 1), result.result_set.rows[0].values[0].integer);
    try std.testing.expectEqualStrings("from proc", result.result_set.rows[0].values[1].text);
    result.deinit(allocator);

    result = try exec(&db, &reader, "SELECT id, body FROM memories;");
    try std.testing.expectEqual(@as(usize, 0), result.result_set.rows.len);
    result.deinit(allocator);

    result = try exec(&db, &writer, "COMMIT;");
    result.deinit(allocator);

    result = try exec(&db, &reader, "SELECT id, body FROM memories;");
    defer result.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), result.result_set.rows.len);
    try std.testing.expectEqual(@as(i64, 1), result.result_set.rows[0].values[0].integer);
    try std.testing.expectEqualStrings("from proc", result.result_set.rows[0].values[1].text);
}

test "mysql-style stored procedure control flow rejects unsupported stored-program features" {
    const allocator = std.testing.allocator;

    var db = executor.Database.init(allocator);
    defer db.deinit();
    var session = executor.Session.init(allocator);
    defer session.deinit();

    var result = try exec(&db, &session, "CREATE TABLE memories (id INTEGER, body TEXT);");
    result.deinit(allocator);

    try std.testing.expectError(
        error.UnsupportedProcedure,
        exec(&db, &session, "CREATE PROCEDURE bad_cursor() BEGIN DECLARE cur CURSOR FOR SELECT * FROM memories; END;"),
    );
    try std.testing.expectError(
        error.UnsupportedProcedure,
        exec(&db, &session, "CREATE PROCEDURE bad_dynamic() BEGIN PREPARE stmt FROM 'SELECT 1'; END;"),
    );
}
