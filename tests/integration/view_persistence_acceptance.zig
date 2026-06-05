const std = @import("std");
const shovelerdb = @import("shovelerdb");

const executor = shovelerdb.db.executor;
const persistence = shovelerdb.db.persistence;

fn exec(db: *executor.Database, session: *executor.Session, sql: []const u8) !executor.ExecutionResult {
    return db.executeSql(session, sql);
}

fn execOk(allocator: std.mem.Allocator, db: *executor.Database, session: *executor.Session, sql: []const u8) !void {
    var result = try exec(db, session, sql);
    result.deinit(allocator);
}

fn createDurableViewFixture(allocator: std.mem.Allocator) !struct {
    db: executor.Database,
    session: executor.Session,
} {
    var db = executor.Database.init(allocator);
    errdefer db.deinit();
    var session = executor.Session.init(allocator);
    errdefer session.deinit();

    try execOk(allocator, &db, &session, "CREATE TABLE memories (id INTEGER, body TEXT, embedding VECTOR(2));");
    try execOk(allocator, &db, &session, "CREATE TABLE memory_tags (id INTEGER, memory_id INTEGER, name TEXT);");
    try execOk(allocator, &db, &session, "BEGIN;");

    const statements = [_][]const u8{
        "INSERT INTO memories VALUES (1, 'project plan', [1, 0]);",
        "INSERT INTO memories VALUES (2, 'project note', [0.8, 0.2]);",
        "INSERT INTO memories VALUES (3, 'personal note', [0, 1]);",
        "INSERT INTO memory_tags VALUES (1, 1, 'project');",
        "INSERT INTO memory_tags VALUES (2, 2, 'project');",
        "INSERT INTO memory_tags VALUES (3, 3, 'personal');",
    };
    for (statements) |statement| {
        try execOk(allocator, &db, &session, statement);
    }

    try execOk(allocator, &db, &session, "COMMIT;");
    try execOk(allocator, &db, &session,
        \\CREATE VIEW project_memory AS
        \\SELECT m.id AS memory_id, m.body, l2_distance(m.embedding, [1, 0]) AS distance
        \\FROM memories AS m
        \\JOIN memory_tags AS t ON t.memory_id = m.id
        \\WHERE t.name = 'project'
        \\ORDER BY distance ASC
        \\LIMIT 10;
    );
    return .{ .db = db, .session = session };
}

test "rich views remain executable after snapshot reopen" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var fixture = try createDurableViewFixture(allocator);
    defer fixture.session.deinit();
    defer fixture.db.deinit();

    var snapshot = try fixture.db.exportSnapshot();
    defer snapshot.deinit();
    try std.testing.expectEqual(@as(usize, 1), snapshot.catalog.listViews().len);
    try std.testing.expect(std.mem.startsWith(u8, snapshot.catalog.listViews()[0].body, "SELECT m.id AS memory_id"));

    try persistence.writeSnapshot(allocator, io, tmp.dir, "views.shovel", &snapshot);

    var reopened_snapshot = try persistence.readSnapshot(allocator, io, tmp.dir, "views.shovel");
    defer reopened_snapshot.deinit();
    try std.testing.expectEqualStrings(snapshot.catalog.listViews()[0].body, reopened_snapshot.catalog.listViews()[0].body);

    var reopened = try executor.Database.initFromSnapshot(allocator, &reopened_snapshot);
    defer reopened.deinit();
    var reopened_session = executor.Session.init(allocator);
    defer reopened_session.deinit();

    var result = try exec(
        &reopened,
        &reopened_session,
        "SELECT v.memory_id, v.body FROM project_memory AS v WHERE v.distance < 0.3 ORDER BY v.memory_id ASC;",
    );
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), result.result_set.rows.len);
    try std.testing.expectEqualStrings("memory_id", result.result_set.columns[0]);
    try std.testing.expectEqualStrings("body", result.result_set.columns[1]);
    try std.testing.expectEqual(@as(i64, 1), result.result_set.rows[0].values[0].integer);
    try std.testing.expectEqualStrings("project plan", result.result_set.rows[0].values[1].text);
    try std.testing.expectEqual(@as(i64, 2), result.result_set.rows[1].values[0].integer);
    try std.testing.expectEqualStrings("project note", result.result_set.rows[1].values[1].text);
}
