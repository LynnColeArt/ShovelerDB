const concurrency = @import("concurrency.zig");

pub fn diagnosticForCommitQueue(snapshot: concurrency.CommitQueueSnapshot) ?concurrency.Diagnostic {
    return snapshot.backpressureDiagnostic();
}

pub fn errorForDiagnostic(diagnostic: concurrency.Diagnostic) concurrency.ConcurrencyError {
    return diagnostic.toError();
}

pub fn kindForError(err: anyerror) ?concurrency.DiagnosticKind {
    return concurrency.diagnosticKindFromError(err);
}

test "commit queue backpressure maps to typed diagnostic and error" {
    const std = @import("std");

    const snapshot = concurrency.CommitQueueSnapshot{
        .queued_writes = 1,
        .queue_limit = 1,
        .last_assigned_sequence = 7,
    };

    const diagnostic = diagnosticForCommitQueue(snapshot).?;
    try std.testing.expectEqual(concurrency.DiagnosticKind.commit_queue_full, diagnostic.kind());
    try std.testing.expectEqual(error.CommitQueueFull, errorForDiagnostic(diagnostic));
    try std.testing.expectEqual(concurrency.DiagnosticKind.commit_queue_full, kindForError(error.CommitQueueFull).?);
}
