const std = @import("std");

pub const CommitSequence = u64;
pub const SnapshotGeneration = u64;
pub const QueueDepth = usize;

pub const ConcurrencyError = error{
    CommitQueueFull,
    SnapshotRetentionExceeded,
    CheckpointAlreadyRunning,
    VectorOverlayBacklogExceeded,
    InvalidCommitQueueLimit,
    InvalidSnapshotRetentionLimit,
    InvalidCheckpointBudget,
    InvalidVectorOverlayBudget,
};

pub const DiagnosticKind = enum {
    commit_queue_full,
    snapshot_retention_exceeded,
    checkpoint_already_running,
    vector_overlay_backlog_exceeded,
    invalid_commit_queue_limit,
    invalid_snapshot_retention_limit,
    invalid_checkpoint_budget,
    invalid_vector_overlay_budget,
};

pub fn diagnosticKindFromError(err: anyerror) ?DiagnosticKind {
    return switch (err) {
        error.CommitQueueFull => .commit_queue_full,
        error.SnapshotRetentionExceeded => .snapshot_retention_exceeded,
        error.CheckpointAlreadyRunning => .checkpoint_already_running,
        error.VectorOverlayBacklogExceeded => .vector_overlay_backlog_exceeded,
        error.InvalidCommitQueueLimit => .invalid_commit_queue_limit,
        error.InvalidSnapshotRetentionLimit => .invalid_snapshot_retention_limit,
        error.InvalidCheckpointBudget => .invalid_checkpoint_budget,
        error.InvalidVectorOverlayBudget => .invalid_vector_overlay_budget,
        else => null,
    };
}

pub const Config = struct {
    max_pending_writes: QueueDepth = 1024,
    snapshot_retention_generations: usize = 64,
    checkpoint_generation_budget: usize = 64,
    vector_overlay_drain_budget: usize = 1024,

    pub fn validate(self: Config) ConcurrencyError!void {
        if (self.max_pending_writes == 0) return error.InvalidCommitQueueLimit;
        if (self.snapshot_retention_generations == 0) return error.InvalidSnapshotRetentionLimit;
        if (self.checkpoint_generation_budget == 0) return error.InvalidCheckpointBudget;
        if (self.vector_overlay_drain_budget == 0) return error.InvalidVectorOverlayBudget;
    }
};

pub const default_config = Config{};

pub const BackpressureReason = enum {
    commit_queue_full,
    snapshot_retention_exceeded,
    checkpoint_already_running,
    vector_overlay_backlog_exceeded,
};

pub const BackpressureDiagnostic = struct {
    reason: BackpressureReason,
    queued_writes: QueueDepth = 0,
    queue_limit: QueueDepth = default_config.max_pending_writes,
    committed_generation: SnapshotGeneration = 0,
    last_assigned_sequence: CommitSequence = 0,

    pub fn kind(self: BackpressureDiagnostic) DiagnosticKind {
        return switch (self.reason) {
            .commit_queue_full => .commit_queue_full,
            .snapshot_retention_exceeded => .snapshot_retention_exceeded,
            .checkpoint_already_running => .checkpoint_already_running,
            .vector_overlay_backlog_exceeded => .vector_overlay_backlog_exceeded,
        };
    }

    pub fn toError(self: BackpressureDiagnostic) ConcurrencyError {
        return switch (self.reason) {
            .commit_queue_full => error.CommitQueueFull,
            .snapshot_retention_exceeded => error.SnapshotRetentionExceeded,
            .checkpoint_already_running => error.CheckpointAlreadyRunning,
            .vector_overlay_backlog_exceeded => error.VectorOverlayBacklogExceeded,
        };
    }
};

pub const ConfigurationDiagnostic = struct {
    kind: DiagnosticKind,
    configured_value: usize,
    minimum_value: usize = 1,

    pub fn toError(self: ConfigurationDiagnostic) ConcurrencyError {
        return switch (self.kind) {
            .invalid_commit_queue_limit => error.InvalidCommitQueueLimit,
            .invalid_snapshot_retention_limit => error.InvalidSnapshotRetentionLimit,
            .invalid_checkpoint_budget => error.InvalidCheckpointBudget,
            .invalid_vector_overlay_budget => error.InvalidVectorOverlayBudget,
            else => unreachable,
        };
    }
};

pub const Diagnostic = union(enum) {
    backpressure: BackpressureDiagnostic,
    configuration: ConfigurationDiagnostic,

    pub fn kind(self: Diagnostic) DiagnosticKind {
        return switch (self) {
            .backpressure => |diagnostic| diagnostic.kind(),
            .configuration => |diagnostic| diagnostic.kind,
        };
    }

    pub fn toError(self: Diagnostic) ConcurrencyError {
        return switch (self) {
            .backpressure => |diagnostic| diagnostic.toError(),
            .configuration => |diagnostic| diagnostic.toError(),
        };
    }
};

pub const CommitQueueSnapshot = struct {
    queued_writes: QueueDepth = 0,
    queue_limit: QueueDepth = default_config.max_pending_writes,
    last_assigned_sequence: CommitSequence = 0,

    pub fn validate(self: CommitQueueSnapshot) ConcurrencyError!void {
        if (self.queue_limit == 0) return error.InvalidCommitQueueLimit;
    }

    pub fn canAcceptWrite(self: CommitQueueSnapshot) bool {
        return self.queue_limit > 0 and self.queued_writes < self.queue_limit;
    }

    pub fn nextCommitSequence(self: CommitQueueSnapshot) CommitSequence {
        return self.last_assigned_sequence + 1;
    }

    pub fn backpressureDiagnostic(self: CommitQueueSnapshot) ?Diagnostic {
        if (self.canAcceptWrite()) return null;
        return .{
            .backpressure = .{
                .reason = .commit_queue_full,
                .queued_writes = self.queued_writes,
                .queue_limit = self.queue_limit,
                .last_assigned_sequence = self.last_assigned_sequence,
            },
        };
    }
};

pub const CheckpointSnapshot = struct {
    in_progress: bool = false,
    committed_generation: SnapshotGeneration = 0,

    pub fn busyDiagnostic(self: CheckpointSnapshot) ?Diagnostic {
        if (!self.in_progress) return null;
        return .{
            .backpressure = .{
                .reason = .checkpoint_already_running,
                .committed_generation = self.committed_generation,
            },
        };
    }
};

pub const VectorOverlaySnapshot = struct {
    committed_delta_count: usize = 0,
    drain_budget: usize = default_config.vector_overlay_drain_budget,
    last_drained_generation: SnapshotGeneration = 0,

    pub fn validate(self: VectorOverlaySnapshot) ConcurrencyError!void {
        if (self.drain_budget == 0) return error.InvalidVectorOverlayBudget;
    }

    pub fn backlogDiagnostic(self: VectorOverlaySnapshot) ?Diagnostic {
        if (self.drain_budget > 0 and self.committed_delta_count <= self.drain_budget) return null;
        return .{
            .backpressure = .{
                .reason = .vector_overlay_backlog_exceeded,
                .queue_limit = self.drain_budget,
                .committed_generation = self.last_drained_generation,
            },
        };
    }
};

pub fn configurationDiagnostic(config: Config) ?Diagnostic {
    if (config.max_pending_writes == 0) {
        return .{
            .configuration = .{
                .kind = .invalid_commit_queue_limit,
                .configured_value = config.max_pending_writes,
            },
        };
    }
    if (config.snapshot_retention_generations == 0) {
        return .{
            .configuration = .{
                .kind = .invalid_snapshot_retention_limit,
                .configured_value = config.snapshot_retention_generations,
            },
        };
    }
    if (config.checkpoint_generation_budget == 0) {
        return .{
            .configuration = .{
                .kind = .invalid_checkpoint_budget,
                .configured_value = config.checkpoint_generation_budget,
            },
        };
    }
    if (config.vector_overlay_drain_budget == 0) {
        return .{
            .configuration = .{
                .kind = .invalid_vector_overlay_budget,
                .configured_value = config.vector_overlay_drain_budget,
            },
        };
    }
    return null;
}

test "default concurrency config is valid" {
    try default_config.validate();
    try std.testing.expect(configurationDiagnostic(default_config) == null);
}

test "commit queue snapshot returns typed backpressure diagnostic" {
    const queue = CommitQueueSnapshot{
        .queued_writes = 2,
        .queue_limit = 2,
        .last_assigned_sequence = 41,
    };

    const diagnostic = queue.backpressureDiagnostic().?;
    try std.testing.expectEqual(DiagnosticKind.commit_queue_full, diagnostic.kind());
    try std.testing.expectEqual(error.CommitQueueFull, diagnostic.toError());
    try std.testing.expectEqual(@as(CommitSequence, 42), queue.nextCommitSequence());
}

test "configuration diagnostics map to stable error kinds" {
    const diagnostic = configurationDiagnostic(.{
        .max_pending_writes = 0,
    }).?;

    try std.testing.expectEqual(DiagnosticKind.invalid_commit_queue_limit, diagnostic.kind());
    try std.testing.expectEqual(error.InvalidCommitQueueLimit, diagnostic.toError());
    try std.testing.expectEqual(DiagnosticKind.commit_queue_full, diagnosticKindFromError(error.CommitQueueFull).?);
    try std.testing.expect(diagnosticKindFromError(error.OutOfMemory) == null);
}
