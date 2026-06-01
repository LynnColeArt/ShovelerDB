const std = @import("std");
const shovelerdb = @import("shovelerdb");

const executor = shovelerdb.db.executor;

fn exec(db: *executor.Database, session: *executor.Session, sql: []const u8) !executor.ExecutionResult {
    return db.executeSql(session, sql);
}

fn createFixture(allocator: std.mem.Allocator) !struct {
    db: executor.Database,
    session: executor.Session,
} {
    var db = executor.Database.init(allocator);
    errdefer db.deinit();
    var session = executor.Session.init(allocator);
    errdefer session.deinit();

    var result = try exec(&db, &session, "CREATE TABLE memory_scores (id INTEGER, tag TEXT, score FLOAT);");
    result.deinit(allocator);
    result = try exec(&db, &session, "BEGIN;");
    result.deinit(allocator);

    const statements = [_][]const u8{
        "INSERT INTO memory_scores VALUES (1, 'project', 0.4);",
        "INSERT INTO memory_scores VALUES (2, 'project', 0.8);",
        "INSERT INTO memory_scores VALUES (3, 'personal', 0.2);",
        "INSERT INTO memory_scores VALUES (4, 'idea', 1.0);",
        "INSERT INTO memory_scores VALUES (5, 'idea', 3.0);",
    };
    for (statements) |statement| {
        result = try exec(&db, &session, statement);
        result.deinit(allocator);
    }
    result = try exec(&db, &session, "COMMIT;");
    result.deinit(allocator);

    return .{ .db = db, .session = session };
}

test "group by having and aggregate aliases execute through SQL" {
    const allocator = std.testing.allocator;
    var fixture = try createFixture(allocator);
    defer fixture.session.deinit();
    defer fixture.db.deinit();

    var result = try exec(&fixture.db, &fixture.session,
        \\SELECT tag, COUNT(*) AS total, AVG(score) AS average_score
        \\FROM memory_scores
        \\GROUP BY tag
        \\HAVING total > 1
        \\ORDER BY average_score DESC;
    );
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), result.result_set.rows.len);
    try std.testing.expectEqualStrings("tag", result.result_set.columns[0]);
    try std.testing.expectEqualStrings("total", result.result_set.columns[1]);
    try std.testing.expectEqualStrings("average_score", result.result_set.columns[2]);
    try std.testing.expectEqualStrings("idea", result.result_set.rows[0].values[0].text);
    try std.testing.expectEqual(@as(i64, 2), result.result_set.rows[0].values[1].integer);
    try std.testing.expectEqual(@as(f64, 2.0), result.result_set.rows[0].values[2].float);
    try std.testing.expectEqualStrings("project", result.result_set.rows[1].values[0].text);
    try std.testing.expectEqual(@as(i64, 2), result.result_set.rows[1].values[1].integer);
    try std.testing.expectEqual(@as(f64, 0.6000000000000001), result.result_set.rows[1].values[2].float);
}

test "ungrouped aggregate functions summarize the filtered row set" {
    const allocator = std.testing.allocator;
    var fixture = try createFixture(allocator);
    defer fixture.session.deinit();
    defer fixture.db.deinit();

    var result = try exec(
        &fixture.db,
        &fixture.session,
        "SELECT COUNT(*), SUM(score), AVG(score), MIN(score), MAX(score) FROM memory_scores WHERE tag = 'idea';",
    );
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), result.result_set.rows.len);
    try std.testing.expectEqual(@as(i64, 2), result.result_set.rows[0].values[0].integer);
    try std.testing.expectEqual(@as(f64, 4.0), result.result_set.rows[0].values[1].float);
    try std.testing.expectEqual(@as(f64, 2.0), result.result_set.rows[0].values[2].float);
    try std.testing.expectEqual(@as(f64, 1.0), result.result_set.rows[0].values[3].float);
    try std.testing.expectEqual(@as(f64, 3.0), result.result_set.rows[0].values[4].float);
}

test "non grouped projection in aggregate query produces typed diagnostic" {
    const allocator = std.testing.allocator;
    var fixture = try createFixture(allocator);
    defer fixture.session.deinit();
    defer fixture.db.deinit();

    try std.testing.expectError(
        error.InvalidGrouping,
        exec(&fixture.db, &fixture.session, "SELECT id, COUNT(*) FROM memory_scores GROUP BY tag;"),
    );
    try std.testing.expectEqual(executor.DiagnosticKind.invalid_grouping, executor.diagnosticFromError(error.InvalidGrouping).?);
}
