const std = @import("std");
const shovelerdb = @import("shovelerdb");

const executor = shovelerdb.db.executor;

fn exec(db: *executor.Database, session: *executor.Session, sql: []const u8) !executor.ExecutionResult {
    return db.executeSql(session, sql);
}

test "mysql-style ddl metadata executes through embedded sql" {
    const allocator = std.testing.allocator;

    var db = executor.Database.init(allocator);
    defer db.deinit();
    var session = executor.Session.init(allocator);
    defer session.deinit();

    var result = try exec(&db, &session,
        \\CREATE TABLE IF NOT EXISTS memories (
        \\  id INTEGER PRIMARY KEY AUTO_INCREMENT,
        \\  body TEXT NOT NULL DEFAULT 'seed',
        \\  tag TEXT NULL,
        \\  INDEX idx_tag (tag),
        \\  KEY idx_body (body)
        \\);
    );
    result.deinit(allocator);
    result = try exec(&db, &session,
        \\CREATE TABLE IF NOT EXISTS memories (
        \\  id INTEGER PRIMARY KEY AUTO_INCREMENT,
        \\  body TEXT NOT NULL DEFAULT 'seed',
        \\  tag TEXT NULL,
        \\  INDEX idx_tag (tag),
        \\  KEY idx_body (body)
        \\);
    );
    result.deinit(allocator);

    const table = db.db_catalog.getTable("MEMORIES").?;
    try std.testing.expect(table.column("id").?.primary_key);
    try std.testing.expect(table.column("id").?.auto_increment);
    try std.testing.expect(!table.column("body").?.nullable);
    try std.testing.expectEqualStrings("seed", table.column("body").?.default_value.?.text);
    try std.testing.expectEqual(@as(usize, 3), table.indexes.len);
    try std.testing.expectEqualStrings("PRIMARY", table.indexes[0].name);
    try std.testing.expectEqualStrings("idx_tag", table.indexes[1].name);
    try std.testing.expectEqualStrings("idx_body", table.indexes[2].name);

    result = try exec(&db, &session, "BEGIN;");
    result.deinit(allocator);
    result = try exec(&db, &session, "INSERT INTO memories (tag) VALUES ('project');");
    try std.testing.expectEqual(@as(usize, 1), result.mutation_count);
    result.deinit(allocator);
    result = try exec(&db, &session, "COMMIT;");
    result.deinit(allocator);

    result = try exec(&db, &session, "SELECT id, body, tag FROM memories;");
    try std.testing.expectEqual(@as(usize, 1), result.result_set.rows.len);
    try std.testing.expectEqual(@as(i64, 1), result.result_set.rows[0].values[0].integer);
    try std.testing.expectEqualStrings("seed", result.result_set.rows[0].values[1].text);
    try std.testing.expectEqualStrings("project", result.result_set.rows[0].values[2].text);
    result.deinit(allocator);

    try std.testing.expectError(
        error.ParseDiagnostic,
        exec(&db, &session, "CREATE TABLE rejected (id INTEGER) ENGINE=InnoDB;"),
    );

    result = try exec(&db, &session, "DROP TABLE IF EXISTS missing;");
    result.deinit(allocator);
    result = try exec(&db, &session, "DROP TABLE IF EXISTS memories;");
    result.deinit(allocator);
    try std.testing.expect(db.db_catalog.getTable("memories") == null);
}
