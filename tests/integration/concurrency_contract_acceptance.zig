const std = @import("std");
const shovelerdb = @import("shovelerdb");

const concurrency = shovelerdb.db.concurrency;
const executor = shovelerdb.db.executor;

const ContractHarness = struct {
    allocator: std.mem.Allocator,
    db: executor.Database,

    fn init(allocator: std.mem.Allocator) ContractHarness {
        return .{
            .allocator = allocator,
            .db = executor.Database.init(allocator),
        };
    }

    fn deinit(self: *ContractHarness) void {
        self.db.deinit();
        self.* = undefined;
    }

    fn exec(self: *ContractHarness, session: *executor.Session, sql: []const u8) !executor.ExecutionResult {
        return self.db.executeSql(session, sql);
    }

    fn execOk(self: *ContractHarness, session: *executor.Session, sql: []const u8) !void {
        var result = try self.exec(session, sql);
        result.deinit(self.allocator);
    }

    fn createMemoryTable(self: *ContractHarness, session: *executor.Session) !void {
        try self.execOk(session, "CREATE TABLE memories (id INTEGER, body TEXT, embedding VECTOR(2));");
    }

    fn insertCommittedMemory(
        self: *ContractHarness,
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

    fn expectVisibleRows(
        self: *ContractHarness,
        session: *executor.Session,
        expected_count: usize,
    ) !executor.ExecutionResult {
        var result = try self.exec(session, "SELECT id, body FROM memories ORDER BY id ASC;");
        errdefer result.deinit(self.allocator);

        try std.testing.expectEqual(expected_count, result.result_set.rows.len);
        return result;
    }
};

test "phase 6 harness keeps many reader snapshots stable while one writer commits" {
    const allocator = std.testing.allocator;

    var harness = ContractHarness.init(allocator);
    defer harness.deinit();

    var setup = executor.Session.init(allocator);
    defer setup.deinit();
    var writer = executor.Session.init(allocator);
    defer writer.deinit();
    var observer = executor.Session.init(allocator);
    defer observer.deinit();

    var readers: [4]executor.Session = undefined;
    for (&readers) |*reader| {
        reader.* = executor.Session.init(allocator);
    }
    defer {
        for (&readers) |*reader| {
            reader.deinit();
        }
    }

    try harness.createMemoryTable(&setup);
    try harness.execOk(&setup, "BEGIN;");
    try harness.insertCommittedMemory(&setup, 1, "seed", "[1, 0]");
    try harness.execOk(&setup, "COMMIT;");

    for (&readers) |*reader| {
        try harness.execOk(reader, "BEGIN;");
        var result = try harness.expectVisibleRows(reader, 1);
        result.deinit(allocator);
    }

    try harness.execOk(&writer, "BEGIN;");
    try harness.insertCommittedMemory(&writer, 2, "writer", "[0, 1]");
    try harness.execOk(&writer, "COMMIT;");

    var observer_result = try harness.expectVisibleRows(&observer, 2);
    observer_result.deinit(allocator);

    for (&readers) |*reader| {
        var result = try harness.expectVisibleRows(reader, 1);
        defer result.deinit(allocator);
        try std.testing.expectEqual(@as(i64, 1), result.result_set.rows[0].values[0].integer);
        try std.testing.expectEqualStrings("seed", result.result_set.rows[0].values[1].text);
    }
}

test "phase 6 harness records rollback as local and sequence-neutral" {
    const allocator = std.testing.allocator;

    var harness = ContractHarness.init(allocator);
    defer harness.deinit();

    var setup = executor.Session.init(allocator);
    defer setup.deinit();
    var writer = executor.Session.init(allocator);
    defer writer.deinit();
    var observer = executor.Session.init(allocator);
    defer observer.deinit();

    try harness.createMemoryTable(&setup);

    const before = harness.db.currentCommitSequence();
    try harness.execOk(&writer, "BEGIN;");
    try harness.insertCommittedMemory(&writer, 1, "rolled back", "[1, 1]");
    try harness.execOk(&writer, "ROLLBACK;");

    try std.testing.expectEqual(before, harness.db.currentCommitSequence());

    var result = try harness.expectVisibleRows(&observer, 0);
    result.deinit(allocator);
}

test "phase 6 harness exposes typed backpressure diagnostics for future queue wiring" {
    const config = concurrency.Config{
        .max_pending_writes = 3,
        .snapshot_retention_generations = 8,
        .checkpoint_generation_budget = 2,
        .vector_overlay_drain_budget = 4,
    };
    try config.validate();

    const queue = concurrency.CommitQueueSnapshot{
        .queued_writes = 3,
        .queue_limit = config.max_pending_writes,
        .last_assigned_sequence = 7,
    };

    const diagnostic = queue.backpressureDiagnostic().?;
    try std.testing.expectEqual(concurrency.DiagnosticKind.commit_queue_full, diagnostic.kind());
    try std.testing.expectEqual(error.CommitQueueFull, diagnostic.toError());
    try std.testing.expectEqual(@as(concurrency.CommitSequence, 8), queue.nextCommitSequence());
}

test "phase 6 harness names checkpoint and vector overlay pressure hooks" {
    const checkpoint = concurrency.CheckpointSnapshot{
        .in_progress = true,
        .committed_generation = 12,
    };
    const checkpoint_diagnostic = checkpoint.busyDiagnostic().?;
    try std.testing.expectEqual(concurrency.DiagnosticKind.checkpoint_already_running, checkpoint_diagnostic.kind());
    try std.testing.expectEqual(error.CheckpointAlreadyRunning, checkpoint_diagnostic.toError());

    const overlay = concurrency.VectorOverlaySnapshot{
        .committed_delta_count = 5,
        .drain_budget = 4,
        .last_drained_generation = 11,
    };
    const overlay_diagnostic = overlay.backlogDiagnostic().?;
    try std.testing.expectEqual(concurrency.DiagnosticKind.vector_overlay_backlog_exceeded, overlay_diagnostic.kind());
    try std.testing.expectEqual(error.VectorOverlayBacklogExceeded, overlay_diagnostic.toError());
}
