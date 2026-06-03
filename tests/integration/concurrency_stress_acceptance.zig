const std = @import("std");
const shovelerdb = @import("shovelerdb");

const backpressure = shovelerdb.db.backpressure;
const commit_queue = shovelerdb.db.commit_queue;
const concurrency = shovelerdb.db.concurrency;
const executor = shovelerdb.db.executor;
const vector_overlay = shovelerdb.vector.overlay;

const StressHarness = struct {
    allocator: std.mem.Allocator,
    db: executor.Database,

    fn init(allocator: std.mem.Allocator) StressHarness {
        return .{
            .allocator = allocator,
            .db = executor.Database.init(allocator),
        };
    }

    fn deinit(self: *StressHarness) void {
        self.db.deinit();
        self.* = undefined;
    }

    fn exec(self: *StressHarness, session: *executor.Session, sql: []const u8) !executor.ExecutionResult {
        return self.db.executeSql(session, sql);
    }

    fn execOk(self: *StressHarness, session: *executor.Session, sql: []const u8) !void {
        var result = try self.exec(session, sql);
        result.deinit(self.allocator);
    }

    fn createMemoryTable(self: *StressHarness, session: *executor.Session) !void {
        try self.execOk(session, "CREATE TABLE memories (id INTEGER, body TEXT, embedding VECTOR(2));");
    }

    fn insertMemory(
        self: *StressHarness,
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

    fn selectIds(self: *StressHarness, session: *executor.Session) !executor.ExecutionResult {
        var result = try self.exec(session, "SELECT id, body FROM memories ORDER BY id ASC;");
        errdefer result.deinit(self.allocator);
        return result;
    }

    fn nearestId(self: *StressHarness, session: *executor.Session) !i64 {
        var result = try self.exec(
            session,
            "SELECT id, l2_distance(embedding, [0, 1]) AS distance FROM memories ORDER BY distance ASC LIMIT 1;",
        );
        defer result.deinit(self.allocator);

        try std.testing.expectEqual(@as(usize, 1), result.result_set.rows.len);
        return result.result_set.rows[0].values[0].integer;
    }

    fn expectVisibleSeedOnly(self: *StressHarness, session: *executor.Session) !void {
        var rows = try self.selectIds(session);
        defer rows.deinit(self.allocator);

        try std.testing.expectEqual(@as(usize, 1), rows.result_set.rows.len);
        try std.testing.expectEqual(@as(i64, 1), rows.result_set.rows[0].values[0].integer);
        try std.testing.expectEqualStrings("seed", rows.result_set.rows[0].values[1].text);
    }
};

test "stress interleaved readers writers checkpoint overlap and vector overlay visibility" {
    const allocator = std.testing.allocator;
    const reader_count = 12;
    const writer_commits = 32;
    const expected_committed_rows = writer_commits + 1;

    var harness = StressHarness.init(allocator);
    defer harness.deinit();

    var setup = executor.Session.init(allocator);
    defer setup.deinit();
    var writer = executor.Session.init(allocator);
    defer writer.deinit();
    var observer = executor.Session.init(allocator);
    defer observer.deinit();

    var readers: [reader_count]executor.Session = undefined;
    for (&readers) |*reader| {
        reader.* = executor.Session.init(allocator);
    }
    defer {
        for (&readers) |*reader| reader.deinit();
    }

    try harness.createMemoryTable(&setup);
    try harness.execOk(&setup, "BEGIN;");
    try harness.insertMemory(&setup, 1, "seed", "[1, 0]");
    try harness.execOk(&setup, "COMMIT;");

    const seed_generation = harness.db.currentCommitSequence();
    for (&readers) |*reader| {
        try harness.execOk(reader, "BEGIN;");
        try std.testing.expectEqual(seed_generation, reader.snapshot_sequence.?);
        try harness.expectVisibleSeedOnly(reader);
    }
    try std.testing.expectEqual(@as(usize, reader_count), harness.db.activeSnapshotHandleCount(seed_generation));

    var checkpoint = try harness.db.beginCheckpoint();
    try std.testing.expectEqual(seed_generation, harness.db.checkpointSnapshot().active_generation.?);
    try std.testing.expectError(error.CheckpointAlreadyRunning, harness.db.beginCheckpoint());

    var rollback_attempts: usize = 0;
    for (0..writer_commits) |index| {
        try harness.execOk(&writer, "BEGIN;");
        const vector = if (index % 2 == 0) "[0, 1]" else "[1, 1]";
        try harness.insertMemory(&writer, @intCast(100 + index), "writer", vector);
        try harness.execOk(&writer, "COMMIT;");

        if (index % 5 == 0) {
            const before_rollback = harness.db.currentCommitSequence();
            try harness.execOk(&writer, "BEGIN;");
            try harness.insertMemory(&writer, @intCast(10_000 + index), "rolled_back", "[1, 0]");
            try harness.execOk(&writer, "ROLLBACK;");
            try std.testing.expectEqual(before_rollback, harness.db.currentCommitSequence());
            rollback_attempts += 1;
        }

        try harness.expectVisibleSeedOnly(&readers[index % reader_count]);
    }

    try std.testing.expect(rollback_attempts > 0);
    try std.testing.expectEqual(@as(usize, reader_count), harness.db.activeSnapshotHandleCount(seed_generation));
    try std.testing.expectEqual(@as(usize, 1), harness.db.retainedSnapshotGenerationCount());

    checkpoint.complete();
    try std.testing.expect(!harness.db.checkpointSnapshot().in_progress);
    try std.testing.expectEqual(seed_generation, harness.db.checkpointSnapshot().last_completed_generation);

    for (&readers) |*reader| {
        try harness.expectVisibleSeedOnly(reader);
    }

    var observer_rows = try harness.selectIds(&observer);
    defer observer_rows.deinit(allocator);
    try std.testing.expectEqual(@as(usize, expected_committed_rows), observer_rows.result_set.rows.len);
    try std.testing.expectEqual(@as(i64, 100), try harness.nearestId(&observer));
    try std.testing.expectEqual(@as(usize, expected_committed_rows), harness.db.vectorOverlayDeltaCount());

    const drained = try harness.db.drainVectorOverlay(allocator, harness.db.currentCommitSequence(), 8);
    defer vector_overlay.Overlay.deinitDrained(allocator, drained);
    try std.testing.expectEqual(@as(usize, 8), drained.len);
    try std.testing.expectEqual(@as(usize, expected_committed_rows - drained.len), harness.db.vectorOverlayDeltaCount());

    for (&readers) |*reader| {
        try harness.execOk(reader, "COMMIT;");
    }
    try std.testing.expectEqual(@as(usize, 0), harness.db.activeSnapshotHandleCount(seed_generation));
    try std.testing.expectEqual(@as(usize, 0), harness.db.retainedSnapshotGenerationCount());
}

test "stress backpressure diagnostics preserve queued state after saturation" {
    var queue = commit_queue.Queue.init(.{
        .max_pending_writes = 2,
        .snapshot_retention_generations = 8,
        .checkpoint_generation_budget = 2,
        .vector_overlay_drain_budget = 4,
    });

    try queue.enqueue();
    try queue.enqueue();
    try std.testing.expectError(error.CommitQueueFull, queue.enqueue());

    const diagnostic = backpressure.diagnosticForCommitQueue(queue.snapshot()).?;
    try std.testing.expectEqual(concurrency.DiagnosticKind.commit_queue_full, diagnostic.kind());
    try std.testing.expectEqual(error.CommitQueueFull, diagnostic.toError());
    try std.testing.expectEqual(@as(concurrency.QueueDepth, 2), queue.snapshot().queued_writes);

    queue.abortQueuedCommit();
    queue.abortQueuedCommit();
    try std.testing.expectEqual(@as(concurrency.QueueDepth, 0), queue.snapshot().queued_writes);

    try queue.enqueue();
    try std.testing.expectEqual(@as(concurrency.CommitSequence, 1), queue.completeQueuedCommit());
    try std.testing.expectEqual(@as(concurrency.CommitSequence, 1), queue.snapshot().last_assigned_sequence);
}
