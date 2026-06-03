const std = @import("std");
const shovelerdb = @import("shovelerdb");

const backpressure = shovelerdb.db.backpressure;
const commit_queue = shovelerdb.db.commit_queue;
const concurrency = shovelerdb.db.concurrency;
const executor = shovelerdb.db.executor;

const QueueHarness = struct {
    allocator: std.mem.Allocator,
    db: executor.Database,

    fn init(allocator: std.mem.Allocator) QueueHarness {
        return .{
            .allocator = allocator,
            .db = executor.Database.init(allocator),
        };
    }

    fn deinit(self: *QueueHarness) void {
        self.db.deinit();
        self.* = undefined;
    }

    fn exec(self: *QueueHarness, session: *executor.Session, sql: []const u8) !executor.ExecutionResult {
        return self.db.executeSql(session, sql);
    }

    fn execOk(self: *QueueHarness, session: *executor.Session, sql: []const u8) !void {
        var result = try self.exec(session, sql);
        result.deinit(self.allocator);
    }

    fn createTable(self: *QueueHarness, session: *executor.Session) !void {
        try self.execOk(session, "CREATE TABLE memories (id INTEGER, body TEXT);");
    }

    fn insertMemory(self: *QueueHarness, session: *executor.Session, id: i64, body: []const u8) !void {
        var statement = std.ArrayList(u8).empty;
        defer statement.deinit(self.allocator);

        try statement.print(
            self.allocator,
            "INSERT INTO memories VALUES ({d}, '{s}');",
            .{ id, body },
        );
        try self.execOk(session, statement.items);
    }
};

test "database writer commits complete through ordered commit queue" {
    const allocator = std.testing.allocator;

    var harness = QueueHarness.init(allocator);
    defer harness.deinit();

    var setup = executor.Session.init(allocator);
    defer setup.deinit();
    var first = executor.Session.init(allocator);
    defer first.deinit();
    var second = executor.Session.init(allocator);
    defer second.deinit();

    try harness.createTable(&setup);

    try harness.execOk(&first, "BEGIN;");
    try harness.insertMemory(&first, 1, "first");
    try harness.execOk(&second, "BEGIN;");
    try harness.insertMemory(&second, 2, "second");

    try harness.execOk(&first, "COMMIT;");
    try std.testing.expectEqual(@as(concurrency.CommitSequence, 1), first.last_commit_sequence.?);
    try std.testing.expectEqual(@as(concurrency.CommitSequence, 1), harness.db.currentCommitSequence());
    try std.testing.expectEqual(@as(concurrency.QueueDepth, 0), harness.db.currentCommitQueueSnapshot().queued_writes);
    try std.testing.expectEqual(@as(concurrency.CommitSequence, 1), harness.db.currentCommitQueueSnapshot().last_assigned_sequence);

    try harness.execOk(&second, "COMMIT;");
    try std.testing.expectEqual(@as(concurrency.CommitSequence, 2), second.last_commit_sequence.?);
    try std.testing.expectEqual(@as(concurrency.CommitSequence, 2), harness.db.currentCommitSequence());
    try std.testing.expectEqual(@as(concurrency.QueueDepth, 0), harness.db.currentCommitQueueSnapshot().queued_writes);
    try std.testing.expectEqual(@as(concurrency.CommitSequence, 2), harness.db.currentCommitQueueSnapshot().last_assigned_sequence);
}

test "rollback never enters commit queue or advances sequence" {
    const allocator = std.testing.allocator;

    var harness = QueueHarness.init(allocator);
    defer harness.deinit();

    var setup = executor.Session.init(allocator);
    defer setup.deinit();
    var writer = executor.Session.init(allocator);
    defer writer.deinit();

    try harness.createTable(&setup);

    const before = harness.db.currentCommitSequence();
    const queue_before = harness.db.currentCommitQueueSnapshot();

    try harness.execOk(&writer, "BEGIN;");
    try harness.insertMemory(&writer, 1, "rolled back");
    try harness.execOk(&writer, "ROLLBACK;");

    try std.testing.expectEqual(before, harness.db.currentCommitSequence());
    try std.testing.expectEqual(queue_before.last_assigned_sequence, harness.db.currentCommitQueueSnapshot().last_assigned_sequence);
    try std.testing.expectEqual(@as(concurrency.QueueDepth, 0), harness.db.currentCommitQueueSnapshot().queued_writes);
}

test "bounded commit queue returns typed backpressure diagnostic when full" {
    var queue = commit_queue.Queue.init(.{
        .max_pending_writes = 1,
        .snapshot_retention_generations = 64,
        .checkpoint_generation_budget = 64,
        .vector_overlay_drain_budget = 1024,
    });

    try queue.enqueue();
    try std.testing.expectError(error.CommitQueueFull, queue.enqueue());

    const diagnostic = backpressure.diagnosticForCommitQueue(queue.snapshot()).?;
    try std.testing.expectEqual(concurrency.DiagnosticKind.commit_queue_full, diagnostic.kind());
    try std.testing.expectEqual(error.CommitQueueFull, backpressure.errorForDiagnostic(diagnostic));

    queue.abortQueuedCommit();
    try std.testing.expectEqual(@as(concurrency.QueueDepth, 0), queue.snapshot().queued_writes);
}
