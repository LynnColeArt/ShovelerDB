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

    var result = try exec(&db, &session, "CREATE TABLE memories (id INTEGER, body TEXT, embedding VECTOR(2));");
    result.deinit(allocator);
    result = try exec(&db, &session, "CREATE TABLE memory_tags (id INTEGER, memory_id INTEGER, name TEXT);");
    result.deinit(allocator);
    result = try exec(&db, &session, "BEGIN;");
    result.deinit(allocator);

    const statements = [_][]const u8{
        "INSERT INTO memories VALUES (1, 'project plan', [1, 0]);",
        "INSERT INTO memories VALUES (2, 'project note', [0.8, 0.2]);",
        "INSERT INTO memories VALUES (3, 'personal note', [0, 1]);",
        "INSERT INTO memory_tags VALUES (1, 1, 'project');",
        "INSERT INTO memory_tags VALUES (2, 2, 'project');",
        "INSERT INTO memory_tags VALUES (3, 3, 'personal');",
    };
    for (statements) |statement| {
        result = try exec(&db, &session, statement);
        result.deinit(allocator);
    }
    result = try exec(&db, &session, "COMMIT;");
    result.deinit(allocator);

    return .{ .db = db, .session = session };
}

test "CTE join query supports qualified identifiers aliases vector filtering and ordering" {
    const allocator = std.testing.allocator;
    var fixture = try createFixture(allocator);
    defer fixture.session.deinit();
    defer fixture.db.deinit();

    var result = try exec(&fixture.db, &fixture.session,
        \\WITH ranked AS (
        \\  SELECT m.id, m.body, l2_distance(m.embedding, [1, 0]) AS distance
        \\  FROM memories AS m
        \\  JOIN memory_tags AS t ON t.memory_id = m.id
        \\  WHERE t.name = 'project'
        \\)
        \\SELECT id, body
        \\FROM ranked
        \\WHERE distance < 0.3
        \\ORDER BY distance ASC
        \\LIMIT 10;
    );
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), result.result_set.rows.len);
    try std.testing.expectEqualStrings("id", result.result_set.columns[0]);
    try std.testing.expectEqualStrings("body", result.result_set.columns[1]);
    try std.testing.expectEqual(@as(i64, 1), result.result_set.rows[0].values[0].integer);
    try std.testing.expectEqualStrings("project plan", result.result_set.rows[0].values[1].text);
    try std.testing.expectEqual(@as(i64, 2), result.result_set.rows[1].values[0].integer);
}

test "derived table left join keeps unmatched left rows as nulls" {
    const allocator = std.testing.allocator;
    var fixture = try createFixture(allocator);
    defer fixture.session.deinit();
    defer fixture.db.deinit();

    var result = try exec(&fixture.db, &fixture.session,
        \\SELECT d.id, t.name
        \\FROM (SELECT id FROM memories WHERE id < 4) AS d
        \\LEFT JOIN memory_tags AS t ON t.memory_id = d.id AND t.name = 'missing'
        \\ORDER BY d.id ASC;
    );
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 3), result.result_set.rows.len);
    try std.testing.expectEqual(@as(i64, 1), result.result_set.rows[0].values[0].integer);
    try std.testing.expectEqual(@as(i64, 2), result.result_set.rows[1].values[0].integer);
    try std.testing.expectEqual(@as(i64, 3), result.result_set.rows[2].values[0].integer);
    try std.testing.expectEqual(shovelerdb.db.value.Value.null, result.result_set.rows[0].values[1]);
    try std.testing.expectEqual(shovelerdb.db.value.Value.null, result.result_set.rows[1].values[1]);
    try std.testing.expectEqual(shovelerdb.db.value.Value.null, result.result_set.rows[2].values[1]);
}

test "cross join produces deterministic cartesian rows" {
    const allocator = std.testing.allocator;
    var fixture = try createFixture(allocator);
    defer fixture.session.deinit();
    defer fixture.db.deinit();

    var result = try exec(
        &fixture.db,
        &fixture.session,
        "SELECT m.id, t.name FROM memories AS m CROSS JOIN memory_tags AS t ORDER BY m.id ASC, t.id ASC LIMIT 4;",
    );
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 4), result.result_set.rows.len);
    try std.testing.expectEqual(@as(i64, 1), result.result_set.rows[0].values[0].integer);
    try std.testing.expectEqualStrings("project", result.result_set.rows[0].values[1].text);
    try std.testing.expectEqual(@as(i64, 1), result.result_set.rows[1].values[0].integer);
    try std.testing.expectEqualStrings("project", result.result_set.rows[1].values[1].text);
    try std.testing.expectEqual(@as(i64, 1), result.result_set.rows[2].values[0].integer);
    try std.testing.expectEqualStrings("personal", result.result_set.rows[2].values[1].text);
    try std.testing.expectEqual(@as(i64, 2), result.result_set.rows[3].values[0].integer);
}

test "ambiguous unqualified columns produce a typed diagnostic" {
    const allocator = std.testing.allocator;
    var fixture = try createFixture(allocator);
    defer fixture.session.deinit();
    defer fixture.db.deinit();

    try std.testing.expectError(
        error.AmbiguousColumn,
        exec(
            &fixture.db,
            &fixture.session,
            "SELECT id FROM memories AS m JOIN memory_tags AS t ON t.memory_id = m.id;",
        ),
    );
    try std.testing.expectEqual(executor.DiagnosticKind.ambiguous_column, executor.diagnosticFromError(error.AmbiguousColumn).?);
}

test "views can wrap richer select sources" {
    const allocator = std.testing.allocator;
    var fixture = try createFixture(allocator);
    defer fixture.session.deinit();
    defer fixture.db.deinit();

    var result = try exec(&fixture.db, &fixture.session,
        \\CREATE VIEW project_memory_tags AS
        \\SELECT m.id AS memory_id, t.name AS tag
        \\FROM memories AS m
        \\JOIN memory_tags AS t ON t.memory_id = m.id
        \\WHERE t.name = 'project'
        \\ORDER BY m.id DESC;
    );
    result.deinit(allocator);

    result = try exec(
        &fixture.db,
        &fixture.session,
        "SELECT memory_id, tag FROM project_memory_tags ORDER BY memory_id ASC;",
    );
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), result.result_set.rows.len);
    try std.testing.expectEqualStrings("memory_id", result.result_set.columns[0]);
    try std.testing.expectEqualStrings("tag", result.result_set.columns[1]);
    try std.testing.expectEqual(@as(i64, 1), result.result_set.rows[0].values[0].integer);
    try std.testing.expectEqualStrings("project", result.result_set.rows[0].values[1].text);
    try std.testing.expectEqual(@as(i64, 2), result.result_set.rows[1].values[0].integer);
}
