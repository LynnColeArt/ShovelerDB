const std = @import("std");
const concurrency = @import("concurrency.zig");
const backpressure = @import("backpressure.zig");

pub const Queue = struct {
    config: concurrency.Config,
    pending_writes: concurrency.QueueDepth = 0,
    last_assigned_sequence: concurrency.CommitSequence = 0,

    pub fn init(config: concurrency.Config) Queue {
        return .{ .config = config };
    }

    pub fn snapshot(self: Queue) concurrency.CommitQueueSnapshot {
        return .{
            .queued_writes = self.pending_writes,
            .queue_limit = self.config.max_pending_writes,
            .last_assigned_sequence = self.last_assigned_sequence,
        };
    }

    pub fn enqueue(self: *Queue) concurrency.ConcurrencyError!void {
        try self.snapshot().validate();
        if (backpressure.diagnosticForCommitQueue(self.snapshot())) |diagnostic| {
            return diagnostic.toError();
        }
        self.pending_writes += 1;
    }

    pub fn abortQueuedCommit(self: *Queue) void {
        std.debug.assert(self.pending_writes > 0);
        self.pending_writes -= 1;
    }

    pub fn completeQueuedCommit(self: *Queue) concurrency.CommitSequence {
        std.debug.assert(self.pending_writes > 0);
        self.pending_writes -= 1;
        self.last_assigned_sequence += 1;
        return self.last_assigned_sequence;
    }

    pub fn syncToSequence(self: *Queue, sequence: concurrency.CommitSequence) void {
        self.last_assigned_sequence = sequence;
    }
};

test "commit queue assigns ordered commit sequences" {
    var queue = Queue.init(concurrency.default_config);

    try queue.enqueue();
    try std.testing.expectEqual(@as(concurrency.QueueDepth, 1), queue.snapshot().queued_writes);
    try std.testing.expectEqual(@as(concurrency.CommitSequence, 1), queue.completeQueuedCommit());

    try queue.enqueue();
    try std.testing.expectEqual(@as(concurrency.CommitSequence, 2), queue.completeQueuedCommit());
    try std.testing.expectEqual(@as(concurrency.QueueDepth, 0), queue.snapshot().queued_writes);
    try std.testing.expectEqual(@as(concurrency.CommitSequence, 2), queue.snapshot().last_assigned_sequence);
}

test "commit queue reports typed backpressure when full" {
    var queue = Queue.init(.{
        .max_pending_writes = 1,
        .snapshot_retention_generations = 64,
        .checkpoint_generation_budget = 64,
        .vector_overlay_drain_budget = 1024,
    });

    try queue.enqueue();
    try std.testing.expectError(error.CommitQueueFull, queue.enqueue());
    const diagnostic = backpressure.diagnosticForCommitQueue(queue.snapshot()).?;
    try std.testing.expectEqual(concurrency.DiagnosticKind.commit_queue_full, diagnostic.kind());
    queue.abortQueuedCommit();
    try std.testing.expectEqual(@as(concurrency.QueueDepth, 0), queue.snapshot().queued_writes);
}
