const std = @import("std");
const shovelerdb = @import("shovelerdb");

const concurrency = shovelerdb.db.concurrency;
const executor = shovelerdb.db.executor;
const vector_overlay = shovelerdb.vector.overlay;

const OverlayHarness = struct {
    allocator: std.mem.Allocator,
    db: executor.Database,

    fn init(allocator: std.mem.Allocator) OverlayHarness {
        return .{
            .allocator = allocator,
            .db = executor.Database.init(allocator),
        };
    }

    fn deinit(self: *OverlayHarness) void {
        self.db.deinit();
        self.* = undefined;
    }

    fn exec(self: *OverlayHarness, session: *executor.Session, sql: []const u8) !executor.ExecutionResult {
        return self.db.executeSql(session, sql);
    }

    fn execOk(self: *OverlayHarness, session: *executor.Session, sql: []const u8) !void {
        var result = try self.exec(session, sql);
        result.deinit(self.allocator);
    }

    fn createMemoryTable(self: *OverlayHarness, session: *executor.Session) !void {
        try self.execOk(session, "CREATE TABLE memories (id INTEGER, body TEXT, embedding VECTOR(2));");
    }

    fn insertMemory(
        self: *OverlayHarness,
        session: *executor.Session,
        id: i64,
        body: []const u8,
        vector_literal: []const u8,
    ) !void {
        var statement = std.ArrayList(u8).empty;
        defer statement.deinit(self.allocator);

        try statement.print(
            self.allocator,
            "INSERT INTO memories VALUES ({d}, '{s}', {s});",
            .{ id, body, vector_literal },
        );
        try self.execOk(session, statement.items);
    }

    fn selectIds(self: *OverlayHarness, session: *executor.Session) !executor.ExecutionResult {
        var result = try self.exec(session, "SELECT id, body FROM memories ORDER BY id ASC;");
        errdefer result.deinit(self.allocator);
        return result;
    }

    fn nearestBySql(self: *OverlayHarness, session: *executor.Session) !executor.ExecutionResult {
        var result = try self.exec(
            session,
            "SELECT id, l2_distance(embedding, [0, 1]) AS distance FROM memories ORDER BY distance ASC LIMIT 1;",
        );
        errdefer result.deinit(self.allocator);
        return result;
    }
};

test "checkpoint coordination blocks overlap without mutating active reader snapshots" {
    const allocator = std.testing.allocator;

    var harness = OverlayHarness.init(allocator);
    defer harness.deinit();

    var setup = executor.Session.init(allocator);
    defer setup.deinit();
    var reader = executor.Session.init(allocator);
    defer reader.deinit();
    var writer = executor.Session.init(allocator);
    defer writer.deinit();

    try harness.createMemoryTable(&setup);
    try harness.execOk(&setup, "BEGIN;");
    try harness.insertMemory(&setup, 1, "seed", "[1, 0]");
    try harness.execOk(&setup, "COMMIT;");

    try harness.execOk(&reader, "BEGIN;");
    var checkpoint = try harness.db.beginCheckpoint();
    try std.testing.expect(harness.db.checkpointSnapshot().in_progress);
    try std.testing.expectEqual(@as(concurrency.SnapshotGeneration, 1), harness.db.checkpointSnapshot().active_generation.?);
    try std.testing.expectError(error.CheckpointAlreadyRunning, harness.db.beginCheckpoint());

    try harness.execOk(&writer, "BEGIN;");
    try harness.insertMemory(&writer, 2, "writer", "[0, 1]");
    try harness.execOk(&writer, "COMMIT;");

    var reader_rows = try harness.selectIds(&reader);
    try std.testing.expectEqual(@as(usize, 1), reader_rows.result_set.rows.len);
    try std.testing.expectEqual(@as(i64, 1), reader_rows.result_set.rows[0].values[0].integer);
    reader_rows.deinit(allocator);

    checkpoint.complete();
    try std.testing.expect(!harness.db.checkpointSnapshot().in_progress);
    try std.testing.expectEqual(@as(concurrency.SnapshotGeneration, 1), harness.db.checkpointSnapshot().last_completed_generation);
}

test "failed checkpoint coordination leaves committed in-memory state intact" {
    const allocator = std.testing.allocator;

    var harness = OverlayHarness.init(allocator);
    defer harness.deinit();

    var setup = executor.Session.init(allocator);
    defer setup.deinit();
    var observer = executor.Session.init(allocator);
    defer observer.deinit();

    try harness.createMemoryTable(&setup);
    try harness.execOk(&setup, "BEGIN;");
    try harness.insertMemory(&setup, 1, "seed", "[1, 0]");
    try harness.execOk(&setup, "COMMIT;");

    var checkpoint = try harness.db.beginCheckpoint();
    checkpoint.fail();
    try std.testing.expect(!harness.db.checkpointSnapshot().in_progress);
    try std.testing.expectEqual(@as(concurrency.SnapshotGeneration, 0), harness.db.checkpointSnapshot().last_completed_generation);

    var rows = try harness.selectIds(&observer);
    defer rows.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 1), rows.result_set.rows.len);
    try std.testing.expectEqual(@as(i64, 1), rows.result_set.rows[0].values[0].integer);
}

test "committed vector writes are visible to exact SQL scans and overlay drain hooks" {
    const allocator = std.testing.allocator;

    var harness = OverlayHarness.init(allocator);
    defer harness.deinit();

    var setup = executor.Session.init(allocator);
    defer setup.deinit();
    var writer = executor.Session.init(allocator);
    defer writer.deinit();
    var observer = executor.Session.init(allocator);
    defer observer.deinit();

    try harness.createMemoryTable(&setup);

    try harness.execOk(&writer, "BEGIN;");
    try harness.insertMemory(&writer, 1, "far", "[1, 0]");
    try harness.execOk(&writer, "COMMIT;");
    try std.testing.expectEqual(@as(usize, 1), harness.db.vectorOverlayCandidateCount("memories", "embedding"));

    try harness.execOk(&writer, "BEGIN;");
    try harness.insertMemory(&writer, 2, "near", "[0, 1]");
    try harness.execOk(&writer, "COMMIT;");
    try std.testing.expectEqual(@as(usize, 2), harness.db.vectorOverlayDeltaCount());
    try std.testing.expectEqual(@as(usize, 2), harness.db.vectorOverlayCandidateCount("MEMORIES", "EMBEDDING"));

    var nearest = try harness.nearestBySql(&observer);
    try std.testing.expectEqual(@as(usize, 1), nearest.result_set.rows.len);
    try std.testing.expectEqual(@as(i64, 2), nearest.result_set.rows[0].values[0].integer);
    nearest.deinit(allocator);

    const drained = try harness.db.drainVectorOverlay(allocator, harness.db.currentCommitSequence(), 10);
    defer vector_overlay.Overlay.deinitDrained(allocator, drained);
    try std.testing.expectEqual(@as(usize, 2), drained.len);
    try std.testing.expectEqual(@as(usize, 0), harness.db.vectorOverlayDeltaCount());
}
