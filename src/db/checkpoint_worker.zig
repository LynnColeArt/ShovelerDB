const std = @import("std");
const concurrency = @import("concurrency.zig");

pub const Snapshot = struct {
    in_progress: bool = false,
    active_generation: ?concurrency.SnapshotGeneration = null,
    last_completed_generation: concurrency.SnapshotGeneration = 0,

    pub fn busyDiagnostic(self: Snapshot) ?concurrency.Diagnostic {
        if (!self.in_progress) return null;
        return .{
            .backpressure = .{
                .reason = .checkpoint_already_running,
                .committed_generation = self.active_generation orelse self.last_completed_generation,
            },
        };
    }
};

pub const Ticket = struct {
    worker: *Worker,
    generation: concurrency.SnapshotGeneration,
    closed: bool = false,

    pub fn complete(self: *Ticket) void {
        if (self.closed) return;
        self.worker.complete(self.generation);
        self.closed = true;
    }

    pub fn fail(self: *Ticket) void {
        if (self.closed) return;
        self.worker.fail(self.generation);
        self.closed = true;
    }
};

pub const Worker = struct {
    in_progress: bool = false,
    active_generation: ?concurrency.SnapshotGeneration = null,
    last_completed_generation: concurrency.SnapshotGeneration = 0,

    pub fn begin(self: *Worker, generation: concurrency.SnapshotGeneration) concurrency.ConcurrencyError!Ticket {
        if (self.in_progress) return error.CheckpointAlreadyRunning;
        self.in_progress = true;
        self.active_generation = generation;
        return .{
            .worker = self,
            .generation = generation,
        };
    }

    pub fn snapshot(self: Worker) Snapshot {
        return .{
            .in_progress = self.in_progress,
            .active_generation = self.active_generation,
            .last_completed_generation = self.last_completed_generation,
        };
    }

    fn complete(self: *Worker, generation: concurrency.SnapshotGeneration) void {
        std.debug.assert(self.in_progress);
        self.last_completed_generation = generation;
        self.in_progress = false;
        self.active_generation = null;
    }

    fn fail(self: *Worker, generation: concurrency.SnapshotGeneration) void {
        _ = generation;
        std.debug.assert(self.in_progress);
        self.in_progress = false;
        self.active_generation = null;
    }
};

test "checkpoint worker blocks overlap and preserves generation on failure" {
    var worker = Worker{};

    var first = try worker.begin(7);
    try std.testing.expectEqual(concurrency.DiagnosticKind.checkpoint_already_running, worker.snapshot().busyDiagnostic().?.kind());
    try std.testing.expectError(error.CheckpointAlreadyRunning, worker.begin(7));

    first.fail();
    try std.testing.expectEqual(@as(concurrency.SnapshotGeneration, 0), worker.snapshot().last_completed_generation);

    var second = try worker.begin(8);
    second.complete();
    try std.testing.expectEqual(@as(concurrency.SnapshotGeneration, 8), worker.snapshot().last_completed_generation);
}
