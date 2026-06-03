const std = @import("std");
const shovelerdb = @import("shovelerdb");

const concurrency = shovelerdb.db.concurrency;
const executor = shovelerdb.db.executor;

const SnapshotHarness = struct {
    allocator: std.mem.Allocator,
    db: executor.Database,

    fn init(allocator: std.mem.Allocator) SnapshotHarness {
        return .{
            .allocator = allocator,
            .db = executor.Database.init(allocator),
        };
    }

    fn deinit(self: *SnapshotHarness) void {
        self.db.deinit();
        self.* = undefined;
    }

    fn exec(self: *SnapshotHarness, session: *executor.Session, sql: []const u8) !executor.ExecutionResult {
        return self.db.executeSql(session, sql);
    }

    fn execOk(self: *SnapshotHarness, session: *executor.Session, sql: []const u8) !void {
        var result = try self.exec(session, sql);
        result.deinit(self.allocator);
    }

    fn createMemoryTable(self: *SnapshotHarness, session: *executor.Session) !void {
        try self.execOk(session, "CREATE TABLE memories (id INTEGER, body TEXT);");
    }

    fn insertMemory(
        self: *SnapshotHarness,
        session: *executor.Session,
        id: i64,
        body: []const u8,
    ) !void {
        var statement = std.ArrayList(u8).empty;
        defer statement.deinit(self.allocator);

        try statement.print(
            self.allocator,
            "INSERT INTO memories VALUES ({d}, '{s}');",
            .{ id, body },
        );
        try self.execOk(session, statement.items);
    }

    fn selectMemories(self: *SnapshotHarness, session: *executor.Session) !executor.ExecutionResult {
        var result = try self.exec(session, "SELECT id, body FROM memories ORDER BY id ASC;");
        errdefer result.deinit(self.allocator);
        return result;
    }
};

test "reader generation handle retains committed rows only when a writer advances the generation" {
    const allocator = std.testing.allocator;

    var harness = SnapshotHarness.init(allocator);
    defer harness.deinit();

    var setup = executor.Session.init(allocator);
    defer setup.deinit();
    var reader = executor.Session.init(allocator);
    defer reader.deinit();
    var writer = executor.Session.init(allocator);
    defer writer.deinit();

    try harness.createMemoryTable(&setup);
    try harness.execOk(&setup, "BEGIN;");
    try harness.insertMemory(&setup, 1, "seed");
    try harness.execOk(&setup, "COMMIT;");

    const reader_generation: concurrency.SnapshotGeneration = harness.db.currentCommitSequence();
    try harness.execOk(&reader, "BEGIN;");
    try std.testing.expectEqual(reader_generation, reader.snapshot_sequence.?);
    try std.testing.expectEqual(@as(usize, 1), harness.db.activeSnapshotHandleCount(reader_generation));
    try std.testing.expectEqual(@as(usize, 0), harness.db.retainedSnapshotGenerationCount());
    try std.testing.expect(harness.db.retainedSnapshotRowCount(reader_generation, "memories") == null);

    try harness.execOk(&writer, "BEGIN;");
    try harness.insertMemory(&writer, 2, "writer");
    try harness.execOk(&writer, "COMMIT;");

    try std.testing.expectEqual(@as(concurrency.CommitSequence, 2), harness.db.currentCommitSequence());
    try std.testing.expectEqual(@as(usize, 1), harness.db.activeSnapshotHandleCount(reader_generation));
    try std.testing.expectEqual(@as(usize, 1), harness.db.retainedSnapshotGenerationCount());
    try std.testing.expectEqual(@as(usize, 1), harness.db.retainedSnapshotRowCount(reader_generation, "memories").?);

    var result = try harness.selectMemories(&reader);
    try std.testing.expectEqual(@as(usize, 1), result.result_set.rows.len);
    try std.testing.expectEqual(@as(i64, 1), result.result_set.rows[0].values[0].integer);
    try std.testing.expectEqualStrings("seed", result.result_set.rows[0].values[1].text);
    result.deinit(allocator);

    try harness.execOk(&reader, "COMMIT;");
    try std.testing.expectEqual(@as(usize, 0), harness.db.activeSnapshotHandleCount(reader_generation));
    try std.testing.expectEqual(@as(usize, 0), harness.db.retainedSnapshotGenerationCount());
}

test "local writes read over the captured generation instead of later committed rows" {
    const allocator = std.testing.allocator;

    var harness = SnapshotHarness.init(allocator);
    defer harness.deinit();

    var setup = executor.Session.init(allocator);
    defer setup.deinit();
    var reader_writer = executor.Session.init(allocator);
    defer reader_writer.deinit();
    var writer = executor.Session.init(allocator);
    defer writer.deinit();

    try harness.createMemoryTable(&setup);
    try harness.execOk(&setup, "BEGIN;");
    try harness.insertMemory(&setup, 1, "seed");
    try harness.execOk(&setup, "COMMIT;");

    try harness.execOk(&reader_writer, "BEGIN;");

    try harness.execOk(&writer, "BEGIN;");
    try harness.insertMemory(&writer, 2, "intervening");
    try harness.execOk(&writer, "COMMIT;");

    try harness.insertMemory(&reader_writer, 3, "local");

    var result = try harness.selectMemories(&reader_writer);
    defer result.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), result.result_set.rows.len);
    try std.testing.expectEqual(@as(i64, 1), result.result_set.rows[0].values[0].integer);
    try std.testing.expectEqualStrings("seed", result.result_set.rows[0].values[1].text);
    try std.testing.expectEqual(@as(i64, 3), result.result_set.rows[1].values[0].integer);
    try std.testing.expectEqualStrings("local", result.result_set.rows[1].values[1].text);
}

test "rollback and deinit release active generation handles" {
    const allocator = std.testing.allocator;

    var harness = SnapshotHarness.init(allocator);
    defer harness.deinit();

    var setup = executor.Session.init(allocator);
    defer setup.deinit();
    var reader = executor.Session.init(allocator);
    defer reader.deinit();

    try harness.createMemoryTable(&setup);
    try harness.execOk(&setup, "BEGIN;");
    try harness.insertMemory(&setup, 1, "seed");
    try harness.execOk(&setup, "COMMIT;");

    const generation = harness.db.currentCommitSequence();
    try harness.execOk(&reader, "BEGIN;");
    try std.testing.expectEqual(@as(usize, 1), harness.db.activeSnapshotHandleCount(generation));
    try harness.execOk(&reader, "ROLLBACK;");
    try std.testing.expectEqual(@as(usize, 0), harness.db.activeSnapshotHandleCount(generation));

    var deinit_reader = executor.Session.init(allocator);
    try harness.execOk(&deinit_reader, "BEGIN;");
    try std.testing.expectEqual(@as(usize, 1), harness.db.activeSnapshotHandleCount(generation));
    deinit_reader.deinit();
    try std.testing.expectEqual(@as(usize, 0), harness.db.activeSnapshotHandleCount(generation));
}
