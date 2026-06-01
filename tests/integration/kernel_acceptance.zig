const std = @import("std");
const shovelerdb = @import("shovelerdb");

const executor = shovelerdb.db.executor;
const persistent = shovelerdb.db.database;
const row_store = shovelerdb.db.row_store;
const value = shovelerdb.db.value;

test "embedded SQL kernel handles transactions views procedures and vector search" {
    const allocator = std.testing.allocator;

    var db = executor.Database.init(allocator);
    defer db.deinit();
    var session = executor.Session.init(allocator);
    defer session.deinit();

    var result = try db.executeSql(&session, "CREATE TABLE memories (id INTEGER, body TEXT, embedding VECTOR(2));");
    result.deinit(allocator);
    result = try db.executeSql(&session, "CREATE VIEW recent AS SELECT id, body FROM memories ORDER BY id DESC LIMIT 1;");
    result.deinit(allocator);
    result = try db.executeSql(&session, "CREATE PROCEDURE remember() BEGIN INSERT INTO memories VALUES (2, 'from proc', [0, 1]); END;");
    result.deinit(allocator);

    result = try db.executeSql(&session, "BEGIN;");
    result.deinit(allocator);
    result = try db.executeSql(&session, "INSERT INTO memories VALUES (1, 'draft', [1, 0]);");
    try std.testing.expectEqual(@as(usize, 1), result.mutation_count);
    result.deinit(allocator);
    result = try db.executeSql(&session, "SELECT * FROM memories;");
    try std.testing.expectEqual(@as(usize, 1), result.result_set.rows.len);
    result.deinit(allocator);
    result = try db.executeSql(&session, "ROLLBACK;");
    result.deinit(allocator);
    result = try db.executeSql(&session, "SELECT * FROM memories;");
    try std.testing.expectEqual(@as(usize, 0), result.result_set.rows.len);
    result.deinit(allocator);

    result = try db.executeSql(&session, "BEGIN;");
    result.deinit(allocator);
    result = try db.executeSql(&session, "INSERT INTO memories VALUES (1, 'committed', [1, 0]);");
    try std.testing.expectEqual(@as(usize, 1), result.mutation_count);
    result.deinit(allocator);
    result = try db.executeSql(&session, "CALL remember();");
    try std.testing.expectEqual(@as(usize, 1), result.mutation_count);
    result.deinit(allocator);
    result = try db.executeSql(&session, "COMMIT;");
    result.deinit(allocator);

    result = try db.executeSql(&session, "SELECT * FROM recent;");
    try std.testing.expectEqual(@as(usize, 1), result.result_set.rows.len);
    try std.testing.expectEqual(@as(i64, 2), result.result_set.rows[0].values[0].integer);
    try std.testing.expectEqualStrings("from proc", result.result_set.rows[0].values[1].text);
    result.deinit(allocator);

    result = try db.executeSql(
        &session,
        "SELECT id, l2_distance(embedding, [1, 0]) FROM memories ORDER BY l2_distance(embedding, [1, 0]) ASC LIMIT 1;",
    );
    defer result.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), result.result_set.rows.len);
    try std.testing.expectEqualStrings("l2_distance", result.result_set.columns[1]);
    try std.testing.expectEqual(@as(i64, 1), result.result_set.rows[0].values[0].integer);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), result.result_set.rows[0].values[1].float, 0.000001);
}

test "embedded persistence API reopens committed table rows" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    var db = try persistent.Database.openOrCreate(allocator, io, tmp.dir, "agent-memory.shovel");
    defer db.deinit();
    try db.createTable(.{
        .name = "memories",
        .columns = &.{
            .{ .name = "id", .column_type = .integer, .nullable = false },
            .{ .name = "body", .column_type = .text, .nullable = false },
            .{ .name = "embedding", .column_type = .{ .vector = .{ .dimension = 2 } }, .nullable = false },
        },
    });

    var tx = try db.beginTransaction("memories");
    defer tx.deinit();
    var body = try value.Value.initText(allocator, "durable");
    defer body.deinit(allocator);
    var embedding = try value.Value.initVector(allocator, .float32, 2, &.{ 0.25, 0.75 });
    defer embedding.deinit(allocator);

    const row_id = try tx.insert(&.{ .{ .integer = 1 }, body, embedding });
    try tx.commit();
    try std.testing.expectEqual(@as(row_store.RowId, 1), row_id);
    try db.close();

    var reopened = try persistent.Database.open(allocator, io, tmp.dir, "agent-memory.shovel");
    defer reopened.deinit();
    const table = (try reopened.table("memories")).?;
    try std.testing.expectEqual(@as(usize, 3), table.columns.len);

    const rows = try reopened.rows("memories");
    try std.testing.expectEqual(@as(usize, 1), rows.len);
    try std.testing.expectEqual(@as(row_store.RowId, 1), rows[0].id);
    try std.testing.expectEqualStrings("durable", rows[0].values[1].text);
    try std.testing.expectEqualSlices(f32, &.{ 0.25, 0.75 }, rows[0].values[2].vector.values);
}
