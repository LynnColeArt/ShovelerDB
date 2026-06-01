const std = @import("std");
const test_analyzer = @import("test_analyzer.zig");

pub const Bucket = enum {
    sacred_candidate,
    adaptation_candidate,
    rejected_by_policy,
    deferred_candidate,

    pub fn label(self: Bucket) []const u8 {
        return switch (self) {
            .sacred_candidate => "sacred-candidate",
            .adaptation_candidate => "adaptation-candidate",
            .rejected_by_policy => "rejected-by-policy",
            .deferred_candidate => "deferred-candidate",
        };
    }
};

pub const Classification = struct {
    bucket: Bucket,
    reason: []const u8,
};

pub fn classify(analysis: test_analyzer.Analysis) Classification {
    if (analysis.rejected_statements > 0) {
        return .{
            .bucket = .rejected_by_policy,
            .reason = "contains SQL that ShovelerDB intentionally rejects",
        };
    }

    if (analysis.statements == 0) {
        return .{
            .bucket = .deferred_candidate,
            .reason = "no candidate SQL statements detected",
        };
    }

    if (analysis.unterminated_statement) {
        return .{
            .bucket = .adaptation_candidate,
            .reason = "contains an unterminated statement under the current analyzer",
        };
    }

    if (analysis.directives > 0 or
        analysis.harness_commands > 0 or
        analysis.expected_errors > 0 or
        analysis.delimiter_changes > 0)
    {
        return .{
            .bucket = .adaptation_candidate,
            .reason = "policy-clean SQL wrapped in MariaDB test harness behavior",
        };
    }

    return .{
        .bucket = .sacred_candidate,
        .reason = "plain policy-clean SQL",
    };
}

test "classifier rejects files with policy violations" {
    const analysis = test_analyzer.Analysis{
        .statements = 2,
        .accepted_statements = 1,
        .rejected_statements = 1,
    };
    const result = classify(analysis);
    try std.testing.expectEqual(Bucket.rejected_by_policy, result.bucket);
}

test "classifier marks harnessed but policy-clean tests for adaptation" {
    const analysis = test_analyzer.Analysis{
        .statements = 11,
        .accepted_statements = 11,
        .directives = 4,
        .harness_commands = 1,
        .delimiter_changes = 1,
    };
    const result = classify(analysis);
    try std.testing.expectEqual(Bucket.adaptation_candidate, result.bucket);
}

test "classifier marks plain policy-clean SQL as sacred candidate" {
    const analysis = test_analyzer.Analysis{
        .statements = 2,
        .accepted_statements = 2,
    };
    const result = classify(analysis);
    try std.testing.expectEqual(Bucket.sacred_candidate, result.bucket);
}

test "classifier defers files with no candidate SQL" {
    const result = classify(.{});
    try std.testing.expectEqual(Bucket.deferred_candidate, result.bucket);
}

